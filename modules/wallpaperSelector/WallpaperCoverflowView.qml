pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects as GE

Item {
    id: root

    required property var folderModel
    required property string currentWallpaperPath
    property bool useDarkMode: Appearance.m3colors.darkmode
    signal wallpaperSelected(string filePath)
    signal directorySelected(string dirPath)
    signal closeRequested()

    property string _lastThumbnailSizeName: "x-large"
    readonly property real _dpr: root.window ? root.window.devicePixelRatio : 1

    function updateThumbnails() {
        const w = Math.round(root.cardW * root._dpr * 2)
        const h = Math.round(root.cardH * root._dpr * 2)
        let sizeName = Images.thumbnailSizeNameForDimensions(w, h)
        if (sizeName === "normal" || sizeName === "large") sizeName = "x-large"
        root._lastThumbnailSizeName = sizeName
        Wallpapers.generateThumbnail(sizeName)
    }

    Timer {
        id: thumbnailDebounce
        interval: 150
        onTriggered: {
            if (root.totalCount <= 0) return
            if (root.cardW <= 8 || root.cardH <= 8) return
            root.updateThumbnails()
        }
    }

    // --- Geometry ---
    readonly property real cardW: Math.min(width * 0.27, 440)
    readonly property real cardH: cardW * 1.35
    readonly property real sideCardScale: 0.78
    readonly property real sideCardGap: Math.min(cardW * 0.46, Math.max(40, (width - cardW) / (visiblePerSide + 1.5)))
    readonly property int visiblePerSide: 4
    readonly property int totalCount: folderModel?.count ?? 0
    readonly property int slotCount: 1 + visiblePerSide * 2

    // --- Distribution curves ---
    function scaleAt(d) {
        if (d === 0) return 1.0 + root._focusPulse * 0.018
        const a = Math.abs(d)
        return Math.max(0.32, sideCardScale * Math.pow(0.88, a - 1))
    }
    function opacityAt(d) {
        if (d === 0) return 1.0
        const a = Math.abs(d)
        return Math.max(0.08, 0.88 * Math.pow(0.72, a - 1))
    }
    function zAt(d) { return 200 - Math.abs(d) * 20 }
    function yAt(d) {
        if (d === 0) return -root._focusPulse * 8
        return Math.min(34, Math.abs(d) * 9)
    }
    function rotationAt(d) {
        if (d === 0) return 0
        return d > 0 ? -36 : 36
    }

    // --- State ---
    property int currentIndex: 0
    property bool _initialized: false

    property real _focusPulse: 0
    property int _wheelRemainder: 0

    SequentialAnimation {
        id: focusPulseAnim
        running: false

        NumberAnimation {
            target: root
            property: "_focusPulse"
            to: 1
            duration: Math.max(1, Appearance.animation.clickBounce.duration * 0.45)
            easing.type: Appearance.animation.clickBounce.type
            easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "_focusPulse"
            to: 0
            duration: Math.max(1, Appearance.animation.clickBounce.duration * 0.7)
            easing.type: Appearance.animation.clickBounce.type
            easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
        }
    }

    // --- Color accent ---
    readonly property string _currentFilePath: totalCount > 0 ? (_filePath(currentIndex)) : ""
    readonly property bool _currentIsDir: totalCount > 0 ? (_fileIsDir(currentIndex)) : false

    ColorQuantizer {
        id: focusedCardQuantizer
        source: root._currentFilePath.length > 0 && !root._currentIsDir
                ? "file://" + root._currentFilePath
                : ""
        depth: 0
        rescaleSize: 4
    }

    readonly property color accentColor: {
        const extracted = focusedCardQuantizer?.colors?.[0]
        if (!extracted || root._currentIsDir || root._currentFilePath.length === 0)
            return Appearance.colors.colPrimary
        return ColorUtils.mix(extracted, Appearance.colors.colPrimary, 0.55)
    }

    property color _smoothAccent: accentColor
    Behavior on _smoothAccent {
        enabled: Appearance.animationsEnabled
        ColorAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    // --- Model helpers ---
    function _filePath(absIdx) {
        if (absIdx < 0 || absIdx >= totalCount) return ""
        return folderModel.get(absIdx, "filePath") ?? ""
    }
    function _fileName(absIdx) {
        if (absIdx < 0 || absIdx >= totalCount) return ""
        return folderModel.get(absIdx, "fileName") ?? ""
    }
    function _fileIsDir(absIdx) {
        if (absIdx < 0 || absIdx >= totalCount) return false
        return folderModel.get(absIdx, "fileIsDir") ?? false
    }
    function _fileUrl(absIdx) {
        if (absIdx < 0 || absIdx >= totalCount) return ""
        return folderModel.get(absIdx, "fileUrl") ?? ""
    }

    function moveSelection(delta) {
        if (totalCount === 0) return
        const next = Math.max(0, Math.min(totalCount - 1, currentIndex + delta))
        if (next === currentIndex) return
        currentIndex = next
        if (Appearance.animationsEnabled) {
            focusPulseAnim.restart()
        }
    }

    function activateCurrent() {
        if (totalCount === 0) return
        const fp = folderModel.get(currentIndex, "filePath")
        const isDir = folderModel.get(currentIndex, "fileIsDir")
        if (isDir) directorySelected(fp)
        else wallpaperSelected(fp)
    }

    function _scrollToCurrentWallpaper() {
        if (_initialized || totalCount === 0) return
        for (let i = 0; i < totalCount; i++) {
            if (_filePath(i) === currentWallpaperPath) {
                currentIndex = i
                _initialized = true
                return
            }
        }
        _initialized = true
    }

    onTotalCountChanged: _scrollToCurrentWallpaper()
    Component.onCompleted: {
        root._scrollToCurrentWallpaper()
        root.updateThumbnails()
    }

    onCardWChanged: thumbnailDebounce.restart()
    onCardHChanged: thumbnailDebounce.restart()

    Connections {
        target: Wallpapers
        function onDirectoryChanged() {
            thumbnailDebounce.restart()
        }
    }

    Connections {
        target: root.folderModel
        function onCountChanged() {
            thumbnailDebounce.restart()
        }
    }

    Connections {
        target: root.folderModel
        function onFolderChanged() {
            root._initialized = false
            root.currentIndex = 0
            root._scrollToCurrentWallpaper()
            if (Appearance.animationsEnabled) {
                focusPulseAnim.restart()
            }

            thumbnailDebounce.restart()
        }
    }

    // --- Keyboard ---
    Keys.onPressed: event => {
        const alt = (event.modifiers & Qt.AltModifier) !== 0
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0

        if (!searchField.activeFocus && ctrl && event.key === Qt.Key_F) {
            searchField.forceActiveFocus()
            event.accepted = true
            return
        }

        if (!searchField.activeFocus && event.key === Qt.Key_Slash) {
            searchField.forceActiveFocus()
            event.accepted = true
            return
        }

        if (searchField.activeFocus) {
            if (event.key === Qt.Key_Escape) {
                root.closeRequested();
                event.accepted = true
            }
            return
        }

        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true
        }
        else if ((alt || ctrl) && event.key === Qt.Key_Left) {
            Wallpapers.navigateBack()
            event.accepted = true
        }
        else if ((alt || ctrl) && event.key === Qt.Key_Right) {
            Wallpapers.navigateForward()
            event.accepted = true
        }
        else if ((alt || ctrl) && (event.key === Qt.Key_Up || event.key === Qt.Key_Backspace)) {
            Wallpapers.navigateUp()
            event.accepted = true
        }
        else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Up) {
            root.moveSelection(-Math.max(1, root.visiblePerSide))
            event.accepted = true
        }
        else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Down) {
            root.moveSelection(Math.max(1, root.visiblePerSide))
            event.accepted = true
        }
        else if (event.key === Qt.Key_Left) {
            root.moveSelection(-(shift ? 3 : 1))
            event.accepted = true
        }
        else if (event.key === Qt.Key_Right) {
            root.moveSelection(shift ? 3 : 1)
            event.accepted = true
        }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activateCurrent();
            event.accepted = true
        }
        else if (event.key === Qt.Key_Home) {
            root.currentIndex = 0
            if (Appearance.animationsEnabled) focusPulseAnim.restart()
            event.accepted = true
        }
        else if (event.key === Qt.Key_End) {
            root.currentIndex = Math.max(0, root.totalCount - 1)
            if (Appearance.animationsEnabled) focusPulseAnim.restart()
            event.accepted = true
        }
    }

    // --- Scroll wheel ---
     WheelHandler {
         acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
         onWheel: event => {
             const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
             root._wheelRemainder += delta
             const steps = root._wheelRemainder >= 0
                 ? Math.floor(root._wheelRemainder / 120)
                 : Math.ceil(root._wheelRemainder / 120)
             if (steps !== 0) {
                 root._wheelRemainder -= steps * 120
                 root.moveSelection(-steps)
             }
         }
     }

    // Background click-to-close
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.BackButton | Qt.ForwardButton
        onClicked: root.closeRequested()
        z: -1

        onPressed: event => {
            if (event.button === Qt.BackButton) {
                Wallpapers.navigateBack()
            } else if (event.button === Qt.ForwardButton) {
                Wallpapers.navigateForward()
            } else {
                event.accepted = false
            }
        }
    }

    GlassBackground {
        id: headerBackground
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 24

        z: 50

        screenX: { const m = headerBackground.mapToGlobal(0, 0); return m.x }
        screenY: { const m = headerBackground.mapToGlobal(0, 0); return m.y }

        implicitHeight: 44
        implicitWidth: headerRow.implicitWidth + 20
        radius: Appearance.angelEverywhere ? Appearance.angel.roundingNormal
            : Appearance.inirEverywhere ? Appearance.inir.roundingNormal
            : Appearance.rounding.full

        fallbackColor: Appearance.colors.colLayer1
        inirColor: Appearance.inir.colLayer1
        auroraTransparency: Appearance.aurora.popupTransparentize

        opacity: root.totalCount > 0 ? 1.0 : 0.0
        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            id: headerRow
            anchors.centerIn: parent
            spacing: 8

            MaterialSymbol {
                text: root._currentIsDir ? "folder" : "image"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.angelEverywhere ? Appearance.angel.colText
                    : Appearance.inirEverywhere ? Appearance.inir.colText
                    : Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.angelEverywhere ? Appearance.angel.colText
                    : Appearance.inirEverywhere ? Appearance.inir.colText
                    : Appearance.colors.colOnSurfaceVariant
                text: root.totalCount > 0
                    ? (root._currentIsDir
                       ? FileUtils.folderNameForPath(root._currentFilePath)
                       : FileUtils.fileNameForPath(root._currentFilePath))
                    : ""
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }
    }

    // ===================== CARDS =====================
    Item {
        id: cardContainer
        clip: true
        anchors {
            left: parent.left
            right: parent.right
            top: headerBackground.bottom
            topMargin: 24
            bottom: toolbar.top
            bottomMargin: 16
        }

        Repeater {
            model: root.totalCount === 0 ? 0 : root.slotCount

            delegate: Item {
                id: cardDelegate
                required property int index

                readonly property int offset: index - root.visiblePerSide
                readonly property int modelIdx: root.currentIndex + offset

                readonly property bool hasData: modelIdx >= 0 && modelIdx < root.totalCount
                readonly property string filePath: hasData ? root._filePath(modelIdx) : ""
                readonly property string fileName: hasData ? root._fileName(modelIdx) : ""
                readonly property bool fileIsDir: hasData ? root._fileIsDir(modelIdx) : false
                readonly property url fileUrl: hasData ? root._fileUrl(modelIdx) : ""

                readonly property bool isCurrent: offset === 0
                readonly property bool isActiveWallpaper: filePath.length > 0 && filePath === root.currentWallpaperPath
                readonly property bool hasBorder: isCurrent || isActiveWallpaper

                readonly property real effectiveOffset: offset

                visible: hasData
                width: root.cardW
                height: root.cardH

                x: cardContainer.width / 2 - width / 2 + effectiveOffset * root.sideCardGap
                y: (cardContainer.height - height) / 2 + root.yAt(effectiveOffset)
                z: root.zAt(effectiveOffset)
                scale: root.scaleAt(effectiveOffset)
                opacity: root.opacityAt(effectiveOffset)

                Behavior on x {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                }
                Behavior on y {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on scale {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                }
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                transform: Rotation {
                    origin.x: effectiveOffset <= 0 ? root.cardW : 0
                    origin.y: root.cardH / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: root.rotationAt(effectiveOffset)

                    Behavior on angle {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                        }
                    }
                }

                StyledRectangularShadow {
                    target: card
                    visible: !Appearance.auroraEverywhere
                    radius: card.radius
                    opacity: cardDelegate.isCurrent ? 0.96 : 0.32
                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                Rectangle {
                    id: card
                    anchors.fill: parent
                    radius: Appearance.angelEverywhere ? Appearance.angel.roundingLarge
                          : Appearance.inirEverywhere ? Appearance.inir.roundingLarge
                          : Appearance.rounding.large
                    color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                         : Appearance.inirEverywhere ? Appearance.inir.colLayer1
                         : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                         : Appearance.colors.colLayer1
                    clip: true

                    border.width: cardDelegate.isCurrent ? 2 : (cardDelegate.isActiveWallpaper ? 1.5 : 1)
                    border.color: {
                        if (cardDelegate.isCurrent)
                            return root._smoothAccent
                        if (cardDelegate.isActiveWallpaper)
                            return Appearance.colors.colPrimary
                        return Appearance.angelEverywhere ? Appearance.angel.colBorderSubtle
                             : Appearance.inirEverywhere ? Appearance.inir.colBorderSubtle
                             : Appearance.colors.colOutlineVariant
                    }

                    Behavior on border.width {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    Behavior on border.color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    AngelPartialBorder {
                        targetRadius: card.radius
                        coverage: cardDelegate.isCurrent ? 0.58 : 0.42
                        borderColor: cardDelegate.isCurrent ? root._smoothAccent
                                    : cardDelegate.isActiveWallpaper ? Appearance.colors.colPrimary
                                    : Appearance.angel.colBorderSubtle
                    }

                    ThumbnailImage {
                        id: thumbImage
                        anchors.fill: parent
                        anchors.margins: 2

                        readonly property bool shouldShow: cardDelegate.hasData
                                    && !cardDelegate.fileIsDir
                                    && cardDelegate.filePath.length > 0
                                    && Images.isValidMediaByName(cardDelegate.fileName)

                        visible: shouldShow
                        generateThumbnail: shouldShow
                        sourcePath: shouldShow ? cardDelegate.filePath : ""

                        thumbnailSizeName: root._lastThumbnailSizeName

                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        mipmap: true
                        sourceSize.width: Math.round(root.cardW * root._dpr * 2)
                        sourceSize.height: Math.round(root.cardH * root._dpr * 2)

                        Connections {
                            target: Wallpapers
                            function onThumbnailGenerated(directory) {
                                if (thumbImage.status !== Image.Error) return;
                                if (!thumbImage.sourcePath || thumbImage.sourcePath.length === 0) return;
                                if (FileUtils.parentDirectory(thumbImage.sourcePath) !== directory) return;
                                thumbImage.source = "";
                                thumbImage.source = thumbImage.thumbnailPath;
                            }
                            function onThumbnailGeneratedFile(filePath) {
                                if (thumbImage.status !== Image.Error) return;
                                if (!thumbImage.sourcePath || thumbImage.sourcePath.length === 0) return;
                                if (Qt.resolvedUrl(thumbImage.sourcePath) !== Qt.resolvedUrl(filePath)) return;
                                thumbImage.source = "";
                                thumbImage.source = thumbImage.thumbnailPath;
                            }
                        }

                        layer.enabled: true
                        layer.effect: GE.OpacityMask {
                            maskSource: Rectangle {
                                width: thumbImage.width
                                height: thumbImage.height
                                radius: card.radius - 2
                            }
                        }
                    }

                    Loader {
                        active: cardDelegate.hasData && cardDelegate.fileIsDir
                        anchors.fill: parent
                        anchors.margins: 2
                        sourceComponent: DirectoryIcon {
                            fileModelData: ({
                                filePath: cardDelegate.filePath,
                                fileName: cardDelegate.fileName,
                                fileIsDir: cardDelegate.fileIsDir,
                                fileUrl: cardDelegate.fileUrl
                            })
                            sourceSize.width: root.cardW
                            sourceSize.height: root.cardH
                        }
                    }

                    Rectangle {
                        visible: cardDelegate.isActiveWallpaper && cardDelegate.isCurrent
                        anchors {
                            top: parent.top
                            right: parent.right
                            topMargin: 16
                            rightMargin: 16
                        }
                        width: badgeRow.implicitWidth + 20
                        height: badgeRow.implicitHeight + 12
                        radius: height / 2
                        color: ColorUtils.applyAlpha(root._smoothAccent, 0.85)
                        border.width: 1
                        border.color: ColorUtils.transparentize(root._smoothAccent, 0.4)

                        scale: visible ? 1.0 : 0.75
                        opacity: visible ? 1.0 : 0.0
                        Behavior on scale {
                            enabled: Appearance.animationsEnabled
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                        }
                        Behavior on opacity {
                            enabled: Appearance.animationsEnabled
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        RowLayout {
                            id: badgeRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "check_circle"
                                iconSize: Appearance.font.pixelSize.small
                                fill: 1
                                color: ColorUtils.contrastColor(root._smoothAccent)
                            }
                            StyledText {
                                text: Translation.tr("Active")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                color: ColorUtils.contrastColor(root._smoothAccent)
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: card.radius
                        color: Appearance.inirEverywhere ? Appearance.inir.colLayer0
                             : Appearance.colors.colLayer0
                        opacity: cardDelegate.isCurrent ? 0 : (Appearance.auroraEverywhere ? 0.12 : 0.18)
                        Behavior on opacity {
                            enabled: Appearance.animationsEnabled
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (cardDelegate.isCurrent) {
                                if (cardDelegate.fileIsDir) root.directorySelected(cardDelegate.filePath)
                                else root.wallpaperSelected(cardDelegate.filePath)
                            } else {
                                root.currentIndex = cardDelegate.modelIdx
                                if (Appearance.animationsEnabled) focusPulseAnim.restart()
                            }
                        }
                    }
                }
            }
        }
    }

    // ===================== NAV ARROWS =====================
    RippleButton {
        anchors {
            left: cardContainer.left
            leftMargin: 24
            verticalCenter: cardContainer.verticalCenter
        }
        implicitWidth: 48
        implicitHeight: 48
        buttonRadius: 24
        z: 80
        visible: root.totalCount > 1 && root.currentIndex > 0
        opacity: visible ? 1.0 : 0.0
        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        onClicked: root.moveSelection(-1)
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: "chevron_left"
            iconSize: 28
            color: Appearance.angelEverywhere ? Appearance.angel.colText
                 : Appearance.inirEverywhere ? Appearance.inir.colText
                 : Appearance.colors.colOnSurfaceVariant
        }
    }

    RippleButton {
        anchors {
            right: cardContainer.right
            rightMargin: 24
            verticalCenter: cardContainer.verticalCenter
        }
        implicitWidth: 48
        implicitHeight: 48
        buttonRadius: 24
        z: 80
        visible: root.totalCount > 1 && root.currentIndex < root.totalCount - 1
        opacity: visible ? 1.0 : 0.0
        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        onClicked: root.moveSelection(1)
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: "chevron_right"
            iconSize: 28
            color: Appearance.angelEverywhere ? Appearance.angel.colText
                  : Appearance.inirEverywhere ? Appearance.inir.colText
                  : Appearance.colors.colOnSurfaceVariant
        }
    }

    // ===================== BOTTOM TOOLBAR =====================
    Toolbar {
        id: toolbar
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 24
        }
        screenX: { const m = toolbar.mapToGlobal(0, 0); return m.x }
        screenY: { const m = toolbar.mapToGlobal(0, 0); return m.y }

        IconToolbarButton {
            implicitWidth: height
            enabled: (root.folderModel?.currentFolderHistoryIndex ?? 0) > 0
            onClicked: Wallpapers.navigateBack()
            text: "arrow_back"
            StyledToolTip { text: Translation.tr("Back") }
        }

        IconToolbarButton {
            implicitWidth: height
            onClicked: Wallpapers.navigateUp()
            text: "arrow_upward"
            StyledToolTip { text: Translation.tr("Up") }
        }

        IconToolbarButton {
            implicitWidth: height
            enabled: (root.folderModel?.currentFolderHistoryIndex ?? 0) < ((root.folderModel?.folderHistory?.length ?? 0) - 1)
            onClicked: Wallpapers.navigateForward()
            text: "arrow_forward"
            StyledToolTip { text: Translation.tr("Forward") }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: Math.min(root.width * 0.22, 260)
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.angelEverywhere ? Appearance.angel.colText
                 : Appearance.inirEverywhere ? Appearance.inir.colText
                 : Appearance.colors.colOnSurfaceVariant
            text: FileUtils.folderNameForPath(String(root.folderModel?.folder ?? ""))
            elide: Text.ElideMiddle
            maximumLineCount: 1
        }

        IconToolbarButton {
            implicitWidth: height
            onClicked: root.useDarkMode = !root.useDarkMode
            text: root.useDarkMode ? "dark_mode" : "light_mode"
            StyledToolTip { text: Translation.tr("Toggle light/dark mode") }
        }

        IconToolbarButton {
            implicitWidth: height
            onClicked: Wallpapers.randomFromCurrentFolder()
            text: "shuffle"
            StyledToolTip { text: Translation.tr("Random wallpaper") }
        }

        Item { Layout.fillWidth: true }

        MaterialTextField {
            id: searchField
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Math.min(root.width * 0.34, 520)
            placeholderText: Translation.tr("Search")
            text: Wallpapers.searchQuery
            onTextChanged: Wallpapers.searchQuery = text
            enableSettingsSearch: false
        }

        Item { Layout.fillWidth: true }

        IconToolbarButton {
            implicitWidth: height
            enabled: (Wallpapers.searchQuery ?? "").length > 0
            onClicked: Wallpapers.searchQuery = ""
            text: "backspace"
            StyledToolTip { text: Translation.tr("Clear search") }
        }

        Rectangle {
            implicitWidth: 1; implicitHeight: 20
            color: Appearance.angelEverywhere ? Appearance.angel.colBorderSubtle
                 : Appearance.inirEverywhere ? Appearance.inir.colBorderSubtle
                 : Appearance.colors.colOnSurfaceVariant
            opacity: 0.3
        }

        StyledText {
            visible: root.totalCount > 0
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.angelEverywhere ? Appearance.angel.colText
                 : Appearance.inirEverywhere ? Appearance.inir.colText
                 : Appearance.colors.colOnSurfaceVariant
            text: root.totalCount > 0 ? "%1 / %2".arg(root.currentIndex + 1).arg(root.totalCount) : ""
        }

        Rectangle {
            implicitWidth: 1; implicitHeight: 20
            color: Appearance.angelEverywhere ? Appearance.angel.colBorderSubtle
                 : Appearance.inirEverywhere ? Appearance.inir.colBorderSubtle
                 : Appearance.colors.colOnSurfaceVariant
            opacity: 0.3
        }

        IconToolbarButton {
            implicitWidth: height
            onClicked: root.closeRequested()
            text: "close"
            StyledToolTip { text: Translation.tr("Close") }
        }
    }

 }
