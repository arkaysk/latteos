//! Kompatibilita hardvéru: platforma (CPU, RAM, disk, firmvér) a generácia grafiky s odporúčaným ovládačom.
//!
//! Cieľ (1. 10. 2026): inštalácia a beh pohodlne na každom PC do 10 rokov, solídne na PC 10–15 rokov
//! (≈ 2011–2016: Sandy Bridge … Skylake, HD 7000 … RX 400, GTX 600 … GTX 10xx).
//! Iba čítanie z /proc a /sys (~1 ms), takže to môže bežať pri každom štarte v `latte-boot`.

use crate::Gpu;
use std::fmt::Write as _;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

/// Závažnosť zistenia.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    /// len pre informáciu (Device Manager, Barista)
    Info,
    /// pôjde, ale s obmedzením — ukázať používateľovi s návodom
    Warn,
    /// LatteOS tu nepobeží rozumne (inštalátor má odmietnuť alebo dôrazne varovať)
    Block,
}

impl Level {
    pub fn as_str(self) -> &'static str {
        match self { Level::Info => "info", Level::Warn => "warn", Level::Block => "block" }
    }
}

/// Jedno zistenie s radou, čo urobiť.
#[derive(Debug, Clone)]
pub struct Finding {
    pub level: Level,
    /// krátky kľúč (cpu-v2, ram, disk-hdd, gpu-radeon-si…) pre Device Manager a preklady
    pub id: &'static str,
    pub text: String,
    /// rada: balík, parameter jadra, nastavenie; prázdne = nič netreba
    pub fix: String,
}

fn f(level: Level, id: &'static str, text: impl Into<String>, fix: impl Into<String>) -> Finding {
    Finding { level, id, text: text.into(), fix: fix.into() }
}

/// Platforma počítača (bez grafiky).
#[derive(Debug, Clone, Default)]
pub struct Platform {
    pub cpu_model: String,
    /// logické jadrá (vlákna)
    pub threads: usize,
    /// úroveň x86-64 (1–4) podľa príznakov CPU; 0 = iná architektúra / nezistené
    pub x86_level: u8,
    pub ram_mb: u64,
    pub swap_mb: u64,
    /// koreňový systém súborov leží na rotačnom disku (HDD)
    pub root_hdd: bool,
    pub root_free_gb: u64,
    pub uefi: bool,
    pub secure_boot: bool,
}

impl Platform {
    pub fn read() -> Self {
        let cpuinfo = fs::read_to_string("/proc/cpuinfo").unwrap_or_default();
        let meminfo = fs::read_to_string("/proc/meminfo").unwrap_or_default();
        let (root_hdd, root_free_gb) = root_disk();
        Platform {
            cpu_model: cpuinfo.lines().find_map(|l| l.strip_prefix("model name")?.split_once(':').map(|(_, v)| v.trim().to_string())).unwrap_or_default(),
            threads: cpuinfo.lines().filter(|l| l.starts_with("processor")).count(),
            x86_level: x86_level(&cpuinfo),
            ram_mb: meminfo_kb(&meminfo, "MemTotal:") / 1024,
            swap_mb: meminfo_kb(&meminfo, "SwapTotal:") / 1024,
            root_hdd,
            root_free_gb,
            uefi: Path::new("/sys/firmware/efi").exists(),
            secure_boot: secure_boot(),
        }
    }
}

fn meminfo_kb(m: &str, key: &str) -> u64 {
    m.lines().find_map(|l| l.strip_prefix(key)?.split_whitespace().next()?.parse().ok()).unwrap_or(0)
}

