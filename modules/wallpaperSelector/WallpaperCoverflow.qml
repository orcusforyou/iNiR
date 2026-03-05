pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Fullscreen coverflow wallpaper selector — independent overlay panel.
 * Floats over the user's actual wallpaper with 3D perspective cards.
 */
Scope {
    id: root

    readonly property var focusedScreen: CompositorService.isNiri
        ? (Quickshell.screens.find(s => s.name === NiriService.currentOutput) ?? Quickshell.screens[0])
        : (Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0])

    readonly property var targetScreen: {
        const targetMon = Config.options?.wallpaperSelector?.targetMonitor ?? ""
        if (targetMon && targetMon.length > 0) {
            const s = Quickshell.screens.find(scr => scr.name === targetMon)
            if (s) return s
        }
        return root.focusedScreen
    }

    Loader {
        id: coverflowLoader
        active: GlobalStates.coverflowSelectorOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            screen: root.targetScreen

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:coverflowSelector"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            // Scrim (dark overlay behind cards)
            Rectangle {
                id: scrim
                anchors.fill: parent
                color: Appearance.colors.colScrim
                opacity: GlobalStates.coverflowSelectorOpen ? 1.0 : 0.0
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RadialGradient {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colScrim, 1) }
                        GradientStop { position: 0.55; color: ColorUtils.transparentize(Appearance.colors.colScrim, 1) }
                        GradientStop { position: 1.0; color: Appearance.colors.colScrim }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: ColorUtils.applyAlpha(Appearance.colors.colScrim, 0.34) }
                        GradientStop { position: 0.5; color: "transparent" }
                        GradientStop { position: 1.0; color: ColorUtils.applyAlpha(Appearance.colors.colScrim, 0.34) }
                    }
                    opacity: 0.9
                }
            }

            WallpaperCoverflowView {
                id: coverflowContent
                anchors.fill: parent
                focus: true
                folderModel: Wallpapers.folderModel
                currentWallpaperPath: Wallpapers.effectiveWallpaperPath

                // Entry animation
                transformOrigin: Item.Center
                scale: GlobalStates.coverflowSelectorOpen ? 1.0 : 0.92
                opacity: GlobalStates.coverflowSelectorOpen ? 1.0 : 0.0
                y: GlobalStates.coverflowSelectorOpen ? 0 : 12
                Behavior on scale {
                    enabled: Appearance.animationsEnabled
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    enabled: Appearance.animationsEnabled
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                onWallpaperSelected: filePath => {
                    if (filePath && filePath.length > 0) {
                        const normalizedPath = FileUtils.trimFileProtocol(String(filePath))
                        Wallpapers.select(normalizedPath, coverflowContent.useDarkMode)
                        Config.setNestedValue("wallpaperSelector.targetMonitor", "")
                        GlobalStates.coverflowSelectorOpen = false
                    }
                }
                onDirectorySelected: dirPath => {
                    Wallpapers.setDirectory(dirPath)
                }
                onCloseRequested: {
                    Config.setNestedValue("wallpaperSelector.targetMonitor", "")
                    GlobalStates.coverflowSelectorOpen = false
                }
            }

            // Click outside to close (Hyprland)
            CompositorFocusGrab {
                id: grab
                windows: [ panelWindow ]
                active: CompositorService.isHyprland && coverflowLoader.active
                onCleared: () => {
                    if (!active) {
                        Config.setNestedValue("wallpaperSelector.targetMonitor", "")
                        GlobalStates.coverflowSelectorOpen = false
                    }
                }
            }
        }
    }

    // Generate thumbnails when opening
    Connections {
        target: GlobalStates
        function onCoverflowSelectorOpenChanged() {
            if (GlobalStates.coverflowSelectorOpen) {
                const wp = Wallpapers.effectiveWallpaperPath
                const wpDir = FileUtils.parentDirectory(FileUtils.trimFileProtocol(String(wp)))
                if (wpDir && wpDir.length > 0) {
                    Wallpapers.setDirectory(wpDir)
                }
                Wallpapers.searchQuery = ""
                coverflowContent.updateThumbnails()
            }
        }
    }

    IpcHandler {
        target: "coverflowSelector"

        function toggle(): void {
            GlobalStates.coverflowSelectorOpen = !GlobalStates.coverflowSelectorOpen
        }

        function open(): void {
            GlobalStates.coverflowSelectorOpen = true
        }

        function close(): void {
            GlobalStates.coverflowSelectorOpen = false
        }
    }

    Loader {
        active: CompositorService.isHyprland
        sourceComponent: Item {
            GlobalShortcut {
                name: "coverflowSelectorToggle"
                description: "Toggle coverflow wallpaper selector"
                onPressed: {
                    GlobalStates.coverflowSelectorOpen = !GlobalStates.coverflowSelectorOpen
                }
            }
        }
    }
}
