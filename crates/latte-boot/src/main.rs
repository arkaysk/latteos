//! latte-boot — štart LatteOS: detekcia HW/SW, výber režimu NORMAL/SAFE, počítadlo pádov.
//!
//! Príkazy:
//!   probe                  vypíše rýchly test HW a grafiky (TOML)
//!   select [--dry-run]     rozhodne režim a zapíše /run/latteos/{mode.toml,session.env,hyprland.conf}
//!   session-start          (volá latte-session) zvýši počítadlo pádov NORMAL; exit 3 = prejdi do SAFE
//!   ok [--after S] [--require PROC]
//!                          relácia je zdravá → počítadlo = 0
//!   reset                  počítadlo = 0 a zruší „nabudúce SAFE“ (ponuka „skúsiť NORMAL“)
//!   force-safe             nabudúce naštartuj SAFE (jednorazovo)
//!   status                 vypíše aktuálny režim a počítadlo
//!
//! Cesty (pre testy bez roota): LATTE_RUN_DIR (/run/latteos), LATTE_STATE_DIR (/var/lib/latteos),
//! LATTE_CONF (/etc/latteos/boot.toml).

use latte_hw::{compat, q, Probe};
use std::env;
use std::fs;
use std::io::Write as _;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::ExitCode;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const EXIT_GO_SAFE: u8 = 3;

struct Paths {
    run: PathBuf,
    state: PathBuf,
    conf: PathBuf,
}

impl Paths {
    fn new() -> Self {
        let p = |k: &str, d: &str| PathBuf::from(env::var(k).unwrap_or_else(|_| d.to_string()));
        Paths {
            run: p("LATTE_RUN_DIR", "/run/latteos"),
            state: p("LATTE_STATE_DIR", "/var/lib/latteos"),
            conf: p("LATTE_CONF", "/etc/latteos/boot.toml"),
        }
    }
    fn crash_count(&self) -> PathBuf { self.state.join("crash-count") }
    fn force_safe(&self) -> PathBuf { self.state.join("force-safe") }
    fn mode_toml(&self) -> PathBuf { self.run.join("mode.toml") }
}

/// /etc/latteos/boot.toml — jednoduché `kľúč = hodnota`, bez sekcií.
struct Config {
    /// povoliť VMSVGA 3D (vm-3d) — experimentálne, ROADMAP F1
    allow_vm3d: bool,
    /// po koľkých pádoch NORMAL za sebou ide SAFE
    crash_limit: u32,
    /// po koľkých sekundách je relácia zdravá (`ok --after`)
    healthy_secs: u64,
}

impl Config {
    fn load(p: &Paths) -> Self {
        let mut c = Config { allow_vm3d: false, crash_limit: 2, healthy_secs: 60 };
        for line in fs::read_to_string(&p.conf).unwrap_or_default().lines() {
            let line = line.split('#').next().unwrap_or("").trim();
            let Some((k, v)) = line.split_once('=') else { continue };
            let v = v.trim().trim_matches('"');
            match k.trim() {
                "allow_vm3d" => c.allow_vm3d = v == "true",
                "crash_limit" => c.crash_limit = v.parse().unwrap_or(c.crash_limit),
                "healthy_secs" => c.healthy_secs = v.parse().unwrap_or(c.healthy_secs),
                _ => {}
            }
        }
        c
    }
}

#[derive(Debug)]
struct Decision {
    mode: &'static str,     // normal | safe
    renderer: &'static str, // hw | vm-3d | sw-gl | pixman
    tier: &'static str,     // plny | standard | usporny | minimalny (latte_hw::tier_for) | softver | safe
    reason: String,
}

fn safe(reason: impl Into<String>) -> Decision {
    Decision { mode: "safe", renderer: "pixman", tier: "safe", reason: reason.into() }
}