/// Úroveň mikroarchitektúry x86-64 (psABI): v2 = SSE4.2/POPCNT (Nehalem 2008+, Bulldozer),
/// v3 = AVX2/FMA/BMI (Haswell 2013+, Excavator/Zen), v4 = AVX-512.
pub fn x86_level(cpuinfo: &str) -> u8 {
    let Some(flags) = cpuinfo.lines().find_map(|l| l.strip_prefix("flags")?.split_once(':').map(|(_, v)| v.to_string())) else { return 0 };
    let has = |f: &str| flags.split_whitespace().any(|x| x == f);
    if !has("lm") { return 0; }
    let v2 = ["cx16", "lahf_lm", "popcnt", "sse4_1", "sse4_2", "ssse3"].iter().all(|f| has(f));
    let v3 = v2 && ["avx", "avx2", "bmi1", "bmi2", "f16c", "fma", "abm", "movbe", "xsave"].iter().all(|f| has(f));
    let v4 = v3 && ["avx512f", "avx512bw", "avx512cd", "avx512dq", "avx512vl"].iter().all(|f| has(f));
    1 + v2 as u8 + v3 as u8 + v4 as u8
}

/// Secure Boot zapnutý? (premenná EFI: 4 bajty atribútov + hodnota)
fn secure_boot() -> bool {
    fs::read("/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c")
        .map(|b| b.get(4) == Some(&1))
        .unwrap_or(false)
}

/// (koreň na HDD, voľné GB na koreni)
fn root_disk() -> (bool, u64) {
    let Ok(md) = fs::metadata("/") else { return (false, 0) };
    let dev = md.dev();
    let (major, minor) = (((dev >> 8) & 0xfff) | ((dev >> 32) & !0xfff), (dev & 0xff) | ((dev >> 12) & !0xff));
    let hdd = fs::canonicalize(format!("/sys/dev/block/{major}:{minor}")).map(|p| rotational(&p, 0)).unwrap_or(false);
    (hdd, free_gb("/"))
}

/// Rotačný disk pod blokovým zariadením; LVM/LUKS (dm-*) a RAID idú cez `slaves`, oddiel cez rodiča.
fn rotational(p: &Path, depth: u8) -> bool {
    if depth > 4 { return false; }
    if let Ok(rd) = fs::read_dir(p.join("slaves")) {
        let slaves: Vec<PathBuf> = rd.flatten().filter_map(|e| fs::canonicalize(e.path()).ok()).collect();
        if !slaves.is_empty() {
            return slaves.iter().any(|s| rotational(s, depth + 1));
        }
    }
    let read = |q: &Path| fs::read_to_string(q.join("queue/rotational")).ok().map(|s| s.trim() == "1");
    read(p).or_else(|| p.parent().and_then(read)).unwrap_or(false)
}

fn free_gb(path: &str) -> u64 {
    // std nemá statvfs a latte-hw je bez závislostí → `df` (~2 ms, iba Platform::read)
    std::process::Command::new("df").args(["--output=avail", "-B1G", path]).output().ok()
        .and_then(|o| String::from_utf8_lossy(&o.stdout).lines().nth(1).and_then(|l| l.trim().parse().ok()))
        .unwrap_or(0)
}

/// Generácia grafiky, ktorú LatteOS pozná, s odporúčaným ovládačom.
#[derive(Debug, Clone, PartialEq)]
pub struct GpuFamily {
    /// ľudský názov generácie
    pub name: &'static str,
    /// približný rok uvedenia
    pub year: u16,
    /// má Vulkan (Proton/DXVK, Zink, gamescope) s odporúčaným ovládačom
    pub vulkan: bool,
    /// odporúčaný ovládač / balík
    pub driver: &'static str,
    /// parametre jadra, ktoré treba pridať (prázdne = netreba)
    pub kernel_args: &'static str,
    /// najvyšší rozumný stupeň (plny > standard > usporny > minimalny)
    pub max_tier: &'static str,
}

const fn fam(name: &'static str, year: u16, vulkan: bool, driver: &'static str, kernel_args: &'static str, max_tier: &'static str) -> GpuFamily {
    GpuFamily { name, year, vulkan, driver, kernel_args, max_tier }
}

fn pci_id(s: &str) -> u32 {
    u32::from_str_radix(s.trim_start_matches("0x"), 16).unwrap_or(0)
}

