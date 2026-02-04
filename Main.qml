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

    Process {
        id: detectKbdProcess
        command: ["sh", "-c", "for f in /dev/input/by-id/*-event-kbd; do [ -e \"$f\" ] && echo \"$f\"; done"]
        running: root.needsAutoDetect

        property var detected: []

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length > 0)
                    detectKbdProcess.detected = detectKbdProcess.detected.concat([line])
            }
        }

        onExited: {
            if (detected.length > 0 && root.pluginApi) {
                root.pluginApi.pluginSettings.inputDevices = detected
                root.pluginApi.saveSettings()
                Logger.i("SlowBongo", "Auto-detected " + detected.length + " keyboard(s), saved to settings")
            }
        }
    }

    readonly property int idleTimeout: pluginApi?.pluginSettings?.idleTimeout
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.idleTimeout
        ?? 500

    readonly property string catColor: pluginApi?.pluginSettings?.catColor
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.catColor
        ?? "default"

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
