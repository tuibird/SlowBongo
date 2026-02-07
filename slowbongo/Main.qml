import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Media
import qs.Services.UI

Item {
    id: root

    // === EXTERNAL API ===
    property var pluginApi: null

    // === CORE STATE ===
    property int catState: 0  // 0 = idle (both paws up), 1 = left slap, 2 = right slap
    property bool leftWasLast: false  // Track which paw slapped last to alternate
    property bool paused: false

    // === INSTANCE IDENTIFICATION ===
    readonly property string cavaInstanceId: "plugin:slowbongo:" + Date.now() + Math.random()

    // === INPUT DEVICES (from settings) ===
    readonly property var inputDevices: {
        const saved = pluginApi?.pluginSettings?.inputDevices;
        if (saved && saved.length > 0) return saved;
        return [];
    }

    onPluginApiChanged: {
        if (pluginApi) {
            CavaService.registerComponent(cavaInstanceId);
            Logger.i("SlowBongo", "Registered with CavaService for audio detection");
        }
    }

    Component.onDestruction: CavaService.unregisterComponent(cavaInstanceId)

    // IPC Handler for external control
    IpcHandler {
        target: "plugin:slowbongo"

        function pause() {
            root.paused = true
        }

        function resume() {
            root.paused = false
        }

        function toggle() {
            root.paused = !root.paused
        }
    }

    // === SETTINGS (from pluginApi) ===
    readonly property int idleTimeout: pluginApi?.pluginSettings?.idleTimeout ?? pluginApi?.manifest?.metadata?.defaultSettings?.idleTimeout ?? 500
    readonly property string catColor: pluginApi?.pluginSettings?.catColor ?? pluginApi?.manifest?.metadata?.defaultSettings?.catColor ?? "default"
    readonly property real catSize: pluginApi?.pluginSettings?.catSize ?? pluginApi?.manifest?.metadata?.defaultSettings?.catSize ?? 1.0
    readonly property real catOffsetY: pluginApi?.pluginSettings?.catOffsetY ?? pluginApi?.manifest?.metadata?.defaultSettings?.catOffsetY ?? 0.0
    readonly property bool raveMode: pluginApi?.pluginSettings?.raveMode ?? pluginApi?.manifest?.metadata?.defaultSettings?.raveMode ?? false
    readonly property bool tappyMode: pluginApi?.pluginSettings?.tappyMode ?? pluginApi?.manifest?.metadata?.defaultSettings?.tappyMode ?? false
    readonly property bool useMprisFilter: pluginApi?.pluginSettings?.useMprisFilter ?? pluginApi?.manifest?.metadata?.defaultSettings?.useMprisFilter ?? false

    // === AUDIO REACTIVE STATE ===
    readonly property bool anyMusicPlaying: !CavaService.isIdle
    property int rainbowIndex: 0
    readonly property var rainbowColors: ['#aa0000', '#b65c02', '#bb9c14', '#00a100', '#01019b', '#37005c', '#6a0196']
    property real audioIntensity: 0
    property real smoothedIntensity: 0
    readonly property real beatThreshold: 0.20
    property bool isFlashing: false

    // === COMPUTED MODE FLAGS ===
    readonly property bool mprisAllowed: !useMprisFilter || MediaService.isPlaying
    readonly property bool useTappyMode: tappyMode && anyMusicPlaying && mprisAllowed
    readonly property string currentRainbowColor: rainbowColors[rainbowIndex]
    readonly property bool useRaveColors: raveMode && anyMusicPlaying && mprisAllowed
    readonly property bool showRainbowColor: useRaveColors && isFlashing

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

                stdout: SplitParser {
                    onRead: data => {
                        if (data.includes("EV_KEY") && data.includes("value 1")) root.onKeyPress();
                    }
                }

                stderr: StdioCollector {}

                onExited: (exitCode, exitStatus) => {
                    Logger.w("Slow Bongo", "evtest (" + modelData + ") exited with code " + exitCode);

                    if (exitCode !== 0) {
                        ToastService.show({
                            title: pluginApi?.tr("toast.evtest-error") || "SlowBongo",
                            message: pluginApi?.tr("toast.evtest-error-desc") || "Keyboard monitoring stopped. Restarting...",
                            timeout: 3000
                        });
                    }

                    restartTimer.start();
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
