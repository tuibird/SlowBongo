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

    // Register with CavaService when pluginApi becomes available
    onPluginApiChanged: {
        if (pluginApi) {
            CavaService.registerComponent(cavaInstanceId)
            Logger.i("SlowBongo", "Registered with CavaService for audio detection")
        }
    }

    Component.onDestruction: {
        CavaService.unregisterComponent(cavaInstanceId)
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

    readonly property int catWeight: pluginApi?.pluginSettings?.catWeight
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.catWeight
        ?? Font.Medium

    readonly property bool raveMode: pluginApi?.pluginSettings?.raveMode
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.raveMode
        ?? false

    readonly property bool tappyMode: pluginApi?.pluginSettings?.tappyMode
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.tappyMode
        ?? false

    // Check if any music/audio is currently playing using CavaService
    readonly property bool anyMusicPlaying: !CavaService.isIdle

    // Rainbow color cycling for rave mode
    property int rainbowIndex: 0
    readonly property var rainbowColors: [
        "#cc0000", // Red
        "#cc6600", // Orange
        "#cccc00", // Yellow 
        "#00cc00", // Green 
        "#0000cc", // Blue 
        "#3d0066", // Indigo
        "#7700aa"  // Violet 
    ]

    // Cached audio intensity - recalculated only when CavaService.values changes
    property real audioIntensity: 0

    // Smoothed beat intensity for less jittery color changes
    property real smoothedIntensity: 0
    readonly property real beatThreshold: 0.20  // Lower threshold for more sensitivity

    // Check if tappy mode should be active
    readonly property bool useTappyMode: tappyMode && anyMusicPlaying

    // Update smoothed intensity and detect beats
    Connections {
        target: CavaService
        function onValuesChanged() {
            // Early return if both modes are disabled - skip all calculations
            if (!root.useRaveColors && !root.useTappyMode) return

            // Calculate audio intensity from bass and mid-range frequencies
            if (!CavaService.values || CavaService.values.length === 0) {
                root.audioIntensity = 0
                return
            }

            // Weight bass (0-7) and mid-range (8-15) frequencies
            let bassSum = 0
            let midSum = 0
            const bassCount = Math.min(8, CavaService.values.length)
            const midCount = Math.min(16, CavaService.values.length)

            // Get bass frequencies (bass drum, kick)
            for (let i = 0; i < bassCount; i++) {
                bassSum += CavaService.values[i] || 0
            }

            // Get mid-range frequencies (snare, vocals, melodic elements)
            for (let i = 8; i < midCount; i++) {
                midSum += CavaService.values[i] || 0
            }

            const bassAvg = bassSum / bassCount
            const midAvg = midSum / Math.max(1, midCount - 8)

            // Weight mid-range more heavily (70% mid, 30% bass) for more sensitivity
            root.audioIntensity = (midAvg * 0.7) + (bassAvg * 0.3)

            // Smooth the intensity with exponential moving average
            const alpha = 0.4  // Smoothing factor (0-1, higher = more responsive)
            root.smoothedIntensity = alpha * root.audioIntensity + (1 - alpha) * root.smoothedIntensity

            // Detect beat (intensity spike)
            if (root.smoothedIntensity > root.beatThreshold) {
                if (!beatCooldownTimer.running) {
                    // Rave mode: change color
                    if (root.useRaveColors) {
                        // Advance to next rainbow color
                        root.rainbowIndex = (root.rainbowIndex + 1) % root.rainbowColors.length
                        // Flash the rainbow color
                        root.isFlashing = true
                        flashTimer.restart()
                    }

                    // Tappy mode: make cat tap
                    if (root.useTappyMode) {
                        root.onKeyPress()
                    }

                    // Start cooldown to prevent rapid firing
                    beatCooldownTimer.restart()
                }
            }
        }
    }

    // Flash state - true when showing rainbow color, false when showing base color
    property bool isFlashing: false

    // Cooldown timer to prevent color changes from happening too rapidly
    Timer {
        id: beatCooldownTimer
        interval: 150  // Minimum time between color changes (ms) - increased for performance
        repeat: false
    }

    // Flash duration timer - how long to show the rainbow color before returning to base
    Timer {
        id: flashTimer
        interval: 100  // Show rainbow color for 100ms
        repeat: false
        onTriggered: {
            root.isFlashing = false
        }
    }

    readonly property string currentRainbowColor: rainbowColors[rainbowIndex]

    // Should we use rave mode colors?
    readonly property bool useRaveColors: raveMode && anyMusicPlaying

    // The actual color to display - flash rainbow on beat, otherwise show base color
    readonly property bool showRainbowColor: useRaveColors && isFlashing

    // Debug logging - disabled for performance
    // onRaveModeChanged: {
    //     Logger.i("SlowBongo", "Rave mode: " + raveMode)
    // }

    // onAnyMusicPlayingChanged: {
    //     Logger.i("SlowBongo", "Music playing: " + anyMusicPlaying + " (CavaService.isIdle=" + CavaService.isIdle + ")")
    // }

    // onUseRaveColorsChanged: {
    //     Logger.i("SlowBongo", "Use rave colors: " + useRaveColors + " (raveMode=" + raveMode + ", musicPlaying=" + anyMusicPlaying + ")")
    // }

    // onCurrentRainbowColorChanged: {
    //     Logger.i("SlowBongo", "Rainbow color changed to: " + currentRainbowColor + " (beat detected, intensity=" + smoothedIntensity.toFixed(2) + ")")
    // }

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