fn decide(p: &Probe, cfg: &Config, crashes: u32, force_safe: bool) -> Decision {
    let cm = &p.cmdline;
    if cm.mode.as_deref() == Some("safe") {
        return safe("vynútené parametrom kernelu latte.mode=safe");
    }
    if force_safe {
        return safe("vynútené: „nabudúce SAFE“");
    }
    let forced_normal = cm.mode.as_deref() == Some("normal");
    if !forced_normal && crashes >= cfg.crash_limit {
        return safe(format!("{crashes} pády relácie NORMAL za sebou (limit {})", cfg.crash_limit));
    }
    if cm.nomodeset {
        return safe("nomodeset: bez KMS ovládača grafiky");
    }
    if p.gpus.is_empty() {
        return safe("nenašla sa žiadna grafická karta (/sys/class/drm)");
    }
    let d = &p.egl_default;
    let sw = &p.egl_sw;
    let normal = |renderer, tier, reason: String| Decision { mode: "normal", renderer, tier, reason };
    // stupeň pre grafickú kartu (hlavná karta, inak prvá) — radar: Škálovanie hardvéru
    let hw = |reason: String| {
        let main = p.gpus.iter().find(|g| g.boot_vga).or(p.gpus.first());
        let (tier, mut why) = main.map(latte_hw::tier_for).unwrap_or(("standard", String::new()));
        // generácia karty a platforma (RAM, CPU) môžu stupeň znížiť: stará karta s veľkou VRAM, 4 GB RAM…
        let fam = main.and_then(compat::gpu_family);
        let (tier, cap) = compat::cap_tier(tier, fam.as_ref(), &p.platform);
        if !cap.is_empty() { why = format!("{why}, obmedzené na {tier}: {cap}"); }
        Decision { mode: "normal", renderer: "hw", tier, reason: if why.is_empty() { reason } else { format!("{reason}; stupeň: {why}") } }
    };

    match cm.renderer.as_deref() {
        Some("pixman") => return safe("vynútené latte.renderer=pixman"),
        Some("sw-gl") if sw.gles_at_least(3, 0) => return normal("sw-gl", "softver", "vynútené latte.renderer=sw-gl".into()),
        Some("vm-3d") if d.gles_at_least(3, 0) => return normal("vm-3d", "softver", "vynútené latte.renderer=vm-3d".into()),
        Some("hw") if d.gles_at_least(3, 0) => return hw("vynútené latte.renderer=hw".into()),
        _ => {}
    }

    // test vypršal (pomalý disk pri štarte), no karta má skutočný KMS ovládač: kompozitor to skúsi sám,
    // ako wlroots — padne až pri zlyhaní; pád relácie prepne na SAFE cez počítadlo pádov
    if d.timed_out && p.virt.is_none() {
        if let Some(g) = p.gpus.iter().find(|g| g.boot_vga && latte_hw::REAL_KMS.contains(&g.driver.as_str())) {
            return hw(format!("test grafiky vypršal ({} ms), používa sa ovládač {}; pád relácie → SAFE", d.millis, g.driver));
        }
    }
    if d.gles_at_least(3, 0) && !d.is_software() {
        if p.virt.is_none() {
            return hw(format!("HW akcelerácia: {} (GLES {}.{})", d.renderer, d.gles.0, d.gles.1));
        }
        if cfg.allow_vm3d {
            return normal("vm-3d", "softver", format!("VM 3D povolené v boot.toml: {}", d.renderer));
        }
    }
    if sw.gles_at_least(3, 0) {
        let why = match &p.virt {
            Some(v) if d.ok && !d.is_software() => format!("VM ({v}): 3D ({}) je experimentálne, použije sa llvmpipe", d.renderer),
            Some(v) => format!("VM ({v}): softvérové GL (llvmpipe)"),
            None => format!("bez HW GLES 3 ({}), softvérové GL", if d.ok { d.renderer.as_str() } else { "nedostupné" }),
        };
        return normal("sw-gl", "softver", why);
    }
    safe(format!("OpenGL ES 3 nedostupné ani softvérovo ({})", sw.error))
}

