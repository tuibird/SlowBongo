import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    readonly property var mainInstance: pluginApi?.mainInstance
    readonly property string screenName: screen?.name ?? ""
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
    readonly property bool isBarVertical: section === "left" || section === "right"

    readonly property real contentWidth: isBarVertical
        ? capsuleHeight
        : catText.implicitWidth
    readonly property real contentHeight: isBarVertical
        ? catText.implicitHeight
        : capsuleHeight

    implicitWidth: isBarVertical ? capsuleHeight : contentWidth
    implicitHeight: isBarVertical ? contentHeight : capsuleHeight

    // Each pose is two glyphs (left half + right half):
    // b = left half paw up,  d = left half paw down
    // c = right half paw up, a = right half paw down
    readonly property var glyphMap: ["bc", "dc", "ba"]  // [idle, leftSlap, rightSlap]

    readonly property int catState: mainInstance?.catState ?? 0
    readonly property bool paused: mainInstance?.paused ?? false

    FontLoader {
        id: bongoFont
        source: pluginApi ? pluginApi.pluginDir + "/bongocatfont.woff" : ""
    }

    Rectangle {
        id: visualCapsule
        width: root.contentWidth
        height: root.contentHeight
        anchors.centerIn: parent
        radius: Style.radiusL
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth
        clip: true

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.mainInstance) {
                    root.mainInstance.paused = !root.mainInstance.paused;
                }
            }
        }

        Text {
            id: catText
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: bongoFont.name
            // Use fixed size
            font.pixelSize: root.capsuleHeight * 0.95
            // Shift to bottom of the bar
            y: parent.height * 0.8
            color: Color.mOnSurface
            text: root.glyphMap[root.catState] ?? "bc"
            visible: !root.paused
            renderType: Text.NativeRenderingzxczxczxczcccasd
        }

        NIcon {
            anchors.centerIn: parent
            icon: "player-pause-filled"
            pointSize: root.barFontSize
            color: Color.mOnSurface
            visible: root.paused
        }
    }
}
