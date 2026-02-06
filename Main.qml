import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Media

Item {
    id: root

    property var pluginApi: null

    // Unique instance ID for CavaService registration
    readonly property string cavaInstanceId: "plugin:slowbongo:" + Date.now() + Math.random()

    property int catState: 0  // 0 = idle (both paws up), 1 = left slap, 2 = right slap
    property bool leftWasLast: false  // Track which paw slapped last to alternate
    property bool paused: false

    readonly property bool needsAutoDetect: {
        const saved = pluginApi?.pluginSettings?.inputDevices;
        if (saved && saved.length > 0) return false;
        const legacy = pluginApi?.pluginSettings?.inputDevice ?? pluginApi?.manifest?.metadata?.defaultSettings?.inputDevice;
        return !legacy;
    }

    readonly property var inputDevices: {
        const saved = pluginApi?.pluginSettings?.inputDevices;
        if (saved && saved.length > 0) return saved;
        const legacy = pluginApi?.pluginSettings?.inputDevice ?? pluginApi?.manifest?.metadata?.defaultSettings?.inputDevice;
        if (legacy) return [legacy];
        return ["/dev/input/event0"];
    }

    property var autoDetectedDevices: []

    // Try by-id first for keyboard devices
    Process {
        id: detectByIdProcess
        command: ["sh", "-c", "for f in /dev/input/by-id/*-event-kbd; do [ -e \"$f\" ] && echo \"$f\"; done"]
        running: root.needsAutoDetect

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line.length > 0) root.autoDetectedDevices = root.autoDetectedDevices.concat([line]);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (root.autoDetectedDevices.length === 0) {
                detectEvtestProcess.running = true;
            } else {
                saveDetectedDevices();
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
                const line = data.trim();
                if (line.match(/keyboard|keypad/i)) {
                    const match = line.match(/^(\/dev\/input\/event\d+):/);
                    if (match) root.autoDetectedDevices = root.autoDetectedDevices.concat([match[1]]);
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (root.autoDetectedDevices.length === 0) {
                detectFallbackProcess.running = true;
            } else {
                saveDetectedDevices();
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
                const line = data.trim();
                if (line.length > 0) root.autoDetectedDevices = root.autoDetectedDevices.concat([line]);
            }
        }

        onExited: (exitCode, exitStatus) => saveDetectedDevices()
    }

    function saveDetectedDevices() {
        if (root.autoDetectedDevices.length > 0 && root.pluginApi) {
            root.pluginApi.pluginSettings.inputDevices = root.autoDetectedDevices;
            root.pluginApi.saveSettings();
            Logger.i("SlowBongo", "Auto-detected " + root.autoDetectedDevices.length + " keyboard device(s), saved to settings");
        }
    }

    onPluginApiChanged: {
        if (pluginApi) {
            CavaService.registerComponent(cavaInstanceId);
            Logger.i("SlowBongo", "Registered with CavaService for audio detection");
        }
    }

    Component.onDestruction: CavaService.unregisterComponent(cavaInstanceId)

    readonly property int idleTimeout: pluginApi?.pluginSettings?.idleTimeout ?? pluginApi?.manifest?.metadata?.defaultSettings?.idleTimeout ?? 500
    readonly property string catColor: pluginApi?.pluginSettings?.catColor ?? pluginApi?.manifest?.metadata?.defaultSettings?.catColor ?? "default"
    readonly property real catSize: pluginApi?.pluginSettings?.catSize ?? pluginApi?.manifest?.metadata?.defaultSettings?.catSize ?? 1.0
    readonly property real catOffsetY: pluginApi?.pluginSettings?.catOffsetY ?? pluginApi?.manifest?.metadata?.defaultSettings?.catOffsetY ?? 0.0
    readonly property bool raveMode: pluginApi?.pluginSettings?.raveMode ?? pluginApi?.manifest?.metadata?.defaultSettings?.raveMode ?? false
    readonly property bool tappyMode: pluginApi?.pluginSettings?.tappyMode ?? pluginApi?.manifest?.metadata?.defaultSettings?.tappyMode ?? false

    readonly property bool anyMusicPlaying: !CavaService.isIdle
    property int rainbowIndex: 0
    readonly property var rainbowColors: ['#aa0000', '#b65c02', '#bb9c14', '#00a100', '#01019b', '#37005c', '#6a0196']
    property real audioIntensity: 0
    property real smoothedIntensity: 0
    readonly property real beatThreshold: 0.20
    readonly property bool useTappyMode: tappyMode && anyMusicPlaying

    Connections {
        target: CavaService
        function onValuesChanged() {
            if (!root.useRaveColors && !root.useTappyMode) return;

            if (!CavaService.values || CavaService.values.length === 0) {
                root.audioIntensity = 0;
                return;
            }

            let bassSum = 0;
            let midSum = 0;
            const bassCount = Math.min(8, CavaService.values.length);
            const midCount = Math.min(16, CavaService.values.length);

            for (let i = 0; i < bassCount; i++) {
                bassSum += CavaService.values[i] || 0;
            }

            for (let i = 8; i < midCount; i++) {
                midSum += CavaService.values[i] || 0;
            }

            const bassAvg = bassSum / bassCount;
            const midAvg = midSum / Math.max(1, midCount - 8);
            root.audioIntensity = (bassAvg * 0.8) + (midAvg * 0.6);

            const alpha = 0.4;
            root.smoothedIntensity = alpha * root.audioIntensity + (1 - alpha) * root.smoothedIntensity;

            if (root.smoothedIntensity > root.beatThreshold) {
                if (!beatCooldownTimer.running) {
                    if (root.useRaveColors) {
                        root.rainbowIndex = (root.rainbowIndex + 1) % root.rainbowColors.length;
                        root.isFlashing = true;
                        flashTimer.restart();
                    }

                    if (root.useTappyMode) root.onKeyPress();

                    beatCooldownTimer.restart();
                }
            }
        }
    }

    property bool isFlashing: false

    Timer {
        id: beatCooldownTimer
        interval: 150
        repeat: false
    }

    Timer {
        id: flashTimer
        interval: 100
        repeat: false
        onTriggered: root.isFlashing = false
    }

    readonly property string currentRainbowColor: rainbowColors[rainbowIndex]
    readonly property bool useRaveColors: raveMode && anyMusicPlaying
    readonly property bool showRainbowColor: useRaveColors && isFlashing

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

                onExited: (exitCode, exitStatus) => {
                    Logger.w("SlowBongo", "evtest (" + modelData + ") exited with code " + exitCode + ", restarting...");
                    restartTimer.start();
                }

                stdout: SplitParser {
                    onRead: data => {
                        if (data.includes("EV_KEY") && data.includes("value 1")) root.onKeyPress();
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