fn in_ranges(id: u32, r: &[(u32, u32)]) -> bool {
    r.iter().any(|&(a, b)| id >= a && id <= b)
}

// AMD Southern Islands (GCN 1, HD 7000 / R7 240–250 / R9 270–280, 2012): Tahiti, Pitcairn, Cape Verde, Oland, Hainan
const AMD_SI: [(u32, u32); 4] = [(0x6600, 0x663f), (0x6660, 0x666f), (0x6780, 0x679f), (0x6800, 0x683f)];
// AMD Sea Islands (GCN 2, R7 260 / R9 290 / Kaveri, Kabini, Mullins APU, 2013–14)
const AMD_CIK: [(u32, u32); 5] = [(0x6640, 0x665f), (0x67a0, 0x67bf), (0x1304, 0x131d), (0x9830, 0x983f), (0x9850, 0x985f)];
// NVIDIA podľa PCI ID (prvé čipy generácie; mobilné varianty patria do rovnakých rozsahov)
const NV_KEPLER: [(u32, u32); 2] = [(0x0fc0, 0x103f), (0x1180, 0x12ff)];
const NV_MAXWELL: [(u32, u32); 3] = [(0x1340, 0x13ff), (0x1400, 0x15ef), (0x1600, 0x17ff)];
const NV_PASCAL: [(u32, u32); 2] = [(0x15f0, 0x15ff), (0x1b00, 0x1d7f)];
const NV_VOLTA: [(u32, u32); 1] = [(0x1d80, 0x1dff)];
const NV_TURING: [(u32, u32); 2] = [(0x1e00, 0x1fff), (0x2180, 0x21ff)];

/// Generácia karty. `None` = neznáma (napr. VM, simpledrm) — rozhodne test EGL.
pub fn gpu_family(g: &Gpu) -> Option<GpuFamily> {
    let id = pci_id(&g.device);
    match g.vendor.as_str() {
        "0x1002" => Some(amd_family(g, id)),
        "0x10de" => Some(nv_family(id)),
        "0x8086" => Some(intel_family(id)),
        _ => None,
    }
}

fn amd_family(g: &Gpu, id: u32) -> GpuFamily {
    if in_ranges(id, &AMD_SI) {
        return fam("AMD GCN 1 (Southern Islands, HD 7000)", 2012, true, "amdgpu (RADV)", "radeon.si_support=0 amdgpu.si_support=1", "usporny");
    }
    if in_ranges(id, &AMD_CIK) {
        return fam("AMD GCN 2 (Sea Islands, R7/R9 200)", 2013, true, "amdgpu (RADV)", "radeon.cik_support=0 amdgpu.cik_support=1", "usporny");
    }
    if g.gfx > 0 {
        return match g.gfx / 10000 {
            8 => fam("AMD GCN 3–4 (Fiji, Polaris: RX 400/500)", 2015, true, "amdgpu (RADV)", "", "usporny"),
            9 => fam("AMD GCN 5 (Vega)", 2017, true, "amdgpu (RADV)", "", "standard"),
            10 => fam("AMD RDNA 1–2", 2019, true, "amdgpu (RADV)", "", "plny"),
            _ => fam("AMD RDNA 3+", 2022, true, "amdgpu (RADV)", "", "plny"),
        };
    }
    if g.driver == "radeon" {
        // pred GCN: TeraScale (HD 2000–6000, 2007–2011) — r600 v Mesa, OpenGL 3.3/4.x, bez Vulkanu
        return fam("AMD TeraScale (HD 2000–6000)", 2009, false, "radeon (r600, OpenGL)", "", "minimalny");
    }
    // amdgpu bez KFD (staršie jadro, APU bez ROCm) — GCN 3+, generácia nezistená
    fam("AMD GCN 3+ (generácia nezistená)", 2015, true, "amdgpu (RADV)", "", "standard")
}

