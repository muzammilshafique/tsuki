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

        // ── Search Input Tile (Navigable Box with M3 focus border) ───────────
        Rectangle {
            id: searchTile
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 380
            Layout.preferredHeight: 40
            Layout.minimumWidth: 240
            Layout.maximumWidth: 540
            radius: 20
            color: searchField.activeFocus
                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                : (searchTileHover.hovered
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06))
                    : appSettings.inputColor)

            border.color: searchField.activeFocus ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
            border.width: searchField.activeFocus ? 2 : 1
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            HoverHandler { id: searchTileHover; cursorShape: Qt.IBeamCursor }

            // Left search icon
            YIcon {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 14
                size: 18
                source: "qrc:/tsuki_app/icons/actions/search.svg"
                color: searchField.activeFocus ? appSettings.accentColor : appSettings.textSecColor
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            TextField {
                id: searchField
                anchors.fill: parent
                leftPadding: 42
                rightPadding: searchField.text.length > 0 ? 36 : 16
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
                    searchField.clear()
                    searchField.focus = false
                    topBar.focusGridRequested()
                }
                Keys.onDownPressed: (event) => {
                    event.accepted = true
                    searchField.focus = false
                    topBar.focusGridRequested()
                }
                onAccepted: {
                    searchField.focus = false
                    topBar.focusGridRequested()
                }
                onTextChanged: {
                    topBar.searchQuery = text
                    topBar.searchRequested(text)
                }
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
            focus: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 40
            implicitWidth: sortInner.implicitWidth + 28

            background: Rectangle {
                radius: 10
                color: (sortBtn.hovered || sortPopup.visible || sortBtn.activeFocus)
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                    : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
                border.color: (sortBtn.hovered || sortPopup.visible || sortBtn.activeFocus)
                    ? appSettings.accentColor
                    : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                border.width: (sortPopup.visible || sortBtn.activeFocus) ? 1.5 : 1
                scale: sortBtn.pressed ? 0.96 : (sortBtn.activeFocus ? 1.02 : 1.0)
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
                        color: (sortBtn.hovered || sortPopup.visible) ? appSettings.accentColor : appSettings.textSecColor
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
                        color: (sortPopup.visible || sortBtn.hovered) ? appSettings.accentColor : appSettings.textSecColor
                        rotation: sortPopup.visible ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
                y: sortBtn.height + 6
                x: sortBtn.width - width
                width: 220
                padding: 6
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

                background: Rectangle {
                    color: appSettings.surfaceColor
                    radius: 12
                    border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
                    border.width: 1
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(0, 0, 0, 0.45)
                        shadowBlur: 0.6
                        shadowVerticalOffset: 4
                    }
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
                                color: sortItemMA.containsMouse 
                                    ? appSettings.surfaceAltColor 
                                    : (uiController.searchModel.sortMode === modelData.mode ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.12) : "transparent")
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Label {
                                    Layout.fillWidth: true
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData.label
                                    color: (uiController.searchModel.sortMode === modelData.mode || sortItemMA.containsMouse) ? appSettings.accentColor : appSettings.textColor
                                    font.pixelSize: 13
                                    font.weight: uiController.searchModel.sortMode === modelData.mode ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }

                                YIcon {
                                    size: 14
                                    source: "qrc:/tsuki_app/icons/actions/check.svg"
                                    color: appSettings.accentColor
                                    visible: uiController.searchModel.sortMode === modelData.mode
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

        // + Add Game Dynamic Spring Button (Second, far right)
        Button {
            id: addGameBtn
            padding: 0
            focus: true
            Layout.alignment: Qt.AlignVCenter

            readonly property bool isBtnActive: addGameBtn.hovered || addGameBtn.activeFocus
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
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
    }
}