fn session_env(d: &Decision) -> String {
    let mut s = format!(
        "# vygeneroval latte-boot select — nemeniť ručne\nLATTE_MODE={}\nLATTE_RENDERER={}\nLATTE_TIER={}\n",
        d.mode, d.renderer, d.tier
    );
    match d.renderer {
        // llvmpipe pre kompozitor (GBM) aj klientov; LIBGL_ALWAYS_SOFTWARE na GBM nefunguje (ROADMAP F0)
        "sw-gl" => s.push_str("MESA_LOADER_DRIVER_OVERRIDE=kms_swrast\nLIBGL_ALWAYS_SOFTWARE=1\n"),
        "pixman" => s.push_str("WLR_RENDERER=pixman\nLIBGL_ALWAYS_SOFTWARE=1\n"),
        _ => {}
    }
    s
}

fn hyprland_conf(d: &Decision, virt: bool) -> String {
    let mut s = String::from("# vygeneroval latte-boot select — nemeniť ručne; načíta /usr/share/latteos/hypr/hyprland.conf\n");
    if virt || d.renderer != "hw" {
        s.push_str("cursor {\n    no_hardware_cursors = true\n}\n");
    }
    if d.tier == "softver" {
        s.push_str("# stupeň Softvér: každý pohyb stojí CPU → bez efektov\n");
        s.push_str("decoration {\n    blur {\n        enabled = false\n    }\n    shadow {\n        enabled = false\n    }\n}\n");
        s.push_str("animations {\n    enabled = false\n}\n");
    }
    if d.renderer == "vm-3d" {
        s.push_str("# vm-3d (experimentálne): bez commit_timing sa GL klienti na vmwgfx zasekávajú (setup/f1/RESULTS.md)\n");
        s.push_str("render {\n    commit_timing_enabled = false\n}\n");
    }
    s
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn read_u32(path: &PathBuf) -> u32 {
    fs::read_to_string(path).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0)
}

/// Zápis cez dočasný súbor + rename, práva 0664 (skupina `latte` môže zapisovať počítadlo).
fn write_atomic(path: &PathBuf, content: &str, mode: u32) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("tmp");
    {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(content.as_bytes())?;
        f.sync_all()?;
    }
    fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))?;
    fs::rename(&tmp, path)
}

fn current_mode(p: &Paths) -> String {
    fs::read_to_string(p.mode_toml())
        .unwrap_or_default()
        .lines()
        .find_map(|l| l.strip_prefix("mode = ").map(|v| v.trim_matches('"').to_string()))
        .unwrap_or_else(|| "safe".into())
}

fn ppid() -> u32 {
    // /proc/self/stat: "pid (comm) state ppid …" — comm môže obsahovať medzery, preto od poslednej ')'
    fs::read_to_string("/proc/self/stat")
        .ok()
        .and_then(|s| s.rsplit_once(')').map(|(_, r)| r.to_string()))
        .and_then(|r| r.split_whitespace().nth(1).and_then(|v| v.parse().ok()))
        .unwrap_or(0)
}

fn process_running(name: &str) -> bool {
    fs::read_dir("/proc").map(|rd| {
        rd.filter_map(|e| e.ok())
            .any(|e| fs::read_to_string(e.path().join("comm")).map(|c| c.trim() == name).unwrap_or(false))
    }).unwrap_or(false)
}

/// Neznáme hodnoty parametrov kernelu (preklep v GRUB): varovanie do záznamu, rozhodnutie ide ďalej automaticky.
fn cmdline_warnings(c: &latte_hw::Cmdline) -> Vec<String> {
    let mut w = Vec::new();
    if let Some(m) = c.mode.as_deref().filter(|m| !["safe", "normal"].contains(m)) {
        w.push(format!("neznáme latte.mode={m} (povolené: safe, normal) — ignorujem"));
    }
    if let Some(r) = c.renderer.as_deref().filter(|r| !["hw", "vm-3d", "sw-gl", "pixman"].contains(r)) {
        w.push(format!("neznáme latte.renderer={r} (povolené: hw, vm-3d, sw-gl, pixman) — ignorujem"));
    }
    w
}