fn nv_family(id: u32) -> GpuFamily {
    if in_ranges(id, &NV_TURING) || id >= 0x2000 {
        return fam("NVIDIA Turing a novšia (RTX 20+, GTX 16)", 2018, true, "akmod-nvidia (595+, otvorené moduly)", "", if id >= 0x2200 { "plny" } else { "standard" });
    }
    if in_ranges(id, &NV_VOLTA) {
        return fam("NVIDIA Volta", 2017, true, "akmod-nvidia-580xx", "", "standard");
    }
    if in_ranges(id, &NV_PASCAL) {
        return fam("NVIDIA Pascal (GTX 10xx)", 2016, true, "akmod-nvidia-580xx", "", "usporny");
    }
    if in_ranges(id, &NV_MAXWELL) {
        return fam("NVIDIA Maxwell (GTX 750, 900)", 2014, true, "akmod-nvidia-580xx", "", "usporny");
    }
    if in_ranges(id, &NV_KEPLER) {
        // vetva 470 už nedrží krok s jadrom Fedory → nouveau + NVK (Vulkan), bez preklápania taktov
        return fam("NVIDIA Kepler (GTX 600/700)", 2012, true, "nouveau + NVK (Mesa)", "", "minimalny");
    }
    fam("NVIDIA Fermi a staršia", 2010, false, "nouveau (OpenGL)", "", "minimalny")
}

fn intel_family(id: u32) -> GpuFamily {
    // podľa PCI ID integrovanej grafiky (Mesa: crocus = Gen4–7, iris = Gen8+, anv Vulkan od Gen8, hasvk Gen7)
    match id {
        0x0100..=0x012f => fam("Intel Gen6 (Sandy Bridge, HD 2000/3000)", 2011, false, "i915 (crocus, OpenGL 3.3)", "", "minimalny"),
        0x0150..=0x016f | 0x0402..=0x0d2f | 0x0f30..=0x0f3f => fam("Intel Gen7 (Ivy Bridge, Haswell, Bay Trail)", 2013, true, "i915 (crocus, hasvk)", "", "minimalny"),
        0x1602..=0x163f | 0x22b0..=0x22bf => fam("Intel Gen8 (Broadwell, Cherry Trail)", 2015, true, "i915 (iris, anv)", "", "minimalny"),
        0x4600..=0x46ff | 0x4c80..=0x4cff | 0x9a40..=0x9aff | 0xa700..=0xa7ff | 0x7d00..=0x7dff | 0x6420..=0x64ff
            => fam("Intel Xe (11. gen. a novšie)", 2020, true, "i915/xe (iris, anv)", "", "usporny"),
        0x5690..=0x56ff | 0xe200..=0xe2ff => fam("Intel Arc", 2022, true, "i915/xe (iris, anv)", "", "plny"),
        _ => fam("Intel Gen9 (Skylake … Comet Lake, UHD 600)", 2016, true, "i915 (iris, anv)", "", "minimalny"),
    }
}

/// Poradie stupňov od najvyššieho.
pub const TIERS: [&str; 4] = ["plny", "standard", "usporny", "minimalny"];

fn tier_rank(t: &str) -> usize {
    TIERS.iter().position(|x| *x == t).unwrap_or(1)
}

/// Najvyšší stupeň, ktorý unesie platforma (RAM, CPU) — grafika sama nestačí:
/// pod 6 GB RAM sa blur a animácie s veľkými textúrami nezmestia vedľa prehliadača.
pub fn platform_cap(p: &Platform) -> (&'static str, String) {
    if p.ram_mb > 0 && p.ram_mb < 3 * 1024 { return ("minimalny", format!("{} MB RAM", p.ram_mb)); }
    if p.threads > 0 && p.threads <= 2 { return ("minimalny", format!("{} vlákna CPU", p.threads)); }
    if p.ram_mb > 0 && p.ram_mb < 6 * 1024 { return ("usporny", format!("{} GB RAM", (p.ram_mb + 512) / 1024)); }
    if p.threads > 0 && p.threads <= 4 { return ("standard", format!("{} vlákna CPU", p.threads)); }
    ("plny", String::new())
}

