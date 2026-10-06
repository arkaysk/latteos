// ScrollHint — ukazovateľ rolovania pre Flickable / ListView / GridView (zadanie 24. 9.: „na okraji nevidím,
// ako ďaleko som“). Pás pri pravom (alebo spodnom) okraji; pri rolovaní a pod myšou zvýraznený, dá sa potiahnuť.
// Chytá sa v páse širokom 16 px, jazdec má 8 px a pod myšou 12 px (6. 10.: pôvodné 4 px sa myšou nedali
// pohodlne chytiť). Vkladá sa dovnútra zoznamu: ScrollHint { flick: zoznam; colors: theme } — sám sa prevesí
// na zoznam (nie na jeho obsah), takže s obsahom neroluje.
import QtQuick

Item {
    id: hint
    required property var flick
    required property var colors
    property bool horizontal: false
    readonly property int thick: 16            // šírka pásu, v ktorom sa jazdec chytá
    readonly property int bar: ma.containsMouse || ma.pressed ? 12 : 8
    readonly property real ratio: horizontal ? flick.width / Math.max(1, flick.contentWidth) : flick.height / Math.max(1, flick.contentHeight)
    readonly property real pos: horizontal ? flick.contentX / Math.max(1, flick.contentWidth - flick.width) : flick.contentY / Math.max(1, flick.contentHeight - flick.height)
    readonly property bool needed: ratio < 0.999
    parent: flick
    visible: needed
    x: horizontal ? 0 : flick.width - width
    y: horizontal ? flick.height - height : 0
    width: horizontal ? flick.width : thick
    height: horizontal ? thick : flick.height
    z: 50

    Rectangle {    // koľajnica (iba keď je aktívna)
        anchors.fill: parent; radius: 8
        color: Qt.rgba(hint.colors.fg.r, hint.colors.fg.g, hint.colors.fg.b, 0.06)
        opacity: ma.containsMouse || ma.pressed || hint.flick.moving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    Rectangle {    // jazdec: veľkosť = aká časť je vidieť, poloha = kde som
        id: thumb
        readonly property real len: Math.max(48, (hint.horizontal ? hint.width : hint.height) * hint.ratio)
        readonly property real travel: (hint.horizontal ? hint.width : hint.height) - len
        // jazdec je pri vonkajšom okraji pásu, pod myšou sa rozšíri smerom dnu
        x: hint.horizontal ? travel * Math.max(0, Math.min(1, hint.pos)) : hint.thick - hint.bar - 2
        y: hint.horizontal ? hint.thick - hint.bar - 2 : travel * Math.max(0, Math.min(1, hint.pos))
        width: hint.horizontal ? len : hint.bar
        height: hint.horizontal ? hint.bar : len
        radius: hint.bar / 2
        Behavior on width { enabled: !hint.horizontal; NumberAnimation { duration: 120 } }
        Behavior on height { enabled: hint.horizontal; NumberAnimation { duration: 120 } }
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