fn cmd_select(p: &Paths, dry: bool) -> ExitCode {
    let cfg = Config::load(p);
    if latte_hw::wait_for_drm(Duration::from_secs(5)).is_none() {
        eprintln!("latte-boot: /dev/dri/card* sa neobjavilo do 5 s");
    }
    let probe = Probe::run();
    for w in cmdline_warnings(&probe.cmdline) {
        eprintln!("latte-boot: {w}");
    }
    let crashes = read_u32(&p.crash_count());
    let force = p.force_safe().exists();
    let d = decide(&probe, &cfg, crashes, force);

    let mut toml = String::from("# LatteOS — výsledok latte-boot select (jediné miesto pravdy pre greeter, reláciu a shell)\n[mode]\n");
    toml.push_str(&format!("mode = {}\nrenderer = {}\ntier = {}\nreason = {}\ndecided_at = {}\ncrash_count = {}\n\n",
        q(d.mode), q(d.renderer), q(d.tier), q(&d.reason), now(), crashes));
    toml.push_str(&probe.to_toml());
    toml.push('\n');
    toml.push_str(&compat::to_toml(&probe.platform, &probe.gpus, &compat::check(&probe.platform, &probe.gpus, probe.virt.as_deref())));

    println!("latte-boot: {} · {} · {} — {} ({} ms)", d.mode, d.renderer, d.tier, d.reason, probe.millis);
    if dry {
        print!("{toml}");
        return ExitCode::SUCCESS;
    }
    let res = write_atomic(&p.mode_toml(), &toml, 0o644)
        .and_then(|_| write_atomic(&p.run.join("session.env"), &session_env(&d), 0o644))
        .and_then(|_| write_atomic(&p.run.join("hyprland.conf"), &hyprland_conf(&d, probe.virt.is_some()), 0o644));
    if let Err(e) = res {
        eprintln!("latte-boot: zápis do {} zlyhal: {e}", p.run.display());
        return ExitCode::FAILURE;
    }
    if force {
        let _ = fs::remove_file(p.force_safe()); // „nabudúce SAFE“ platí len raz
    }
    ExitCode::SUCCESS
}

fn cmd_session_start(p: &Paths) -> ExitCode {
    if current_mode(p) != "normal" {
        return ExitCode::SUCCESS;
    }
    let cfg = Config::load(p);
    let prev = read_u32(&p.crash_count());
    if prev >= cfg.crash_limit {
        println!("latte-boot: {prev} pády NORMAL za sebou → SAFE");
        return ExitCode::from(EXIT_GO_SAFE);
    }
    if let Err(e) = write_atomic(&p.crash_count(), &format!("{}\n", prev + 1), 0o664) {
        eprintln!("latte-boot: počítadlo pádov sa nedá zapísať ({e}); pokračujem");
    }
    ExitCode::SUCCESS
}

fn cmd_ok(p: &Paths, args: &[String]) -> ExitCode {
    let cfg = Config::load(p);
    let mut after = 0u64;
    let mut require: Option<String> = None;
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--after" => after = it.next().and_then(|v| v.parse().ok()).unwrap_or(cfg.healthy_secs),
            "--require" => require = it.next().cloned(),
            _ => {}
        }
    }
    // rodič = kompozitor, ktorý `ok` spustil (exec-once). Ak medzitým spadne, `ok` ostane sirotou
    // (nový rodič) a nesmie vynulovať počítadlo, hoci by napr. Noctalia bežala už v relácii SAFE.
    let parent = ppid();
    thread::sleep(Duration::from_secs(after));
    if after > 0 && ppid() != parent {
        println!("latte-boot ok: kompozitor (pid {parent}) medzitým skončil → relácia nie je zdravá");
        return ExitCode::FAILURE;
    }
    if let Some(name) = &require {
        if !process_running(name) {
            println!("latte-boot ok: {name} nebeží → relácia nie je zdravá, počítadlo ostáva");
            return ExitCode::FAILURE;
        }
    }
    if current_mode(p) == "normal" {
        if let Err(e) = write_atomic(&p.crash_count(), "0\n", 0o664) {
            eprintln!("latte-boot ok: {e}");
            return ExitCode::FAILURE;
        }
        println!("latte-boot ok: relácia NORMAL zdravá, počítadlo = 0");
    }
    ExitCode::SUCCESS
}

