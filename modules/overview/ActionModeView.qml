import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * ActionModeView — Full keyboard-navigable action panel for the overview.
 *
 * Replaces normal search results when the user types the action prefix ("/").
 * Shows categorized actions from GlobalActions + live package search results.
 *
 * Keyboard navigation:
 *   - Up/Down: navigate items
 *   - Enter: execute selected action
 *   - Tab/Shift+Tab: cycle category tabs
 *   - Typing: fuzzy filter all actions
 */
Item {
    id: root
    property string query: ""
    property int selectedCategoryIndex: 0

    readonly property var categoryList: [
        { id: "all",        label: Translation.tr("All"),        icon: "apps" },
        { id: "system",     label: Translation.tr("System"),     icon: "settings_suggest" },
        { id: "appearance", label: Translation.tr("Appearance"), icon: "palette" },
        { id: "tools",      label: Translation.tr("Tools"),      icon: "build" },
        { id: "media",      label: Translation.tr("Media"),      icon: "headphones" },
        { id: "settings",   label: Translation.tr("Settings"),   icon: "tune" },
    ]
    readonly property string selectedCategory: categoryList[selectedCategoryIndex]?.id ?? "all"

    // Package search trigger detection
    readonly property bool isPackageInstall: query.toLowerCase().startsWith("install ")
    readonly property bool isPackageRemove: query.toLowerCase().startsWith("remove ")
    readonly property bool isPackageSearch: query.toLowerCase().startsWith("search ")
    readonly property bool isPackageQuery: isPackageInstall || isPackageRemove || isPackageSearch
    readonly property string packageQuery: {
        if (isPackageInstall) return query.substring(8).trim()
        if (isPackageRemove) return query.substring(7).trim()
        if (isPackageSearch) return query.substring(7).trim()
        return ""
    }

    // Flat list of actionable items only (no headers — tabs handle categorization)
    readonly property var displayItems: {
        let items = []

        // Actions
        let actions = []
        if (root.query === "") {
            actions = selectedCategory === "all"
                ? GlobalActions.allActions
                : GlobalActions.listByCategory(selectedCategory)
        } else {
            actions = GlobalActions.fuzzyQuery(root.query)
            if (selectedCategory !== "all")
                actions = actions.filter(a => a.category === selectedCategory)
        }
        for (const a of actions) {
            items.push({
                type: "action",
                key: `action_${a.id}`,
                name: a.name,
                description: a.description ?? "",
                icon: a.icon ?? "settings",
                category: a.category ?? "",
                action: a
            })
        }

        // Package results
        if (root.isPackageQuery && PackageSearch.results.length > 0) {
            for (let i = 0; i < Math.min(PackageSearch.results.length, 30); i++) {
                const pkg = PackageSearch.results[i]
                items.push({
                    type: "package",
                    key: `pkg_${pkg.repo}_${pkg.name}`,
                    name: pkg.name,
                    description: pkg.description ?? "",
                    icon: pkg.installed ? "check_circle" : (root.isPackageRemove ? "delete" : "download"),
                    category: pkg.repo ?? "",
                    pkg: pkg
                })
            }
        }

        return items
    }

    readonly property bool showLoading: root.isPackageQuery && PackageSearch.searching
    readonly property bool showEmpty: displayItems.length === 0 && root.query !== "" && !showLoading

    onPackageQueryChanged: {
        if (root.packageQuery.length >= 2) {
            if (root.isPackageRemove) {
                PackageSearch.searchInstalled(root.packageQuery)
            } else {
                PackageSearch.search(root.packageQuery)
            }
        } else {
            PackageSearch.clear()
        }
    }

    Component.onDestruction: PackageSearch.clear()

    signal actionExecuted()

    implicitWidth: mainColumn.implicitWidth
    implicitHeight: mainColumn.implicitHeight

    function focusFirstItem(): void {
        if (actionList.count > 0) {
            actionList.currentIndex = 0
            actionList.forceActiveFocus()
        }
    }

    function _executePackageAction(pkg): void {
        const terminal = Config.options?.apps?.terminal ?? "kitty"
        const name = pkg.name
        if (root.isPackageRemove) {
            Quickshell.execDetached(["/usr/bin/bash", "-c",
                `${terminal} -e /usr/bin/bash -c 'sudo pacman -Rns ${name} ; echo "\\nPress Enter to close..." ; read'`])
        } else {
            // Detect AUR helper: prefer yay, then paru, fallback to sudo pacman
            const helper = pkg.isAur
                ? "if command -v yay &>/dev/null; then yay -S " + name + "; elif command -v paru &>/dev/null; then paru -S " + name + "; else echo 'No AUR helper found'; fi"
                : "sudo pacman -S " + name
            Quickshell.execDetached(["/usr/bin/bash", "-c",
                `${terminal} -e /usr/bin/bash -c '${helper} ; echo "\\nPress Enter to close..." ; read'`])
        }
        root.actionExecuted()
    }

    ColumnLayout {
        id: mainColumn
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        spacing: 0

        // ── Category Tab Bar (uses existing SecondaryTabBar widget) ──
        SecondaryTabBar {
            id: categoryTabBar
            Layout.fillWidth: true
            Layout.topMargin: 4
            currentIndex: root.selectedCategoryIndex
            onCurrentIndexChanged: root.selectedCategoryIndex = currentIndex

            Repeater {
                model: root.categoryList
                SecondaryTabButton {
                    buttonText: modelData.label
                    buttonIcon: modelData.icon
                    selected: categoryTabBar.currentIndex === index
                }
            }
        }

        // ── Package command hints ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.topMargin: 6
            Layout.bottomMargin: 2
            spacing: 16
            visible: root.query === "" || root.query.length <= 3

            Repeater {
                model: [
                    { cmd: "install <pkg>", desc: Translation.tr("Install package") },
                    { cmd: "remove <pkg>", desc: Translation.tr("Remove package") },
                    { cmd: "search <pkg>", desc: Translation.tr("Search packages") },
                ]
                delegate: RowLayout {
                    spacing: 4
                    StyledText {
                        text: modelData.cmd
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary
                        opacity: 0.7
                    }
                    StyledText {
                        text: modelData.desc
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        opacity: 0.5
                    }
                }
            }
        }

        // ── Action/Package List ──
        ListView {
            id: actionList
            Layout.fillWidth: true
            implicitHeight: Math.min(520, contentHeight + topMargin + bottomMargin)
            clip: true
            topMargin: 6
            bottomMargin: 6
            spacing: 2
            highlightMoveDuration: 100
            focus: true

            model: root.displayItems

            Connections {
                target: root
                function onQueryChanged() {
                    if (actionList.count > 0)
                        actionList.currentIndex = 0
                }
            }

            // ── Delegate: RippleButton matching SearchItem style ──
            delegate: RippleButton {
                id: delegateBtn
                property var entry: modelData
                property bool isAction: entry?.type === "action"
                property bool isPackage: entry?.type === "package"
                property bool keyboardDown: false

                anchors.left: parent?.left
                anchors.right: parent?.right

                property int horizontalMargin: 10
                property int buttonHorizontalPadding: 10
                property int buttonVerticalPadding: 6

                implicitHeight: delegateRow.implicitHeight + buttonVerticalPadding * 2

                // Style tokens — exactly match SearchItem.qml
                buttonRadius: Appearance.angelEverywhere ? Appearance.angel.roundingSmall
                    : Appearance.inirEverywhere ? Appearance.inir.roundingSmall : Appearance.rounding.normal
                colBackground: (delegateBtn.down || delegateBtn.keyboardDown)
                    ? (Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
                        : Appearance.inirEverywhere ? Appearance.inir.colPrimaryActive : Appearance.colors.colPrimaryContainerActive)
                    : ((delegateBtn.hovered || delegateBtn.focus)
                        ? (Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                            : Appearance.inirEverywhere ? Appearance.inir.colLayer2
                            : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                            : Appearance.colors.colPrimaryContainer)
                        : "transparent")
                colBackgroundHover: Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                    : Appearance.inirEverywhere ? Appearance.inir.colLayer2Hover
                    : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                    : Appearance.colors.colPrimaryContainer
                colRipple: Appearance.inirEverywhere ? Appearance.inir.colPrimaryActive : Appearance.colors.colPrimaryContainerActive

                background {
                    anchors.fill: delegateBtn
                    anchors.leftMargin: delegateBtn.horizontalMargin
                    anchors.rightMargin: delegateBtn.horizontalMargin
                }

                PointingHandInteraction {}

                onClicked: {
                    // Capture values before closing overview (which destroys this component)
                    const isPkgQuery = root.isPackageQuery
                    const pkgQuery = root.packageQuery
                    const query = root.query
                    const isPkgRemove = root.isPackageRemove
                    const actionFn = isAction ? entry.action?.execute : null
                    const pkg = isPackage ? entry.pkg : null
                    root.actionExecuted()
                    GlobalStates.overviewOpen = false
                    if (isAction && actionFn) {
                        const args = isPkgQuery ? pkgQuery : query
                        actionFn(args)
                    } else if (isPackage && pkg) {
                        const terminal = Config.options?.apps?.terminal ?? "kitty"
                        const name = pkg.name
                        if (isPkgRemove) {
                            Quickshell.execDetached(["/usr/bin/bash", "-c",
                                `${terminal} -e /usr/bin/bash -c 'sudo pacman -Rns ${name} ; echo "\\nPress Enter to close..." ; read'`])
                        } else {
                            const helper = pkg.isAur
                                ? "if command -v yay &>/dev/null; then yay -S " + name + "; elif command -v paru &>/dev/null; then paru -S " + name + "; else echo 'No AUR helper found'; fi"
                                : "sudo pacman -S " + name
                            Quickshell.execDetached(["/usr/bin/bash", "-c",
                                `${terminal} -e /usr/bin/bash -c '${helper} ; echo "\\nPress Enter to close..." ; read'`])
                        }
                    }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        delegateBtn.keyboardDown = true
                        delegateBtn.clicked()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) {
                        root.selectedCategoryIndex = (root.selectedCategoryIndex + 1) % root.categoryList.length
                        event.accepted = true
                    } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) {
                        root.selectedCategoryIndex = (root.selectedCategoryIndex - 1 + root.categoryList.length) % root.categoryList.length
                        event.accepted = true
                    }
                }
                Keys.onReleased: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        delegateBtn.keyboardDown = false
                        event.accepted = true
                    }
                }

                RowLayout {
                    id: delegateRow
                    spacing: 10
                    anchors.fill: parent
                    anchors.leftMargin: delegateBtn.horizontalMargin + delegateBtn.buttonHorizontalPadding
                    anchors.rightMargin: delegateBtn.horizontalMargin + delegateBtn.buttonHorizontalPadding

                    // Icon circle
                    Rectangle {
                        implicitWidth: 35
                        implicitHeight: 35
                        radius: Appearance.angelEverywhere ? Appearance.angel.roundingSmall
                            : Appearance.inirEverywhere ? Appearance.inir.roundingSmall
                            : Appearance.rounding.full
                        color: {
                            if (isPackage && entry.pkg?.installed)
                                return ColorUtils.transparentize(
                                    Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary, 0.3)
                            return delegateBtn.focus
                                ? (Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary)
                                : (Appearance.inirEverywhere ? Appearance.inir.colLayer2
                                    : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                                    : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                                    : Appearance.colors.colSecondaryContainer)
                        }

                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: 150 }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: entry?.icon ?? "settings"
                            iconSize: 22
                            fill: (isPackage && entry.pkg?.installed) ? 1 : 0
                            color: {
                                if (isPackage && entry.pkg?.installed)
                                    return Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary
                                return delegateBtn.focus
                                    ? (Appearance.inirEverywhere ? Appearance.inir.colOnPrimary : Appearance.colors.colOnPrimary)
                                    : Appearance.m3colors.m3onSurface
                            }
                        }
                    }

                    // Name + description
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        // Category label (small, above name) for filtered "all" results
                        StyledText {
                            visible: root.selectedCategory === "all" && root.query !== "" && isAction
                            text: entry?.category ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: entry?.name ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: entry?.description ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    // Package badges
                    RowLayout {
                        visible: isPackage
                        spacing: 4

                        StyledText {
                            visible: entry?.pkg?.version ? true : false
                            text: entry?.pkg?.version ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                        }

                        Rectangle {
                            visible: entry?.pkg?.repo ? true : false
                            implicitWidth: repoText.implicitWidth + 10
                            implicitHeight: repoText.implicitHeight + 4
                            radius: height / 2
                            color: entry?.pkg?.isAur
                                ? ColorUtils.transparentize(Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary, 0.3)
                                : (Appearance.inirEverywhere ? Appearance.inir.colLayer2 : Appearance.colors.colSecondaryContainer)

                            StyledText {
                                id: repoText
                                anchors.centerIn: parent
                                text: entry?.pkg?.repo ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: entry?.pkg?.isAur
                                    ? (Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary)
                                    : (Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnSecondaryContainer)
                            }
                        }

                        Rectangle {
                            visible: entry?.pkg?.installed ?? false
                            implicitWidth: installedText.implicitWidth + 10
                            implicitHeight: installedText.implicitHeight + 4
                            radius: height / 2
                            color: ColorUtils.transparentize(
                                Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary, 0.2)

                            StyledText {
                                id: installedText
                                anchors.centerIn: parent
                                text: Translation.tr("Installed")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary
                            }
                        }
                    }

                    // Action hint on hover/focus
                    StyledText {
                        Layout.fillWidth: false
                        visible: delegateBtn.hovered || delegateBtn.focus
                        text: isAction
                            ? (entry?.action?.verb ?? Translation.tr("Run"))
                            : (root.isPackageRemove ? Translation.tr("Remove") : Translation.tr("Install"))
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }
        }

        // ── Loading indicator ──
        RowLayout {
            visible: root.showLoading
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            BusyIndicator {
                running: root.showLoading
                implicitWidth: 20
                implicitHeight: 20
            }
            StyledText {
                text: Translation.tr("Searching packages...")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        // ── Empty state ──
        ColumnLayout {
            visible: root.showEmpty
            Layout.fillWidth: true
            Layout.topMargin: 20
            Layout.bottomMargin: 20
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "search_off"
                iconSize: 28
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No results for \"%1\"").arg(root.query)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }
}
