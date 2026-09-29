// CelaObrazovka — je aktívne okno naozaj na celú obrazovku (Hyprland fullscreen 2, film, hra)? Maximalizované okno
// (fullscreen 1, tak LatteOS maximalizuje) sa nepočíta. Iba udalosti IPC Hyprlandu, žiadny polling ani procesy.
import QtQuick
import Quickshell.Hyprland

Item {
    id: co
    property bool active: false
    function update() {
        const t = Hyprland.activeToplevel, o = t ? t.lastIpcObject : null, ws = Hyprland.focusedWorkspace;
        active = !!o && (o.fullscreen === 2 || o.fullscreen === 3) && !!ws && !!o.workspace && o.workspace.id === ws.id;
    }
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (/^(fullscreen|activewindowv2|workspacev2|closewindow|focusedmonv2)$/.test(e.name)) ask.restart(); }
    }
    // refreshToplevels je asynchrónne: najprv vyžiadať, o chvíľu prečítať
    Timer { id: ask; interval: 60; onTriggered: { Hyprland.refreshToplevels(); read.restart(); } }
    Timer { id: read; interval: 150; onTriggered: co.update() }
    Component.onCompleted: ask.start()
}
