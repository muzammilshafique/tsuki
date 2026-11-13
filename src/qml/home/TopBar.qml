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
    signal searchRequested(string query)
    signal addGameRequested()
    signal focusGridRequested()
    signal focusSidebarRequested()

    function forceSearchFocus() { searchTile.forceActiveFocus() }
    function activateSearch() { searchField.forceActiveFocus() }

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
                    sortBtn.forceActiveFocus()
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
                    if (uiController.searchModel.filterType === 4) return "Search recently played games…"
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
                    color: parent.hovered ? appSettings.surfaceAltColor : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
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

        // Top-Right Sort Dropdown Squircle Button (First)
        Button {
            id: sortBtn
            padding: 0
            activeFocusOnTab: false
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 40
            implicitWidth: sortInner.implicitWidth + 28

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
                    searchTile.forceActiveFocus()
                }
            }
            Keys.onRightPressed: (event) => {
                if (!sortPopup.visible) {
                    event.accepted = true
                    addGameBtn.forceActiveFocus()
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

            background: Rectangle {
                radius: 10
                color: sortBtn.isHighlighted
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                    : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
                border.color: sortBtn.isHighlighted
                    ? appSettings.accentColor
                    : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                border.width: (sortPopup.visible || sortBtn.isKeyboardFocused) ? 1.5 : 1
                scale: sortBtn.pressed ? 0.96 : (sortBtn.isKeyboardFocused ? 1.02 : 1.0)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
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
                        size: 16
                        source: "qrc:/tsuki_app/icons/actions/sort.svg"
                        color: sortBtn.isHighlighted ? appSettings.accentColor : appSettings.textSecColor
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: topBar.currentSortName()
                        color: appSettings.textColor
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        renderType: Text.QtRendering
                    }

                    YIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 12
                        source: "qrc:/tsuki_app/icons/actions/chevron_down.svg"
                        color: sortBtn.isHighlighted ? appSettings.accentColor : appSettings.textSecColor
                        rotation: sortPopup.visible ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
                width: 220
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
                    color: appSettings.surfaceColor
                    radius: 14
                    border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
                    border.width: 1
                    layer.enabled: true
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
                                    readonly property bool isHovered: sortItemMA.containsMouse || sortBtn.focusedPopupIndex === index

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: sortRow.isSelected
                                            ? appSettings.accentColor
                                            : (sortRow.isHovered ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: String(sortRow.modelData.label)
                                            color: sortRow.isSelected
                                                ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                                                : appSettings.textColor
                                            font.pixelSize: 13
                                            font.weight: sortRow.isSelected ? Font.DemiBold : Font.Normal
                                            renderType: Text.QtRendering
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }

                                        YIcon {
                                            size: 14
                                            source: "qrc:/tsuki_app/icons/actions/check.svg"
                                            color: sortRow.isSelected
                                                ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                                                : appSettings.accentColor
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

        // + Add Game Dynamic Spring Button (Second, far right)
        Button {
            id: addGameBtn
            padding: 0
            activeFocusOnTab: false
            Layout.alignment: Qt.AlignVCenter

            readonly property bool isBtnActive: addGameBtn.hovered || (addGameBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
            property real expandedWidth: 10 + 16 + 8 + addGameLabel.implicitWidth + 14
            implicitWidth: isBtnActive ? expandedWidth : 40
            implicitHeight: 40

            Behavior on implicitWidth {
                SpringAnimation { spring: 4; damping: 0.25; epsilon: 0.25 }
            }

            background: Rectangle {
                radius: 20
                color: addGameBtn.hovered ? Qt.lighter(appSettings.accentColor, 1.08) : appSettings.accentColor
                scale: addGameBtn.pressed ? 0.96 : (addGameBtn.activeFocus ? 1.02 : 1.0)
                Behavior on scale { NumberAnimation { duration: 100 } }
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            contentItem: Item {
                clip: true
                implicitWidth: addGameBtn.implicitWidth
                implicitHeight: 40

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    spacing: 8

                    Item {
                        width: 16
                        height: parent.height
                        YIcon {
                            anchors.centerIn: parent
                            size: 16
                            source: "qrc:/tsuki_app/icons/actions/add.svg"
                            color: appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff"
                        }
                    }

                    Label {
                        id: addGameLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Add Game"
                        color: appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        renderType: Text.QtRendering
                        opacity: addGameBtn.isBtnActive ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }

            onClicked: topBar.addGameRequested()
            Keys.onLeftPressed: (event) => {
                event.accepted = true
                sortBtn.forceActiveFocus()
            }
            Keys.onDownPressed: (event) => {
                event.accepted = true
                topBar.focusGridRequested()
            }
            Keys.onEscapePressed: (event) => {
                event.accepted = true
                topBar.focusGridRequested()
            }
            Keys.onReturnPressed: (event) => {
                event.accepted = true
                topBar.addGameRequested()
            }
            Keys.onEnterPressed: (event) => {
                event.accepted = true
                topBar.addGameRequested()
            }
            Keys.onSpacePressed: (event) => {
                event.accepted = true
                topBar.addGameRequested()
            }
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Backspace) {
                    event.accepted = true
                    topBar.focusGridRequested()
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
    }
}
