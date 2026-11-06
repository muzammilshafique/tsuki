import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Rectangle {
    id: topBar
    Layout.fillWidth: true
    Layout.preferredHeight: 88
    color: "transparent"

    property string searchQuery: ""
    readonly property bool isSearchFocused: searchField.activeFocus
    signal searchRequested(string query)
    signal addGameRequested()
    signal focusGridRequested()
    signal focusSidebarRequested()

    function forceSearchFocus() { searchTile.forceActiveFocus() }
    function activateSearch() { searchTile.startEditing() }

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

        // Search Input Tile (Navigable Box with focus border)
        Rectangle {
            id: searchTile
            Layout.preferredWidth: 340
            Layout.preferredHeight: 44
            Layout.minimumWidth: 220
            Layout.maximumWidth: 480
            radius: 22
            color: appSettings.inputColor

            property bool isEditing: false
            readonly property bool isTileFocused: searchTile.activeFocus && !isEditing && uiController.isKeyboardNavActive

            border.color: (isTileFocused || (isEditing && searchField.activeFocus)) ? appSettings.accentColor : "transparent"
            border.width: (isTileFocused || (isEditing && searchField.activeFocus)) ? 2.5 : 1
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }
            Behavior on border.width { NumberAnimation { duration: 150 } }

            focus: true

            function startEditing() {
                searchTile.isEditing = true
                searchField.forceActiveFocus()
            }

            function stopEditing() {
                searchTile.isEditing = false
                searchField.focus = false
                searchTile.forceActiveFocus()
            }

            Keys.onEscapePressed: (event) => { event.accepted = true; topBar.focusGridRequested() }
            Keys.onDownPressed: (event) => { event.accepted = true; topBar.focusGridRequested() }
            Keys.onLeftPressed: (event) => { event.accepted = true; topBar.focusSidebarRequested() }
            Keys.onRightPressed: (event) => { event.accepted = true; addGameBtn.forceActiveFocus() }
            Keys.onReturnPressed: (event) => { event.accepted = true; searchTile.startEditing() }
            Keys.onEnterPressed: (event) => { event.accepted = true; searchTile.startEditing() }
            Keys.onSpacePressed: (event) => { event.accepted = true; searchTile.startEditing() }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                visible: !searchTile.isEditing
                onClicked: searchTile.startEditing()
            }

            YIcon {
                anchors.verticalCenter: parent.verticalCenter
                x: 14
                size: 20
                source: "qrc:/tsuki_app/icons/actions/search.svg"
                color: (searchTile.isTileFocused || searchTile.isEditing) ? appSettings.accentColor : appSettings.textSecColor
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            TextField {
                id: searchField
                anchors.fill: parent
                leftPadding: 44
                rightPadding: searchField.text.length > 0 ? 36 : 16
                color: appSettings.textColor
                font.pixelSize: 14
                background: null

                visible: searchTile.isEditing || searchField.text.length > 0
                placeholderText: {
                    if (uiController.searchModel.filterType === 3) return "Search favourite games…"
                    if (uiController.searchModel.filterType === 4) return "Search recently played games…"
                    return "Search games in library…"
                }
                placeholderTextColor: appSettings.textTerColor

                Keys.onEscapePressed: (event) => {
                    event.accepted = true
                    searchTile.stopEditing()
                }
                Keys.onDownPressed: (event) => {
                    event.accepted = true
                    searchTile.isEditing = false
                    searchField.focus = false
                    topBar.focusGridRequested()
                }
                onAccepted: {
                    searchTile.isEditing = false
                    searchField.focus = false
                    topBar.focusGridRequested()
                }
                onTextChanged: {
                    topBar.searchQuery = text
                    topBar.searchRequested(text)
                }
            }

            ToolButton {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 6
                implicitWidth: 32
                implicitHeight: 32
                visible: searchField.text.length > 0

                background: Rectangle {
                    radius: 16
                    color: parent.hovered ? appSettings.surfaceAltColor : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                contentItem: YIcon {
                    anchors.centerIn: parent
                    size: 18
                    source: "qrc:/tsuki_app/icons/actions/close.svg"
                    color: appSettings.textSecColor
                }
                onClicked: {
                    searchField.clear()
                    if (!searchTile.isEditing) searchTile.forceActiveFocus()
                }
            }

            GamepadPrompt {
                anchors.left: parent.left
                anchors.leftMargin: 44
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: searchField.text.length === 0 && !searchTile.isEditing

                prefixText: (uiController.gamepad && uiController.gamepad.isConnected && uiController.isKeyboardNavActive) ? "Press" : ""
                iconSource: (uiController.gamepad && uiController.gamepad.isConnected && uiController.isKeyboardNavActive) ? uiController.gamepad.searchIconSource : ""
                keyName: ""
                suffixText: {
                    if (uiController.gamepad && uiController.gamepad.isConnected && uiController.isKeyboardNavActive) return "to Search"
                    if (uiController.searchModel.filterType === 3) return "Search favourite games…"
                    if (uiController.searchModel.filterType === 4) return "Search recently played games…"
                    return "Search games in library…"
                }
                textColor: appSettings.textSecColor
                iconColor: appSettings.textSecColor
                pixelSize: 14
                iconSize: 17
            }
        }

        // Category Quick Filter Pills
        RowLayout {
            spacing: 6
            Repeater {
                model: ["All", "Action", "RPG", "Adventure", "Indie"]
                delegate: Button {
                    required property string modelData
                    readonly property bool isActiveCat: (modelData === "All" && uiController.searchModel.categoryFilter === "") ||
                                                        (uiController.searchModel.categoryFilter === modelData)
                    text: modelData
                    implicitHeight: 34
                    onClicked: {
                        uiController.searchModel.categoryFilter = (modelData === "All") ? "" : modelData
                    }
                    background: Rectangle {
                        radius: 17
                        color: parent.isActiveCat ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.18) : appSettings.inputColor
                        border.color: parent.isActiveCat ? appSettings.accentColor : "transparent"
                        border.width: 1
                    }
                    contentItem: Label {
                        text: parent.text
                        color: parent.isActiveCat ? appSettings.accentColor : appSettings.textSecColor
                        font.pixelSize: 13
                        font.weight: parent.isActiveCat ? Font.DemiBold : Font.Normal
                        leftPadding: 12; rightPadding: 12
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // + Add Game Pill Button
        Button {
            id: addGameBtn
            text: "Add Game"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            padding: 0
            focus: true
            implicitWidth: 14 + 20 + 8 + addGameLabel.implicitWidth + 18
            implicitHeight: 44

            background: Rectangle {
                radius: 22
                color: appSettings.accentColor
            }

            contentItem: Row {
                anchors.centerIn: parent
                spacing: 8
                YIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 18
                    source: "qrc:/tsuki_app/icons/actions/add.svg"
                    color: appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff"
                }
                Label {
                    id: addGameLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: addGameBtn.text
                    color: appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff"
                    font: addGameBtn.font
                }
            }

            onClicked: topBar.addGameRequested()
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }

        // Top-Right Downloading Button (Dynamic Spring Pill Button)
        Button {
            id: downloadingBtn
            font.pixelSize: 14
            font.weight: Font.DemiBold
            padding: 0
            focus: true

            property int activeCount: downloadManager ? downloadManager.activeDownloadCount : 0
            property int focusedDlIndex: 0
            text: activeCount > 0 ? ("Downloading (" + activeCount + ")") : "Downloads"

            readonly property bool isBtnHovered: !uiController.isKeyboardNavActive && downloadingBtn.hovered
            readonly property bool isKeyboardFocused: uiController.isKeyboardNavActive && downloadingBtn.activeFocus
            property real expandedWidth: 14 + 20 + 8 + dlLabel.implicitWidth + 16
            implicitWidth: (isBtnHovered || isKeyboardFocused || dlPopup.visible || activeCount > 0) ? expandedWidth : 44
            implicitHeight: 44

            Behavior on implicitWidth {
                SpringAnimation { spring: 4; damping: 0.25; epsilon: 0.25 }
            }

            background: Rectangle {
                property color accent: appSettings.accentColor
                radius: 22
                color: (downloadingBtn.isBtnHovered || downloadingBtn.isKeyboardFocused || dlPopup.visible) ? accent : "transparent"
                border.color: (downloadingBtn.isBtnHovered || downloadingBtn.isKeyboardFocused || dlPopup.visible) ? "transparent" : accent
                border.width: (downloadingBtn.isBtnHovered || downloadingBtn.isKeyboardFocused || dlPopup.visible) ? 0 : 1.5
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }

            contentItem: Item {
                clip: true
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    YIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 20
                        source: "qrc:/tsuki_app/icons/actions/download.svg"
                        color: (downloadingBtn.isBtnHovered || downloadingBtn.isKeyboardFocused || dlPopup.visible) ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : appSettings.accentColor
                    }

                    Label {
                        id: dlLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: downloadingBtn.text
                        color: (downloadingBtn.isBtnHovered || downloadingBtn.isKeyboardFocused || dlPopup.visible) ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : appSettings.accentColor
                        font: downloadingBtn.font
                        opacity: (downloadingBtn.isBtnHovered || downloadingBtn.isKeyboardFocused || dlPopup.visible || downloadingBtn.activeCount > 0) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }
                }
            }

            onClicked: {
                if (dlPopup.visible) dlPopup.close()
                else {
                    downloadingBtn.focusedDlIndex = 0
                    dlPopup.open()
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }

            DownloadsDropdown {
                id: dlPopup
                focusedIndex: downloadingBtn.focusedDlIndex
                onFocusedIndexChanged: downloadingBtn.focusedDlIndex = focusedIndex
            }
        }

        // Top-Right Sort Button (Dynamic Spring Pill Button)
        Button {
            id: sortBtn
            text: "Sort: " + topBar.currentSortName()
            font.pixelSize: 14
            font.weight: Font.DemiBold
            padding: 0
            focus: true

            property int focusedSortIndex: uiController.searchModel.sortMode

            readonly property bool isBtnHovered: !uiController.isKeyboardNavActive && sortBtn.hovered
            readonly property bool isKeyboardFocused: uiController.isKeyboardNavActive && sortBtn.activeFocus
            property real expandedWidth: 14 + 20 + 8 + sortLabel.implicitWidth + 16
            implicitWidth: (isBtnHovered || isKeyboardFocused || sortPopup.visible) ? expandedWidth : 44
            implicitHeight: 44

            Behavior on implicitWidth {
                SpringAnimation { spring: 4; damping: 0.25; epsilon: 0.25 }
            }

            background: Rectangle {
                property color accent: appSettings.accentColor
                radius: 22
                color: (sortBtn.isBtnHovered || sortBtn.isKeyboardFocused || sortPopup.visible) ? accent : "transparent"
                border.color: (sortBtn.isBtnHovered || sortBtn.isKeyboardFocused || sortPopup.visible) ? "transparent" : accent
                border.width: (sortBtn.isBtnHovered || sortBtn.isKeyboardFocused || sortPopup.visible) ? 0 : 1.5
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }

            contentItem: Item {
                clip: true
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    YIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 20
                        source: "qrc:/tsuki_app/icons/actions/sort.svg"
                        color: (sortBtn.isBtnHovered || sortBtn.isKeyboardFocused || sortPopup.visible) ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : appSettings.accentColor
                    }

                    Label {
                        id: sortLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: sortBtn.text
                        color: (sortBtn.isBtnHovered || sortBtn.isKeyboardFocused || sortPopup.visible) ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : appSettings.accentColor
                        font: sortBtn.font
                        opacity: (sortBtn.isBtnHovered || sortBtn.isKeyboardFocused || sortPopup.visible) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }
                }
            }

            onClicked: {
                if (sortPopup.visible) sortPopup.close()
                else sortPopup.open()
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }

            Popup {
                id: sortPopup
                y: sortBtn.height + 8
                x: sortBtn.width - width
                width: 220
                padding: 6
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                background: Rectangle {
                    color: appSettings.surfaceColor
                    radius: 12
                    border.color: appSettings.borderColor
                    border.width: 1
                }

                contentItem: Column {
                    spacing: 2
                    Repeater {
                        model: topBar.sortOptions
                        delegate: Item {
                            required property int index
                            required property var modelData
                            width: sortPopup.width - 12
                            height: 38

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: sortItemMA.containsMouse ? appSettings.surfaceAltColor : (uiController.searchModel.sortMode === modelData.mode ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                            }

                            Label {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: Text.AlignVCenter
                                text: modelData.label
                                color: (uiController.searchModel.sortMode === modelData.mode || sortItemMA.containsMouse) ? appSettings.accentColor : appSettings.textColor
                                font.pixelSize: 13
                                font.weight: uiController.searchModel.sortMode === modelData.mode ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
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