/// Stupeň obmedzený generáciou karty aj platformou: nižší z `tier`, `family.max_tier` a `platform_cap`.
/// Vráti (stupeň, dôvod obmedzenia alebo prázdne).
pub fn cap_tier(tier: &'static str, fam: Option<&GpuFamily>, p: &Platform) -> (&'static str, String) {
    if !TIERS.contains(&tier) { return (tier, String::new()); }   // softver/safe sa nemenia
    let mut out = tier;
    let mut why = String::new();
    if let Some(f) = fam {
        if tier_rank(f.max_tier) > tier_rank(out) { out = f.max_tier; why = f.name.to_string(); }
    }
    let (pc, pwhy) = platform_cap(p);
    if tier_rank(pc) > tier_rank(out) { out = pc; why = pwhy; }
    (out, why)
}

/// Všetky zistenia pre inštalátor, Device Manager a `latte-boot compat`.
pub fn check(p: &Platform, gpus: &[Gpu], virt: Option<&str>) -> Vec<Finding> {
    let mut v = Vec::new();
    match p.x86_level {
        0 => v.push(f(Level::Block, "cpu-arch", "procesor nie je 64-bitový x86-64 (LatteOS je iba pre x86-64)", "")),
        1 => v.push(f(Level::Warn, "cpu-v2", "procesor bez SSE4.2/POPCNT (pred rokom 2009): systém pobeží, no časť hier, Flatpakov a AI nie", "")),
        2 => v.push(f(Level::Info, "cpu-v3", "procesor bez AVX2 (pred Haswellom 2013): softvérové kreslenie a lokálna AI sú pomalšie", "stupeň Úsporný; AI cez domáci server alebo online")),
        _ => {}
    }
    if p.threads > 0 && p.threads <= 2 {
        v.push(f(Level::Warn, "cpu-threads", format!("iba {} vlákna CPU", p.threads), "stupeň Minimálny, bez živej tapety"));
    }
    if p.ram_mb > 0 {
        if p.ram_mb < 2 * 1024 - 128 {
            v.push(f(Level::Block, "ram", format!("{} MB RAM — minimum sú 2 GB", p.ram_mb), ""));
        } else if p.ram_mb < 4 * 1024 - 256 {
            v.push(f(Level::Warn, "ram", format!("{} MB RAM — odporúčané sú 4 GB+", p.ram_mb), "zram (predvolené vo Fedore), stupeň Minimálny, prehliadač s menej kartami"));
        } else if p.ram_mb < 8 * 1024 - 512 {
            v.push(f(Level::Info, "ram", format!("{} GB RAM", (p.ram_mb + 512) / 1024), "stupeň najviac Úsporný pri hrách"));
        }
        if p.swap_mb == 0 {
            v.push(f(Level::Warn, "swap", "bez swapu ani zram — pri zaplnení RAM zasiahne OOM", "dnf install zram-generator-defaults"));
        }
    }
    if p.root_hdd {
        v.push(f(Level::Warn, "disk-hdd", "systém je na rotačnom disku (HDD): štart a prvé spustenie aplikácií sú pomalé",
                 "SSD je najväčšie zrýchlenie pre starý PC"));
    }
    if p.root_free_gb > 0 && p.root_free_gb < 10 {
        v.push(f(Level::Warn, "disk-free", format!("na systémovom disku je voľných iba {} GB", p.root_free_gb), "dnf clean all; flatpak uninstall --unused"));
    }
    if !p.uefi {
        v.push(f(Level::Info, "bios", "štart cez starý BIOS (legacy), nie UEFI", "funguje; pre Atomic (bootc) a Secure Boot je lepšie UEFI"));
    }
    let main = gpus.iter().find(|g| g.boot_vga).or(gpus.first());
    match main {
        None if virt.is_none() => v.push(f(Level::Warn, "gpu-none", "nenašla sa grafická karta s ovládačom (iba simpledrm?)", "SAFE relácia (pixman); skontrolovať nomodeset")),
        _ => {}
    }
    for g in gpus {
        let Some(fam) = gpu_family(g) else { continue };
        let card = format!("{} ({}:{})", fam.name, g.vendor, g.device);
        if !fam.kernel_args.is_empty() && g.driver == "radeon" {
            v.push(f(Level::Warn, "gpu-amdgpu", format!("{card} beží na starom ovládači radeon — bez Vulkanu (hry, Proton)"),
                     format!("grubby --update-kernel=ALL --args=\"{}\"", fam.kernel_args)));
        }
        if !fam.vulkan {
            v.push(f(Level::Warn, "gpu-novulkan", format!("{card}: bez Vulkanu — hry cez Proton/DXVK a gamescope nepôjdu"), "Herňa iba pre natívne OpenGL hry"));
        }
        if g.vendor == "0x10de" {
            let nv_loaded = g.driver == "nvidia";
            if fam.driver.starts_with("akmod") && !nv_loaded {
                v.push(f(Level::Info, "gpu-nvidia", format!("{card} beží na nouveau; plný výkon dá {}", fam.driver),
                         format!("RPM Fusion: dnf install {}{}", fam.driver.split_whitespace().next().unwrap_or(""),
                                 if p.secure_boot { " (Secure Boot: po inštalácii mokutil --import a potvrdiť kľúč pri reštarte)" } else { "" })));
            }
            if nv_loaded && fam.driver.starts_with("nouveau") {
                v.push(f(Level::Warn, "gpu-nvidia-legacy", format!("{card}: proprietárny ovládač pre túto generáciu už nedrží krok s jadrom Fedory"),
                         "pri páde po aktualizácii jadra: SAFE › odinštalovať akmod-nvidia-470xx, nouveau + NVK"));
            }
        }
        if fam.year > 0 && fam.year < 2011 && virt.is_none() {
            v.push(f(Level::Info, "gpu-old", format!("{card} je staršia ako 15 rokov — LatteOS pobeží v stupni Minimálny alebo Softvér"), ""));
        }
    }
    v.sort_by(|a, b| b.level.cmp(&a.level));
    v
}

