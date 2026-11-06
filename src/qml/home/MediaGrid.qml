import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Item {
    id: mediaGrid
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

    readonly property bool isDark: appSettings.isEffectiveDark
    readonly property int  cardRadius: appSettings.cardRadius

    readonly property bool hasTitleBelow: appSettings.titleVisibility === 0
    readonly property bool hasTagAboveTitle: hasTitleBelow && appSettings.tagPosition === 1
    readonly property bool hasTagBelowTitle: hasTitleBelow && appSettings.tagPosition === 0

    readonly property int metaHeight: {
        if (!hasTitleBelow) return 0
        if (hasTagAboveTitle || hasTagBelowTitle) return 52
        return 34
    }

    function typeLabel(t, runnerTag) {
        if (runnerTag && runnerTag.length > 0) return runnerTag
        return t === 0 ? "PROTON-GE" : (t === 1 ? "WINE" : "CUSTOM")
    }
    function tagColor(t) {
        return t === 0 ? appSettings.tagColorSeries
                       : (t === 1 ? appSettings.tagColorMovie
                                  : appSettings.tagColorAnime)
    }

    GridView {
        id: grid
        anchors.fill: parent
        clip: false
        model: mediaGrid.model
        cellWidth:  Math.floor(width / Math.max(1, Math.floor(width / appSettings.thumbScaleTarget)))
        cellHeight: Math.floor(((cellWidth - 16) * 1.5) + mediaGrid.metaHeight)

        focus: true
        keyNavigationEnabled: false

        Connections {
            target: mediaGrid.model
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

        function activatePrimaryAction(gameId) {
            if (appSettings.leftClickBehavior === 0) {
                if (uiController.launchPipeline.isGameRunning(gameId)) {
                    mediaGrid.gameDetailsRequested(gameId)
                } else {
                    uiController.launchPipeline.launchGame(gameId)
                    mediaGrid.gameLaunched(gameId)
                }
            } else {
                mediaGrid.gameDetailsRequested(gameId)
            }
        }

        function selectCurrent() {
            if (grid.currentIndex >= 0 && grid.currentIndex < grid.count) {
                let itemData = mediaGrid.model.get(grid.currentIndex)
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
            let currItem = grid.currentItem
            if (currItem && currItem.isMenuOpen) {
                currItem.isMenuOpen = false
                return
            }
            if (grid.count === 0 || grid.currentIndex % mediaGrid.columns === 0) {
                mediaGrid.focusSidebarRequested()
            } else if (grid.currentIndex > 0) {
                grid.currentIndex--
            }
        }

        Keys.onRightPressed: (event) => {
            event.accepted = true
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
            let currItem = grid.currentItem
            if (currItem && currItem.isMenuOpen) {
                currItem.navigateMenuUp()
                return
            }
            if (grid.count === 0 || grid.currentIndex < mediaGrid.columns) {
                mediaGrid.focusTopBarRequested()
            } else {
                grid.currentIndex = Math.max(0, grid.currentIndex - mediaGrid.columns)
            }
        }

        Keys.onDownPressed: (event) => {
            event.accepted = true
            let currItem = grid.currentItem
            if (currItem && currItem.isMenuOpen) {
                currItem.navigateMenuDown()
                return
            }
            if (grid.currentIndex + mediaGrid.columns < grid.count) {
                grid.currentIndex += mediaGrid.columns
            } else if (grid.currentIndex < grid.count - 1) {
                grid.currentIndex = grid.count - 1
            }
        }

        Keys.onEscapePressed: (event) => {
            event.accepted = true
            let currItem = grid.currentItem
            if (currItem && currItem.isMenuOpen) {
                currItem.isMenuOpen = false
            } else {
                mediaGrid.focusSidebarRequested()
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

        // ── Delegate ─────────────────────────────────────────────────────────
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

            property bool isMenuOpen: false
            property int menuFocusedIndex: 0
            readonly property int menuItemCount: 6

            function openContextMenuFromKeyboard() {
                menuFocusedIndex = 0
                isMenuOpen = true
            }

            function toggleContextMenuFromKeyboard() {
                isMenuOpen = !isMenuOpen
                if (isMenuOpen) menuFocusedIndex = 0
            }

            function navigateMenuUp() {
                menuFocusedIndex = (menuFocusedIndex - 1 + menuItemCount) % menuItemCount
            }

            function navigateMenuDown() {
                menuFocusedIndex = (menuFocusedIndex + 1) % menuItemCount
            }

            function triggerMenuAction() {
                isMenuOpen = false
                switch (menuFocusedIndex) {
                    case 0: // Configure / Edit
                        mediaGrid.gameDetailsRequested(cell.gameId)
                        break
                    case 1: // Winetricks
                        mediaGrid.winetricksRequested(cell.prefixId, cell.title)
                        break
                    case 2: // Open Game Directory
                        uiController.gameManager.openGameDirectory(cell.gameId)
                        break
                    case 3: // Open Prefix Directory
                        uiController.prefixManager.openPrefixInFileManager(cell.prefixId)
                        break
                    case 4: // Favourite
                        uiController.gameManager.toggleFavorite(cell.gameId)
                        break
                    case 5: // Remove Game
                        uiController.gameManager.removeGame(cell.gameId, false)
                        break
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

                Rectangle {
                    id: cardBg
                    anchors.fill: parent
                    radius: mediaGrid.cardRadius
                    color: appSettings.surfaceColor
                    antialiasing: true
                }

                Rectangle {
                    id: cardMask
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: mediaGrid.cardRadius + 2.5
                    color: "white"
                    antialiasing: true
                    visible: false
                    layer.enabled: true
                    layer.smooth: true
                }

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
                        brightness: cell.isMenuOpen ? -0.25 : (cell.isCardBlurred ? -0.28 : 0.0)
                        Behavior on blur { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on brightness { NumberAnimation { duration: 180 } }
                    }

                    Rectangle { anchors.fill: parent; color: appSettings.surfaceColor }

                    // Metadata below cover
                    Item {
                        id: metadataArea
                        visible: mediaGrid.metaHeight > 0
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: mediaGrid.metaHeight

                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: 1
                            color: mediaGrid.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 6

                            Label {
                                text: cell.title
                                color: appSettings.textColor
                                font { pixelSize: 14; weight: Font.Medium }
                                renderType: Text.QtRendering
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Layout.fillWidth: true
                            }

                            Label {
                                text: cell.year
                                color: cell.isRunning ? "#34d399" : appSettings.textSecColor
                                font.pixelSize: 12
                                font.weight: cell.isRunning ? Font.Bold : Font.Normal
                                visible: appSettings.showYear && cell.year.length > 0
                            }
                        }
                    }

                    // Cover area
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
                            sourceSize.width: 300; sourceSize.height: 450
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                            visible: status === Image.Ready
                        }

                        // Subtle Hover darkening + Play Overlay Icon
                        Rectangle {
                            visible: !cell.isMenuOpen
                            anchors.fill: parent
                            color: "#000000"
                            opacity: cell.isHoveredOrFocused ? 0.28 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                    }
                }

                // Floating Runner / Status Tag Badge (Top-Left)
                Rectangle {
                    visible: !cell.isMenuOpen
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 8
                    z: 12
                    height: 22
                    radius: 4
                    width: onPosterTagLabel.implicitWidth + 12
                    property color tagC: cell.isRunning ? "#34d399" : mediaGrid.tagColor(cell.type)
                    color: cell.isHoveredOrFocused ? tagC : Qt.rgba(0, 0, 0, 0.78)
                    border.color: tagC
                    border.width: 1

                    Label {
                        id: onPosterTagLabel
                        anchors.centerIn: parent
                        text: cell.isRunning ? "RUNNING" : mediaGrid.typeLabel(cell.type, cell.runnerTag)
                        color: cell.isHoveredOrFocused ? "#0f0f11" : parent.tagC
                        font { pixelSize: 10; weight: Font.DemiBold; letterSpacing: 0.5 }
                        renderType: Text.QtRendering
                    }
                }

                // Center Play / Stop Pill Indicator on Hover
                Rectangle {
                    visible: cell.isHoveredOrFocused && !cell.isMenuOpen
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -mediaGrid.metaHeight / 2
                    width: 48
                    height: 48
                    radius: 24
                    color: cell.isRunning ? "#ef4444" : appSettings.accentColor
                    z: 13
                    scale: cell.isHoveredOrFocused ? 1.0 : 0.7
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    YIcon {
                        anchors.centerIn: parent
                        size: 20
                        source: cell.isRunning ? "qrc:/tsuki_app/icons/actions/stop.svg" : "qrc:/tsuki_app/icons/actions/play.svg"
                        color: cell.isRunning ? "#ffffff" : (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                    }
                }

                // Card MouseArea (Left-click launches game, Right-click opens context menu)
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
                        uiController.setKeyboardNavActive(false)
                        grid.currentIndex = cell.index
                        grid.forceActiveFocus()
                        if (mouse.button === Qt.RightButton) {
                            cell.isMenuOpen = true
                        } else {
                            if (cell.isRunning) {
                                uiController.launchPipeline.stopGame(cell.gameId)
                            } else {
                                grid.activatePrimaryAction(cell.gameId)
                            }
                        }
                    }
                }

                // Top-Right Quick Configure Button on Hover
                Rectangle {
                    id: quickConfigBtn
                    visible: (cell.isHoveredOrFocused || cell.isPinned || cell.isFavorite) && !cell.isMenuOpen
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    width: 28; height: 28; radius: 14
                    color: quickCfgMA.containsMouse ? appSettings.accentColor : Qt.rgba(0, 0, 0, 0.78)
                    border.color: cell.isFavorite ? "#fbbf24" : appSettings.accentColor
                    border.width: 1
                    z: 18

                    YIcon {
                        anchors.centerIn: parent
                        size: 14
                        source: cell.isHoveredOrFocused
                                ? "qrc:/tsuki_app/icons/actions/settings.svg"
                                : (cell.isPinned ? "qrc:/tsuki_app/icons/actions/pin.svg" : "qrc:/tsuki_app/icons/nav/star.svg")
                        color: quickCfgMA.containsMouse ? "#0f0f11" : (cell.isFavorite && !cell.isHoveredOrFocused ? "#fbbf24" : "#ffffff")
                    }

                    MouseArea {
                        id: quickCfgMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mediaGrid.gameDetailsRequested(cell.gameId)
                    }
                }

                // ── Glassmorphic Context Menu Overlay (Right-Click / Menu Button) ──
                Rectangle {
                    id: actionOverlay
                    anchors.fill: cardContent
                    radius: mediaGrid.cardRadius
                    color: Qt.rgba(0, 0, 0, 0.58)
                    opacity: cell.isMenuOpen ? 1.0 : 0.0
                    visible: opacity > 0
                    z: 25
                    clip: true
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: cell.isMenuOpen = false
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 16, 168)
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "Configure / Edit", icon: "qrc:/tsuki_app/icons/actions/settings.svg", tint: appSettings.accentColor, idx: 0 },
                                { label: "Winetricks",       icon: "qrc:/tsuki_app/icons/actions/wrench.svg",   tint: "#38bdf8",               idx: 1 },
                                { label: "Game Directory",   icon: "qrc:/tsuki_app/icons/actions/folder.svg",   tint: "#a1a1aa",               idx: 2 },
                                { label: "Prefix Directory", icon: "qrc:/tsuki_app/icons/nav/prefix.svg",       tint: "#a1a1aa",               idx: 3 },
                                { label: cell.isFavorite ? "Unfavourite" : "Favourite", icon: "qrc:/tsuki_app/icons/nav/star.svg", tint: "#fbbf24", idx: 4 },
                                { label: "Remove Game",      icon: "qrc:/tsuki_app/icons/actions/trash.svg",    tint: "#ef4444",               idx: 5 }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool isFocusedRow: uiController.isKeyboardNavActive && cell.isMenuOpen && cell.menuFocusedIndex === modelData.idx
                                readonly property bool isRowActive: rowMA.containsMouse || isFocusedRow

                                Layout.fillWidth: true
                                height: 32
                                radius: 16
                                color: isRowActive ? modelData.tint : Qt.rgba(0.14, 0.14, 0.18, 0.92)
                                border.color: isFocusedRow ? "#ffffff" : Qt.rgba(1, 1, 1, 0.14)
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    YIcon {
                                        size: 15
                                        source: modelData.icon
                                        color: parent.parent.isRowActive ? "#0f0f11" : modelData.tint
                                    }
                                    Label {
                                        text: modelData.label
                                        color: parent.parent.isRowActive ? "#0f0f11" : "#ffffff"
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                MouseArea {
                                    id: rowMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        cell.menuFocusedIndex = modelData.idx
                                        cell.triggerMenuAction()
                                    }
                                }
                            }
                        }
                    }
                }

                // Squircle border
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: mediaGrid.cardRadius
                    antialiasing: true
                    border.color: cell.isRunning
                        ? "#34d399"
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

    // Empty state
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12
        visible: grid.count === 0

        YIcon {
            Layout.alignment: Qt.AlignHCenter
            source: "qrc:/tsuki_app/icons/brand/tsuki-sidebar.svg"
            color: appSettings.textTerColor
            size: 52
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: {
                if (uiController.searchModel.filterType === 3) return "No Favourite Games Yet"
                if (uiController.searchModel.filterType === 4) return "No Recently Played Games"
                return "Your Tsuki Game Library is Empty"
            }
            color: appSettings.textColor
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "Add locally downloaded Windows games (.exe) to launch them through Wine or Proton-GE."
            color: appSettings.textSecColor
            font.pixelSize: 14
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            text: "+ Add Windows Game (.exe)"
            onClicked: mediaGrid.addGameRequested()
            background: Rectangle {
                radius: 22
                color: appSettings.accentColor
                implicitWidth: 230
                implicitHeight: 44
            }
            contentItem: Label {
                text: parent.text
                color: "#0f0f11"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}

