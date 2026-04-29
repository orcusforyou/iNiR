pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.functions

/**
 * Idle service backed by Quickshell IdleMonitor (ext-idle-notify-v1).
 * Replaces the previous swayidle-based implementation.
 */
Singleton {
    id: root

    property bool inhibit: false
    readonly property int screenOffTimeout: Config.options?.idle?.screenOffTimeout ?? 300
    readonly property int lockTimeout: Config.options?.idle?.lockTimeout ?? 600
    readonly property int suspendTimeout: Config.options?.idle?.suspendTimeout ?? 0
    readonly property string launcherPath: Quickshell.shellPath("scripts/inir")

    function toggleInhibit(active = null): void {
        if (active !== null) {
            inhibit = active;
        } else {
            inhibit = !inhibit;
        }
        Persistent.states.idle.inhibit = inhibit;
    }

    // ── Screen off ───────────────────────────────────────────────
    // respectInhibitors: false — the screen turns off after the user's
    // configured timeout regardless of what's playing. A monitor sitting
    // bright at 100% during a movie is the bug, not the feature.
    IdleMonitor {
        id: screenOffMonitor
        enabled: !root.inhibit && root.screenOffTimeout > 0
        timeout: root.screenOffTimeout
        respectInhibitors: false
        onIsIdleChanged: {
            console.log("[Idle] screen-off isIdle=" + isIdle + " (timeout=" + timeout + "s)")
            if (isIdle) CompositorService.powerOffMonitors()
            else        CompositorService.powerOnMonitors()
        }
    }

    // ── Lock ─────────────────────────────────────────────────────
    // respectInhibitors: true (default) — don't lock during fullscreen video.
    IdleMonitor {
        id: lockMonitor
        enabled: !root.inhibit && root._effectiveLockTimeout > 0
        timeout: root._effectiveLockTimeout
        onIsIdleChanged: {
            console.log("[Idle] lock isIdle=" + isIdle + " (timeout=" + timeout + "s)")
            if (isIdle)
                Quickshell.execDetached([root.launcherPath, "lock", "activate"])
        }
    }

    // ── Suspend ──────────────────────────────────────────────────
    // respectInhibitors: true (default) — don't suspend during a video call.
    IdleMonitor {
        id: suspendMonitor
        enabled: !root.inhibit && root.suspendTimeout > 0
        timeout: root.suspendTimeout
        onIsIdleChanged: {
            console.log("[Idle] suspend isIdle=" + isIdle + " (timeout=" + timeout + "s)")
            if (isIdle)
                Quickshell.execDetached(["/usr/bin/systemctl", "suspend", "-i"])
        }
    }

    // ── Lock before sleep (logind PrepareForSleep D-Bus signal) ─
    Process {
        id: sleepWatcher
        running: Config.options?.idle?.lockBeforeSleep !== false
        command: [
            "/usr/bin/dbus-monitor", "--system", "--profile",
            "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
        ]
        stdout: SplitParser {
            onRead: (line) => {
                // dbus-monitor --profile emits tab-separated lines; the signal line contains "PrepareForSleep"
                if (line.includes("PrepareForSleep"))
                    Quickshell.execDetached([root.launcherPath, "lock", "activate"])
            }
        }
    }

    // Effective lock timeout accounts for suspend overlap
    readonly property int _effectiveLockTimeout: {
        const lockBeforeSleep = Config.options?.idle?.lockBeforeSleep !== false
        let t = root.lockTimeout
        if (root.suspendTimeout > 0 && lockBeforeSleep) {
            const lockBeforeSuspendTime = Math.max(1, root.suspendTimeout - 5)
            if (t <= 0 || t > lockBeforeSuspendTime)
                t = lockBeforeSuspendTime
        }
        return t
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready && Persistent.states?.idle?.inhibit)
                root.inhibit = true
        }
    }
}