/// TOML výpis (časť `[platform]` v mode.toml a výstup `latte-boot compat`).
pub fn to_toml(p: &Platform, gpus: &[Gpu], findings: &[Finding]) -> String {
    let q = crate::q;
    let mut s = String::new();
    let _ = writeln!(s, "[platform]");
    let _ = writeln!(s, "cpu = {}\nthreads = {}\nx86_level = {}", q(&p.cpu_model), p.threads, p.x86_level);
    let _ = writeln!(s, "ram_mb = {}\nswap_mb = {}\nroot_hdd = {}\nroot_free_gb = {}", p.ram_mb, p.swap_mb, p.root_hdd, p.root_free_gb);
    let _ = writeln!(s, "uefi = {}\nsecure_boot = {}", p.uefi, p.secure_boot);
    for g in gpus {
        if let Some(fam) = gpu_family(g) {
            let _ = writeln!(s, "\n[[platform.gpu]]\ncard = {}\nfamily = {}\nyear = {}\nvulkan = {}\ndriver = {}\nmax_tier = {}",
                             q(&g.card), q(fam.name), fam.year, fam.vulkan, q(fam.driver), q(fam.max_tier));
            if !fam.kernel_args.is_empty() { let _ = writeln!(s, "kernel_args = {}", q(fam.kernel_args)); }
        }
    }
    for x in findings {
        let _ = writeln!(s, "\n[[platform.finding]]\nlevel = {}\nid = {}\ntext = {}", q(x.level.as_str()), q(x.id), q(&x.text));
        if !x.fix.is_empty() { let _ = writeln!(s, "fix = {}", q(&x.fix)); }
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gpu(vendor: &str, device: &str, driver: &str, gfx: u32) -> Gpu {
        Gpu { card: "card0".into(), vendor: vendor.into(), device: device.into(), driver: driver.into(),
              boot_vga: true, connected: 1, vram_mb: 2048, gfx, apu: false }
    }
    fn pc(ram_gb: u64, threads: usize) -> Platform {
        Platform { ram_mb: ram_gb * 1024, swap_mb: 4096, threads, x86_level: 3, uefi: true, ..Default::default() }
    }

    #[test]
    fn x86_levels() {
        let base = "flags\t: fpu lm cx8 sse sse2";
        assert_eq!(x86_level(base), 1);
        let v2 = format!("{base} cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3");
        assert_eq!(x86_level(&v2), 2);
        let v3 = format!("{v2} avx avx2 bmi1 bmi2 f16c fma abm movbe xsave");
        assert_eq!(x86_level(&v3), 3);
        assert_eq!(x86_level("flags\t: fpu sse"), 0);
    }

    #[test]
    fn amd_old_cards() {
        let si = gpu_family(&gpu("0x1002", "0x6798", "radeon", 0)).unwrap();   // HD 7970
        assert!(si.kernel_args.contains("si_support"));
        let cik = gpu_family(&gpu("0x1002", "0x67b1", "radeon", 0)).unwrap();  // R9 290
        assert!(cik.kernel_args.contains("cik_support"));
        let ts = gpu_family(&gpu("0x1002", "0x6739", "radeon", 0)).unwrap();   // HD 6850
        assert!(!ts.vulkan);
        let polaris = gpu_family(&gpu("0x1002", "0x6987", "amdgpu", 80003)).unwrap(); // RX 640 (latte-lab)
        assert_eq!(polaris.max_tier, "usporny");
    }

    #[test]
    fn nvidia_generations() {
        assert!(gpu_family(&gpu("0x10de", "0x1187", "nouveau", 0)).unwrap().name.contains("Kepler"));   // GTX 760
        assert!(gpu_family(&gpu("0x10de", "0x13c2", "nouveau", 0)).unwrap().name.contains("Maxwell"));  // GTX 970
        assert!(gpu_family(&gpu("0x10de", "0x1c03", "nvidia", 0)).unwrap().name.contains("Pascal"));    // GTX 1060
        assert!(gpu_family(&gpu("0x10de", "0x2504", "nvidia", 0)).unwrap().name.contains("Turing"));    // RTX 3060
        assert!(gpu_family(&gpu("0x10de", "0x0de1", "nouveau", 0)).unwrap().name.contains("Fermi"));    // GT 430
    }

    #[test]
    fn intel_generations() {
        assert!(gpu_family(&gpu("0x8086", "0x0126", "i915", 0)).unwrap().name.contains("Sandy"));
        assert!(gpu_family(&gpu("0x8086", "0x0412", "i915", 0)).unwrap().name.contains("Gen7"));        // HD 4600
        assert!(gpu_family(&gpu("0x8086", "0x5912", "i915", 0)).unwrap().name.contains("Gen9"));        // HD 630
    }

    #[test]
    fn caps() {
        let polaris = gpu_family(&gpu("0x1002", "0x6987", "amdgpu", 80003));
        assert_eq!(cap_tier("standard", polaris.as_ref(), &pc(16, 8)).0, "usporny");
        assert_eq!(cap_tier("plny", None, &pc(4, 8)).0, "usporny");
        assert_eq!(cap_tier("plny", None, &pc(16, 2)).0, "minimalny");
        assert_eq!(cap_tier("plny", None, &pc(32, 16)), ("plny", String::new()));
        assert_eq!(cap_tier("softver", None, &pc(2, 2)).0, "softver");
    }

    #[test]
    fn findings_radeon_si() {
        let v = check(&pc(8, 4), &[gpu("0x1002", "0x6798", "radeon", 0)], None);
        let a = v.iter().find(|x| x.id == "gpu-amdgpu").expect("rada amdgpu");
        assert!(a.fix.contains("amdgpu.si_support=1"));
        assert!(check(&pc(1, 4), &[], None).iter().any(|x| x.level == Level::Block));
    }
}
