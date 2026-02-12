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
    property bool waiting: false
    property bool blinking: false

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
    readonly property int waitingTimeout: pluginApi?.pluginSettings?.waitingTimeout ?? pluginApi?.manifest?.metadata?.defaultSettings?.waitingTimeout ?? 5000
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
            if (root.paused) return;
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
        root.waiting = false;
        root.leftWasLast = !root.leftWasLast;
        root.catState = root.leftWasLast ? 1 : 2;
        idleTimer.restart();
        waitingTimer.restart();
    }

    onPausedChanged: {
        if (root.paused) {
            idleTimer.stop();
            waitingTimer.stop();
            root.waiting = false;
            root.blinking = false;
            root.catState = 0;
        } else {
            waitingTimer.restart();
        }
    }

    onWaitingChanged: {
        if (root.waiting) {
            root.blinking = false;
        }
    }

    Timer {
        id: idleTimer
        interval: root.idleTimeout
        repeat: false
        onTriggered: root.catState = 0
    }

    Timer {
        id: waitingTimer
        interval: root.waitingTimeout
        repeat: false
        onTriggered: root.waiting = true
    }

    Timer {
        id: blinkIntervalTimer
        interval: 6000 + Math.random() * 8000
        repeat: true
        running: !root.paused && !root.waiting
        onTriggered: {
            interval = 6000 + Math.random() * 8000;
            if (Math.random() < 0.5) {
                root.blinking = true;
                blinkDurationTimer.start();
            } else {
                root.blinkFlutterCount = 0;
                root.blinking = true;
                flutterTimer.start();
            }
        }
    }

    property int blinkFlutterCount: 0

    Timer {
        id: blinkDurationTimer
        interval: 450
        repeat: false
        onTriggered: root.blinking = false
    }

    Timer {
        id: flutterTimer
        interval: 120
        repeat: false
        onTriggered: {
            root.blinkFlutterCount++;
            root.blinking = !root.blinking;
            if (root.blinkFlutterCount < 4) {
                flutterTimer.start();
            } else {
                root.blinking = false;
            }
        }
    }

    Repeater {
        model: root.inputDevices

        Item {
            id: deviceMonitor
            required property string modelData

            property int retryCount: 0
            property bool hasNotified: false
            readonly property var retryIntervals: [30000, 90000, 300000] // 30s, 1:30, 5min

            Process {
                id: evtestProc
                command: ["evtest", deviceMonitor.modelData]
                running: true

                stdout: SplitParser {
                    onRead: data => {
                        if (data.includes("EV_KEY") && data.includes("value 1")) root.onKeyPress();
                    }
                }

                stderr: StdioCollector {}

                onRunningChanged: {
                    if (running) {
                        // Successfully started - reset retry counter and notification flag
                        deviceMonitor.retryCount = 0;
                        deviceMonitor.hasNotified = false;
                    }
                }

                onExited: exitCode => {
                    Logger.w("Slow Bongo", "evtest (" + deviceMonitor.modelData + ") exited with code " + exitCode);

                    if (exitCode !== 0) {
                        deviceMonitor.retryCount++;

                        // Only show notification on first failure to avoid spam
                        if (!deviceMonitor.hasNotified) {
                            ToastService.showWarning(
                                root.pluginApi?.tr("toast.evtest-error") ?? "SlowBongo",
                                root.pluginApi?.tr("toast.device-disconnected") ?? ("Device disconnected: " + deviceMonitor.modelData)
                            );
                            deviceMonitor.hasNotified = true;
                        }

                        // Check to continue retrying
                        if (deviceMonitor.retryCount <= deviceMonitor.retryIntervals.length) {
                            const interval = deviceMonitor.retryIntervals[deviceMonitor.retryCount - 1];
                            const intervalSec = Math.floor(interval / 1000);
                            Logger.i("Slow Bongo", "Will retry in " + intervalSec + "s (attempt " + deviceMonitor.retryCount + "/" + deviceMonitor.retryIntervals.length + ")");
                            restartTimer.interval = interval;
                            restartTimer.start();
                        } else {
                            Logger.w("Slow Bongo", "Max retries reached for device: " + deviceMonitor.modelData + ". Giving up.");
                            ToastService.showInfo(
                                root.pluginApi?.tr("toast.device-gave-up") ?? "SlowBongo",
                                root.pluginApi?.tr("toast.device-gave-up-desc") ?? ("Stopped trying to reconnect to: " + deviceMonitor.modelData)
                            );
                        }
                    } else {
                        // Clean exit (exitCode 0) - don't spam, just quietly retry once
                        restartTimer.interval = deviceMonitor.retryIntervals[0];
                        restartTimer.start();
                    }
                }
            }

            Timer {
                id: restartTimer
                repeat: false
                onTriggered: {
                    // Check if device file exists before attempting restart
                    deviceCheckProc.running = true;
                }
            }

            // Check if device file exists before restarting evtest
            Process {
                id: deviceCheckProc
                command: ["test", "-e", deviceMonitor.modelData]
                running: false

                onExited: exitCode => {
                    if (exitCode === 0) {
                        // Device exists, safe to restart evtest
                        Logger.i("Slow Bongo", "Device detected, restarting monitoring: " + deviceMonitor.modelData);
                        evtestProc.running = true;
                    } else {
                        // Device doesn't exist, schedule next check
                        if (deviceMonitor.retryCount <= deviceMonitor.retryIntervals.length) {
                            Logger.i("Slow Bongo", "Device not found, will check again: " + deviceMonitor.modelData);
                            restartTimer.start();
                        }
                    }
                }
            }
        }
    }
}
