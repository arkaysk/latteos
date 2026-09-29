// ScrollHint — ukazovateľ rolovania pre Flickable / ListView / GridView (zadanie 24. 9.: „na okraji nevidím,
// ako ďaleko som“). Tenký pás pri pravom (alebo spodnom) okraji; pri rolovaní a pod myšou zvýraznený,
// dá sa potiahnuť. Vkladá sa dovnútra zoznamu: ScrollHint { flick: zoznam; colors: theme } — sám sa prevesí
// na zoznam (nie na jeho obsah), takže s obsahom neroluje.
import QtQuick

Item {
    id: hint
    required property var flick
    required property var colors
    property bool horizontal: false
    readonly property real ratio: horizontal ? flick.width / Math.max(1, flick.contentWidth) : flick.height / Math.max(1, flick.contentHeight)
    readonly property real pos: horizontal ? flick.contentX / Math.max(1, flick.contentWidth - flick.width) : flick.contentY / Math.max(1, flick.contentHeight - flick.height)
    readonly property bool needed: ratio < 0.999
    parent: flick
    visible: needed
    x: horizontal ? 0 : flick.width - width + 2
    y: horizontal ? flick.height - height + 2 : 0
    width: horizontal ? flick.width : 8
    height: horizontal ? 8 : flick.height
    z: 50

    Rectangle {    // koľajnica (iba keď je aktívna)
        anchors.fill: parent; radius: 4
        color: Qt.rgba(hint.colors.fg.r, hint.colors.fg.g, hint.colors.fg.b, 0.06)
        opacity: ma.containsMouse || ma.pressed || hint.flick.moving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    Rectangle {    // jazdec: veľkosť = aká časť je vidieť, poloha = kde som
        id: thumb
        readonly property real len: Math.max(28, (hint.horizontal ? hint.width : hint.height) * hint.ratio)
        readonly property real travel: (hint.horizontal ? hint.width : hint.height) - len
        x: hint.horizontal ? travel * Math.max(0, Math.min(1, hint.pos)) : 2
        y: hint.horizontal ? 2 : travel * Math.max(0, Math.min(1, hint.pos))
        width: hint.horizontal ? len : (ma.containsMouse || ma.pressed ? 6 : 4)
        height: hint.horizontal ? (ma.containsMouse || ma.pressed ? 6 : 4) : len
        radius: 3
        color: hint.colors.primary
        opacity: ma.containsMouse || ma.pressed || hint.flick.moving ? 0.9 : 0.45
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    MouseArea {    // ťahanie a klik na koľajnicu
        id: ma
        anchors.fill: parent; hoverEnabled: true
        function jump(m) {
            const f = hint.horizontal ? (m.x - thumb.len / 2) / Math.max(1, thumb.travel) : (m.y - thumb.len / 2) / Math.max(1, thumb.travel);
            const k = Math.max(0, Math.min(1, f));
            if (hint.horizontal) hint.flick.contentX = k * (hint.flick.contentWidth - hint.flick.width);
            else hint.flick.contentY = k * (hint.flick.contentHeight - hint.flick.height);
        }
        onPressed: (m) => jump(m)
        onPositionChanged: (m) => { if (pressed) jump(m); }
    }
}
