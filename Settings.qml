import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    spacing: Style.marginL

    property var pluginApi: null

    // Requirement check states
    property bool evtestInstalled: false
    property bool inInputGroup: false
    property bool cavaInstalled: false
    property string currentUser: ""

    // Editable settings properties
    property string editCatColor: {
        let saved = pluginApi?.pluginSettings?.catColor
        if (saved && saved.length > 0) return saved
        return pluginApi?.manifest?.metadata?.defaultSettings?.catColor ?? "default"
    }

    property real editCatSize: {
        let saved = pluginApi?.pluginSettings?.catSize
        if (saved !== undefined && saved !== null) return saved
        return pluginApi?.manifest?.metadata?.defaultSettings?.catSize ?? 1.0
    }

    property real editCatOffsetY: {
        let saved = pluginApi?.pluginSettings?.catOffsetY
        if (saved !== undefined && saved !== null) return saved
        return pluginApi?.manifest?.metadata?.defaultSettings?.catOffsetY ?? 0.0
    }

    property var editInputDevices: {
        let saved = pluginApi?.pluginSettings?.inputDevices
        if (saved && saved.length > 0) return saved
        let legacy = pluginApi?.pluginSettings?.inputDevice
            ?? pluginApi?.manifest?.metadata?.defaultSettings?.inputDevice
        return legacy ? [legacy] : []
    }

    property bool editRaveMode: {
        let saved = pluginApi?.pluginSettings?.raveMode
        if (saved !== undefined && saved !== null) return saved
        return pluginApi?.manifest?.metadata?.defaultSettings?.raveMode ?? false
    }

    property bool editTappyMode: {
        let saved = pluginApi?.pluginSettings?.tappyMode
        if (saved !== undefined && saved !== null) return saved
        return pluginApi?.manifest?.metadata?.defaultSettings?.tappyMode ?? false
    }

    property bool editUseMprisFilter: {
        let saved = pluginApi?.pluginSettings?.useMprisFilter
        if (saved !== undefined && saved !== null) return saved
        return pluginApi?.manifest?.metadata?.defaultSettings?.useMprisFilter ?? false
    }

    // Status colors (with fallback for theme compatibility)
    readonly property color statusSuccessColor: Color.mSuccess ?? Color.mPrimary
    readonly property color statusErrorColor: Color.mError ?? "#c00202"

    // Configuration data
    readonly property var colorOptions: [
        { key: "default",   labelKey: "colors.default",   color: Color.mOnSurface },
        { key: "primary",   labelKey: "colors.primary",   color: Color.mPrimary },
        { key: "secondary", labelKey: "colors.secondary", color: Color.mSecondary },
        { key: "tertiary",  labelKey: "colors.tertiary",  color: Color.mTertiary },
    ]

    property var inputDevices: []

    function isSelected(key) {
        return root.editInputDevices.indexOf(key) >= 0
    }

    function toggleDevice(key) {
        let list = root.editInputDevices.slice()
        let idx = list.indexOf(key)
        if (idx >= 0)
            list.splice(idx, 1)
        else
            list.push(key)
        root.editInputDevices = list
    }

    Component.onCompleted: {
        evtestCheck.running = true
        cavaCheck.running = true
        userCheck.running = true
        byIdListProcess.running = true
    }

    Process {
        id: evtestCheck
        command: ["which", "evtest"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode, exitStatus) {
            root.evtestInstalled = (exitCode == 0)
        }
    }

    Process {
        id: cavaCheck
        command: ["which", "cava"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode, exitStatus) {
            root.cavaInstalled = (exitCode == 0)
        }
    }

    Process {
        id: userCheck
        command: ["id", "-un"]
        stdout: SplitParser {
            onRead: data => {
                root.currentUser = data.trim()
            }
        }
        stderr: StdioCollector {}
        onExited: function(exitCode, exitStatus) {
            if (exitCode == 0 && root.currentUser.length > 0)
                groupCheck.running = true
        }
    }

    Process {
        id: groupCheck
        command: ["sh", "-c", "id -nG '" + root.currentUser + "' | tr ' ' '\\n' | grep -qx input"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode, exitStatus) {
            root.inInputGroup = (exitCode == 0)
        }
    }

    // Try by-id first
    Process {
        id: byIdListProcess
        command: ["sh", "-c", "[ -d /dev/input/by-id ] && for f in /dev/input/by-id/*-event-*; do [ -e \"$f\" ] && echo \"$(basename \"$f\")|$(readlink -f \"$f\")\"; done || true"]

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length === 0) return
                const parts = line.split("|")
                if (parts.length !== 2) return
                const name = parts[0]
                const resolved = parts[1]
                if (!resolved.startsWith("/dev/input/event")) return

                const eventNum = resolved.replace(/.*\//, "")
                let friendly = name
                    .replace(/^usb-/, "")
                    .replace(/-event-\w+$/, "")
                    .replace(/-if\d+$/, "")
                    .replace(/_/g, " ")

                root.inputDevices = root.inputDevices.concat([{
                    key: resolved,
                    name: friendly,
                    eventDev: eventNum
                }])
            }
        }

        stderr: StdioCollector {}

        onExited: function(exitCode, exitStatus) {
            // Always try to get names from sysfs
            sysfsListProcess.running = true
        }
    }

    // Get device names from sysfs
    Process {
        id: sysfsListProcess
        command: ["sh", "-c", "for f in /dev/input/event*; do [ -c \"$f\" ] && echo \"$f|$(cat /sys/class/input/$(basename $f)/device/name 2>/dev/null || basename $f)\"; done"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length === 0) return
                const parts = line.split("|")
                if (parts.length !== 2) return
                const device = parts[0]
                const name = parts[1]
                const eventNum = device.replace(/.*\//, "")

                // Filter out non-keyboardy devices
                const nameLower = name.toLowerCase()
                const excludePatterns = [
                    /power button/i,
                    /sleep button/i,
                    /lid switch/i,
                    /video bus/i,
                    /audio/i,
                    /hdmi/i,
                    /speaker/i,
                    /headphone/i,
                    /mic\b/i
                ]

                const shouldExclude = excludePatterns.some(pattern => pattern.test(name))
                if (shouldExclude) return

                // Check if we already have this device from by-id
                const exists = root.inputDevices.some(d => d.key === device)
                if (!exists) {
                    root.inputDevices = root.inputDevices.concat([{
                        key: device,
                        name: name,
                        eventDev: eventNum
                    }])
                }
            }
        }

        stderr: StdioCollector {}
    }

    // Requirements Section
    Text {
        text: pluginApi?.tr("settings.requirements") || "Requirements"
        color: Color.mOnSurface
        font.family: Style.fontFamily
        font.pointSize: Style.fontSizeM
        font.weight: Font.DemiBold
    }

    NBox {
        Layout.fillWidth: true
        implicitHeight: reqContent.implicitHeight + Style.marginM * 2

        ColumnLayout {
            id: reqContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.marginM
            spacing: Style.marginS

            RowLayout {
                spacing: Style.marginS
                NIcon {
                    icon: root.evtestInstalled ? "circle-check-filled" : "circle-x-filled"
                    color: root.evtestInstalled ? root.statusSuccessColor : root.statusErrorColor
                    pointSize: Style.fontSizeM
                }
                Text {
                    text: root.evtestInstalled
                        ? (pluginApi?.tr("settings.evtest-installed") || "evtest is installed")
                        : (pluginApi?.tr("settings.evtest-not-installed") || "evtest is not installed")
                    color: root.evtestInstalled ? root.statusSuccessColor : root.statusErrorColor
                    font.pointSize: Style.fontSizeM
                }
            }

            RowLayout {
                spacing: Style.marginS
                NIcon {
                    icon: root.inInputGroup ? "circle-check-filled" : "circle-x-filled"
                    color: root.inInputGroup ? root.statusSuccessColor : root.statusErrorColor
                    pointSize: Style.fontSizeM
                }
                Text {
                    text: root.inInputGroup
                        ? (pluginApi?.tr("settings.in-input-group") || "User is in the input group")
                        : (pluginApi?.tr("settings.not-in-input-group") || "User is not in the input group")
                    color: root.inInputGroup ? root.statusSuccessColor : root.statusErrorColor
                    font.pointSize: Style.fontSizeM
                }
            }

            RowLayout {
                spacing: Style.marginS
                NIcon {
                    icon: root.cavaInstalled ? "circle-check-filled" : "circle-x-filled"
                    color: root.cavaInstalled ? root.statusSuccessColor : root.statusErrorColor
                    pointSize: Style.fontSizeM
                }
                Text {
                    text: root.cavaInstalled
                        ? (pluginApi?.tr("settings.cava-installed") || "cava is installed (for rave mode)")
                        : (pluginApi?.tr("settings.cava-not-installed") || "cava is not installed (rave mode won't work)")
                    color: root.cavaInstalled ? root.statusSuccessColor : root.statusErrorColor
                    font.pointSize: Style.fontSizeM
                }
            }
        }
    }

    NDivider {
        Layout.fillWidth: true
    }

    // Input Devices Section
    Text {
        text: pluginApi?.tr("settings.input-devices") || "Input Devices"
        color: Color.mOnSurface
        font.family: Style.fontFamily
        font.pointSize: Style.fontSizeM
        font.weight: Font.DemiBold
    }

    NBox {
        Layout.fillWidth: true
        implicitHeight: Math.min(devContent.implicitHeight + Style.marginM * 2, 400)

        NScrollView {
            id: deviceScrollView
            anchors.fill: parent
            anchors.margins: Style.marginM
            horizontalPolicy: ScrollBar.AlwaysOff

            ColumnLayout {
                id: devContent
                width: deviceScrollView.availableWidth
                spacing: Style.marginS

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
                            spacing: Style.marginM

                            Rectangle {
                                id: checkBox
                                implicitWidth: Math.round(Style.baseWidgetSize * 0.7)
                                implicitHeight: Math.round(Style.baseWidgetSize * 0.7)
                                radius: Style.iRadiusXS
                                color: parent.parent.isChecked ? Color.mPrimary : Color.mSurface
                                border.color: parent.parent.isHovered ? Color.mPrimary : Color.mOutline
                                border.width: Style.borderS

                                Behavior on color {
                                    ColorAnimation { duration: Style.animationFast }
                                }
                                Behavior on border.color {
                                    ColorAnimation { duration: Style.animationFast }
                                }

                                NIcon {
                                    visible: parent.parent.parent.isChecked
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
                                    text: parent.parent.parent.modelData.name
                                    color: Color.mOnSurface
                                    font.pointSize: Style.fontSizeM
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: parent.parent.parent.modelData.eventDev
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
        }
    }

    NDivider {
        Layout.fillWidth: true
    }

    // Colours Section
    Text {
        text: pluginApi?.tr("settings.colours") || "Colours"
        color: Color.mOnSurface
        font.family: Style.fontFamily
        font.pointSize: Style.fontSizeM
        font.weight: Font.DemiBold
    }

    NBox {
        id: colourBox
        Layout.fillWidth: true
        implicitHeight: colourContent.implicitHeight + Style.marginM * 2

        property int circleSize: Math.round(Style.baseWidgetSize * 0.9)
        property int columnCount: root.colorOptions.length
        property real availableInner: colourBox.width - Style.marginM * 2
        property real columnWidth: columnCount > 0 ? availableInner / columnCount : 0

        ColumnLayout {
            id: colourContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.marginM
            spacing: 0

            Row {
                id: colourRow
                Layout.fillWidth: true

                Repeater {
                    model: root.colorOptions

                    Item {
                        required property var modelData
                        required property int index

                        width: colourBox.columnWidth
                        height: colorCol.implicitHeight

                        ColumnLayout {
                            id: colorCol
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Style.marginXS

                            Rectangle {
                                id: colorCircle
                                property bool isSelected: root.editCatColor === modelData.key
                                property bool isHovered: circleMouseArea.containsMouse

                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: colourBox.circleSize
                                implicitHeight: implicitWidth
                                radius: width / 2
                                color: modelData.color
                                border.color: isSelected ? Color.mOnSurface : "transparent"
                                border.width: isSelected ? Style.borderS + 1 : 0
                                scale: isHovered ? 1.15 : 1.0

                                Behavior on scale {
                                    NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic }
                                }
                                Behavior on border.color {
                                    ColorAnimation { duration: Style.animationFast }
                                }

                                MouseArea {
                                    id: circleMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.editCatColor = modelData.key
                                }

                                NIcon {
                                    anchors.centerIn: parent
                                    icon: "check"
                                    pointSize: Math.max(Style.fontSizeXS, colorCircle.implicitWidth * 0.4)
                                    color: Color.mOnPrimary
                                    visible: colorCircle.isSelected
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: pluginApi?.tr(modelData.labelKey) || modelData.key.charAt(0).toUpperCase() + modelData.key.slice(1)
                                color: Color.mOnSurfaceVariant
                                font.pointSize: Style.fontSizeS
                            }
                        }
                    }
                }
            }
        }
    }

    // Rave Mode
    NToggle {
        label: pluginApi?.tr("settings.rave-mode") || "Rave Mode"
        description: pluginApi?.tr("settings.rave-mode-desc") || "Change colors to the beat when music is playing"
        checked: root.editRaveMode
        onToggled: checked => root.editRaveMode = checked
        defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.raveMode ?? false
    }

    // Tappy Mode
    NToggle {
        label: pluginApi?.tr("settings.tappy-mode") || "Tappy Mode"
        description: pluginApi?.tr("settings.tappy-mode-desc") || "Make the cat tap along to the beat when music is playing"
        checked: root.editTappyMode
        onToggled: checked => root.editTappyMode = checked
        defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.tappyMode ?? false
    }

    // MPRIS Filtering
    NToggle {
        label: pluginApi?.tr("settings.mpris-filter") || "MPRIS Filtering"
        description: pluginApi?.tr("settings.mpris-filter-desc") || "Only react to audio when a non-blacklisted media player is playing (uses NoctalisShell audio blacklist)"
        checked: root.editUseMprisFilter
        onToggled: checked => root.editUseMprisFilter = checked
        defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.useMprisFilter ?? false
    }

    NDivider {
        Layout.fillWidth: true
    }

    // Cat Size Section
    NValueSlider {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.cat-size") || "Cat Size"
        value: root.editCatSize
        from: 0.5
        to: 1.5
        stepSize: 0.01
        onMoved: value => root.editCatSize = value
    }

    // Vertical Position Section
    NValueSlider {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.vertical-position") || "Vertical Position"
        value: root.editCatOffsetY
        from: -0.5
        to: 0.5
        stepSize: 0.01
        onMoved: value => root.editCatOffsetY = value
    }

    function saveSettings() {
        if (!pluginApi) {
            Logger.e("Slow Bongo", "Cannot save settings: pluginApi is null")
            return
        }
        pluginApi.pluginSettings.inputDevices = root.editInputDevices
        pluginApi.pluginSettings.catColor = root.editCatColor
        pluginApi.pluginSettings.catSize = root.editCatSize
        pluginApi.pluginSettings.catOffsetY = root.editCatOffsetY
        pluginApi.pluginSettings.raveMode = root.editRaveMode
        pluginApi.pluginSettings.tappyMode = root.editTappyMode
        pluginApi.pluginSettings.useMprisFilter = root.editUseMprisFilter
        pluginApi.saveSettings()
        Logger.i("Slow Bongo", "Settings saved successfully")
    }
}
