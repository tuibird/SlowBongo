import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property var screen: null
    property string widgetId: ""
    property string section: ""
    property string barPosition: ""

    readonly property var mainInstance: pluginApi?.mainInstance
    readonly property string screenName: screen?.name ?? ""
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    // Settings tie-ins
    readonly property real catSize: mainInstance?.catSize ?? 1.0
    readonly property real catOffsetY: mainInstance?.catOffsetY ?? 0.0
    readonly property real widthPadding: pluginApi?.pluginSettings?.widthPadding ?? 0.2

    // Glyph map: b = left paw up, d = left paw down, c = right paw up, a = right paw down
    readonly property var glyphMap: ["bc", "dc", "ba"]  // [idle, leftSlap, rightSlap]

    readonly property int catState: mainInstance?.catState ?? 0
    readonly property bool paused: mainInstance?.paused ?? false
    readonly property string catColorKey: mainInstance?.catColor ?? "default"
    readonly property bool showRainbowColor: mainInstance?.showRainbowColor ?? false
    readonly property string rainbowColor: mainInstance?.currentRainbowColor ?? "#ff0000"

    function resolveColor(key) {
        switch (key) {
            case "primary":   return Color.mPrimary
            case "secondary": return Color.mSecondary
            case "tertiary":  return Color.mTertiary
            case "error":     return Color.mError
            default:          return Color.mOnSurface
        }
    }

    readonly property color resolvedCatColor: showRainbowColor ? rainbowColor : resolveColor(catColorKey)

    // Sizing: capsule dimensions drive implicit size
    readonly property real horizontalPadding: capsuleHeight * widthPadding
    readonly property real contentWidth: isBarVertical
        ? capsuleHeight
        : catText.implicitWidth + horizontalPadding
    readonly property real contentHeight: isBarVertical
        ? catText.implicitHeight + horizontalPadding
        : capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    FontLoader {
        id: bongoFont
        source: pluginApi ? pluginApi.pluginDir + "/bongocatfont.woff" : ""
    }

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        radius: Style.radiusL
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        Text {
            id: catText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.capsuleHeight * root.catOffsetY
            font.family: bongoFont.name
            font.pixelSize: root.capsuleHeight * root.catSize
            font.weight: Font.Thin
            color: mouseArea.containsMouse ? Color.mOnHover : root.resolvedCatColor
            text: root.glyphMap[root.catState] ?? "bc"
            visible: !root.paused
            renderType: Text.NativeRendering
        }

        NIcon {
            anchors.centerIn: parent
            icon: "player-pause-filled"
            pointSize: root.barFontSize
            color: mouseArea.containsMouse ? Color.mOnHover : root.resolvedCatColor
            visible: root.paused
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, screen);
            } else if (root.mainInstance) {
                root.mainInstance.paused = !root.mainInstance.paused;
            }
        }
    }

    NPopupContextMenu {
        id: contextMenu
        model: [{
            "label": I18n.tr("actions.widget-settings"),
            "action": "widget-settings",
            "icon": "settings"
        }]
        onTriggered: action => {
            contextMenu.close();
            PanelService.closeContextMenu(screen);
            if (action === "widget-settings") {
                BarService.openPluginSettings(screen, pluginApi.manifest);
            }
        }
    }
}
