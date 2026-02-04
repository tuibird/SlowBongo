import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

NScrollView {
    id: root
    horizontalPolicy: ScrollBar.AlwaysOff

    property var pluginApi: null

    property bool evtestInstalled: false
    property bool inInputGroup: false

    property var selectedDevices: {
        let saved = pluginApi?.pluginSettings?.inputDevices
        if (saved && saved.length > 0) return saved
        let legacy = pluginApi?.pluginSettings?.inputDevice
            ?? pluginApi?.manifest?.metadata?.defaultSettings?.inputDevice
        return legacy ? [legacy] : []
    }
    property var inputDevices: []

    function isSelected(key) {
        return root.selectedDevices.indexOf(key) >= 0
    }

    function toggleDevice(key) {
        let list = root.selectedDevices.slice()
        let idx = list.indexOf(key)
        if (idx >= 0)
            list.splice(idx, 1)``
        else
            list.push(key)
        root.selectedDevices = list
    }

    Component.onCompleted: {
        evtestCheck.running = true
        groupCheck.running = true
        deviceListProcess.running = true
    }

    Process {
        id: evtestCheck
        command: ["which", "evtest"]
        onExited: function(exitCode, exitStatus) {
            root.evtestInstalled = (exitCode === 0)
        }
    }

    Process {
        id: groupCheck
        command: ["sh", "-c", "groups | tr ' ' '\\n' | grep -qx input"]
        onExited: function(exitCode, exitStatus) {
            root.inInputGroup = (exitCode === 0)
        }
    }

    Process {
        id: deviceListProcess
        command: ["sh", "-c", "for f in /dev/input/by-id/*; do echo \"$(basename \"$f\")|$(readlink -f \"$f\")\"; done 2>/dev/null"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length === 0) return
                const parts = line.split("|")
                if (parts.length < 2) return
                const byIdName = parts[0]
                const resolved = parts[1]
                if (!resolved.startsWith("/dev/input/event")) return
                const eventNum = resolved.replace(/.*\//, "")
                let friendly = byIdName
                    .replace(/^usb-/, "")
                    .replace(/-event-\w+$/, "")
                    .replace(/-if\d+$/, "")
                    .replace(/_/g, " ")
                root.inputDevices = root.inputDevices.concat([{
                    key: "/dev/input/by-id/" + byIdName,
                    name: friendly,
                    eventDev: eventNum
                }])
            }
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Style.marginL

        NLabel {
            label: "Requirements Check"
            description: "Checks if evtest is installed and if the user is in the input group"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            RowLayout {
                spacing: Style.marginS

                NIcon {
                    icon: root.evtestInstalled ? "circle-check-filled" : "circle-x-filled"
                    color: root.evtestInstalled ? Color.mPrimary : Color.mError
                    pointSize: Style.fontSizeM
                }

                Text {
                    text: root.evtestInstalled ? "evtest is installed" : "evtest is not installed"
                    color: root.evtestInstalled ? Color.mPrimary : Color.mError
                    font.pointSize: Style.fontSizeM
                }
            }

            RowLayout {
                spacing: Style.marginS

                NIcon {
                    icon: root.inInputGroup ? "circle-check-filled" : "circle-x-filled"
                    color: root.inInputGroup ? Color.mPrimary : Color.mError
                    pointSize: Style.fontSizeM
                }

                Text {
                    text: root.inInputGroup ? "User is in the input group" : "User is not in the input group"
                    color: root.inInputGroup ? Color.mPrimary : Color.mError
                    font.pointSize: Style.fontSizeM
                }
            }
        }

        NLabel {
            label: "Input Devices"
            description: "Select one or more input devices to listen for key events"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS

            Repeater {
                model: root.inputDevices

                Rectangle {
                    required property var modelData

                    property bool isChecked: root.isSelected(modelData.key)
                    property bool isHovered: mouseArea.containsMouse

                    Layout.fillWidth: true
                    implicitHeight: rowContent.implicitHeight + Style.marginS * 2
                    radius: Style.iRadiusXS
                    color: isHovered ? Color.mSurfaceContainer : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Style.animationFast }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.toggleDevice(modelData.key)
                    }

                    RowLayout {
                        id: rowContent
                        anchors.fill: parent
                        anchors.leftMargin: Style.marginS
                        anchors.rightMargin: Style.marginS
                        spacing: Style.marginL

                        Rectangle {
                            id: checkBox
                            implicitWidth: Math.round(Style.baseWidgetSize * 0.7)
                            implicitHeight: Math.round(Style.baseWidgetSize * 0.7)
                            radius: Style.iRadiusXS
                            color: isChecked ? Color.mPrimary : Color.mSurface
                            border.color: isHovered ? Color.mPrimary : Color.mOutline
                            border.width: Style.borderS

                            Behavior on color {
                                ColorAnimation { duration: Style.animationFast }
                            }
                            Behavior on border.color {
                                ColorAnimation { duration: Style.animationFast }
                            }

                            NIcon {
                                visible: isChecked
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: -1
                                icon: "check"
                                color: Color.mOnPrimary
                                pointSize: Math.max(Style.fontSizeXS, checkBox.implicitWidth * 0.5)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: modelData.name
                                color: Color.mOnSurface
                                font.pointSize: Style.fontSizeM
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: modelData.eventDev
                                color: Color.mOnSurfaceVariant
                                font.pointSize: Style.fontSizeS
                                visible: text !== ""
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS

            NIcon {
                id: savedIcon
                icon: "circle-check"
                color: Color.mPrimary
                pointSize: Style.fontSizeM
                opacity: 0
            }

            Text {
                id: savedLabel
                text: "Saved!"
                color: Color.mPrimary
                font.pointSize: Style.fontSizeM
                font.weight: Font.DemiBold
                opacity: 0
            }
        }

    }

    

    SequentialAnimation {
        id: savedAnim

        NumberAnimation {
            targets: [savedIcon, savedLabel]
            property: "opacity"
            to: 1
            duration: 150
            easing.type: Easing.OutCubic
        }

        PauseAnimation { duration: 1500 }

        NumberAnimation {
            targets: [savedIcon, savedLabel]
            property: "opacity"
            to: 0
            duration: 300
            easing.type: Easing.InCubic
        }
    }

    function saveSettings() {
        if (!pluginApi) {
            Logger.e("SlowBongo", "Cannot save settings: pluginApi is null")
            return
        }
        pluginApi.pluginSettings.inputDevices = root.selectedDevices
        pluginApi.saveSettings()
        savedAnim.restart()
        Logger.i("SlowBongo", "Settings saved successfully")
    }
}
