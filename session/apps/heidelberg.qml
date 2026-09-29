// LatteOS — Heidelberg, editor dokumentov (old/IDEAS.md: „originálny LatteOS editor dokumentov“).
// Dva režimy podľa súboru:
//   Dokument   (docx, odt, rtf, epub, html a nový dokument) — WYSIWYG: písmo a veľkosť, B I U S, farba,
//              zarovnanie, nadpisy, zoznamy; strana A4/A5/Letter s okrajmi ako na papieri (príprava na tlač).
//              docx/odt/rtf/epub sa otvárajú a ukladajú cez pandoc (originál sa pri prvom uložení zazálohuje
//              ako „súbor~“); vlastný formát bez strát je HTML.
//   Text       (md, txt) — zdroj vľavo, náhľad vpravo, formátovanie značkami Markdownu.
// Spoločné: Kontrola textu (hunspell: preklepy s návrhmi, zdvojené slová, medzery), Export DOCX/ODT/EPUB/HTML/PDF,
// Tlač (PDF podľa nastavenia strany → lp, inak prehliadač PDF), Ctrl+S, Ctrl+N, Ctrl+F7 kontrola.
// PDF robí weasyprint (doinštaluje sa pri prvom použití). PDF sa otvára na úpravu cez pdftohtml (poppler-utils)
// a ukladá sa vedľa ako „názov (upravené).html“ — originál ostáva. Spúšťa sa: latte-app heidelberg [súbor]
import QtQuick
import Quickshell
import Quickshell.Io
import "common"

