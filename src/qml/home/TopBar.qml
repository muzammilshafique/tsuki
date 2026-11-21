import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Rectangle {
    id: topBar
    Layout.fillWidth: true
    Layout.preferredHeight: 84
    color: "transparent"

    property string searchQuery: ""
    readonly property bool isSearchFocused: searchField.activeFocus
    readonly property bool isAddMenuOpen: addFabMenu.isMenuOpen
    signal searchRequested(string query)
    signal addGameRequested(string platform)
    signal focusGridRequested()
    signal focusSidebarRequested()

    function forceSearchFocus() { searchTile.forceActiveFocus() }
    function activateSearch() { searchField.forceActiveFocus() }
    function openAddMenu() { addFabMenu.openMenu() }
    function closeAddMenu() { addFabMenu.closeMenu() }

    readonly property var filterOptions: [
        { key: "linux",     label: "Linux Only" },
        { key: "windows",   label: "Windows Only" },
        { key: "epic",      label: "Epic Only" },
        { key: "favourite", label: "Favourite" },
        { key: "local",     label: "Local" }
    ]

    function isFilterKeySelected(key) {
        if (!uiController || !uiController.searchModel) return false
        const sm = uiController.searchModel
        const af = sm.activeFilters || []
        if (af.indexOf(key) !== -1) return true
        if (af.length === 0 && sm.filterType === 3 && key === "favourite") return true
        return false
    }

    function isCategorySelected(cat) {
        if (!uiController || !uiController.searchModel) return false
        const sm = uiController.searchModel
        const ac = sm.activeCategories || []
        if (ac.indexOf(cat) !== -1) return true
        if (ac.length === 0 && sm.categoryFilter === cat) return true
        return false
    }

    function isAllGamesSelected() {
        if (!uiController || !uiController.searchModel) return true
        return !uiController.searchModel.hasActiveFilters
    }

    function toggleFilterKey(key) {
        if (!uiController || !uiController.searchModel) return
        const sm = uiController.searchModel
        const af = sm.activeFilters ? Array.from(sm.activeFilters) : []
        if (af.length === 0 && sm.filterType === 3) {
            sm.filterType = -1
            if (key === "favourite") return
            sm.toggleFilter("favourite")
        }
        sm.toggleFilter(key)
    }

    function currentFilterName() {
        if (!uiController || !uiController.searchModel) return "All Games"
        const sm = uiController.searchModel
        let labels = []
        for (let i = 0; i < filterOptions.length; ++i) {
            if (isFilterKeySelected(filterOptions[i].key)) {
                labels.push(filterOptions[i].label)
            }
        }
        const cats = sm.activeCategories || []
        for (let j = 0; j < cats.length; ++j) {
            labels.push(cats[j])
        }
        if (cats.length === 0 && sm.categoryFilter && sm.categoryFilter.length > 0) {
            labels.push(sm.categoryFilter)
        }
        if (labels.length === 0) return "All Games"
        if (labels.length === 1) return labels[0]
        return labels.length + " Filters"
    }

    readonly property var sortOptions: [
        { label: "Recently Played / Default", mode: 0 },
        { label: "Title (A → Z)",             mode: 1 },
        { label: "Title (Z → A)",             mode: 2 },
        { label: "Playtime (Most Played)",    mode: 3 },
        { label: "Date Added (Newest)",       mode: 4 }
    ]

    function currentSortName() {
        let mode = uiController.searchModel.sortMode
        switch (mode) {
            case 1: return "A → Z"
            case 2: return "Z → A"
            case 3: return "Most Played"
            case 4: return "Newest"
            default: return "Default"
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        spacing: 16

        // ── Search Input Tile (Navigable Box with M3 focus border) ───────────
        Rectangle {
            id: searchTile
            focus: true
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 380
            Layout.preferredHeight: 40
            Layout.minimumWidth: 240
            Layout.maximumWidth: 540
            radius: 20
            readonly property bool isEditing: searchField.activeFocus
            readonly property bool isTileFocused: searchTile.activeFocus && (uiController ? uiController.isKeyboardNavActive : false)
            readonly property bool isSearchHovered: searchTileHover.hovered || searchField.hovered
            color: {
                let base = appSettings.inputColor
                if (searchField.activeFocus || searchTile.isTileFocused) {
                    return appSettings.isEffectiveDark
                        ? Qt.rgba(Math.min(1.0, base.r + 0.08), Math.min(1.0, base.g + 0.08), Math.min(1.0, base.b + 0.08), 1.0)
                        : Qt.rgba(Math.max(0.0, base.r - 0.04), Math.max(0.0, base.g - 0.04), Math.max(0.0, base.b - 0.04), 1.0)
                }
                if (isSearchHovered) {
                    return appSettings.isEffectiveDark
                        ? Qt.rgba(Math.min(1.0, base.r + 0.04), Math.min(1.0, base.g + 0.04), Math.min(1.0, base.b + 0.04), 1.0)
                        : Qt.rgba(Math.max(0.0, base.r - 0.02), Math.max(0.0, base.g - 0.02), Math.max(0.0, base.b - 0.02), 1.0)
                }
                return base
            }

            border.color: (searchField.activeFocus || searchTile.isTileFocused)
                ? appSettings.accentColor
                : (isSearchHovered
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14))
                    : appSettings.borderColor)
            border.width: (searchField.activeFocus || searchTile.isTileFocused) ? 2 : 1
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            Keys.onLeftPressed: (event) => {
                if (!searchTile.isEditing) {
                    event.accepted = true
                    topBar.focusSidebarRequested()
                }
            }
            Keys.onRightPressed: (event) => {
                if (!searchTile.isEditing) {
                    event.accepted = true
                    filterBtn.forceActiveFocus()
                }
            }
            Keys.onDownPressed: (event) => {
                event.accepted = true
                topBar.focusGridRequested()
            }
            Keys.onReturnPressed: (event) => {
                event.accepted = true
                searchField.forceActiveFocus()
            }
            Keys.onEnterPressed: (event) => {
                event.accepted = true
                searchField.forceActiveFocus()
            }
            Keys.onSpacePressed: (event) => {
                if (!searchTile.isEditing) {
                    event.accepted = true
                    searchField.forceActiveFocus()
                }
            }
            Keys.onEscapePressed: (event) => {
                event.accepted = true
                topBar.focusGridRequested()
            }
            Keys.onPressed: (event) => {
                if (!searchTile.isEditing && event.key === Qt.Key_Backspace) {
                    event.accepted = true
                    topBar.focusGridRequested()
                }
            }

            HoverHandler { id: searchTileHover; cursorShape: Qt.IBeamCursor }

            // Left search icon
            YIcon {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 14
                size: 18
                source: "qrc:/tsuki_app/icons/actions/search.svg"
                color: (searchField.activeFocus || searchTile.isTileFocused) ? appSettings.accentColor : appSettings.textSecColor
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            TextField {
                id: searchField
                anchors.fill: parent
                leftPadding: 42
                rightPadding: searchField.text.length > 0 ? 36 : 44
                color: appSettings.textColor
                font.pixelSize: 13
                background: null
                verticalAlignment: Text.AlignVCenter
                selectByMouse: true
                renderType: Text.QtRendering

                placeholderText: {
                    if (uiController.searchModel.filterType === 3) return "Search favourite games…"
                    return "Search games in library…"
                }
                placeholderTextColor: appSettings.textTerColor

                Keys.onEscapePressed: (event) => {
                    event.accepted = true
                    if (searchField.text.length > 0) {
                        searchTile.forceActiveFocus()
                    } else {
                        topBar.focusGridRequested()
                    }
                }
                Keys.onDownPressed: (event) => {
                    event.accepted = true
                    topBar.focusGridRequested()
                }
                onAccepted: {
                    topBar.focusGridRequested()
                }
                onTextChanged: {
                    topBar.searchQuery = text
                    topBar.searchRequested(text)
                }
            }

            GamepadPrompt {
                readonly property bool showPrompt: Boolean(uiController && uiController.isKeyboardNavActive) && searchField.text.length === 0 && !searchTile.isEditing
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 12
                opacity: showPrompt ? 0.85 : 0.0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                iconSource: (uiController && uiController.controllerManager) ? uiController.controllerManager.searchIconSource : ""
                keyName: "/"
                pixelSize: 12
                iconSize: 17
                iconColor: searchTile.isTileFocused ? appSettings.accentColor : appSettings.textSecColor
            }

            // Clear text button
            ToolButton {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 6
                implicitWidth: 28
                implicitHeight: 28
                visible: searchField.text.length > 0
                focusPolicy: Qt.NoFocus

                background: Rectangle {
                    radius: 14
                    color: appSettings.surfaceAltColor
                    opacity: parent.hovered ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }

                contentItem: YIcon {
                    anchors.centerIn: parent
                    size: 14
                    source: "qrc:/tsuki_app/icons/actions/close.svg"
                    color: appSettings.textSecColor
                }
                onClicked: {
                    searchField.clear()
                    searchField.forceActiveFocus()
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Top-Right M3 Pill Multi-Select Filter & Collections Dropdown (Matches Sort Dropdown)
        Button {
            id: filterBtn
            objectName: "libraryFilterBtn"
            padding: 0
            activeFocusOnTab: false
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 40
            implicitWidth: Math.max(114, filterInner.implicitWidth + 32)

            property int focusedPopupIndex: 0
            readonly property var userCategories: (uiController && uiController.gameManager && uiController.gameManager.categories)
                ? uiController.gameManager.categories : []
            readonly property int popupItemCount: 1 + topBar.filterOptions.length + userCategories.length

            function handlePopupDown() {
                if (popupItemCount > 0) focusedPopupIndex = (focusedPopupIndex + 1) % popupItemCount
            }
            function handlePopupUp() {
                if (popupItemCount > 0) focusedPopupIndex = (focusedPopupIndex - 1 + popupItemCount) % popupItemCount
            }
            function handlePopupSelect() {
                if (focusedPopupIndex === 0) {
                    if (uiController && uiController.searchModel) uiController.searchModel.clearFilters()
                    filterPopup.close()
                    return
                }
                const fIdx = focusedPopupIndex - 1
                if (fIdx >= 0 && fIdx < topBar.filterOptions.length) {
                    topBar.toggleFilterKey(topBar.filterOptions[fIdx].key)
                    return
                }
                const cIdx = fIdx - topBar.filterOptions.length
                if (cIdx >= 0 && cIdx < userCategories.length) {
                    if (uiController && uiController.searchModel) {
                        uiController.searchModel.toggleCategory(userCategories[cIdx])
                    }
                }
            }

            readonly property bool isBtnHovered: filterHover.hovered
            readonly property bool isKeyboardFocused: filterBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
            readonly property bool isFilterActive: Boolean(uiController && uiController.searchModel && uiController.searchModel.hasActiveFilters)
            readonly property bool isHighlighted: filterPopup.visible || isBtnHovered || isKeyboardFocused || isFilterActive

            Keys.onLeftPressed: (event) => {
                if (!filterPopup.visible) {
                    event.accepted = true
                    searchTile.forceActiveFocus()
                }
            }
            Keys.onRightPressed: (event) => {
                if (!filterPopup.visible) {
                    event.accepted = true
                    sortBtn.forceActiveFocus()
                }
            }
            Keys.onUpPressed: (event) => {
                if (filterPopup.visible) {
                    event.accepted = true
                    filterBtn.handlePopupUp()
                }
            }
            Keys.onDownPressed: (event) => {
                event.accepted = true
                if (filterPopup.visible) filterBtn.handlePopupDown()
                else topBar.focusGridRequested()
            }
            Keys.onReturnPressed: (event) => {
                event.accepted = true
                if (filterPopup.visible) filterBtn.handlePopupSelect()
                else { filterBtn.focusedPopupIndex = 0; filterPopup.open() }
            }
            Keys.onEnterPressed: (event) => {
                event.accepted = true
                if (filterPopup.visible) filterBtn.handlePopupSelect()
                else { filterBtn.focusedPopupIndex = 0; filterPopup.open() }
            }
            Keys.onSpacePressed: (event) => {
                event.accepted = true
                if (filterPopup.visible) filterBtn.handlePopupSelect()
                else { filterBtn.focusedPopupIndex = 0; filterPopup.open() }
            }
            Keys.onEscapePressed: (event) => {
                event.accepted = true
                if (filterPopup.visible) filterPopup.close()
                else topBar.focusGridRequested()
            }
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Backspace) {
                    event.accepted = true
                    if (filterPopup.visible) filterPopup.close()
                    else topBar.focusGridRequested()
                }
            }

            background: Rectangle {
                radius: height / 2
                color: filterBtn.isFilterActive
                    ? appSettings.secondaryContainer
                    : ((filterBtn.isBtnHovered || filterPopup.visible)
                        ? appSettings.surfaceContainerHighest
                        : appSettings.surfaceContainerHigh)
                border.color: appSettings.accentColor
                border.width: (filterPopup.visible || filterBtn.isKeyboardFocused) ? 2 : 0
                scale: filterBtn.pressed ? 0.96 : (filterBtn.isKeyboardFocused ? 1.02 : 1.0)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 100 } }
            }

            contentItem: Item {
                implicitWidth: filterInner.implicitWidth
                implicitHeight: 40
                Row {
                    id: filterInner
                    anchors.centerIn: parent
                    spacing: 8
                    YIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 16
                        source: "qrc:/tsuki_app/icons/actions/tune.svg"
                        color: filterBtn.isFilterActive
                            ? appSettings.onSecondaryContainer
                            : (filterBtn.isHighlighted ? appSettings.accentColor : appSettings.textSecColor)
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: topBar.currentFilterName()
                        color: filterBtn.isFilterActive ? appSettings.onSecondaryContainer : appSettings.textColor
                        font.family: "Rubik"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        renderType: Text.QtRendering
                    }
                    YIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 18
                        symbol: "keyboard_arrow_down"
                        color: filterBtn.isFilterActive
                            ? appSettings.onSecondaryContainer
                            : (filterBtn.isHighlighted ? appSettings.accentColor : appSettings.textSecColor)
                        rotation: filterPopup.visible ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
            }

            HoverHandler { id: filterHover; cursorShape: Qt.PointingHandCursor }
            onClicked: {
                if (filterPopup.visible) {
                    filterPopup.close()
                } else {
                    filterBtn.focusedPopupIndex = 0
                    filterPopup.open()
                }
            }

            Popup {
                id: filterPopup
                y: filterBtn.height + 4
                x: filterBtn.width - width
                width: Math.max(filterBtn.width, 252)
                padding: 6
                dim: false
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

                onClosed: {
                    if (uiController && uiController.isKeyboardNavActive) {
                        filterBtn.forceActiveFocus()
                    } else {
                        filterBtn.focus = false
                    }
                }

                property real unfoldProgress: 0.0

                enter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "unfoldProgress"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                    }
                }
                exit: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 140; easing.type: Easing.InCubic }
                        NumberAnimation { property: "unfoldProgress"; from: 1.0; to: 0.0; duration: 160; easing.type: Easing.InCubic }
                    }
                }

                readonly property real fullContentHeight: Math.min(400, filterPopupCol.implicitHeight + 12)
                implicitHeight: fullContentHeight * unfoldProgress
                height: implicitHeight

                background: Rectangle {
                    color: appSettings.surfaceContainer
                    border.width: 0
                    radius: 16
                    layer.enabled: filterPopup.visible
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.45 : 0.18)
                        shadowBlur: 0.6
                        shadowVerticalOffset: 4
                    }
                }

                contentItem: Item {
                    clip: true

                    ColumnLayout {
                        id: filterPopupCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 6

                        Flickable {
                            id: filterFlick
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(340, filterCol.implicitHeight)
                            contentHeight: filterCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: filterCol
                                width: filterFlick.width
                                spacing: 2

                                // Row 0: All Games (Clears multi-select filters)
                                Item {
                                    id: allGamesRow
                                    width: filterCol.width
                                    height: 36
                                    readonly property bool isSelected: topBar.isAllGamesSelected()
                                    readonly property bool isHovered: allGamesMA.containsMouse || (Boolean(uiController && uiController.isKeyboardNavActive) && filterBtn.focusedPopupIndex === 0)

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: appSettings.surfaceContainerHighest
                                        opacity: (!allGamesRow.isSelected && allGamesRow.isHovered) ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: appSettings.secondaryContainer
                                        opacity: allGamesRow.isSelected ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: Qt.rgba(0, 0, 0, 0)
                                        border.color: appSettings.accentColor
                                        border.width: 1.5
                                        opacity: (filterBtn.focusedPopupIndex === 0 && !allGamesRow.isSelected && Boolean(uiController && uiController.isKeyboardNavActive)) ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: "All Games"
                                            color: allGamesRow.isSelected ? appSettings.onSecondaryContainer : appSettings.textColor
                                            font.family: "Rubik"
                                            font.pixelSize: 13
                                            font.weight: allGamesRow.isSelected ? Font.DemiBold : Font.Normal
                                            renderType: Text.QtRendering
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                        YIcon {
                                            size: 16
                                            symbol: "check"
                                            color: appSettings.onSecondaryContainer
                                            visible: allGamesRow.isSelected
                                        }
                                    }

                                    MouseArea {
                                        id: allGamesMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (uiController && uiController.searchModel) {
                                                uiController.searchModel.clearFilters()
                                            }
                                            filterPopup.close()
                                        }
                                    }
                                }

                                // Multi-select Filter Rows: Linux Only, Windows Only, Epic Only, Favourite, Local
                                Repeater {
                                    model: topBar.filterOptions
                                    delegate: Item {
                                        id: filterRow
                                        required property int index
                                        required property var modelData
                                        width: filterCol.width
                                        height: 36
                                        readonly property int popupRowIdx: index + 1
                                        readonly property bool isSelected: topBar.isFilterKeySelected(modelData.key)
                                        readonly property bool isHovered: fItemMA.containsMouse || (Boolean(uiController && uiController.isKeyboardNavActive) && filterBtn.focusedPopupIndex === popupRowIdx)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: appSettings.surfaceContainerHighest
                                            opacity: (!filterRow.isSelected && filterRow.isHovered) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: appSettings.secondaryContainer
                                            opacity: filterRow.isSelected ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: Qt.rgba(0, 0, 0, 0)
                                            border.color: appSettings.accentColor
                                            border.width: 1.5
                                            opacity: (filterBtn.focusedPopupIndex === filterRow.popupRowIdx && !filterRow.isSelected && Boolean(uiController && uiController.isKeyboardNavActive)) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 14
                                            spacing: 8
                                            Text {
                                                Layout.fillWidth: true
                                                text: String(filterRow.modelData.label)
                                                color: filterRow.isSelected ? appSettings.onSecondaryContainer : appSettings.textColor
                                                font.family: "Rubik"
                                                font.pixelSize: 13
                                                font.weight: filterRow.isSelected ? Font.DemiBold : Font.Normal
                                                renderType: Text.QtRendering
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            YIcon {
                                                size: 16
                                                symbol: "check"
                                                color: appSettings.onSecondaryContainer
                                                visible: filterRow.isSelected
                                            }
                                        }

                                        MouseArea {
                                            id: fItemMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: topBar.toggleFilterKey(filterRow.modelData.key)
                                        }
                                    }
                                }

                                // Collections Section (multi-selectable)
                                Item {
                                    visible: filterBtn.userCategories.length > 0
                                    width: filterCol.width
                                    height: 9
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        height: 1
                                        color: appSettings.borderColor
                                    }
                                }

                                Repeater {
                                    model: filterBtn.userCategories
                                    delegate: Item {
                                        id: catRow
                                        required property int index
                                        required property string modelData
                                        width: filterCol.width
                                        height: 36
                                        readonly property int popupRowIdx: 1 + topBar.filterOptions.length + index
                                        readonly property bool isSelected: topBar.isCategorySelected(modelData)
                                        readonly property bool isHovered: cItemMA.containsMouse || (Boolean(uiController && uiController.isKeyboardNavActive) && filterBtn.focusedPopupIndex === popupRowIdx)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: appSettings.surfaceContainerHighest
                                            opacity: (!catRow.isSelected && catRow.isHovered) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: appSettings.secondaryContainer
                                            opacity: catRow.isSelected ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: Qt.rgba(0, 0, 0, 0)
                                            border.color: appSettings.accentColor
                                            border.width: 1.5
                                            opacity: (filterBtn.focusedPopupIndex === catRow.popupRowIdx && !catRow.isSelected && Boolean(uiController && uiController.isKeyboardNavActive)) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 8
                                            spacing: 6

                                            Text {
                                                Layout.fillWidth: true
                                                text: catRow.modelData
                                                color: catRow.isSelected ? appSettings.onSecondaryContainer : appSettings.textColor
                                                font.family: "Rubik"
                                                font.pixelSize: 13
                                                font.weight: catRow.isSelected ? Font.DemiBold : Font.Normal
                                                renderType: Text.QtRendering
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }

                                            YIcon {
                                                size: 16
                                                symbol: "check"
                                                color: appSettings.onSecondaryContainer
                                                visible: catRow.isSelected
                                            }

                                            ToolButton {
                                                implicitWidth: 24
                                                implicitHeight: 24
                                                focusPolicy: Qt.NoFocus
                                                background: Rectangle {
                                                    radius: 12
                                                    color: parent.hovered ? Qt.rgba(239/255, 68/255, 68/255, 0.2) : "transparent"
                                                }
                                                contentItem: YIcon {
                                                    anchors.centerIn: parent
                                                    size: 13
                                                    source: "qrc:/tsuki_app/icons/actions/close.svg"
                                                    color: catRow.isSelected ? appSettings.onSecondaryContainer : appSettings.textSecColor
                                                }
                                                onClicked: {
                                                    if (uiController && uiController.gameManager) {
                                                        if (uiController.searchModel && topBar.isCategorySelected(catRow.modelData)) {
                                                            uiController.searchModel.toggleCategory(catRow.modelData)
                                                        }
                                                        uiController.gameManager.deleteCollection(catRow.modelData)
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: cItemMA
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.right: parent.right
                                            anchors.rightMargin: 32
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (uiController && uiController.searchModel) {
                                                    uiController.searchModel.toggleCategory(catRow.modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Compact "+ New Collection" Row
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            Layout.rightMargin: 4
                            spacing: 6

                            TextField {
                                id: newCollectionInput
                                Layout.fillWidth: true
                                implicitHeight: 32
                                placeholderText: "New collection…"
                                color: appSettings.textColor
                                placeholderTextColor: appSettings.textTerColor
                                font.family: "Rubik"
                                font.pixelSize: 12
                                leftPadding: 12
                                rightPadding: 10
                                background: Rectangle {
                                    radius: 16
                                    color: appSettings.surfaceContainerHigh
                                    border.color: newCollectionInput.activeFocus ? appSettings.accentColor : "transparent"
                                    border.width: newCollectionInput.activeFocus ? 1.5 : 0
                                }
                                onAccepted: {
                                    const nm = text.trim()
                                    if (nm.length > 0 && uiController && uiController.gameManager) {
                                        uiController.gameManager.createCollection(nm)
                                        text = ""
                                    }
                                }
                            }

                            M3Button {
                                text: "Add"
                                buttonType: "tonal"
                                implicitHeight: 32
                                enabled: newCollectionInput.text.trim().length > 0
                                onClicked: {
                                    const nm = newCollectionInput.text.trim()
                                    if (nm.length > 0 && uiController && uiController.gameManager) {
                                        uiController.gameManager.createCollection(nm)
                                        newCollectionInput.text = ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Top-Right M3 Pill Sort Dropdown (Second)
        Button {
            id: sortBtn
            padding: 0
            activeFocusOnTab: false
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 40
            implicitWidth: Math.max(112, sortInner.implicitWidth + 32)

            property int focusedPopupIndex: 0
            function handlePopupDown() {
                focusedPopupIndex = (focusedPopupIndex + 1) % topBar.sortOptions.length
            }
            function handlePopupUp() {
                focusedPopupIndex = (focusedPopupIndex - 1 + topBar.sortOptions.length) % topBar.sortOptions.length
            }
            function handlePopupSelect() {
                if (focusedPopupIndex >= 0 && focusedPopupIndex < topBar.sortOptions.length) {
                    uiController.searchModel.sortMode = topBar.sortOptions[focusedPopupIndex].mode
                }
                sortPopup.close()
            }

            Keys.onReturnPressed: (event) => {
                event.accepted = true
                if (sortPopup.visible) sortBtn.handlePopupSelect()
                else {
                    sortBtn.syncActiveIndex()
                    sortPopup.open()
                }
            }
            Keys.onEnterPressed: (event) => {
                event.accepted = true
                if (sortPopup.visible) sortBtn.handlePopupSelect()
                else {
                    sortBtn.syncActiveIndex()
                    sortPopup.open()
                }
            }
            Keys.onSpacePressed: (event) => {
                event.accepted = true
                if (sortPopup.visible) sortBtn.handlePopupSelect()
                else {
                    sortBtn.syncActiveIndex()
                    sortPopup.open()
                }
            }
            Keys.onLeftPressed: (event) => {
                if (!sortPopup.visible) {
                    event.accepted = true
                    filterBtn.forceActiveFocus()
                }
            }
            Keys.onRightPressed: (event) => {
                if (!sortPopup.visible) {
                    event.accepted = true
                    addFabMenu.forceFocus()
                }
            }
            Keys.onUpPressed: (event) => {
                if (sortPopup.visible) {
                    event.accepted = true
                    sortBtn.handlePopupUp()
                }
            }
            Keys.onDownPressed: (event) => {
                event.accepted = true
                if (sortPopup.visible) {
                    sortBtn.handlePopupDown()
                } else {
                    topBar.focusGridRequested()
                }
            }
            Keys.onEscapePressed: (event) => {
                event.accepted = true
                if (sortPopup.visible) {
                    sortPopup.close()
                } else {
                    topBar.focusGridRequested()
                }
            }
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Backspace) {
                    event.accepted = true
                    if (sortPopup.visible) sortPopup.close()
                    else topBar.focusGridRequested()
                }
            }

            function syncActiveIndex() {
                for (let i = 0; i < topBar.sortOptions.length; ++i) {
                    if (topBar.sortOptions[i].mode === uiController.searchModel.sortMode) {
                        focusedPopupIndex = i
                        break
                    }
                }
            }

            readonly property bool isBtnHovered: sortHover.hovered
            readonly property bool isKeyboardFocused: sortBtn.activeFocus && (uiController ? uiController.isKeyboardNavActive : false)
            readonly property bool isHighlighted: sortPopup.visible || isBtnHovered || isKeyboardFocused

            // Material 3 Pill Dropdown Trigger (matching StyledCombo)
            background: Rectangle {
                radius: height / 2
                color: (sortBtn.isBtnHovered || sortPopup.visible)
                    ? appSettings.surfaceContainerHighest
                    : appSettings.surfaceContainerHigh
                border.color: appSettings.accentColor
                border.width: (sortPopup.visible || sortBtn.isKeyboardFocused) ? 2 : 0
                scale: sortBtn.pressed ? 0.96 : (sortBtn.isKeyboardFocused ? 1.02 : 1.0)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 100 } }
            }

            contentItem: Item {
                implicitWidth: sortInner.implicitWidth
                implicitHeight: 40

                Row {
                    id: sortInner
                    anchors.centerIn: parent
                    spacing: 8

                    YIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 17
                        symbol: "sort"
                        color: sortBtn.isHighlighted ? appSettings.accentColor : appSettings.textSecColor
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: topBar.currentSortName()
                        color: appSettings.textColor
                        font.family: "Rubik"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        renderType: Text.QtRendering
                    }

                    YIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 18
                        symbol: "keyboard_arrow_down"
                        color: sortBtn.isHighlighted ? appSettings.accentColor : appSettings.textSecColor
                        rotation: sortPopup.visible ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
            }

            onClicked: {
                if (sortPopup.visible) {
                    sortPopup.close()
                } else {
                    sortBtn.syncActiveIndex()
                    sortPopup.open()
                }
            }

            HoverHandler {
                id: sortHover
                cursorShape: Qt.PointingHandCursor
            }

            Popup {
                id: sortPopup
                y: sortBtn.height + 4
                x: sortBtn.width - width
                width: Math.max(sortBtn.width, 240)
                padding: 6
                dim: false
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

                onClosed: {
                    if (uiController && uiController.isKeyboardNavActive) {
                        sortBtn.forceActiveFocus()
                    } else {
                        sortBtn.focus = false
                    }
                }

                property real unfoldProgress: 0.0

                enter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "unfoldProgress"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                    }
                }
                exit: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 140; easing.type: Easing.InCubic }
                        NumberAnimation { property: "unfoldProgress"; from: 1.0; to: 0.0; duration: 160; easing.type: Easing.InCubic }
                    }
                }

                readonly property real fullContentHeight: Math.min(280, topBar.sortOptions.length * 38 + 12)
                implicitHeight: fullContentHeight * unfoldProgress
                height: implicitHeight

                background: Rectangle {
                    color: appSettings.surfaceContainer
                    border.width: 0
                    radius: 16
                    layer.enabled: sortPopup.visible
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.45 : 0.18)
                        shadowBlur: 0.6
                        shadowVerticalOffset: 4
                    }
                }

                contentItem: Item {
                    clip: true

                    Flickable {
                        id: sortFlick
                        anchors.fill: parent
                        contentHeight: sortCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: sortCol
                            width: sortFlick.width
                            spacing: 2

                            Repeater {
                                model: topBar.sortOptions
                                delegate: Item {
                                    id: sortRow
                                    required property int index
                                    required property var modelData
                                    width: sortCol.width
                                    height: 36
                                    readonly property bool isSelected: uiController.searchModel.sortMode === modelData.mode
                                    readonly property bool isHovered: sortItemMA.containsMouse || (Boolean(uiController && uiController.isKeyboardNavActive) && sortBtn.focusedPopupIndex === index)

                                    // Hover highlight (opacity-only prevents #00000000 -> color dark flash)
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: appSettings.surfaceContainerHighest
                                        opacity: (!sortRow.isSelected && sortRow.isHovered) ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                    }

                                    // Selected container highlight
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: appSettings.secondaryContainer
                                        opacity: sortRow.isSelected ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                    }

                                    // Keyboard focus ring
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: Qt.rgba(0, 0, 0, 0)
                                        border.color: appSettings.accentColor
                                        border.width: 1.5
                                        opacity: (sortBtn.focusedPopupIndex === index && !sortRow.isSelected && Boolean(uiController && uiController.isKeyboardNavActive)) ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: String(sortRow.modelData.label)
                                            color: sortRow.isSelected
                                                ? appSettings.onSecondaryContainer
                                                : appSettings.textColor
                                            font.family: "Rubik"
                                            font.pixelSize: 13
                                            font.weight: sortRow.isSelected ? Font.DemiBold : Font.Normal
                                            renderType: Text.QtRendering
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }

                                        YIcon {
                                            size: 16
                                            symbol: "check"
                                            color: appSettings.onSecondaryContainer
                                            visible: sortRow.isSelected
                                        }
                                    }

                                    MouseArea {
                                        id: sortItemMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            uiController.searchModel.sortMode = modelData.mode
                                            sortPopup.close()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // + Add Game Expanding Pill FAB Menu (Top Right)
        M3FabMenu {
            id: addFabMenu
            objectName: "topBarAddFabMenu"
            Layout.alignment: Qt.AlignVCenter
            fabSize: 40
            buttonLabel: "Add Game"
            expandUpward: false
            onItemSelected: (platform) => topBar.addGameRequested(platform)
            onFocusLeftRequested: sortBtn.forceActiveFocus()
            onFocusDownRequested: topBar.focusGridRequested()
        }
    }
}
