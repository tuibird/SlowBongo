import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
    id: root

    property var pluginApi: null

    // 0 = idle (both paws up), 1 = left slap, 2 = right slap
    property int catState: 0

    // Track which paw slapped last to alternate
    property bool leftWasLast: false

    property bool paused: false

    readonly property bool needsAutoDetect: {
        let saved = pluginApi?.pluginSettings?.inputDevices
        if (saved && saved.length > 0) return false
        let legacy = pluginApi?.pluginSettings?.inputDevice
            ?? pluginApi?.manifest?.metadata?.defaultSettings?.inputDevice
        return !legacy
    }

    readonly property var inputDevices: {
        let saved = pluginApi?.pluginSettings?.inputDevices
        if (saved && saved.length > 0) return saved
        let legacy = pluginApi?.pluginSettings?.inputDevice
            ?? pluginApi?.manifest?.metadata?.defaultSettings?.inputDevice
        if (legacy) return [legacy]
        return ["/dev/input/event0"]
    }

    property var autoDetectedDevices: []

    // Try by-id first for keyboard devices
    Process {
        id: detectByIdProcess
        command: ["sh", "-c", "for f in /dev/input/by-id/*-event-kbd; do [ -e \"$f\" ] && echo \"$f\"; done"]
        running: root.needsAutoDetect

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length > 0)
                    root.autoDetectedDevices = root.autoDetectedDevices.concat([line])
            }
        }

        onExited: function(exitCode, exitStatus) {
            // If no by-id keyboards found, try evtest
            if (root.autoDetectedDevices.length === 0) {
                detectEvtestProcess.running = true
            } else {
                saveDetectedDevices()
            }
        }
    }

    // Fallback: use evtest to find keyboard devices
    Process {
        id: detectEvtestProcess
        command: ["evtest"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                // Look for lines with "keyboard" or "keypad"
                if (line.match(/keyboard|keypad/i)) {
                    const match = line.match(/^(\/dev\/input\/event\d+):/)
                    if (match) {
                        root.autoDetectedDevices = root.autoDetectedDevices.concat([match[1]])
                    }
                }
            }
        }

        onExited: function(exitCode, exitStatus) {
            // If evtest found nothing, fall back to event3
            if (root.autoDetectedDevices.length === 0) {
                detectFallbackProcess.running = true
            } else {
                saveDetectedDevices()
            }
        }
    }

    // Final fallback: try /dev/input/event3 (common for laptop keyboards)
    Process {
        id: detectFallbackProcess
        command: ["sh", "-c", "[ -c /dev/input/event3 ] && echo /dev/input/event3"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length > 0)
                    root.autoDetectedDevices = root.autoDetectedDevices.concat([line])
            }
        }

        onExited: function(exitCode, exitStatus) {
            saveDetectedDevices()
        }
    }

    function saveDetectedDevices() {
        if (root.autoDetectedDevices.length > 0 && root.pluginApi) {
            root.pluginApi.pluginSettings.inputDevices = root.autoDetectedDevices
            root.pluginApi.saveSettings()
            Logger.i("SlowBongo", "Auto-detected " + root.autoDetectedDevices.length + " keyboard device(s), saved to settings")
        }
    }

    readonly property int idleTimeout: pluginApi?.pluginSettings?.idleTimeout
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.idleTimeout
        ?? 500

    readonly property string catColor: pluginApi?.pluginSettings?.catColor
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.catColor
        ?? "default"

    readonly property real catSize: pluginApi?.pluginSettings?.catSize
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.catSize
        ?? 1.0

    readonly property real catOffsetY: pluginApi?.pluginSettings?.catOffsetY
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.catOffsetY
        ?? 0.0

    function onKeyPress() {
        if (root.paused) return;
        root.leftWasLast = !root.leftWasLast;
        root.catState = root.leftWasLast ? 1 : 2;
        idleTimer.restart();
    }

    onPausedChanged: {
        if (root.paused) {
            idleTimer.stop();
            root.catState = 0;
        }
    }

    Timer {
        id: idleTimer
        interval: root.idleTimeout
        repeat: false
        onTriggered: root.catState = 0
    }

    Repeater {
        model: root.inputDevices

        Item {
            required property string modelData

            Process {
                id: evtestProc
                command: ["evtest", modelData]
                running: true

                onExited: function(exitCode, exitStatus) {
                    Logger.w("SlowBongo", "evtest (" + modelData + ") exited with code " + exitCode + ", restarting...")
                    restartTimer.start();
                }

                stdout: SplitParser {
                    onRead: data => {
                        if (data.includes("EV_KEY") && data.includes("value 1")) {
                            root.onKeyPress();
                        }
                    }
                }
            }

            Timer {
                id: restartTimer
                interval: 2000
                repeat: false
                onTriggered: evtestProc.running = true
            }
        }
    }
}
