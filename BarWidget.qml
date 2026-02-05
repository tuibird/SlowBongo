import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

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
        : catText.implicitWidth * (mainInstance?.catSize ?? 1.0)
    readonly property real contentHeight: isBarVertical
        ? catText.implicitHeight * (mainInstance?.catSize ?? 1.0)
        : capsuleHeight

    implicitWidth: isBarVertical ? capsuleHeight : contentWidth
    implicitHeight: isBarVertical ? contentHeight : capsuleHeight

    // Each pose is two glyphs (left half + right half):
    // b = left half paw up,  d = left half paw down
    // c = right half paw up, a = right half paw down
    readonly property var glyphMap: ["bc", "dc", "ba"]  // [idle, leftSlap, rightSlap]

    readonly property int catState: mainInstance?.catState ?? 0
    readonly property bool paused: mainInstance?.paused ?? false
    readonly property string catColorKey: mainInstance?.catColor ?? "default"

    function resolveColor(key) {
        switch (key) {
            case "primary":   return Color.mPrimary
            case "secondary": return Color.mSecondary
            case "tertiary":  return Color.mTertiary
            case "error":     return Color.mError
            default:          return Color.mOnSurface
        }
    }

    readonly property color resolvedCatColor: resolveColor(catColorKey)

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
        clip: false

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    PanelService.showContextMenu(contextMenu, root, screen);
                } else {
                    if (root.mainInstance) {
                        root.mainInstance.paused = !root.mainInstance.paused;
                    }
                }
            }
        }

        NPopupContextMenu {
            id: contextMenu

            model: [
                {
                    "label": I18n.tr("actions.widget-settings"),
                    "action": "widget-settings",
                    "icon": "settings"
                },
            ]

            onTriggered: action => {
                contextMenu.close();
                PanelService.closeContextMenu(screen);

                if (action === "widget-settings") {
                    BarService.openPluginSettings(screen, pluginApi.manifest);
                }
            }
        }

        Text {
            id: catText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: parent.height * (root.mainInstance?.catOffsetY ?? 0.0)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: bongoFont.name
            font.pixelSize: root.capsuleHeight * 0.95 * (root.mainInstance?.catSize ?? 1.0)
            color: root.resolvedCatColor
            text: root.glyphMap[root.catState] ?? "bc"
            visible: !root.paused
            renderType: Text.NativeRendering
        }

        NIcon {
            anchors.centerIn: parent
            icon: "player-pause-filled"
            pointSize: root.barFontSize
            color: root.resolvedCatColor
            visible: root.paused
        }
    }
}
