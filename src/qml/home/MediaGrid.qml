import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    property var model

    signal gameLaunched(string gameId)
    signal gameDetailsRequested(string gameId)
    signal winetricksRequested(string prefixId, string gameTitle)
    signal addGameRequested()
    signal focusSidebarRequested()
    signal focusTopBarRequested()

    property alias gridView: grid
    function forceFocus() { grid.forceActiveFocus() }
    readonly property int columns: Math.max(1, Math.floor(grid.width / grid.cellWidth))

    // ── Dynamic Settings & Helpers (Matching Yoru M3 Architecture) ───────────
    readonly property bool isDark: appSettings.isEffectiveDark
    readonly property int  cardRadius: appSettings.cardRadius

    readonly property bool hasTitleBelow: appSettings.titleVisibility === 0
    readonly property bool hasTagAboveTitle: hasTitleBelow && appSettings.tagPosition === 1
    readonly property bool hasTagBelowTitle: hasTitleBelow && appSettings.tagPosition === 0

    // Snug metadata height with zero empty bottom space
    readonly property int  metaHeight: {
        if (!hasTitleBelow) return 0
        if (hasTagAboveTitle || hasTagBelowTitle) return 52
        return 32
    }

    function typeLabel(t, runnerTag) {
        if (runnerTag && runnerTag.length > 0) {
            let upper = runnerTag.toUpperCase()
            if (upper === "LINUX" || upper === "NATIVE") return "LINUX"
            if (upper === "PROTON-GE" || upper === "PROTON") return "PROTON"
            return runnerTag
        }
        return t === 3 ? "LINUX" : (t === 0 ? "PROTON" : (t === 1 ? "WINE" : "CUSTOM"))
    }

    function tagColor(t) {
        if (t === 3) return appSettings.tagColorLinux
        return t === 0 ? appSettings.tagColorSeries
                       : (t === 1 ? appSettings.tagColorMovie
                                  : appSettings.tagColorAnime)
    }

    // ── GridView ─────────────────────────────────────────────────────────────
    GridView {
        id: grid
        anchors.fill: parent
        clip: false
        model: root.model
        cellWidth:  Math.floor(width / Math.max(1, Math.floor(width / appSettings.thumbScaleTarget)))
        cellHeight: Math.floor(((cellWidth - 16) * 1.5) + root.metaHeight)

        focus: true
        keyNavigationEnabled: false

        Connections {
            target: root.model
            function onModelReset() {
                grid.currentIndex = 0
                grid.positionViewAtBeginning()
            }
        }

        property bool isHoldingActionKey: false
        property bool holdTriggered: false

        Timer {
            id: holdMenuTimer
            interval: 450
            repeat: false
            onTriggered: {
                if (grid.isHoldingActionKey) {
                    grid.holdTriggered = true
                    let currItem = grid.currentItem
                    if (currItem && typeof currItem.openContextMenuFromKeyboard === "function") {
                        currItem.openContextMenuFromKeyboard()
                    }
                }
            }
        }

        onActiveFocusChanged: {
            if (!activeFocus) {
                holdMenuTimer.stop()
                grid.isHoldingActionKey = false
                grid.holdTriggered = false
            }
        }

        function activatePrimaryAction(gameId) {
            if (!gameId || gameId.length === 0) return
            if (appSettings.leftClickBehavior === 0) {
                if (uiController.launchPipeline.isGameRunning(gameId)) {
                    root.gameDetailsRequested(gameId)
                } else {
                    uiController.launchPipeline.launchGame(gameId)
                    root.gameLaunched(gameId)
                }
            } else {
                root.gameDetailsRequested(gameId)
            }
        }

        function selectCurrent() {
            if (grid.currentIndex >= 0 && grid.currentIndex < grid.count) {
                let itemData = root.model.get(grid.currentIndex)
                if (itemData && itemData.id) {
                    activatePrimaryAction(itemData.id)
                }
            }
        }

        onCurrentIndexChanged: {
            grid.positionViewAtIndex(grid.currentIndex, GridView.Contain)
            holdMenuTimer.stop()
            grid.isHoldingActionKey = false
            grid.holdTriggered = false
        }

        Keys.onLeftPressed: (event) => {
            event.accepted = true
            holdMenuTimer.stop()
            grid.isHoldingActionKey = false
            let currItem = grid.currentItem
            if (currItem && currItem.isMenuOpen) {
                currItem.isMenuOpen = false
                return
            }
            if (grid.count === 0) {
                root.focusSidebarRequested()
                return
            }
            if (grid.currentIndex % root.columns === 0) {
                root.focusSidebarRequested()
            } else if (grid.currentIndex > 0) {
                grid.currentIndex--
            }
        }

        Keys.onRightPressed: (event) => {
            event.accepted = true
            holdMenuTimer.stop()
            grid.isHoldingActionKey = false
            let currItem = grid.currentItem
            if (currItem && currItem.isMenuOpen) {
                currItem.isMenuOpen = false
                return
            }
            if (grid.currentIndex < grid.count - 1) {
                grid.currentIndex++
            }
        }

        Keys.onUpPressed: (event) => {
            event.accepted = true
            holdMenuTimer.stop()
            grid.isHoldingActionKey = false
            let currItem = grid.currentItem
            if (currItem && currItem.isMenuOpen) {
                currItem.navigateMenuUp()
                return
            }
            if (grid.count === 0) {
                root.focusTopBarRequested()
                return
            }
            if (grid.currentIndex < root.columns) {
                root.focusTopBarRequested()
            } else {
                grid.currentIndex = Math.max(0, grid.currentIndex - root.columns)
            }
        }

        Keys.onDownPressed: (event) => {
            event.accepted = true
            holdMenuTimer.stop()
            grid.isHoldingActionKey = false
            let currItem = grid.currentItem
            if (currItem && currItem.isMenuOpen) {
                currItem.navigateMenuDown()
                return
            }
            if (grid.currentIndex + root.columns < grid.count) {
                grid.currentIndex += root.columns
            } else if (grid.currentIndex < grid.count - 1) {
                grid.currentIndex = grid.count - 1
            }
        }

        Keys.onEscapePressed: (event) => {
            event.accepted = true
            holdMenuTimer.stop()
            grid.isHoldingActionKey = false
            let currItem = grid.currentItem
            if (currItem && currItem.isMenuOpen) {
                currItem.isMenuOpen = false
            } else {
                root.focusSidebarRequested()
            }
        }

        Keys.onMenuPressed: (event) => {
            event.accepted = true
            let currItem = grid.currentItem
            if (currItem && typeof currItem.toggleContextMenuFromKeyboard === "function") {
                currItem.toggleContextMenuFromKeyboard()
            }
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                event.accepted = true
                if (event.isAutoRepeat) return
                let currItem = grid.currentItem
                if (currItem && currItem.isMenuOpen) {
                    currItem.triggerMenuAction()
                    return
                }
                grid.isHoldingActionKey = true
                grid.holdTriggered = false
                holdMenuTimer.restart()
                return
            }
            if (event.key === Qt.Key_M && !event.isAutoRepeat) {
                event.accepted = true
                let currItem = grid.currentItem
                if (currItem && typeof currItem.toggleContextMenuFromKeyboard === "function") {
                    currItem.toggleContextMenuFromKeyboard()
                }
                return
            }
        }

        Keys.onReleased: (event) => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                event.accepted = true
                if (event.isAutoRepeat) return
                holdMenuTimer.stop()
                if (grid.isHoldingActionKey) {
                    grid.isHoldingActionKey = false
                    if (!grid.holdTriggered) {
                        let currItem = grid.currentItem
                        if (!currItem || !currItem.isMenuOpen) {
                            grid.selectCurrent()
                        }
                    }
                    grid.holdTriggered = false
                }
            }
        }

        populate: Transition {
            SequentialAnimation {
                PauseAnimation { duration: Math.min(Math.max(0, ViewTransition.index) * 25, 200) }
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale";   from: 0.96; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "y"; from: ViewTransition.destination.y + 12; duration: 220; easing.type: Easing.OutCubic }
                }
            }
        }

        // ── Delegate (Exact Yoru Card Aesthetics) ────────────────────────────
        delegate: Item {
            id: cell
            required property int    index
            required property string gameId
            required property string title
            required property string year
            required property url    coverPath
            required property int    type
            required property string runnerTag
            required property string prefixId
            required property bool   isPinned
            required property bool   isFavorite
            required property bool   isRunning
            required property bool   isNative

            property bool isMenuOpen: false
            property int menuFocusedIndex: 0
            readonly property int menuItemCount: 4

            onIsMenuOpenChanged: {
                if (!isMenuOpen) menuFocusedIndex = 0
            }

            function openContextMenuFromKeyboard() {
                menuFocusedIndex = 0
                isMenuOpen = true
            }

            function toggleContextMenuFromKeyboard() {
                if (isMenuOpen) isMenuOpen = false
                else openContextMenuFromKeyboard()
            }

            function navigateMenuUp() {
                menuFocusedIndex = (menuFocusedIndex - 1 + menuItemCount) % menuItemCount
            }

            function navigateMenuDown() {
                menuFocusedIndex = (menuFocusedIndex + 1) % menuItemCount
            }

            function executeAction(actionIdx) {
                cell.isMenuOpen = false
                switch (actionIdx) {
                    case 0: // Edit
                        root.gameDetailsRequested(cell.gameId)
                        break
                    case 1: // Favourite
                        uiController.gameManager.toggleFavorite(cell.gameId)
                        break
                    case 2: // Pin / Unpin
                        uiController.gameManager.togglePin(cell.gameId)
                        break
                    case 3: // Remove Game
                        removeGameDialog.openDialog(cell.gameId, cell.title, cell.prefixId)
                        break
                }
            }

            function triggerMenuAction() {
                executeAction(menuFocusedIndex)
            }

            Connections {
                target: uiController
                function onKeyboardNavActiveChanged() {
                    if (!uiController.isKeyboardNavActive) {
                        cell.isMenuOpen = false
                    }
                }
            }

            width:  grid.cellWidth
            height: grid.cellHeight
            readonly property bool isMouseActive: !uiController.isKeyboardNavActive && hoverMouse.containsMouse
            readonly property bool isTvFocused: uiController.isKeyboardNavActive && cell.GridView.isCurrentItem && grid.activeFocus
            readonly property bool isHoveredOrFocused: isTvFocused || isMouseActive
            readonly property bool isCardBlurred: cell.isMenuOpen || (appSettings.titleVisibility === 1 && isHoveredOrFocused)
            z: isTvFocused ? 50 : ((cell.isMouseActive || cell.isMenuOpen) ? 20 : 1)

            Item {
                id: tile
                anchors.fill: parent
                anchors.margins: 8

                scale: isTvFocused ? 1.06 : ((cell.isMouseActive || cell.isMenuOpen) ? 1.03 : 1.0)
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                HoverHandler {
                    id: tileHover
                    onHoveredChanged: {
                        if (!hovered && !uiController.isKeyboardNavActive) {
                            cell.isMenuOpen = false
                        }
                    }
                }

                // ── Solid rounded card background base ──
                Rectangle {
                    id: cardBg
                    anchors.fill: parent
                    radius: appSettings.cardRadius
                    color: appSettings.surfaceColor
                    antialiasing: true
                }

                // ── Squircle mask shape ──
                Rectangle {
                    id: cardMask
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: appSettings.cardRadius + 2.5
                    color: "white"
                    antialiasing: true
                    visible: false
                    layer.enabled: true
                    layer.smooth: true
                }

                // ── Masked card content (blur layer applies only here) ──
                Item {
                    id: cardContent
                    anchors.fill: parent
                    anchors.margins: 1
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        maskEnabled: true
                        maskSource:  cardMask
                        blurEnabled: cell.isCardBlurred
                        blur: cell.isCardBlurred ? 1.0 : 0.0
                        blurMax: cell.isCardBlurred ? 32 : 0
                        saturation: 0.0
                        brightness: cell.isMenuOpen ? -0.22 : (cell.isCardBlurred ? -0.28 : 0.0)
                        Behavior on blur { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on brightness { NumberAnimation { duration: 180 } }
                    }

                    Rectangle { anchors.fill: parent; color: appSettings.surfaceColor }

                    // ── Metadata (title + runner tag/year below cover) ────────
                    Item {
                        id: metadataArea
                        visible: root.metaHeight > 0
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: root.metaHeight

                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: 1
                            color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
                        }

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 4

                            // 1. Tag Row (Above Title if tagPosition === 1)
                            RowLayout {
                                visible: appSettings.tagPosition === 1
                                spacing: 6
                                Layout.fillWidth: true

                                Rectangle {
                                    width: typeLabelTop.implicitWidth + 8; height: 18; radius: 4
                                    property color tagC: cell.isRunning ? "#22c55e" : root.tagColor(cell.type)
                                    color: Qt.rgba(tagC.r, tagC.g, tagC.b, 0.18)
                                    Label {
                                        id: typeLabelTop; anchors.centerIn: parent
                                        text: cell.isRunning ? "RUNNING" : root.typeLabel(cell.type, cell.runnerTag)
                                        color: parent.tagC
                                        font { pixelSize: 10; weight: Font.Medium; letterSpacing: 0.5 }
                                        renderType: Text.QtRendering
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            // 2. Main Title + Year
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Label {
                                    text: cell.title
                                    color: appSettings.textColor
                                    font { pixelSize: 15; weight: Font.Normal; letterSpacing: 0.1 }
                                    renderType: Text.QtRendering
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    Layout.fillWidth: true
                                }

                                Label {
                                    text: cell.year ? ("(" + cell.year + ")") : ""
                                    color: cell.isRunning ? "#22c55e" : appSettings.textSecColor
                                    font.pixelSize: 13
                                    font.weight: Font.Normal
                                    visible: appSettings.showYear && cell.year && cell.year.length > 0
                                }
                            }

                            // 3. Tag Row (Below Title if tagPosition === 0)
                            RowLayout {
                                visible: appSettings.tagPosition === 0
                                spacing: 6
                                Layout.fillWidth: true

                                Rectangle {
                                    width: typeLabelBottom.implicitWidth + 8; height: 18; radius: 4
                                    property color tagC: cell.isRunning ? "#22c55e" : root.tagColor(cell.type)
                                    color: Qt.rgba(tagC.r, tagC.g, tagC.b, 0.18)
                                    Label {
                                        id: typeLabelBottom; anchors.centerIn: parent
                                        text: cell.isRunning ? "RUNNING" : root.typeLabel(cell.type, cell.runnerTag)
                                        color: parent.tagC
                                        font { pixelSize: 10; weight: Font.Medium; letterSpacing: 0.5 }
                                        renderType: Text.QtRendering
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }
                    }

                    // ── Cover area (poster image + overlays) ─────────────────
                    Item {
                        id: coverArea
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.bottom: metadataArea.visible ? metadataArea.top : parent.bottom
                        clip: true

                        Rectangle { anchors.fill: parent; color: "#0f0f11" }

                        Image {
                            id: coverImg
                            anchors.fill: parent
                            source: cell.coverPath
                            sourceSize.width: 320; sourceSize.height: 480
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                            visible: status === Image.Ready
                        }

                        // Placeholder icon when no cover
                        YIcon {
                            anchors.centerIn: parent
                            size: 44
                            source: "qrc:/tsuki_app/icons/nav/controller.svg"
                            color: appSettings.textTerColor
                            opacity: 0.35
                            visible: cell.coverPath.toString().length === 0 || coverImg.status === Image.Error
                        }

                        // Top vignette (idle view when titleVisibility === 1)
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: 48
                            visible: appSettings.titleVisibility === 1 && !cell.isCardBlurred
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }

                        // Bottom vignette (idle view when titleVisibility === 1)
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 48
                            visible: appSettings.titleVisibility === 1 && !cell.isCardBlurred
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
                            }
                        }

                        // Bottom vignette (when metadata is below)
                        Rectangle {
                            visible: root.metaHeight > 0
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 36
                            gradient: Gradient {
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.3) }
                            }
                        }

                        // Dark tint overlay when blurred on hover
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.46)
                            opacity: (appSettings.titleVisibility === 1 && cell.isHoveredOrFocused && !cell.isMenuOpen) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        // Subtle Hover darkening when title is below
                        Rectangle {
                            visible: appSettings.titleVisibility !== 1 && !cell.isMenuOpen
                            anchors.fill: parent; color: "#000000"
                            opacity: cell.isMouseActive ? 0.08 : 0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                    }
                } // ── END OF cardContent ──

                // ── Floating Tag Badge on Poster (when tagPosition === 2) ──
                Rectangle {
                    id: onPosterTagBadge
                    visible: appSettings.tagPosition === 2 && !cell.isMenuOpen
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 8
                    z: 12
                    height: 22
                    radius: 4
                    width: onPosterTagLabel.implicitWidth + 10
                    property color tagC: cell.isRunning ? "#22c55e" : root.tagColor(cell.type)
                    color: cell.isHoveredOrFocused ? (cell.isRunning ? "#22c55e" : appSettings.accentColor) : Qt.rgba(0, 0, 0, 0.75)
                    border.color: cell.isHoveredOrFocused ? (cell.isRunning ? "#22c55e" : appSettings.accentColor) : Qt.rgba(tagC.r, tagC.g, tagC.b, 0.4)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 160 } }

                    Label {
                        id: onPosterTagLabel
                        anchors.centerIn: parent
                        text: cell.isRunning ? "RUNNING" : root.typeLabel(cell.type, cell.runnerTag)
                        color: cell.isHoveredOrFocused ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : parent.tagC
                        font { pixelSize: 10; weight: Font.Medium; letterSpacing: 0.5 }
                        renderType: Text.QtRendering
                    }
                }

                // ── Center Title Area (Visible on Hover when titleVisibility === 1) ──
                Item {
                    id: centerTitleArea
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 24
                    anchors.bottomMargin: 28
                    z: 12

                    opacity: (appSettings.titleVisibility === 1 && cell.isHoveredOrFocused && !cell.isMenuOpen) ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 6

                        // Tag Row Above Title
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 6
                            visible: appSettings.tagPosition === 1

                            Rectangle {
                                height: 20
                                radius: 4
                                width: hTagLblAbove.implicitWidth + 12
                                property color tagC: cell.isRunning ? "#22c55e" : root.tagColor(cell.type)
                                color: Qt.rgba(tagC.r, tagC.g, tagC.b, 0.25)
                                border.color: Qt.rgba(tagC.r, tagC.g, tagC.b, 0.6)
                                border.width: 1

                                Label {
                                    id: hTagLblAbove
                                    anchors.centerIn: parent
                                    text: cell.isRunning ? "RUNNING" : root.typeLabel(cell.type, cell.runnerTag)
                                    color: parent.tagC
                                    font { pixelSize: 10; weight: Font.Medium; letterSpacing: 0.5 }
                                    renderType: Text.QtRendering
                                }
                            }
                        }

                        // Main Title
                        Label {
                            Layout.fillWidth: true
                            text: cell.title
                            color: "#ffffff"
                            font { pixelSize: 16; weight: Font.Normal }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            lineHeight: 1.2
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            renderType: Text.QtRendering
                        }

                        // Release Year
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: cell.year ? ("(" + cell.year + ")") : ""
                            color: Qt.rgba(1, 1, 1, 0.75)
                            font.pixelSize: 13
                            font.weight: Font.Normal
                            visible: appSettings.showYear && cell.year && cell.year.length > 0
                            renderType: Text.QtRendering
                        }

                        // Tag Row Below Title
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 6
                            visible: appSettings.tagPosition === 0

                            Rectangle {
                                height: 20
                                radius: 4
                                width: hTagLblBelow.implicitWidth + 12
                                property color tagC: cell.isRunning ? "#22c55e" : root.tagColor(cell.type)
                                color: Qt.rgba(tagC.r, tagC.g, tagC.b, 0.25)
                                border.color: Qt.rgba(tagC.r, tagC.g, tagC.b, 0.6)
                                border.width: 1

                                Label {
                                    id: hTagLblBelow
                                    anchors.centerIn: parent
                                    text: cell.isRunning ? "RUNNING" : root.typeLabel(cell.type, cell.runnerTag)
                                    color: parent.tagC
                                    font { pixelSize: 10; weight: Font.Medium; letterSpacing: 0.5 }
                                    renderType: Text.QtRendering
                                }
                            }
                        }
                    }
                }

                // ── Bottom Action Prompt (Visible on Hover when titleVisibility === 1) ──
                Item {
                    id: bottomActionArea
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    height: 18
                    z: 12

                    opacity: (appSettings.titleVisibility === 1 && cell.isHoveredOrFocused && !cell.isMenuOpen) ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    GamepadPrompt {
                        anchors.centerIn: parent
                        prefixText: uiController.isKeyboardNavActive ? "Press" : ""
                        iconSource: (uiController.gamepad && uiController.gamepad.isConnected && uiController.isKeyboardNavActive) ? uiController.gamepad.actionIconSource : ""
                        keyName: (uiController.isKeyboardNavActive && (!uiController.gamepad || !uiController.gamepad.isConnected)) ? "Enter" : ""
                        suffixText: {
                            if (cell.isRunning) return uiController.isKeyboardNavActive ? "to view" : "Click to view"
                            if (appSettings.leftClickBehavior === 1) return uiController.isKeyboardNavActive ? "to view" : "Click to view"
                            return uiController.isKeyboardNavActive ? "to launch" : "Click to play"
                        }
                        textColor: cell.isRunning ? "#22c55e" : appSettings.accentColor
                        iconColor: cell.isRunning ? "#22c55e" : appSettings.accentColor
                        pixelSize: 12
                        iconSize: 14
                        isBold: false
                    }
                }

                // ── Center Quick Play / Stop / View Floating Pill on Hover ───────────
                Rectangle {
                    visible: appSettings.titleVisibility !== 1 && cell.isHoveredOrFocused && !cell.isMenuOpen
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -root.metaHeight / 2
                    width: 48
                    height: 48
                    radius: 24
                    color: cell.isRunning ? "#ef4444" : appSettings.accentColor
                    z: 13
                    scale: (cell.isHoveredOrFocused && !cell.isMenuOpen) ? 1.0 : 0.7
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    YIcon {
                        anchors.centerIn: parent
                        size: 20
                        source: {
                            if (cell.isRunning) return "qrc:/tsuki_app/icons/actions/stop.svg"
                            if (appSettings.leftClickBehavior === 1) return "qrc:/tsuki_app/icons/actions/edit.svg"
                            return "qrc:/tsuki_app/icons/actions/play.svg"
                        }
                        color: cell.isRunning ? "#ffffff" : (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                    }
                }

                // ── Card MouseArea ───────────────────────────────────────────
                MouseArea {
                    id: hoverMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    enabled: !cell.isMenuOpen
                    onPositionChanged: { uiController.setKeyboardNavActive(false) }
                    onPressed: { uiController.setKeyboardNavActive(false) }
                    onClicked: (mouse) => {
                        if (cell.isMenuOpen) {
                            cell.isMenuOpen = false
                            return
                        }
                        uiController.setKeyboardNavActive(false)
                        grid.currentIndex = cell.index
                        grid.forceActiveFocus()
                        if (mouse.button === Qt.RightButton) {
                            cell.isMenuOpen = true
                        } else {
                            if (cell.isRunning) {
                                root.gameDetailsRequested(cell.gameId)
                            } else {
                                grid.activatePrimaryAction(cell.gameId)
                            }
                        }
                    }
                }

                // ── Top-Right Persistent Badges ──────────────────────────────
                // 1. Persistent Pin Badge
                Rectangle {
                    visible: cell.isPinned && !cell.isMenuOpen
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    width: 24; height: 24; radius: 12
                    color: Qt.rgba(0, 0, 0, 0.75)
                    border.color: appSettings.accentColor
                    border.width: 1
                    z: 14

                    YIcon {
                        anchors.centerIn: parent
                        size: 14
                        source: "qrc:/tsuki_app/icons/actions/pin.svg"
                        color: appSettings.accentColor
                    }
                }

                // 2. Persistent Favorite Badge (if not pinned)
                Rectangle {
                    visible: cell.isFavorite && !cell.isPinned && !cell.isMenuOpen
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    width: 24; height: 24; radius: 12
                    color: Qt.rgba(0, 0, 0, 0.75)
                    border.color: "#fbbf24"
                    border.width: 1
                    z: 14

                    YIcon {
                        anchors.centerIn: parent
                        size: 14
                        source: "qrc:/tsuki_app/icons/nav/favourite-filled.svg"
                        color: "#fbbf24"
                    }
                }

                // ── Glassmorphic Action Menu Overlay (Crystal-Sharp on Top of Blur) ──
                Rectangle {
                    id: actionOverlay
                    anchors.fill: cardContent
                    radius: appSettings.cardRadius
                    color: Qt.rgba(0, 0, 0, 0.45)
                    opacity: cell.isMenuOpen ? 1.0 : 0.0
                    visible: opacity > 0
                    z: 20
                    clip: true
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // Dismiss if clicking dark background outside buttons
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: cell.isMenuOpen = false
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 24, 150)
                        spacing: 8
                        transform: Translate {
                            y: cell.isMenuOpen ? 0 : 8
                            Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        // 1. Details / Edit Button
                        Rectangle {
                            id: editBtn
                            readonly property bool isBtnFocused: uiController.isKeyboardNavActive && cell.isMenuOpen && cell.menuFocusedIndex === 0
                            readonly property bool isBtnActive: editMA.containsMouse || isBtnFocused
                            Layout.fillWidth: true
                            height: 38
                            radius: 19
                            color: isBtnActive
                                ? appSettings.accentColor
                                : Qt.rgba(0.15, 0.15, 0.18, 0.88)
                            border.color: isBtnFocused ? "#ffffff" : Qt.rgba(1, 1, 1, 0.15)
                            border.width: isBtnFocused ? 2 : 1
                            scale: editMA.pressed ? 0.96 : (isBtnActive ? 1.04 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                YIcon {
                                    size: 18
                                    source: "qrc:/tsuki_app/icons/actions/edit.svg"
                                    color: editBtn.isBtnActive
                                        ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                                        : "#ffffff"
                                }
                                Label {
                                    text: "Details"
                                    color: editBtn.isBtnActive
                                        ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                                        : "#ffffff"
                                    font.pixelSize: 14
                                    font.weight: Font.Normal
                                    renderType: Text.QtRendering
                                }
                            }
                            MouseArea {
                                id: editMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    cell.isMenuOpen = false
                                    cell.executeAction(0)
                                }
                            }
                        }

                        // 2. Favourite / Unfavourite Button
                        Rectangle {
                            id: favBtnCard
                            readonly property bool isBtnFocused: uiController.isKeyboardNavActive && cell.isMenuOpen && cell.menuFocusedIndex === 1
                            readonly property bool isBtnActive: favMA.containsMouse || isBtnFocused
                            Layout.fillWidth: true
                            height: 38
                            radius: 19
                            color: isBtnActive
                                ? "#fbbf24"
                                : Qt.rgba(0.15, 0.15, 0.18, 0.88)
                            border.color: isBtnFocused
                                ? "#ffffff"
                                : (cell.isFavorite
                                    ? "#fbbf24"
                                    : Qt.rgba(1, 1, 1, 0.15))
                            border.width: isBtnFocused ? 2 : 1
                            scale: favMA.pressed ? 0.96 : (isBtnActive ? 1.04 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                YIcon {
                                    size: 18
                                    source: cell.isFavorite ? "qrc:/tsuki_app/icons/nav/favourite-filled.svg" : "qrc:/tsuki_app/icons/nav/favourite.svg"
                                    color: favBtnCard.isBtnActive
                                        ? "#0f0f11"
                                        : (cell.isFavorite ? "#fbbf24" : "#ffffff")
                                }
                                Label {
                                    text: cell.isFavorite ? "Unfavourite" : "Favourite"
                                    color: favBtnCard.isBtnActive ? "#0f0f11" : "#ffffff"
                                    font.pixelSize: 14
                                    font.weight: Font.Normal
                                    renderType: Text.QtRendering
                                }
                            }
                            MouseArea {
                                id: favMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    cell.isMenuOpen = false
                                    cell.executeAction(1)
                                }
                            }
                        }

                        // 3. Pin to Top / Unpin Button
                        Rectangle {
                            id: pinBtn
                            readonly property bool isBtnFocused: uiController.isKeyboardNavActive && cell.isMenuOpen && cell.menuFocusedIndex === 2
                            readonly property bool isBtnActive: pinMA.containsMouse || isBtnFocused
                            Layout.fillWidth: true
                            height: 38
                            radius: 19
                            color: isBtnActive
                                ? appSettings.accentColor
                                : Qt.rgba(0.15, 0.15, 0.18, 0.88)
                            border.color: isBtnFocused
                                ? "#ffffff"
                                : (cell.isPinned
                                    ? appSettings.accentColor
                                    : Qt.rgba(1, 1, 1, 0.15))
                            border.width: isBtnFocused ? 2 : 1
                            scale: pinMA.pressed ? 0.96 : (isBtnActive ? 1.04 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                YIcon {
                                    size: 18
                                    source: "qrc:/tsuki_app/icons/actions/pin.svg"
                                    color: pinBtn.isBtnActive
                                        ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                                        : (cell.isPinned ? appSettings.accentColor : "#ffffff")
                                }
                                Label {
                                    text: cell.isPinned ? "Unpin" : "Pin to Top"
                                    color: pinBtn.isBtnActive
                                        ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                                        : "#ffffff"
                                    font.pixelSize: 14
                                    font.weight: Font.Normal
                                    renderType: Text.QtRendering
                                }
                            }
                            MouseArea {
                                id: pinMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    cell.isMenuOpen = false
                                    cell.executeAction(2)
                                }
                            }
                        }

                        // 4. Remove Button
                        Rectangle {
                            id: removeBtnCard
                            readonly property bool isBtnFocused: uiController.isKeyboardNavActive && cell.isMenuOpen && cell.menuFocusedIndex === 3
                            readonly property bool isBtnActive: removeMA.containsMouse || isBtnFocused
                            Layout.fillWidth: true
                            height: 38
                            radius: 19
                            color: isBtnActive
                                ? "#ef4444"
                                : Qt.rgba(0.15, 0.15, 0.18, 0.88)
                            border.color: isBtnFocused ? "#ffffff" : Qt.rgba(1, 1, 1, 0.15)
                            border.width: isBtnFocused ? 2 : 1
                            scale: removeMA.pressed ? 0.96 : (isBtnActive ? 1.04 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                YIcon {
                                    size: 18
                                    source: "qrc:/tsuki_app/icons/actions/trash.svg"
                                    color: removeBtnCard.isBtnActive ? "#ffffff" : "#ef4444"
                                }
                                Label {
                                    text: "Remove"
                                    color: "#ffffff"
                                    font.pixelSize: 14
                                    font.weight: Font.Normal
                                    renderType: Text.QtRendering
                                }
                            }
                            MouseArea {
                                id: removeMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    cell.isMenuOpen = false
                                    cell.executeAction(3)
                                }
                            }
                        }
                    }
                }

                // ── Squircle border ──────────────────────────────────────────
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: appSettings.cardRadius
                    antialiasing: true
                    border.color: cell.isRunning
                        ? "#22c55e"
                        : ((cell.isTvFocused || cell.isMouseActive || cell.isMenuOpen)
                            ? appSettings.accentColor
                            : appSettings.borderColor)
                    border.width: cell.isTvFocused ? 3.0 : ((cell.isMouseActive || cell.isMenuOpen || cell.isRunning) ? 2.5 : 1.5)
                    z: 15
                    Behavior on border.color { ColorAnimation { duration: 160 } }
                    Behavior on border.width { NumberAnimation { duration: 160 } }
                }
            }
        }

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    }

    // ── Empty State / Search Indicator (Matching Yoru Layout) ────────────────
    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: grid.count === 0

        YIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "qrc:/tsuki_app/icons/nav/library.svg"
            color: appSettings.textTerColor
            size: 48
            opacity: 0.6
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                if (uiController.searchModel.filterType === 3) return "No Favourite Games Yet"
                if (uiController.searchModel.filterType === 4) return "No Recently Played Games"
                return "Your Game Library is Empty"
            }
            color: appSettings.textColor
            font.pixelSize: 20
            font.weight: Font.Medium
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                if (uiController.searchModel.filterType === 3) return "Right-click any game or tap the star button to add it to favourites."
                if (uiController.searchModel.filterType === 4) return "Games you have launched through Tsuki will appear here."
                return "Add locally downloaded Windows games (.exe) to launch them with Wine or Proton."
            }
            color: appSettings.textSecColor
            font.pixelSize: 15
            font.weight: Font.Normal
        }

        Item { width: 1; height: 6 }

        M3Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Add Game"
            iconSource: "qrc:/tsuki_app/icons/actions/add.svg"
            buttonType: "filled"
            onClicked: root.addGameRequested()
        }
    }

    RemoveGameDialog {
        id: removeGameDialog
    }
}