ShellRoot {
    id: app
    LatteTheme { id: theme }

    readonly property string home: Quickshell.env("HOME") || "/"
    readonly property string docsDir: home + "/Dokumenty"
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string recentFile: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/latteos/heidelberg-recent.json"
    readonly property string prefsFile: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/latteos/heidelberg.json"
    property string path: (Quickshell.env("LATTE_APP_ARGS") || "").trim().replace(/^file:\/\//, "")
    property string savedText: ""
    property bool dirty: editor.text !== savedText
    property string status: ""
    property var recent: []
    property var docs: []
    property bool preview: true
    property bool newRich: true                // nový dokument = Dokument (HTML); Ctrl+Shift+N = poznámka Markdown
    readonly property string ext: path === "" ? (newRich ? "html" : "md") : ((path.match(/\.([^./]+)$/) || [, "md"])[1].toLowerCase())
    readonly property bool isDoc: ["docx", "odt", "rtf", "epub", "doc"].indexOf(ext) >= 0   // cez pandoc
    readonly property bool isPdf: ext === "pdf"                                               // cez pdftohtml (poppler)
    readonly property bool rich: isDoc || isPdf || ext === "html" || ext === "htm"
    property bool hasPoppler: true
    property bool suppressLoad: false
    readonly property string kind: rich ? "html" : (ext === "md" || ext === "markdown" ? "md" : "txt")
    property bool hasPandoc: true
    property bool hasPdf: false
    property bool hasLp: false
    property bool backedUp: false
    readonly property string plain: editor.getText(0, editor.length)
    readonly property int words: plain.trim() === "" ? 0 : plain.trim().split(/\s+/).length

    // ── strana (príprava na tlač) ───────────────────────────────────────────────
    property string pageSize: "A4"             // A4 | A5 | Letter
    property bool landscape: false
    property int marginMm: 25
    property real zoom: 1.0
    readonly property var pageMm: ({ A4: [210, 297], A5: [148, 210], Letter: [216, 279] })[pageSize] || [210, 297]
    readonly property real mmPx: 96 / 25.4 * zoom
    readonly property real pageW: (landscape ? pageMm[1] : pageMm[0]) * mmPx
    readonly property real pageH: (landscape ? pageMm[0] : pageMm[1]) * mmPx
    FileView {
        id: prefs; path: app.prefsFile; printErrors: false
        onLoaded: { try { const j = JSON.parse(text()); app.pageSize = j.pageSize || "A4"; app.landscape = !!j.landscape; app.marginMm = j.marginMm || 25; app.zoom = j.zoom || 1.0; } catch (e) {} }
    }
    function savePrefs() { prefs.setText(JSON.stringify({ pageSize: pageSize, landscape: landscape, marginMm: marginMm, zoom: zoom })); }

    Process { id: popplerCheck; running: true; command: ["sh", "-c", "command -v pdftohtml"]; onExited: (code) => app.hasPoppler = code === 0 }
    // PDF → HTML na úpravu: text, tučné, zlomy strán; zlomy riadkov uprostred viet sa spoja do odsekov
    Process {
        id: pdfLoad
        stdout: StdioCollector {
            onStreamFinished: {
                let b = this.text.replace(/^[\s\S]*<body[^>]*>/i, "").replace(/<\/body>[\s\S]*$/i, "");
                b = b.replace(/&#160;/g, " ").replace(/<a name=\d+><\/a>/g, "")
                     .replace(/([^.!?:>])<br\/>\n(?=[a-zà-ž0-9(„"])/g, "$1 ");
                editor.text = "<p>" + b.replace(/<br\/>\n/g, "</p><p>") + "</p>";
                app.savedText = "";
                app.status = "PDF na úpravu · uloží sa vedľa ako .html";
                app.remember(app.path);
            }
        }
        onExited: (code) => { if (code !== 0) app.status = "PDF sa nepodarilo otvoriť (možno je iba obrázkový/skenovaný)"; }
    }
    function loadPdf() {
        if (!hasPoppler) { status = "Na PDF treba poppler-utils — tlačidlo Doinštalovať hore"; editor.text = ""; savedText = ""; return; }
        pdfLoad.command = ["pdftohtml", "-stdout", "-noframes", "-i", "-q", path];
        pdfLoad.running = true;
    }
    Process { id: pandocCheck; running: true; command: ["sh", "-c", "command -v pandoc"]; onExited: (code) => app.hasPandoc = code === 0 }
    Process { id: toolCheck; running: true; command: ["sh", "-c", "command -v weasyprint >/dev/null && echo pdf; command -v lp >/dev/null && echo lp"]
              stdout: StdioCollector { onStreamFinished: { app.hasPdf = this.text.includes("pdf"); app.hasLp = this.text.includes("lp"); } } }

    // dokumenty (docx, odt…) → HTML na úpravu
    Process {
        id: docLoad
        stdout: StdioCollector {
            onStreamFinished: { editor.text = this.text; app.savedText = editor.text; app.status = "Otvorené cez pandoc"; app.remember(app.path); }
        }
        onExited: (code) => { if (code !== 0) app.status = "Dokument sa nepodarilo otvoriť (pandoc, kód " + code + ")"; }
    }
    function loadDoc() {
        if (!hasPandoc) { status = "Na " + ext.toUpperCase() + " treba pandoc — tlačidlo Doinštalovať hore"; editor.text = ""; savedText = ""; return; }
        docLoad.command = ["pandoc", path, "-t", "html", "--wrap=none"];
        docLoad.running = true;
    }
    Timer { id: pandocWait; interval: 300; onTriggered: app.loadDoc() }     // počkať na kontrolu pandocu
    FileView { id: tmpSrc; path: app.runDir + "/heidelberg-" + Qt.md5(app.path || "novy") + (app.rich ? ".html" : ".md"); printErrors: false; atomicWrites: true }
    FileView { id: tmpPage; path: app.runDir + "/heidelberg-" + Qt.md5(app.path || "novy") + "-strana.html"; printErrors: false; atomicWrites: true }
    Process {
        id: docSave
        property string after: ""              // "print" = po PDF tlačiť
        property string out: ""
        onExited: (code) => {
            if (code !== 0) { app.status = "Nepodarilo sa (kód " + code + ")"; return; }
            if (after === "print") { app.printPdf(out); return; }
            app.status = "Uložené · " + out.split("/").pop() + " · " + Qt.formatTime(new Date(), "HH:mm");
        }
    }
    // HTML strany pre PDF: veľkosť a okraje z nastavenia strany, písmo LatteOS
    function pageHtml(body) {
        const css = "@page { size: " + pageSize + (landscape ? " landscape" : "") + "; margin: " + marginMm + "mm; } "
                  + "body { font-family: 'Manrope', sans-serif; font-size: 11pt; line-height: 1.45; color: #111; } "
                  + "h1, h2, h3 { font-family: 'Fraunces', serif; } img { max-width: 100%; }";
        const inner = String(body).replace(/^[\s\S]*<body[^>]*>/i, "").replace(/<\/body>[\s\S]*$/i, "");
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>" + css + "</style></head><body>" + inner + "</body></html>";
    }
    Process { id: mdHtml; property string out: ""; property string after: ""
              stdout: StdioCollector { onStreamFinished: { tmpPage.setText(app.pageHtml(this.text)); docSave.out = mdHtml.out; docSave.after = mdHtml.after;
                                                           docSave.command = ["weasyprint", tmpPage.path, mdHtml.out]; docSave.running = true; } } }
    function exportAs(fmt, after) {
        const baseName = path ? path.replace(/\.[^./]+$/, "") : docsDir + "/Dokument " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH-mm");
        const out = after === "print" ? runDir + "/heidelberg-tlac.pdf" : baseName + "." + fmt;
        if (fmt === "pdf") {
            if (!hasPdf) { status = "PDF a tlač potrebujú weasyprint — tlačidlo Doinštalovať PDF hore"; return; }
            status = after === "print" ? "Pripravujem tlač…" : "Exportujem PDF…";
            if (rich) { tmpPage.setText(pageHtml(editor.text)); docSave.out = out; docSave.after = after || ""; docSave.command = ["weasyprint", tmpPage.path, out]; docSave.running = true; }
            else { tmpSrc.setText(editor.text); mdHtml.out = out; mdHtml.after = after || ""; mdHtml.command = ["pandoc", "-f", kind === "md" ? "markdown" : "markdown", tmpSrc.path, "-t", "html"]; mdHtml.running = true; }
            return;
        }
        if (!hasPandoc) { status = "Export potrebuje pandoc — Doinštalovať"; return; }
        tmpSrc.setText(editor.text);
        docSave.out = out; docSave.after = "";
        docSave.command = ["pandoc", "-f", rich ? "html" : "markdown", tmpSrc.path, "-s", "-o", out];
        docSave.running = true;
        status = "Exportujem do " + out.split("/").pop() + "…";
    }
    Process { id: printer; onExited: (code) => app.status = code === 0 ? "Odoslané na tlačiareň" : "Tlač zlyhala (lp, kód " + code + ")" }
    function printPdf(pdf) {
        if (hasLp) { printer.command = ["lp", pdf]; printer.running = true; status = "Tlačím…"; }
        else { run(["xdg-open", pdf]); status = "Tlačiareň nie je nastavená: PDF je otvorené v prehliadači, tlač tam cez Ctrl+P"; }
    }
    FileView {
        id: doc
        path: app.isDoc || app.isPdf ? "" : app.path
        printErrors: false
        blockLoading: true
        onLoaded: { editor.text = text(); app.savedText = editor.text; app.status = "Otvorené"; app.remember(app.path); }
        onLoadFailed: { if (app.suppressLoad) { app.suppressLoad = false; return; } if (app.path !== "") { editor.text = ""; app.savedText = ""; app.status = "Nový súbor"; } }
    }
    FileView {
        id: recentView
        path: app.recentFile; printErrors: false
        onLoaded: { try { app.recent = JSON.parse(text()); } catch (e) { app.recent = []; } }
    }
    function remember(p) {
        if (!p) return;
        recent = [p].concat(recent.filter(x => x !== p)).slice(0, 8);
        recentView.setText(JSON.stringify(recent));
    }
    Process {
        id: docsProc; running: true
        command: ["sh", "-c", "mkdir -p \"$1\"; ls -t \"$1\"/*.md \"$1\"/*.txt \"$1\"/*.html \"$1\"/*.docx \"$1\"/*.odt 2>/dev/null | head -20", "sh", app.docsDir]
        stdout: StdioCollector { onStreamFinished: app.docs = this.text.split("\n").filter(l => l !== "") }
    }
    Process { id: runner }
    function run(cmd) { runner.command = cmd; runner.running = true; }

    function open(p) {
        if (dirty && !confirmDiscard) { confirmDiscard = true; pendingOpen = p; status = "Neuložené zmeny! Klikni znova pre zahodenie, alebo Ctrl+S."; return; }
        confirmDiscard = false;
        path = p; backedUp = false; issues = [];
        if (isPdf) loadPdf(); else if (isDoc) loadDoc(); else doc.reload();
    }
    property bool confirmDiscard: false
    property string pendingOpen: ""
    function save() {
        if (path === "") path = docsDir + "/Dokument " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH-mm") + (newRich ? ".html" : ".md");
        if (isPdf) {                 // PDF sa neprepisuje: upravená verzia ide vedľa ako dokument Heidelbergu
            suppressLoad = true;
            path = path.replace(/\.pdf$/i, " (upravené).html");
            status = "Uložené ako " + path.split("/").pop() + " · PDF: Export PDF";
        }
        if (isDoc) {
            if (!hasPandoc) { status = "Uloženie do " + ext.toUpperCase() + " potrebuje pandoc"; return; }
            tmpSrc.setText(editor.text);
            const backup = backedUp ? "" : "cp -n -- \"$3\" \"$3~\" 2>/dev/null; ";
            docSave.out = path; docSave.after = "";
            docSave.command = ["sh", "-c", backup + "pandoc -f html \"$1\" -o \"$2\"", "sh", tmpSrc.path, path, path];
            docSave.running = true; backedUp = true; savedText = editor.text;
            remember(path); return;
        }
        doc.setText(editor.text);
        savedText = editor.text;
        status = "Uložené · " + Qt.formatTime(new Date(), "HH:mm");
        remember(path);
        docsProc.running = true;
    }
    function newDoc(asRich) {
        if (dirty && !confirmDiscard) { confirmDiscard = true; pendingOpen = ""; status = "Neuložené zmeny! Ctrl+N znova pre zahodenie."; return; }
        confirmDiscard = false;
        newRich = asRich; path = ""; editor.text = ""; savedText = ""; issues = [];
        status = asRich ? "Nový dokument (uloží sa do Dokumentov ako HTML, export do DOCX/ODT/PDF)" : "Nová poznámka (Markdown)";
    }

    // ── formátovanie ────────────────────────────────────────────────────────────
    // Text (Markdown): obalí výber značkami
    function wrap(a, b) {
        const s = editor.selectionStart, e = editor.selectionEnd, t = editor.selectedText || "text";
        editor.remove(s, e); editor.insert(s, a + t + b);
        editor.select(s + a.length, s + a.length + t.length); editor.forceActiveFocus();
    }
    function linePrefix(p) {
        const pos = editor.cursorPosition, txt = editor.text;
        const start = txt.lastIndexOf("\n", pos - 1) + 1;
        editor.insert(start, p); editor.forceActiveFocus();
    }
    // Dokument (WYSIWYG): výber sa nahradí rovnakým obsahom obaleným HTML značkou (TextEdit ho vloží ako formát)
    function fragment(s, e) {
        const h = editor.getFormattedText(s, e);
        const m = h.match(/<!--StartFragment-->([\s\S]*)<!--EndFragment-->/);
        return m ? m[1] : h.replace(/^[\s\S]*<body[^>]*>/i, "").replace(/<\/body>[\s\S]*$/i, "");
    }
    function selectWordIfEmpty() {
        if (editor.selectionStart !== editor.selectionEnd) return true;
        const t = plain, p = editor.cursorPosition;
        let a = p, b = p;
        while (a > 0 && /[A-Za-z0-9À-ɏ]/.test(t[a - 1])) a--;
        while (b < t.length && /[A-Za-z0-9À-ɏ]/.test(t[b])) b++;
        if (a === b) return false;
        editor.select(a, b); return true;
    }
    function inline(open, close) {
        if (!selectWordIfEmpty()) return;
        const s = editor.selectionStart, e = editor.selectionEnd;
        const f = fragment(s, e);
        editor.remove(s, e); editor.insert(s, open + f + close);
        editor.select(s, e); editor.forceActiveFocus();
    }
    // blokové: celé odseky pod výberom
    function block(open, close) {
        const t = plain;
        let s = editor.selectionStart, e = editor.selectionEnd;
        while (s > 0 && t[s - 1] !== "\n" && t[s - 1] !== "\u2029") s--;
        while (e < t.length && t[e] !== "\n" && t[e] !== "\u2029") e++;
        const inner = fragment(s, e).replace(/<\/?(p|h[1-6]|li|ul|ol|div)[^>]*>/gi, "").replace(/<br\s*\/?>/gi, "</p><p>");
        editor.remove(s, e); editor.insert(s, open + inner + close);
        editor.cursorPosition = Math.min(s + (e - s), editor.length); editor.forceActiveFocus();
    }
    function clearFormat() {
        if (!selectWordIfEmpty()) return;
        const s = editor.selectionStart, e = editor.selectionEnd;
        const t = editor.getText(s, e).replace(/&/g, "&amp;").replace(/</g, "&lt;");
        editor.remove(s, e); editor.insert(s, t); editor.select(s, e);
    }
    // kontextová ponuka textu (ako vo Worde): úpravy, formát, návrhy pre slovo pod kurzorom
    property string menuWord: ""
    Process {
        id: wordCheck
        property real mx: 0; property real my: 0
        stdout: StdioCollector {
            onStreamFinished: {
                const m = this.text.match(/^& \S+ \d+ \d+: (.*)$/m);
                const ok = /^\*/m.test(this.text);
                const items = [];
                if (m) for (const sgg of m[1].split(", ").slice(0, 6))
                    items.push({ glyph: "check", label: sgg, action: () => app.replaceWord(sgg) });
                else items.push({ glyph: "check", label: ok ? "„" + app.menuWord + "“ je správne" : "Bez návrhov", enabled: false, action: () => {} });
                items.push({ separator: true });
                items.push({ glyph: "books", label: "Pridať „" + app.menuWord + "“ do slovníka", action: () => app.addWord(app.menuWord) });
                ctx.replace(items, "Pravopis · " + app.menuWord);
            }
        }
    }
    function replaceWord(w) {
        const s0 = editor.selectionStart, e0 = editor.selectionEnd;
        if (s0 === e0) return;
        editor.remove(s0, e0); editor.insert(s0, w); editor.select(s0, s0 + w.length);
    }
    function editMenu(x, y) {
        const hasSel = editor.selectionStart !== editor.selectionEnd;
        menuWord = hasSel ? editor.selectedText.trim() : "";
        const items = [
            { glyph: "copy", label: "Vystrihnúť", hint: "Ctrl+X", enabled: hasSel, action: () => editor.cut() },
            { glyph: "copy", label: "Kopírovať", hint: "Ctrl+C", enabled: hasSel, action: () => editor.copy() },
            { glyph: "clipboard", label: "Vložiť", hint: "Ctrl+V", enabled: editor.canPaste, action: () => editor.paste() },
            { glyph: "check", label: "Vybrať všetko", hint: "Ctrl+A", action: () => editor.selectAll() },
            { separator: true },
            { glyph: "pencil", label: "Tučné", hint: "Ctrl+B", enabled: hasSel, action: () => app.fmt("b") },
            { glyph: "pencil", label: "Kurzíva", hint: "Ctrl+I", enabled: hasSel, action: () => app.fmt("i") }
        ];
        if (rich) items.push({ glyph: "x", label: "Vymazať formát", enabled: hasSel, action: () => app.clearFormat() });
        if (hasSel && /^[A-Za-z\u00C0-\u024F]+$/.test(menuWord)) {
            items.push({ separator: true });
            items.push({ glyph: "list-check", label: "Pravopis: návrhy pre „" + menuWord + "“", keepOpen: true, action: () => {
                wordCheck.command = ["sh", "-c", 'printf "^%s\\n" "$1" | hunspell -d "$2" -p "$3" -a', "sh", app.menuWord, app.lang, app.dictFile]; wordCheck.running = true; } });
            items.push({ glyph: "search", label: "Hľadať „" + menuWord + "“ na webe", action: () => Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent(menuWord)) });
        }
        ctx.open(x, y, items, "");
    }
    // pravý klik na dokument v bočnom paneli
    function docMenu(it, x, y) {
        if (!it.key.startsWith("doc:")) return;
        const p = it.key.slice(4);
        ctx.open(x, y, [
            { glyph: "external-link", label: "Otvoriť", action: () => app.open(p) },
            { glyph: "folder", label: "Otvoriť priečinok v Súboroch", action: () => app.run(["latte-app", "subory", p.substring(0, p.lastIndexOf("/"))]) },
            { glyph: "clipboard", label: "Kopírovať cestu", action: () => app.run(["wl-copy", "--", p]) },
            { separator: true },
            { glyph: "history", label: "Odstrániť z nedávnych", enabled: app.recent.indexOf(p) >= 0, action: () => { app.recent = app.recent.filter(x => x !== p); recentView.setText(JSON.stringify(app.recent)); } },
            { glyph: "trash", label: "Presunúť do koša", danger: true, action: () => { app.run(["latte-kos", "vyhod", p]); app.recent = app.recent.filter(x => x !== p); recentView.setText(JSON.stringify(app.recent)); docsProc.running = true; } }
        ], it.label);
    }
    function fmt(what) {
        if (rich) {
            const m = { b: ["<b>", "</b>"], i: ["<i>", "</i>"], u: ["<u>", "</u>"], s: ["<s>", "</s>"], c: ["<code>", "</code>"], a: ["<a href=\"https://\">", "</a>"] };
            if (m[what]) inline(m[what][0], m[what][1]);
            else if (what === "h") block("<h2>", "</h2>");
            else if (what === "h1") block("<h1>", "</h1>");
            else if (what === "h3") block("<h3>", "</h3>");
            else if (what === "p") block("<p>", "</p>");
            else if (what === "l") block("<ul><li>", "</li></ul>");
            else if (what === "n") block("<ol><li>", "</li></ol>");
            else if (what === "q") block("<blockquote>", "</blockquote>");
            return;
        }
        if (what === "b") wrap("**", "**");
        else if (what === "i") wrap("*", "*");
        else if (what === "s") wrap("~~", "~~");
        else if (what === "h" || what === "h1" || what === "h3") linePrefix(what === "h1" ? "# " : (what === "h3" ? "### " : "## "));
        else if (what === "l") linePrefix("- ");
        else if (what === "n") linePrefix("1. ");
        else if (what === "q") linePrefix("> ");
        else if (what === "c") wrap("`", "`");
        else if (what === "a") wrap("[", "](https://)");
    }
    function align(a) { if (rich) block("<p align=\"" + a + "\">", "</p>"); }
    function setFont(family) { if (rich) inline("<span style=\"font-family:'" + family + "'\">", "</span>"); fontPicker = false; }
    function setSize(pt) { if (rich) inline("<span style=\"font-size:" + pt + "pt\">", "</span>"); }
    function setColor(c) { if (rich) inline("<span style=\"color:" + c + "\">", "</span>"); }
    property bool fontPicker: false
    property string fontFilter: ""
    readonly property var fonts: Qt.fontFamilies().filter(f => !/^(Noto Sans .* UI|DejaVu Math|.*Emoji|Symbol)$/.test(f))

    // ── kontrola textu (hunspell + jednoduché pravidlá) ─────────────────────────
    property var issues: []                     // { kind: "preklep"|"zdvojené"|"medzery", word, sugg: [] }
    property bool checking: false
    property bool checkOpen: false
    property string lang: "sk_SK"
    FileView { id: tmpCheck; path: app.runDir + "/heidelberg-kontrola.txt"; printErrors: false; atomicWrites: true }
    // osobný slovník (hunspell -p): názvy LatteOS navyše, „Pridať do slovníka“ pripisuje
    readonly property string dictFile: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/latteos/slovnik.dic"
    FileView { id: dict; path: app.dictFile; printErrors: false
               onLoadFailed: setText("LatteOS\nHeidelberg\nHeidelbergu\nHeidelbergom\nNoctalia\nNoctalie\nHyprland\nFlatpak\nFlathub\nBarista\nKapsa\nKapse\n") }
    function addWord(w) {
        dict.setText((dict.text() || "") + w + "\n");
        issues = issues.filter(x => x.word !== w);
        status = "Pridané do slovníka: " + w;
    }
    Process {
        id: speller
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [], seen = {};
                for (const l of this.text.split("\n")) {
                    // skratky (PDF), slová s číslicou a VeľkéVnútri (LatteOS) sa neopravujú
                    const skip = (w) => /^[A-Z\u00C0-\u00DE]{2,}$/.test(w) || /\d/.test(w) || /[a-z\u00DF-\u024F][A-Z]/.test(w);
                    let m = l.match(/^& (\S+) \d+ \d+: (.*)$/);
                    if (m && skip(m[1])) continue;
                    if (m && !seen[m[1]]) { seen[m[1]] = 1; out.push({ kind: "preklep", word: m[1], sugg: m[2].split(", ").slice(0, 5) }); continue; }
                    m = l.match(/^# (\S+) \d+/);
                    if (m && !skip(m[1]) && !seen[m[1]]) { seen[m[1]] = 1; out.push({ kind: "preklep", word: m[1], sugg: [] }); }
                }
                const t = app.plain;
                const rep = t.match(/(^|[^A-Za-zÀ-ɏ])([A-Za-zÀ-ɏ]+)\s+\2(?![A-Za-zÀ-ɏ])/gi) || [];
                for (const r0 of rep) {
                    const r = r0.replace(/^[^A-Za-z\u00C0-\u024F]/, "");
                    if (!seen[r]) { seen[r] = 1; out.push({ kind: "zdvojené", word: r, sugg: [r.split(/\s+/)[0]] }); }
                }
                if (/ {2,}/.test(t)) out.push({ kind: "medzery", word: "  ", sugg: [" "] });
                const bp = t.match(/ [,.;:!?]/g) || [];
                if (bp.length) out.push({ kind: "medzera pred interpunkciou", word: bp[0], sugg: [bp[0].trim()] });
                app.issues = out; app.checking = false;
                app.status = out.length === 0 ? "Kontrola textu: bez chýb ✓" : "Kontrola textu: " + out.length + " na opravu";
            }
        }
    }
    function checkText() {
        checkOpen = true; checking = true;
        // každý riadok s „^“ (hunspell -a ho nečíta ako príkaz); značky Markdownu nevadia
        tmpCheck.setText(plain.split(/[\n\u2029]/).map(l => "^" + l).join("\n") + "\n");
        speller.command = ["sh", "-c", "hunspell -d \"$1\" -p \"$3\" -a < \"$2\"", "sh", lang, tmpCheck.path, dictFile];
        speller.running = true;
    }
    function findWord(w) {
        const t = plain;
        let i = t.indexOf(w, editor.selectionEnd);
        if (i < 0) i = t.indexOf(w);
        if (i >= 0) { editor.select(i, i + w.length); editor.forceActiveFocus(); }
        return i;
    }
    function fix(issue, s) {
        let n = 0, i;
        const t0 = plain;
        // nahradiť všetky výskyty (od konca, aby sedeli pozície)
        const pos = [];
        for (i = t0.indexOf(issue.word); i >= 0; i = t0.indexOf(issue.word, i + issue.word.length)) pos.push(i);
        for (let k = pos.length - 1; k >= 0; k--) {
            const a = pos[k];
            if (issue.kind === "preklep") {         // iba celé slová
                const before = a > 0 ? t0[a - 1] : " ", after = t0[a + issue.word.length] || " ";
                if (/[A-Za-z0-9À-ɏ]/.test(before) || /[A-Za-z0-9À-ɏ]/.test(after)) continue;
            }
            editor.remove(a, a + issue.word.length); editor.insert(a, s); n++;
        }
        issues = issues.filter(x => !(x.kind === issue.kind && x.word === issue.word));   // delegát má kópiu objektu
        status = "Opravené: " + n + "×";
    }

    FloatingWindow {
        onClosed: Qt.quit()              // zavretie z kompozitora (✕ v titulku, Super+Q) ukončí aj proces
        title: (app.path ? app.path.split("/").pop() : "Nový dokument") + (app.dirty ? " •" : "") + " — Heidelberg"
        implicitWidth: 1320; implicitHeight: 860
        color: theme.surface

        Item {
            id: root
            anchors.fill: parent
            Shortcut { sequence: "Ctrl+S"; onActivated: app.save() }
            Shortcut { sequence: "Ctrl+N"; onActivated: app.newDoc(true) }
            Shortcut { sequence: "Ctrl+Shift+N"; onActivated: app.newDoc(false) }
            Shortcut { sequence: "Ctrl+B"; onActivated: app.fmt("b") }
            Shortcut { sequence: "Ctrl+I"; onActivated: app.fmt("i") }
            Shortcut { sequence: "Ctrl+U"; onActivated: app.fmt("u") }
            Shortcut { sequence: "Ctrl+P"; onActivated: app.exportAs("pdf", "print") }
            Shortcut { sequence: "F7"; onActivated: app.checkText() }
            Shortcut { sequence: "Ctrl++"; onActivated: { app.zoom = Math.min(2, app.zoom + 0.1); app.savePrefs(); } }
            Shortcut { sequence: "Ctrl+-"; onActivated: { app.zoom = Math.max(0.5, app.zoom - 0.1); app.savePrefs(); } }

            SideBar {
                id: side
                theme: theme
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                heading: "Heidelberg"; headingGlyph: "file-text"
                current: "doc:" + app.path
                model: [
                    { title: "Nový", items: [{ key: "new", glyph: "plus", label: "Dokument", sub: "Ctrl+N · písma, strana, tlač" },
                                             { key: "note", glyph: "pencil", label: "Poznámka (Markdown)", sub: "Ctrl+Shift+N" }] },
                    { title: "Nedávne", items: app.recent.map(p => ({ key: "doc:" + p, glyph: "file-text", label: p.split("/").pop(), sub: p.substring(0, p.lastIndexOf("/")).replace(app.home, "~") })) },
                    { title: "Dokumenty", items: app.docs.map(p => ({ key: "doc:" + p, glyph: "file-text", label: p.split("/").pop() })) }
                ]
                onActivated: (it) => { if (it.key === "new") app.newDoc(true); else if (it.key === "note") app.newDoc(false); else app.open(it.key.slice(4)); }
                onContextRequested: (it, x, y) => app.docMenu(it, x, y)
            }

            HeaderBar {
                id: header
                theme: theme
                appId: "latteos-heidelberg"
                anchors { left: side.right; right: parent.right; top: parent.top }
                title: (app.path ? app.path.split("/").pop() : "Nový dokument") + (app.dirty ? "  •  neuložené" : "")
                netVisible: false
                searchPlaceholder: "Hľadať v texte"
                onSearchChanged: (t) => { if (t) app.findWord(t); }
                onCloseRequested: Qt.quit()
                IconButton { theme: theme; glyph: "device-floppy"; tip: "Uložiť (Ctrl+S)"; onClicked: app.save() }
                IconButton { theme: theme; glyph: "list-check"; checked: app.checkOpen; tip: "Kontrola textu (F7)"; onClicked: { if (app.checkOpen) app.checkOpen = false; else app.checkText(); } }
                IconButton { theme: theme; glyph: "eye"; visible: !app.rich; checked: app.preview; tip: "Náhľad"; onClicked: app.preview = !app.preview }
            }

            // ── panel formátovania ─────────────────────────────────────────────
            Flow {
                id: tools
                anchors { left: side.right; right: parent.right; top: header.bottom; leftMargin: 16; rightMargin: 16; topMargin: 10 }
                spacing: 6
                component Fmt: Rectangle {
                    id: fb
                    property string label; property string what; property string tip
                    property bool bold: true
                    signal clicked()
                    width: Math.max(32, ft.implicitWidth + 16); height: 32; radius: 8
                    color: fm.containsMouse ? theme.hover : theme.field
                    Text { id: ft; anchors.centerIn: parent; text: fb.label; color: theme.fg
                           font { family: theme.fontUi; pixelSize: 13; weight: fb.bold ? Font.Bold : Font.Normal; italic: fb.what === "i"; underline: fb.what === "u"; strikeout: fb.what === "s" } }
                    MouseArea { id: fm; anchors.fill: parent; hoverEnabled: true; onClicked: { if (fb.what !== "") app.fmt(fb.what); fb.clicked(); } }
                }
                component Sep: Rectangle { width: 1; height: 32; color: theme.line }
                // písmo a veľkosť (iba Dokument)
                Rectangle {
                    visible: app.rich
                    width: 170; height: 32; radius: 8; color: fpm.containsMouse ? theme.hover : theme.field
                    Text { x: 10; width: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                           text: "Písmo…"; color: theme.fg; font { family: theme.fontUi; pixelSize: 13 } }
                    Glyph { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } name: "chevron-up"; size: 12; color: theme.fgDim; rotation: 180 }
                    MouseArea { id: fpm; anchors.fill: parent; hoverEnabled: true; onClicked: { app.fontFilter = ""; app.fontPicker = !app.fontPicker; } }
                }
                Repeater {
                    model: app.rich ? [9, 11, 12, 14, 18, 24, 32] : []
                    Fmt { required property int modelData; label: String(modelData); what: ""; bold: false; onClicked: app.setSize(modelData) }
                }
                Sep { visible: app.rich }
                Fmt { label: "B"; what: "b" }
                Fmt { label: "I"; what: "i" }
                Fmt { visible: app.rich; label: "U"; what: "u" }
                Fmt { label: "S"; what: "s" }
                Repeater {
                    model: app.rich ? ["#111111", "#C75B4A", "#E08A2E", "#3A8A4F", "#2F6FC9", "#8A4FC9"] : []
                    Rectangle {
                        required property string modelData
                        width: 22; height: 22; radius: 11; anchors.verticalCenter: undefined; y: 5; color: modelData
                        border { color: theme.line; width: 1 }
                        MouseArea { anchors.fill: parent; onClicked: app.setColor(parent.modelData) }
                    }
                }
                Sep {}
                Fmt { label: "H1"; what: "h1" }
                Fmt { label: "H2"; what: "h" }
                Fmt { label: "H3"; what: "h3" }
                Fmt { visible: app.rich; label: "¶"; what: "p" }
                Fmt { label: "• Zoznam"; what: "l" }
                Fmt { label: "1. Zoznam"; what: "n" }
                Fmt { label: "❝"; what: "q" }
                Sep { visible: app.rich }
                Fmt { visible: app.rich; label: "⯇"; what: ""; onClicked: app.align("left") }
                Fmt { visible: app.rich; label: "≡"; what: ""; onClicked: app.align("center") }
                Fmt { visible: app.rich; label: "⯈"; what: ""; onClicked: app.align("right") }
                Fmt { visible: app.rich; label: "▤"; what: ""; onClicked: app.align("justify") }
                Fmt { visible: app.rich; label: "Tx"; what: ""; bold: false; onClicked: app.clearFormat() }
                Fmt { visible: !app.rich; label: "</>"; what: "c" }
                Fmt { label: "Odkaz"; what: "a"; bold: false }
                Sep {}
                // strana a tlač
                Fmt { visible: app.rich; label: app.pageSize + (app.landscape ? " ⟷" : " ↕"); what: ""; bold: false
                      onClicked: { const o = ["A4", "A5", "Letter"]; app.pageSize = o[(o.indexOf(app.pageSize) + 1) % o.length]; app.savePrefs(); } }
                Fmt { visible: app.rich; label: "Na šírku"; what: ""; bold: app.landscape; onClicked: { app.landscape = !app.landscape; app.savePrefs(); } }
                Fmt { visible: app.rich; label: "Okraj " + app.marginMm + " mm"; what: ""; bold: false
                      onClicked: { const o = [15, 20, 25, 30]; app.marginMm = o[(o.indexOf(app.marginMm) + 1) % o.length]; app.savePrefs(); } }
                Fmt { label: "🖶 Tlačiť"; what: ""; onClicked: app.exportAs("pdf", "print") }
                component Exp: Rectangle {
                    id: eb
                    property string label; property string fmt
                    width: et.implicitWidth + 16; height: 32; radius: 8
                    color: em2.containsMouse ? theme.hover : "transparent"; border { color: theme.line; width: 1 }
                    Text { id: et; anchors.centerIn: parent; text: eb.label; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { id: em2; anchors.fill: parent; hoverEnabled: true; onClicked: app.exportAs(eb.fmt) }
                }
                Exp { label: "PDF"; fmt: "pdf" }
                Exp { label: "DOCX"; fmt: "docx" }
                Exp { label: "ODT"; fmt: "odt" }
                Exp { label: "EPUB"; fmt: "epub" }
                Exp { visible: !app.rich; label: "HTML"; fmt: "html" }
                Rectangle {
                    visible: !app.hasPandoc
                    width: pt2.implicitWidth + 18; height: 32; radius: 8; color: theme.primary
                    Text { id: pt2; anchors.centerIn: parent; text: "Doinštalovať dokumenty (pandoc)"; color: theme.fgOnPrimary; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { anchors.fill: parent; onClicked: { inst.command = ["latte-app", "instalator", "--nazov=Podpora_dokumentov_(pandoc)", "install", "pandoc-cli"]; inst.running = true; } }
                }
                Rectangle {
                    visible: !app.hasPoppler && app.isPdf
                    width: pt4.implicitWidth + 18; height: 32; radius: 8; color: theme.primary
                    Text { id: pt4; anchors.centerIn: parent; text: "Doinštalovať otváranie PDF"; color: theme.fgOnPrimary; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { anchors.fill: parent; onClicked: { inst.command = ["latte-app", "instalator", "--nazov=Otváranie_PDF_(poppler)", "install", "poppler-utils"]; inst.running = true; } }
                }
                Rectangle {
                    visible: !app.hasPdf
                    width: pt3.implicitWidth + 18; height: 32; radius: 8; color: theme.field; border { color: theme.primary; width: 1 }
                    Text { id: pt3; anchors.centerIn: parent; text: "Doinštalovať PDF a tlač"; color: theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                    MouseArea { anchors.fill: parent; onClicked: { inst.command = ["latte-app", "instalator", "--nazov=PDF_a_tlač_(weasyprint)", "install", "weasyprint"]; inst.running = true; } }
                }
                Process { id: inst; onExited: { pandocCheck.running = true; toolCheck.running = true; popplerCheck.running = true; } }
            }

            Row {
                id: work
                anchors { left: side.right; right: parent.right; top: tools.bottom; bottom: statusBar.top; margins: 16; topMargin: 10 }
                spacing: 14
                readonly property real checkW: app.checkOpen ? 300 : 0
                readonly property real mainW: width - checkW - (app.checkOpen ? spacing : 0)

                // editor: Dokument = list papiera s okrajmi, Text = zdroj (+ náhľad)
                Rectangle {
                    width: app.rich ? work.mainW : (app.preview ? (work.mainW - 14) / 2 : work.mainW); height: parent.height
                    radius: 12; color: app.rich ? Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.25 : 0.07) : theme.field
                    clip: true
                    Flickable {
                        id: flickDoc
                        ScrollHint { flick: flickDoc; colors: theme }
                        anchors { fill: parent; margins: app.rich ? 0 : 14 }
                        contentWidth: app.rich ? Math.max(width, app.pageW + 48) : width
                        contentHeight: app.rich ? Math.max(app.pageH, editor.implicitHeight + app.marginMm * 2 * app.mmPx) + 48 : editor.implicitHeight
                        clip: true
                        Rectangle {   // strana
                            visible: app.rich
                            x: Math.max(24, (flickDoc.width - app.pageW) / 2); y: 24
                            width: app.pageW; height: Math.max(app.pageH, editor.implicitHeight + app.marginMm * 2 * app.mmPx)
                            color: "white"; border { color: Qt.rgba(0, 0, 0, 0.12); width: 1 }
                            MouseArea {   // klik na prázdnu časť strany = písať na koniec
                                anchors.fill: parent
                                onClicked: { editor.forceActiveFocus(); editor.cursorPosition = editor.length; }
                            }
                            // zlomy strán (orientačne, podľa výšky strany)
                            Repeater {
                                model: Math.max(0, Math.floor(parent.height / app.pageH))
                                Rectangle { required property int index; visible: index > 0; x: 0; y: index * app.pageH; width: parent.width; height: 1; color: Qt.rgba(0, 0, 0, 0.18) }
                            }
                        }
                        TextEdit {
                            id: editor
                            x: app.rich ? Math.max(24, (flickDoc.width - app.pageW) / 2) + app.marginMm * app.mmPx : 0
                            y: app.rich ? 24 + app.marginMm * app.mmPx : 0
                            width: app.rich ? app.pageW - 2 * app.marginMm * app.mmPx : flickDoc.width
                            textFormat: app.rich ? TextEdit.RichText : TextEdit.PlainText
                            wrapMode: TextEdit.Wrap; selectByMouse: true; focus: true; persistentSelection: true
                            color: app.rich ? "#111111" : theme.fg
                            selectionColor: theme.primary; selectedTextColor: theme.fgOnPrimary
                            font { family: app.kind === "txt" ? theme.fontUi : (app.rich ? "Manrope" : theme.fontMono); pixelSize: app.rich ? Math.round(15 * app.zoom) : 14 }
                            onLinkActivated: (l) => Qt.openUrlExternally(l)
                            onTextChanged: if (!activeFocus) flickDoc.contentY = 0       // načítaný dokument od začiatku
                            onCursorRectangleChanged: {
                                if (!activeFocus) return;                               // posúvať iba pri písaní
                                const top = cursorRectangle.y + y, bot = top + cursorRectangle.height;
                                if (top < flickDoc.contentY) flickDoc.contentY = top;
                                else if (bot > flickDoc.contentY + flickDoc.height) flickDoc.contentY = bot - flickDoc.height;
                            }
                            // pravý klik v texte: úpravy, formát, návrhy pravopisu (ľavé tlačidlo ostáva editoru)
                            MouseArea {
                                anchors.fill: parent; acceptedButtons: Qt.RightButton; cursorShape: Qt.IBeamCursor
                                onClicked: (m) => {
                                    const pos = editor.positionAt(m.x, m.y);
                                    if (editor.selectionStart === editor.selectionEnd || pos < editor.selectionStart || pos > editor.selectionEnd) { editor.cursorPosition = pos; app.selectWordIfEmpty(); }
                                    const q = mapToItem(null, m.x, m.y);
                                    app.editMenu(q.x, q.y);
                                }
                            }
                        }
                        Text { visible: app.plain === "" && !app.rich; text: "Píš… (Markdown: # nadpis, **tučné**, *kurzíva*, - zoznam)"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 14 } }
                        Text { visible: app.plain === "" && app.rich; x: editor.x; y: editor.y; text: "Píš… Formátuj tlačidlami hore, Ctrl+P tlačí."; color: "#888"; font { family: "Manrope"; pixelSize: 15 } }
                    }
                }
                // náhľad (Text)
                Rectangle {
                    visible: app.preview && !app.rich
                    width: (work.mainW - 14) / 2; height: parent.height
                    radius: 12; color: Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.12 : 0.03); border { color: theme.line; width: 1 }
                    Flickable {
                        id: rolovanie2
                        ScrollHint { flick: rolovanie2; colors: theme }
                        anchors { fill: parent; margins: 20 }
                        contentHeight: rendered.implicitHeight; clip: true
                        Text {
                            id: rendered
                            width: parent.width; wrapMode: Text.Wrap
                            textFormat: app.kind === "md" ? Text.MarkdownText : Text.PlainText
                            text: app.rich ? "" : editor.text; color: theme.fg; linkColor: theme.primary
                            font { family: app.kind === "txt" ? theme.fontMono : theme.fontUi; pixelSize: 15 }
                            onLinkActivated: (l) => Qt.openUrlExternally(l)
                        }
                    }
                }
                // kontrola textu
                Rectangle {
                    visible: app.checkOpen
                    width: work.checkW; height: parent.height; radius: 12
                    color: Qt.rgba(0, 0, 0, theme.mode === "dark" ? 0.16 : 0.04); border { color: theme.line; width: 1 }
                    Column {
                        id: chead; x: 14; y: 12; width: parent.width - 28; spacing: 8
                        Row {
                            spacing: 8
                            Glyph { name: "list-check"; size: 18; color: theme.primary; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Kontrola textu"; color: theme.fg; font { family: theme.fontUi; pixelSize: 15; weight: Font.Bold }
                                anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row {
                            spacing: 6
                            Repeater {
                                model: [["sk_SK", "SK"], ["en_US", "EN"]]
                                Rectangle {
                                    required property var modelData
                                    width: 42; height: 26; radius: 8; color: app.lang === modelData[0] ? theme.primary : theme.field
                                    Text { anchors.centerIn: parent; text: modelData[1]; color: app.lang === modelData[0] ? theme.fgOnPrimary : theme.fg; font { family: theme.fontUi; pixelSize: 12; weight: Font.Bold } }
                                    MouseArea { anchors.fill: parent; onClicked: { app.lang = modelData[0]; app.checkText(); } }
                                }
                            }
                            Rectangle {
                                width: rct.implicitWidth + 16; height: 26; radius: 8; color: theme.field
                                Text { id: rct; anchors.centerIn: parent; text: app.checking ? "Kontrolujem…" : "Znova"; color: theme.fg; font { family: theme.fontUi; pixelSize: 12 } }
                                MouseArea { anchors.fill: parent; onClicked: app.checkText() }
                            }
                        }
                        Text { visible: !app.checking && app.issues.length === 0; width: parent.width; wrapMode: Text.WordWrap; text: "Bez chýb ✓ (" + app.words + " slov)"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                    }
                    ListView {
                        id: rolovanie3
                        ScrollHint { flick: rolovanie3; colors: theme }
                        anchors { left: parent.left; right: parent.right; top: chead.bottom; bottom: parent.bottom; margins: 10; topMargin: 8 }
                        clip: true; spacing: 6; model: app.issues
                        delegate: Rectangle {
                            id: iss
                            required property var modelData
                            width: ListView.view.width; height: icol.implicitHeight + 16; radius: 10; color: theme.field
                            Column {
                                id: icol; x: 10; y: 8; width: parent.width - 20; spacing: 6
                                Row {
                                    spacing: 6
                                    Text { text: iss.modelData.kind; color: theme.primary; font { family: theme.fontUi; pixelSize: 10; weight: Font.Bold } }
                                    Text { text: iss.modelData.word === "  " ? "dvojitá medzera" : iss.modelData.word; color: theme.fg; font { family: theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                                }
                                Flow {
                                    width: parent.width; spacing: 4
                                    Repeater {
                                        model: iss.modelData.sugg
                                        Rectangle {
                                            required property string modelData
                                            width: sgt.implicitWidth + 14; height: 24; radius: 7; color: sgm.containsMouse ? theme.primary : theme.surface
                                            Text { id: sgt; anchors.centerIn: parent; text: modelData === " " ? "jedna medzera" : modelData; color: sgm.containsMouse ? theme.fgOnPrimary : theme.fg; font { family: theme.fontUi; pixelSize: 12 } }
                                            MouseArea { id: sgm; anchors.fill: parent; hoverEnabled: true; onClicked: app.fix(iss.modelData, modelData) }
                                        }
                                    }
                                    Rectangle {
                                        width: nt.implicitWidth + 14; height: 24; radius: 7; color: "transparent"; border { color: theme.line; width: 1 }
                                        Text { id: nt; anchors.centerIn: parent; text: "Nájsť"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                                        MouseArea { anchors.fill: parent; onClicked: app.findWord(iss.modelData.word) }
                                    }
                                    Rectangle {
                                        width: it2.implicitWidth + 14; height: 24; radius: 7; color: "transparent"; border { color: theme.line; width: 1 }
                                        Text { id: it2; anchors.centerIn: parent; text: "Ignorovať"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                                        MouseArea { anchors.fill: parent; onClicked: app.issues = app.issues.filter(x => !(x.kind === iss.modelData.kind && x.word === iss.modelData.word)) }
                                    }
                                    Rectangle {
                                        visible: iss.modelData.kind === "preklep"
                                        width: at2.implicitWidth + 14; height: 24; radius: 7; color: "transparent"; border { color: theme.line; width: 1 }
                                        Text { id: at2; anchors.centerIn: parent; text: "Do slovníka"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 } }
                                        MouseArea { anchors.fill: parent; onClicked: app.addWord(iss.modelData.word) }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // výber písma (náhľad v danom písme)
            Rectangle {
                visible: app.fontPicker && app.rich
                x: tools.x; y: tools.y + 38; width: 320; height: 420; radius: 12; z: 10
                color: theme.surface; border { color: theme.outline; width: 1 }
                Rectangle {
                    id: ff; x: 10; y: 10; width: parent.width - 20; height: 34; radius: 8; color: theme.field
                    TextInput { id: ffi; anchors { fill: parent; leftMargin: 10; rightMargin: 10 } verticalAlignment: TextInput.AlignVCenter
                                color: theme.fg; font { family: theme.fontUi; pixelSize: 13 }
                                    onTextChanged: app.fontFilter = text
                                Component.onCompleted: forceActiveFocus() }
                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; visible: ffi.text === ""; text: "Hľadať písmo…"; color: theme.fgDim; font { family: theme.fontUi; pixelSize: 13 } }
                }
                ListView {
                    id: rolovanie4
                    ScrollHint { flick: rolovanie4; colors: theme }
                    anchors { left: parent.left; right: parent.right; top: ff.bottom; bottom: parent.bottom; margins: 8 }
                    clip: true
                    model: app.fonts.filter(f => app.fontFilter === "" || f.toLowerCase().includes(app.fontFilter.toLowerCase()))
                    delegate: Rectangle {
                        required property string modelData
                        width: ListView.view.width; height: 34; radius: 8; color: fdm.containsMouse ? theme.hover : "transparent"
                        Text { x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                               text: modelData; color: theme.fg; font { family: modelData; pixelSize: 15 } }
                        MouseArea { id: fdm; anchors.fill: parent; hoverEnabled: true; onClicked: app.setFont(modelData) }
                    }
                }
            }

            ContextMenu { id: ctx; theme: theme; z: 2000 }

            Rectangle {
                id: statusBar
                anchors { left: side.right; right: parent.right; bottom: parent.bottom }
                height: 30; color: "transparent"
                Rectangle { width: parent.width; height: 1; color: theme.line }
                Text {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    text: app.words + " slov · " + app.plain.length + " znakov · "
                          + (app.rich ? "Dokument " + (app.isDoc ? app.ext.toUpperCase() : "HTML") + " · " + app.pageSize + (app.landscape ? " na šírku" : "") + " · " + Math.round(app.zoom * 100) + " %"
                                      : ({ md: "Markdown", txt: "text" })[app.kind])
                          + (app.status ? "   ·   " + app.status : "")
                    color: theme.fgDim; font { family: theme.fontUi; pixelSize: 12 }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "Ctrl+S uložiť · Ctrl+N dokument · Ctrl+B/I/U · Ctrl+P tlačiť · F7 kontrola · Ctrl +/− lupa"
                    color: theme.fgDim; opacity: 0.8; font { family: theme.fontUi; pixelSize: 11 }
                }
            }
        }
    }
    Component.onCompleted: {
        if (isPdf) { Qt.callLater(loadPdf); return; }
        if (isDoc) { pandocWait.start(); return; }
        if (path === "") {
            editor.text = "<h1>Vitaj v Heidelbergu</h1><p>Toto je <b>editor dokumentov LatteOS</b>. Píš na strane ako na papieri: "
                        + "vyber text a zmeň mu <span style=\"font-family:'Fraunces'\">písmo</span>, <span style=\"font-size:18pt\">veľkosť</span> "
                        + "alebo <span style=\"color:#C75B4A\">farbu</span>.</p><ul><li>Strana A4 s okrajmi, Ctrl+P tlačí</li>"
                        + "<li>Export do PDF, DOCX, ODT a EPUB</li><li>F7 skontroluje pravopis</li></ul>"
                        + "<blockquote>Názov Gutenberg je obsadený, preto Heidelberg.</blockquote>";
            savedText = editor.text; status = "Ukážka (neuloží sa, kým nestlačíš Ctrl+S)";
        }
    }
}