fn cmd_status(p: &Paths) -> ExitCode {
    match fs::read_to_string(p.mode_toml()) {
        Ok(s) => print!("{}", s.split("[probe]").next().unwrap_or(&s)),
        Err(_) => println!("{} neexistuje (latte-boot select ešte nebežal)", p.mode_toml().display()),
    }
    println!("# stav\ncrash_count_now = {}\nforce_safe = {}", read_u32(&p.crash_count()), p.force_safe().exists());
    ExitCode::SUCCESS
}

/// `latte-boot compat`: kontrola hardvéru pre inštalátor, Device Manager a podporu (bez testu EGL, ~5 ms).
/// Návratový kód: 0 = v poriadku alebo iba rady, 1 = obmedzenia (warn), 2 = nepodporovaný HW (block).
fn cmd_compat(as_toml: bool) -> ExitCode {
    let pf = compat::Platform::read();
    let gpus = latte_hw::gpus();
    let virt = latte_hw::virtualization();
    let found = compat::check(&pf, &gpus, virt.as_deref());
    if as_toml {
        print!("{}", compat::to_toml(&pf, &gpus, &found));
    } else {
        println!("CPU:   {} · vlákna: {} · x86-64-v{}", pf.cpu_model, pf.threads, pf.x86_level);
        println!("RAM:   {} MB, swap/zram {} MB", pf.ram_mb, pf.swap_mb);
        println!("Disk:  {} · voľné {} GB", if pf.root_hdd { "HDD (rotačný)" } else { "SSD/NVMe" }, pf.root_free_gb);
        println!("Štart: {}{}{}", if pf.uefi { "UEFI" } else { "BIOS (legacy)" }, if pf.secure_boot { " · Secure Boot" } else { "" },
                 virt.as_deref().map(|v| format!(" · VM {v}")).unwrap_or_default());
        for g in &gpus {
            match compat::gpu_family(g) {
                Some(f) => println!("GPU:   {} [{}:{} {}] ~{} · ovládač {} · Vulkan {} · najviac stupeň {}",
                                    f.name, g.vendor, g.device, g.driver, f.year, f.driver, if f.vulkan { "áno" } else { "nie" }, f.max_tier),
                None => println!("GPU:   {}:{} {} (generácia neznáma, rozhodne test EGL)", g.vendor, g.device, g.driver),
            }
        }
        let (cap, why) = compat::platform_cap(&pf);
        if !why.is_empty() { println!("Stupeň platformy: najviac {cap} ({why})"); }
        for x in &found {
            println!("[{}] {}{}", x.level.as_str(), x.text, if x.fix.is_empty() { String::new() } else { format!("\n       → {}", x.fix) });
        }
        if found.is_empty() { println!("Všetko v poriadku."); }
    }
    match found.iter().map(|x| x.level).max() {
        Some(compat::Level::Block) => ExitCode::from(2),
        Some(compat::Level::Warn) => ExitCode::from(1),
        _ => ExitCode::SUCCESS,
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let p = Paths::new();
    match args.first().map(String::as_str) {
        Some("probe") => {
            print!("{}", Probe::run().to_toml());
            ExitCode::SUCCESS
        }
        Some("select") => cmd_select(&p, args.iter().any(|a| a == "--dry-run")),
        Some("session-start") => cmd_session_start(&p),
        Some("ok") => cmd_ok(&p, &args[1..]),
        Some("reset") => {
            let _ = fs::remove_file(p.force_safe());
            match write_atomic(&p.crash_count(), "0\n", 0o664) {
                Ok(_) => { println!("latte-boot: počítadlo = 0, ďalší štart skúsi NORMAL"); ExitCode::SUCCESS }
                Err(e) => { eprintln!("latte-boot reset: {e}"); ExitCode::FAILURE }
            }
        }
        Some("force-safe") => match write_atomic(&p.force_safe(), "1\n", 0o664) {
            Ok(_) => { println!("latte-boot: ďalší štart bude SAFE"); ExitCode::SUCCESS }
            Err(e) => { eprintln!("latte-boot force-safe: {e}"); ExitCode::FAILURE }
        },
        Some("status") => cmd_status(&p),
        Some("compat") => cmd_compat(args.iter().any(|a| a == "--toml")),
        _ => {
            eprintln!("použitie: latte-boot probe | select [--dry-run] | session-start | ok [--after S] [--require PROC] | reset | force-safe | status | compat [--toml]");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use latte_hw::{Cmdline, Egl, Gpu};

    #[test]
    fn neplatne_parametre_kernelu_sa_ohlasia() {
        assert!(cmdline_warnings(&Cmdline::parse("latte.mode=safe latte.renderer=hw")).is_empty());
        let w = cmdline_warnings(&Cmdline::parse("latte.mode=neplatny latte.renderer=vulkan"));
        assert_eq!(w.len(), 2);
        assert!(w[0].contains("latte.mode=neplatny"));
    }

    fn egl(renderer: &str, gles: (u32, u32)) -> Egl {
        Egl { ok: true, renderer: renderer.into(), gles, ..Default::default() }
    }
    fn probe(virt: Option<&str>, d: Egl, sw: Egl, cmdline: &str) -> Probe {
        Probe {
            cmdline: Cmdline::parse(cmdline),
            virt: virt.map(String::from),
            gpus: vec![Gpu { card: "card0".into(), vendor: "0x15ad".into(), device: "0x0405".into(), driver: "vmwgfx".into(), boot_vga: true, connected: 1, vram_mb: 0, gfx: 0, apu: false }],
            egl_default: d,
            egl_sw: sw,
            platform: Default::default(),
            millis: 1,
        }
    }
    fn cfg() -> Config { Config { allow_vm3d: false, crash_limit: 2, healthy_secs: 60 } }
    fn vbox() -> Probe { probe(Some("virtualbox"), egl("SVGA3D; build: RELEASE;", (3, 0)), egl("llvmpipe (LLVM 22)", (3, 2)), "") }

    #[test]
    fn virtualbox_default_is_swgl() {
        let d = decide(&vbox(), &cfg(), 0, false);
        assert_eq!((d.mode, d.renderer, d.tier), ("normal", "sw-gl", "softver"));
    }

    #[test]
    fn virtualbox_vm3d_when_allowed() {
        let d = decide(&vbox(), &Config { allow_vm3d: true, ..cfg() }, 0, false);
        assert_eq!(d.renderer, "vm-3d");
    }

    #[test]
    fn crashes_go_safe() {
        assert_eq!(decide(&vbox(), &cfg(), 2, false).mode, "safe");
        assert_eq!(decide(&vbox(), &cfg(), 1, false).mode, "normal");
    }

    #[test]
    fn forced_normal_ignores_crashes() {
        let mut p = vbox();
        p.cmdline = Cmdline::parse("latte.mode=normal");
        assert_eq!(decide(&p, &cfg(), 5, false).mode, "normal");
    }

    #[test]
    fn cmdline_and_flag_force_safe() {
        let mut p = vbox();
        p.cmdline = Cmdline::parse("latte.mode=safe");
        assert_eq!(decide(&p, &cfg(), 0, false).mode, "safe");
        assert_eq!(decide(&vbox(), &cfg(), 0, true).mode, "safe");
        let mut n = vbox();
        n.cmdline = Cmdline::parse("nomodeset");
        assert_eq!(decide(&n, &cfg(), 0, false).mode, "safe");
    }

    #[test]
    fn timeout_on_real_gpu_goes_normal_hw() {
        let mut p = probe(None, Egl { timed_out: true, error: "eglinfo: timeout 10000 ms".into(), millis: 10000, ..Default::default() }, Egl::default(), "");
        p.gpus[0].driver = "amdgpu".into();
        let d = decide(&p, &cfg(), 0, false);
        assert_eq!((d.mode, d.renderer), ("normal", "hw"));
        assert_eq!(decide(&p, &cfg(), 2, false).mode, "safe"); // pády stále vyhrajú
    }

    #[test]
    fn timeout_without_real_gpu_stays_safe() {
        let p = probe(None, Egl { timed_out: true, ..Default::default() }, Egl::default(), ""); // vmwgfx
        assert_eq!(decide(&p, &cfg(), 0, false).mode, "safe");
    }

    #[test]
    fn real_hw_uses_gpu() {
        let mut p = probe(None, egl("AMD Radeon RX 6700 XT", (3, 2)), egl("llvmpipe", (3, 2)), "");
        p.gpus[0] = Gpu { card: "card1".into(), vendor: "0x1002".into(), device: "0x73df".into(), driver: "amdgpu".into(),
                          boot_vga: true, connected: 1, vram_mb: 12272, gfx: 100301, apu: false };
        let d = decide(&p, &cfg(), 0, false);
        assert_eq!((d.renderer, d.tier), ("hw", "plny"));
    }

    fn amd(gfx: u32, vram_mb: u64, apu: bool) -> Gpu {
        Gpu { card: "card1".into(), vendor: "0x1002".into(), device: "0x6987".into(), driver: "amdgpu".into(),
              boot_vga: true, connected: 1, vram_mb, gfx, apu }
    }

    #[test]
    fn tiers_follow_radar_table() {
        assert_eq!(latte_hw::tier_for(&amd(80003, 4096, false)).0, "usporny");   // RX 550/640 (latte-lab)
        assert_eq!(latte_hw::tier_for(&amd(100302, 8192, false)).0, "standard"); // RX 6600
        assert_eq!(latte_hw::tier_for(&amd(110000, 24576, false)).0, "plny");    // RX 7900 XTX
        assert_eq!(latte_hw::tier_for(&amd(90012, 512, true)).0, "minimalny");   // Renoir APU
        let nv = |d: &str| Gpu { vendor: "0x10de".into(), device: d.into(), driver: "nvidia".into(), ..amd(0, 0, false) };
        assert_eq!(latte_hw::tier_for(&nv("0x1c03")).0, "usporny");              // GTX 1060
        assert_eq!(latte_hw::tier_for(&nv("0x2504")).0, "standard");             // RTX 3060
        assert!(latte_hw::tier_for(&amd(80003, 4096, false)).1.contains("gfx803"));
    }

    #[test]
    fn weak_platform_lowers_tier() {
        let mut p = probe(None, egl("AMD Radeon RX 6600", (3, 2)), Egl::default(), "");
        p.gpus[0] = amd(100302, 8192, false);
        p.platform = compat::Platform { ram_mb: 4096, threads: 4, x86_level: 3, ..Default::default() };
        let d = decide(&p, &cfg(), 0, false);
        assert_eq!((d.renderer, d.tier), ("hw", "usporny"));
        assert!(d.reason.contains("4 GB RAM"), "{}", d.reason);
    }

    #[test]
    fn nothing_works_is_safe() {
        let p = probe(None, Egl::default(), Egl::default(), "");
        assert_eq!(decide(&p, &cfg(), 0, false).mode, "safe");
    }

    #[test]
    fn env_for_renderers() {
        let d = decide(&vbox(), &cfg(), 0, false);
        assert!(session_env(&d).contains("MESA_LOADER_DRIVER_OVERRIDE=kms_swrast"));
        assert!(session_env(&safe("x")).contains("WLR_RENDERER=pixman"));
        assert!(hyprland_conf(&d, true).contains("no_hardware_cursors = true"));
    }
}
