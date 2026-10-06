// LTextInput — textové pole LatteOS so štandardnou ponukou úprav na pravý klik, ako v GNOME a Windows:
// Späť, Znova · Vystrihnúť, Kopírovať, Prilepiť, Odstrániť · Označiť všetko.
// Správanie je z Qt (canUndo, canRedo, canPaste, cut(), paste()… — to isté, čo používa Qt TextEditingContextMenu),
// vzhľad z ContextMenu LatteOS (Qt ponuka je na Waylande orezaná oknom, anglická a bez témy).
// Použitie: LTextInput { latteTheme: theme; … }  (vlastnosť sa nevolá „theme“ — „theme: theme“ by odkazovalo samo na seba)
import QtQuick

TextInput {
    id: field
    property var latteTheme: null
    property bool editMenu: true
    selectByMouse: true
    persistentSelection: true          // výber ostane, kým je otvorená ponuka (inak by „Kopírovať“ nemalo čo kopírovať)

    property var _menu: null
    function _ensureMenu() {
        const root = field.Window.contentItem;
        if (_menu || !root || !latteTheme) return _menu;
        const c = Qt.createComponent("ContextMenu.qml");
        if (c.status === Component.Ready) _menu = c.createObject(root, { theme: latteTheme });
        return _menu;
    }
    function openEditMenu(x, y) {
        const m = _ensureMenu();
        if (!m) return;
        const secret = echoMode !== TextInput.Normal;       // heslo: nič nekopírovať von, ako Qt
        const sel = selectionEnd > selectionStart;
        const act = (fn) => () => { field.forceActiveFocus(); fn(); };
        const p = field.mapToItem(m, x, y);
        m.open(p.x, p.y, [
            { glyph: "arrow-back-up", label: "Späť", hint: "Ctrl+Z", enabled: !readOnly && canUndo, action: act(() => field.undo()) },
            { glyph: "arrow-forward-up", label: "Znova", hint: "Ctrl+Shift+Z", enabled: !readOnly && canRedo, action: act(() => field.redo()) },
            { separator: true },
            { glyph: "cut", label: "Vystrihnúť", hint: "Ctrl+X", enabled: !readOnly && sel && !secret, action: act(() => field.cut()) },
            { glyph: "copy", label: "Kopírovať", hint: "Ctrl+C", enabled: sel && !secret, action: act(() => field.copy()) },
            { glyph: "clipboard", label: "Prilepiť", hint: "Ctrl+V", enabled: !readOnly && canPaste, action: act(() => field.paste()) },
            { glyph: "backspace", label: "Odstrániť", enabled: !readOnly && sel, action: act(() => field.remove(field.selectionStart, field.selectionEnd)) },
            { separator: true },
            { glyph: "select-all", label: "Označiť všetko", hint: "Ctrl+A", enabled: text.length > 0, action: act(() => field.selectAll()) }
        ]);
    }

    MouseArea {
        anchors.fill: parent
        enabled: field.editMenu
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.IBeamCursor
        onClicked: (e) => field.openEditMenu(e.x, e.y)
    }
    Component.onDestruction: if (_menu) _menu.destroy()
}
