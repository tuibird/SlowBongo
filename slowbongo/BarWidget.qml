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

    // Glyph map: b = left paw up, d = left paw down, c = right paw up, a = right paw down, e+f = sleep
    readonly property var glyphMap: ["bc", "dc", "ba"]  // [idle, leftSlap, rightSlap]
    readonly property string sleepGlyph: "ef"

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
        source: pluginApi ? pluginApi.pluginDir + "/bongocat-Regular.otf" : ""
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
            text: root.paused ? root.sleepGlyph : (root.glyphMap[root.catState] ?? "bc")
            visible: true
        }

        Repeater {
            id: zzzRepeater
            property real catFontSize: catText.font.pixelSize
            property color catFontColor: catText.color
            property real catX: catText.x
            property real catY: catText.y
            property real catW: catText.width
            property bool sleeping: root.paused

            readonly property real baseScale: 0.28
            readonly property real scaleStep: 0.07
            readonly property real xOrigin: 0.55
            readonly property real xSpacing: 0.18
            readonly property real floatHeight: 0.7
            readonly property int staggerDelay: 500
            readonly property int floatDuration: 1800
            readonly property int fadeInDuration: 300
            readonly property int fadeOutDuration: 1500

            model: 3
            delegate: Text {
                id: zItem
                required property int index
                text: "z"
                font.pixelSize: zzzRepeater.catFontSize * (zzzRepeater.baseScale + index * zzzRepeater.scaleStep)
                font.weight: Font.Bold
                color: zzzRepeater.catFontColor
                visible: zzzRepeater.sleeping
                opacity: 0
                x: zzzRepeater.catX + zzzRepeater.catW * zzzRepeater.xOrigin + index * zzzRepeater.catFontSize * zzzRepeater.xSpacing
                y: zzzRepeater.catY

                SequentialAnimation {
                    id: zAnim
                    running: zzzRepeater.sleeping
                    loops: Animation.Infinite

                    PauseAnimation { duration: zItem.index * zzzRepeater.staggerDelay }

                    ParallelAnimation {
                        NumberAnimation {
                            target: zItem; property: "y"
                            from: zzzRepeater.catY
                            to: zzzRepeater.catY - zzzRepeater.catFontSize * zzzRepeater.floatHeight
                            duration: zzzRepeater.floatDuration
                            easing.type: Easing.OutQuad
                        }
                        SequentialAnimation {
                            NumberAnimation {
                                target: zItem; property: "opacity"
                                from: 0; to: 1
                                duration: zzzRepeater.fadeInDuration
                            }
                            NumberAnimation {
                                target: zItem; property: "opacity"
                                from: 1; to: 0
                                duration: zzzRepeater.fadeOutDuration
                                easing.type: Easing.InQuad
                            }
                        }
                    }
                }

                onVisibleChanged: {
                    if (!visible) {
                        zAnim.stop();
                        opacity = 0;
                        y = zzzRepeater.catY;
                    }
                }
            }
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
