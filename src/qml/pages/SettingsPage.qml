import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Page {
    id: settingsPage
    objectName: "settingsPage"
    signal backRequested()

    background: Rectangle {
        color: appSettings.bgColor
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    focus: true

    function isAnyModalOpen() {
        return tagColorsModal.visible || gamescopeSettingsDialog.visible
    }

    function isTextInputActive() {
        const fi = settingsPage.Window.activeFocusItem
        if (!fi) return false
        const s = fi.toString()
        if (s.indexOf("M3TextField") !== -1) {
            return Boolean(fi.isEditing)
        }
        return s.indexOf("TextInput") !== -1 || s.indexOf("TextField") !== -1 || s.indexOf("TextArea") !== -1 || s.indexOf("TextEdit") !== -1
    }

    Keys.onEscapePressed: (event) => {
        if (gamescopeSettingsDialog.visible) {
            event.accepted = true
            gamescopeSettingsDialog.close()
        } else if (tagColorsModal.visible) {
            event.accepted = true
            tagColorsModal.close()
        } else {
            event.accepted = true
            settingsPage.backRequested()
        }
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Backspace && !isTextInputActive()) {
            event.accepted = true
            if (gamescopeSettingsDialog.visible) gamescopeSettingsDialog.close()
            else if (tagColorsModal.visible) tagColorsModal.close()
            else settingsPage.backRequested()
        } else if (event.key === Qt.Key_Down && !settingsPage.isAnyModalOpen() && settingsPage.activeFocus) {
            event.accepted = true
            let rows = getVisibleRows()
            if (rows.length > 1) {
                rows[1].forceActiveFocus()
                scrollToSettingRow(rows[1])
            }
        }
    }

    Shortcut {
        sequences: ["/", "Ctrl+F"]
        enabled: settingsPage.visible && settingsPage.StackView.status === StackView.Active && !settingsPage.isAnyModalOpen() && !settingsPage.isTextInputActive()
        onActivated: searchField.forceActiveFocus()
    }

    Connections {
        target: uiController ? uiController.controllerManager : null
        function onSearchActionRequested() {
            if (settingsPage.StackView.status === StackView.Active && !settingsPage.isAnyModalOpen()) {
                uiController.setKeyboardNavActive(true)
                searchField.forceActiveFocus()
            }
        }
    }

    property var settingsCatalog: []
    property var searchResults: []
    property int focusedResultIndex: 0

    function buildIndex() {
        let list = []
        let sections = [secAppearance, secRunners, secPerf, secSystem]
        for (let s = 0; s < sections.length; s++) {
            let sec = sections[s]
            if (!sec || !sec.rowsContainer) continue
            let ch = sec.rowsContainer.children
            for (let i = 0; i < ch.length; i++) {
                let row = ch[i]
                if (row && row.label) {
                    list.push({
                        name: row.label,
                        description: row.description || "",
                        section: sec.sectionTitle,
                        item: row
                    })
                }
            }
        }
        settingsCatalog = list
    }

    function updateSearchResults(query) {
        let q = query.trim().toLowerCase()
        if (q.length === 0) {
            searchResults = []
            searchResultsPopup.close()
            return
        }
        if (settingsCatalog.length === 0) {
            buildIndex()
        }

        let scored = []
        for (let i = 0; i < settingsCatalog.length; i++) {
            let entry = settingsCatalog[i]
            let n = entry.name.toLowerCase()
            let d = entry.description.toLowerCase()
            let s = entry.section.toLowerCase()
            let score = -1
            if (n === q) score = 100
            else if (n.startsWith(q)) score = 85
            else if (n.indexOf(q) !== -1) score = 65
            else if (s.indexOf(q) !== -1) score = 40
            else if (d.indexOf(q) !== -1) score = 25

            if (score > 0) {
                scored.push({
                    name: entry.name,
                    description: entry.description,
                    section: entry.section,
                    item: entry.item,
                    score: score
                })
            }
        }
        scored.sort((a, b) => b.score - a.score)
        searchResults = scored
        focusedResultIndex = 0
        if (scored.length > 0) {
            if (!searchResultsPopup.visible) searchResultsPopup.open()
        } else {
            searchResultsPopup.close()
        }
    }

    function scrollToSetting(targetItem) {
        if (!targetItem || !settingsCol) return
        Qt.callLater(() => {
            scrollToSettingRow(targetItem, true)
            targetItem.forceActiveFocus()
            if (typeof targetItem.highlight === "function") {
                targetItem.highlight()
            }
        })
    }

    function getVisibleRows() {
        let rows = [searchTile]
        let sections = [secAppearance, secRunners, secPerf, secSystem]
        for (let s = 0; s < sections.length; s++) {
            let sec = sections[s]
            if (!sec || !sec.visible || !sec.rowsContainer) continue
            let ch = sec.rowsContainer.children
            for (let i = 0; i < ch.length; i++) {
                let row = ch[i]
                if (row && row.visible && row.label !== undefined) {
                    rows.push(row)
                }
            }
        }
        return rows
    }

    function isDescendant(item, ancestor) {
        let p = item
        while (p) {
            if (p === ancestor) return true
            p = p.parent
        }
        return false
    }

    function findActiveRowIndex(rows) {
        const fi = settingsPage.Window.activeFocusItem
        if (!fi) return -1
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].activeFocus || isDescendant(fi, rows[i])) {
                return i
            }
        }
        return -1
    }

    function scrollToSettingRow(targetItem, centerView) {
        if (!targetItem || targetItem === searchTile || targetItem === backBtn || !settingsCol) return
        let flick = settingsScroll.contentItem
        if (!flick || flick.contentY === undefined) return
        let p = targetItem.mapToItem(settingsCol, 0, 0)
        let maxY = Math.max(0, flick.contentHeight - settingsScroll.height)
        if (centerView) {
            let centered = Math.max(0, Math.min(maxY, p.y - 40))
            rowScrollAnim.to = centered
            rowScrollAnim.restart()
            return
        }
        let viewTop = flick.contentY
        let viewBottom = flick.contentY + settingsScroll.height - 68
        let desiredY = flick.contentY
        if (p.y - 24 < viewTop) {
            desiredY = Math.max(0, p.y - 24)
        } else if (p.y + targetItem.height + 24 > viewBottom) {
            desiredY = Math.min(maxY, p.y + targetItem.height + 24 - (settingsScroll.height - 68))
        }
        if (Math.abs(desiredY - flick.contentY) > 1) {
            rowScrollAnim.to = desiredY
            rowScrollAnim.restart()
        }
    }

    function focusNextSettingRow() {
        let rows = getVisibleRows()
        if (rows.length === 0) return
        let idx = findActiveRowIndex(rows)
        let nextIdx = (idx < 0) ? Math.min(1, rows.length - 1) : Math.min(rows.length - 1, idx + 1)
        let target = rows[nextIdx]
        target.forceActiveFocus()
        scrollToSettingRow(target, false)
    }

    function focusPrevSettingRow() {
        let rows = getVisibleRows()
        if (rows.length === 0) return
        let idx = findActiveRowIndex(rows)
        if (idx <= 0) {
            backBtn.forceActiveFocus()
            return
        }
        let prevIdx = idx - 1
        let target = rows[prevIdx]
        target.forceActiveFocus()
        if (target === searchTile) {
            let flick = settingsScroll.contentItem
            if (flick && flick.contentY !== undefined && flick.contentY > 0) {
                rowScrollAnim.to = 0
                rowScrollAnim.restart()
            }
        } else {
            scrollToSettingRow(target, false)
        }
    }

    Component.onCompleted: {
        Qt.callLater(buildIndex)
        Qt.callLater(() => {
            if (uiController && uiController.isKeyboardNavActive) {
                let rows = getVisibleRows()
                if (rows.length > 1) rows[1].forceActiveFocus()
            }
        })
    }

    // ── Top Navigation & Search Header (Matching Yoru Layout) ────────────────
    Rectangle {
        id: settingsHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 70
        z: 100
        color: appSettings.bgColor
        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: appSettings.borderColor
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 32
            anchors.rightMargin: 32

            // Top-Left: Back Button (Expanding Spring Pill matching Media Header & TopBar)
            Button {
                id: backBtn
                font.pixelSize: 13
                font.weight: Font.DemiBold
                padding: 0
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                readonly property bool isBtnActive: backBtn.hovered || (backBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                property real expandedWidth: 10 + 18 + 8 + backLabel.implicitWidth + 14
                implicitWidth: isBtnActive ? expandedWidth : 40
                implicitHeight: 40

                Behavior on implicitWidth {
                    SpringAnimation { spring: 4; damping: 0.25; epsilon: 0.25 }
                }

                background: Rectangle {
                    property color accent: appSettings.accentColor
                    radius: 20
                    color: backBtn.isBtnActive ? accent : "transparent"
                    border.color: backBtn.isBtnActive ? "transparent" : accent
                    border.width: backBtn.isBtnActive ? 0 : 1.5
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }

                contentItem: Item {
                    clip: true
                    implicitWidth: backBtn.implicitWidth
                    implicitHeight: 40

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        spacing: 8

                        Item {
                            width: 18
                            height: parent.height
                            YIcon {
                                anchors.centerIn: parent
                                size: 18
                                source: "qrc:/tsuki_app/icons/actions/back.svg"
                                color: backBtn.isBtnActive ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : appSettings.accentColor
                            }
                        }

                        Label {
                            id: backLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Back"
                            color: backBtn.isBtnActive ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : appSettings.accentColor
                            font: backBtn.font
                            renderType: Text.QtRendering
                            opacity: backBtn.isBtnActive ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }
                }

                onClicked: settingsPage.backRequested()
                activeFocusOnTab: false
                Keys.onRightPressed: (event) => { event.accepted = true; searchTile.forceActiveFocus() }
                Keys.onDownPressed: (event) => { event.accepted = true; settingsPage.focusNextSettingRow() }
                Keys.onReturnPressed: (event) => { event.accepted = true; settingsPage.backRequested() }
                Keys.onEnterPressed: (event) => { event.accepted = true; settingsPage.backRequested() }
                Keys.onSpacePressed: (event) => { event.accepted = true; settingsPage.backRequested() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            // Center: Material 3 Search Bar Pill
            Rectangle {
                id: searchTile
                focus: true
                activeFocusOnTab: false
                anchors.centerIn: parent
                width: Math.min(420, Math.max(260, parent.width - 320))
                height: 40
                radius: 20
                readonly property bool isEditing: searchField.activeFocus
                readonly property bool isTileFocused: searchTile.activeFocus && (uiController ? uiController.isKeyboardNavActive : false)
                color: (searchField.activeFocus || searchTile.isTileFocused)
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                    : (searchTileHover.hovered
                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06))
                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)))

                border.color: (searchField.activeFocus || searchTile.isTileFocused)
                    ? appSettings.accentColor
                    : (searchTileHover.hovered
                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14))
                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)))
                border.width: (searchField.activeFocus || searchTile.isTileFocused) ? 2 : 1

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Keys.onLeftPressed: (event) => {
                    if (!searchTile.isEditing) {
                        event.accepted = true
                        backBtn.forceActiveFocus()
                    }
                }
                Keys.onUpPressed: (event) => {
                    if (!searchTile.isEditing) {
                        event.accepted = true
                        backBtn.forceActiveFocus()
                    }
                }
                Keys.onDownPressed: (event) => {
                    if (!searchTile.isEditing) {
                        event.accepted = true
                        settingsPage.focusNextSettingRow()
                    }
                }
                Keys.onReturnPressed: (event) => {
                    if (!searchTile.isEditing) {
                        event.accepted = true
                        searchField.forceActiveFocus()
                    }
                }
                Keys.onEnterPressed: (event) => {
                    if (!searchTile.isEditing) {
                        event.accepted = true
                        searchField.forceActiveFocus()
                    }
                }
                Keys.onSpacePressed: (event) => {
                    if (!searchTile.isEditing) {
                        event.accepted = true
                        searchField.forceActiveFocus()
                    }
                }

                HoverHandler { id: searchTileHover; cursorShape: Qt.IBeamCursor }

                YIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    size: 16
                    source: "qrc:/tsuki_app/icons/actions/search.svg"
                    color: (searchField.activeFocus || searchTile.isTileFocused) ? appSettings.accentColor : appSettings.textSecColor
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                TextField {
                    id: searchField
                    anchors.fill: parent
                    placeholderText: "Search settings…"
                    placeholderTextColor: appSettings.textTerColor
                    color: appSettings.textColor
                    font.pixelSize: 13
                    leftPadding: 38
                    rightPadding: (clearSearchBtn.visible ? 34 : 42)
                    selectByMouse: true
                    background: null
                    renderType: Text.QtRendering
                    verticalAlignment: Text.AlignVCenter

                    onTextChanged: settingsPage.updateSearchResults(text)

                    Keys.onDownPressed: (event) => {
                        event.accepted = true
                        if (searchResultsPopup.visible && settingsPage.searchResults.length > 0) {
                            settingsPage.focusedResultIndex = (settingsPage.focusedResultIndex + 1) % settingsPage.searchResults.length
                            sResListView.positionViewAtIndex(settingsPage.focusedResultIndex, ListView.Contain)
                        } else {
                            searchTile.forceActiveFocus()
                            settingsPage.focusNextSettingRow()
                        }
                    }
                    Keys.onUpPressed: (event) => {
                        if (searchResultsPopup.visible && settingsPage.searchResults.length > 0) {
                            event.accepted = true
                            settingsPage.focusedResultIndex = (settingsPage.focusedResultIndex - 1 + settingsPage.searchResults.length) % settingsPage.searchResults.length
                            sResListView.positionViewAtIndex(settingsPage.focusedResultIndex, ListView.Contain)
                        }
                    }
                    Keys.onReturnPressed: (event) => {
                        if (searchResultsPopup.visible && settingsPage.searchResults.length > 0) {
                            event.accepted = true
                            let entry = settingsPage.searchResults[settingsPage.focusedResultIndex]
                            if (entry) {
                                searchResultsPopup.close()
                                searchField.focus = false
                                settingsPage.scrollToSetting(entry.item)
                            }
                        }
                    }
                    Keys.onEnterPressed: (event) => {
                        if (searchResultsPopup.visible && settingsPage.searchResults.length > 0) {
                            event.accepted = true
                            let entry = settingsPage.searchResults[settingsPage.focusedResultIndex]
                            if (entry) {
                                searchResultsPopup.close()
                                searchField.focus = false
                                settingsPage.scrollToSetting(entry.item)
                            }
                        }
                    }
                    Keys.onEscapePressed: (event) => {
                        event.accepted = true
                        if (searchResultsPopup.visible) {
                            searchResultsPopup.close()
                        } else {
                            searchField.clear()
                            searchTile.forceActiveFocus()
                        }
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

                ToolButton {
                    id: clearSearchBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    visible: searchField.text.length > 0
                    focusPolicy: Qt.NoFocus

                    background: Rectangle {
                        radius: 13
                        color: clearSearchBtn.hovered ? appSettings.surfaceAltColor : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    contentItem: YIcon {
                        anchors.centerIn: parent
                        size: 13
                        source: "qrc:/tsuki_app/icons/actions/close.svg"
                        color: appSettings.textSecColor
                    }

                    onClicked: {
                        searchField.clear()
                        searchField.forceActiveFocus()
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }

                // Search Results Floating Popup with M3 Styling & Unfold Animation
                Popup {
                    id: searchResultsPopup
                    y: searchTile.height + 4
                    x: 0
                    width: Math.max(searchTile.width, 360)
                    padding: 6
                    dim: false
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

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

                    readonly property real fullContentHeight: Math.min(290, settingsPage.searchResults.length * 48 + 12)
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

                        ListView {
                            id: sResListView
                            anchors.fill: parent
                            clip: true
                            model: settingsPage.searchResults
                            spacing: 3
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: sResRow
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: 46
                                radius: 10
                                readonly property bool isRowFocused: sResMA.containsMouse || settingsPage.focusedResultIndex === index
                                color: isRowFocused
                                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                                    : "transparent"
                                border.color: isRowFocused ? appSettings.accentColor : "transparent"
                                border.width: isRowFocused ? 1 : 0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 2

                                        Label {
                                            text: sResRow.modelData.name
                                            color: sResRow.isRowFocused ? appSettings.accentColor : appSettings.textColor
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Label {
                                            text: sResRow.modelData.description || sResRow.modelData.section
                                            color: appSettings.textSecColor
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                            visible: text.length > 0
                                        }
                                    }

                                    // Section chip pill
                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        height: 20
                                        radius: 6
                                        implicitWidth: secTagLbl.implicitWidth + 12
                                        color: sResRow.isRowFocused
                                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.16)
                                            : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05))

                                        Label {
                                            id: secTagLbl
                                            anchors.centerIn: parent
                                            text: sResRow.modelData.section
                                            color: sResRow.isRowFocused ? appSettings.accentColor : appSettings.textTerColor
                                            font.pixelSize: 10
                                            font.weight: Font.Medium
                                        }
                                    }
                                }

                                MouseArea {
                                    id: sResMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchResultsPopup.close()
                                        searchField.focus = false
                                        settingsPage.scrollToSetting(sResRow.modelData.item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: rowScrollAnim
        target: settingsScroll.contentItem
        property: "contentY"
        duration: 180
        easing.type: Easing.OutCubic
    }

    // ── Settings Scroll Content ──────────────────────────────────────────────
    ScrollView {
        id: settingsScroll
        anchors.top: settingsHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: availableWidth
        contentHeight: settingsCol.implicitHeight
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            id: settingsVBar
            policy: settingsScroll.contentHeight > settingsScroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width: 6
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: appSettings.accentColor
                opacity: settingsVBar.hovered || settingsVBar.pressed ? 0.85 : 0.45
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }

        ColumnLayout {
            id: settingsCol
            width: Math.min(parent.width - 64, 880)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24

            Item { Layout.preferredHeight: 12 }

            // ── 1. Appearance & Library Layout Card ──────────────────────────
            SettingsGroup {
                id: secAppearance
                Layout.fillWidth: true
                sectionTitle: "Appearance & Layout"

                readonly property var accentPresets: [
                    { name: "Blue",   color: "#5b9cf6" },
                    { name: "Purple", color: "#9c27b0" },
                    { name: "Pink",   color: "#ec4899" },
                    { name: "Red",    color: "#ef4444" },
                    { name: "Orange", color: "#f97316" },
                    { name: "Green",  color: "#10b981" },
                    { name: "Slate",  color: "#94a3b8" }
                ]

                readonly property var bgPresets: appSettings.isEffectiveDark ? [
                    { name: "Default (Auto)", color: "" },
                    { name: "OLED Black",     color: "#000000" },
                    { name: "Midnight Navy",  color: "#0b0f19" },
                    { name: "Deep Charcoal",  color: "#121215" },
                    { name: "Dark Slate",     color: "#161c24" },
                    { name: "Cyber Violet",   color: "#120e1c" }
                ] : [
                    { name: "Default (Auto)", color: "" },
                    { name: "Pure White",     color: "#ffffff" },
                    { name: "Soft Pearl",     color: "#f4f4f5" },
                    { name: "Warm Cream",     color: "#f5f0e8" },
                    { name: "Light Slate",    color: "#eef2f6" },
                    { name: "Soft Linen",     color: "#f5f5f4" }
                ]

                readonly property var sidebarPresets: appSettings.isEffectiveDark ? [
                    { name: "Default (Auto)", color: "" },
                    { name: "OLED Black",     color: "#000000" },
                    { name: "Onyx Dark",      color: "#18181b" },
                    { name: "Midnight Navy",  color: "#0f172a" },
                    { name: "Deep Slate",     color: "#1e232d" },
                    { name: "Dark Plum",      color: "#1a1020" }
                ] : [
                    { name: "Default (Auto)", color: "" },
                    { name: "Pure White",     color: "#ffffff" },
                    { name: "Light Gray",     color: "#f0f2f5" },
                    { name: "Soft Cream",     color: "#ede8df" },
                    { name: "Cool Ice",       color: "#e8eef5" },
                    { name: "Deep Contrast",  color: "#18181b" }
                ]

                // Theme Mode
                SettingRow {
                    label: "Theme Mode"
                    description: "Select light, dark, system, or AMOLED pure black mode"
                    controlItem: M3SegmentedButton {
                        model: [
                            { label: "Dark",   val: 0 },
                            { label: "Light",  val: 1 },
                            { label: "System", val: 2 },
                            { label: "AMOLED", val: 3 }
                        ]
                        selectedValue: appSettings.themeMode
                        onSelectionChanged: (val) => appSettings.themeMode = val
                    }
                }

                RowDiv {}

                // Accent Color (Matching exact AppearanceSection.qml presets)
                SettingRow {
                    label: "Accent Color"
                    description: "Primary accent for active tabs, buttons, focus rings, and highlights"
                    controlItem: M3ColorPicker {
                        presets: secAppearance.accentPresets
                        currentColor: String(appSettings.accentColor)
                        allowCustom: true
                        onColorSelected: (hex) => appSettings.setAccentColor(hex)
                    }
                }

                RowDiv {}

                // Match Sidebar & Background Toggle
                SettingRow {
                    label: "Match Sidebar & Background"
                    description: "Synchronize navigation sidebar and window canvas colors"
                    controlItem: Toggle {
                        checked: appSettings.syncSidebarColor
                        onToggled: (c) => appSettings.setSyncSidebarColor(c)
                    }
                }

                RowDiv {}

                // Background Color
                SettingRow {
                    id: bgSettingRow
                    label: "Background Color"
                    description: appSettings.syncSidebarColor ? "Color applied to both window background and navigation sidebar" : "Primary canvas and window background tone"
                    controlItem: M3ColorPicker {
                        presets: secAppearance.bgPresets
                        currentColor: appSettings.customBgColor
                        allowCustom: true
                        onColorSelected: (hex) => {
                            if (hex === "") appSettings.resetBgColor()
                            else appSettings.setCustomBgColor(hex)
                        }
                    }
                }

                // Sidebar Color (Shown only when independent)
                RowDiv {
                    visible: !appSettings.syncSidebarColor
                }

                SettingRow {
                    id: sidebarSettingRow
                    visible: !appSettings.syncSidebarColor
                    label: "Sidebar Color"
                    description: "Navigation sidebar background tone"
                    controlItem: M3ColorPicker {
                        presets: secAppearance.sidebarPresets
                        currentColor: appSettings.customSidebarColor
                        allowCustom: true
                        onColorSelected: (hex) => {
                            if (hex === "") appSettings.resetSidebarColor()
                            else appSettings.setCustomSidebarColor(hex)
                        }
                    }
                }

                RowDiv {}

                // Runner & Platform Tag Colors
                SettingRow {
                    id: tagColorsRow
                    label: "Runner & Platform Tag Colors"
                    description: "Customize badge colors for Proton, Proton-GE, CachyOS, and Linux"
                    controlItem: M3Button {
                        text: "Edit Colors"
                        buttonType: "tonal"
                        onClicked: tagColorsModal.open()
                    }
                }

                RowDiv {}

                // Poster Size Target
                SettingRow {
                    label: "Poster Card Size"
                    description: "Grid thumbnail target width in pixels"
                    controlItem: StyledSlider {
                        from: 150; to: 280; stepSize: 5
                        value: appSettings.thumbScaleTarget
                        suffix: " px"
                        slider.onMoved: appSettings.thumbScaleTarget = Math.round(slider.value)
                    }
                }

                RowDiv {}

                // Card Corner Radius
                SettingRow {
                    label: "Card Corner Radius"
                    description: "Squircle curvature applied to game poster tiles"
                    controlItem: StyledSlider {
                        from: 4; to: 28; stepSize: 2
                        value: appSettings.cardRadius
                        suffix: " px"
                        slider.onMoved: appSettings.cardRadius = Math.round(slider.value)
                    }
                }

                RowDiv {}

                // Title Visibility (Dropdown per request)
                SettingRow {
                    label: "Game Title Display"
                    description: "Position of title text on library cards"
                    controlItem: StyledCombo {
                        comboModel: ["Below Poster", "On Hover Overlay", "Hide"]
                        selectedIndex: appSettings.titleVisibility
                        onSelected: (idx) => appSettings.titleVisibility = idx
                    }
                }

                RowDiv {}

                // Tag Position (Dropdown per request)
                SettingRow {
                    label: "Runner Tag Position"
                    description: "Where to show the Proton / Wine runner badge"
                    controlItem: StyledCombo {
                        comboModel: ["Below Title", "Above Title", "Badge on Poster", "Hide"]
                        selectedIndex: appSettings.tagPosition
                        onSelected: (idx) => appSettings.tagPosition = idx
                    }
                }

                RowDiv {}

                // Show Release Year
                SettingRow {
                    label: "Show Release Year"
                    description: "Display game release year alongside titles"
                    controlItem: Toggle {
                        checked: appSettings.showYear
                        onToggled: (c) => appSettings.showYear = c
                    }
                }

                RowDiv {}

                // Show Game Name in Details
                SettingRow {
                    label: "Show Game Name in Details"
                    description: "Display game text title on detail page header"
                    controlItem: Toggle {
                        checked: appSettings.showGameName
                        onToggled: (c) => appSettings.showGameName = c
                    }
                }

                RowDiv {}

                // Left-Click Behavior
                SettingRow {
                    label: "Card Left-Click Action"
                    description: "Choose primary action triggered by clicking a game card"
                    controlItem: StyledCombo {
                        comboModel: ["Launch Game Directly", "Open Game Details Page"]
                        selectedIndex: appSettings.leftClickBehavior
                        onSelected: (idx) => appSettings.leftClickBehavior = idx
                    }
                }

                RowDiv {}

                // Minimize on Launch
                SettingRow {
                    label: "Minimize Tsuki on Launch"
                    description: "Minimize launcher window when starting a game session"
                    controlItem: Toggle {
                        checked: appSettings.minimizeOnLaunch
                        onToggled: (c) => appSettings.minimizeOnLaunch = c
                    }
                }
            }

            // ── 2. Runners & Directories Card ────────────────────────────────
            SettingsGroup {
                id: secRunners
                Layout.fillWidth: true
                sectionTitle: "Runners & Directories"

                // Default Runner
                SettingRow {
                    label: "Global Default Runner"
                    description: "Fallback Wine or Proton version assigned to newly added games"
                    controlItem: StyledCombo {
                        property var runners: uiController.runnerManager.installedRunners
                        comboModel: {
                            let list = ["Auto-Detect (System / GE-Proton)"]
                            for (let i = 0; i < runners.length; i++) {
                                list.push(runners[i].name)
                            }
                            return list
                        }
                        selectedIndex: {
                            let curId = appSettings.defaultRunnerId
                            for (let i = 0; i < runners.length; i++) {
                                if (runners[i].id === curId) return i + 1
                            }
                            return 0
                        }
                        onSelected: (idx) => {
                            if (idx === 0) appSettings.defaultRunnerId = ""
                            else if (idx - 1 < runners.length) appSettings.defaultRunnerId = runners[idx - 1].id
                        }
                    }
                }

                RowDiv {}

                // Default Prefix Location (Native system folder picker)
                SettingRow {
                    id: prefixDirRow
                    label: "Default Wine Prefix Directory"
                    description: "Base folder where newly created wine prefixes are initialized"
                    controlItem: RowLayout {
                        spacing: 8
                        M3TextField {
                            implicitWidth: 320
                            text: appSettings.defaultPrefixLocation
                            onCommit: (val) => appSettings.defaultPrefixLocation = val
                        }
                        M3Button {
                            id: prefixDirBrowseBtn
                            text: "Browse…"
                            iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                            buttonType: "tonal"
                            onClicked: {
                                let p = uiController.selectFolder("Select Default Prefix Location", appSettings.defaultPrefixLocation)
                                if (p && p.length > 0) appSettings.defaultPrefixLocation = p
                            }
                            Keys.onLeftPressed: (event) => { event.accepted = true; prefixDirRow.forceActiveFocus() }
                            Keys.onUpPressed: (event) => { event.accepted = true; settingsPage.focusPrevSettingRow() }
                            Keys.onDownPressed: (event) => { event.accepted = true; settingsPage.focusNextSettingRow() }
                            Keys.onEscapePressed: (event) => { event.accepted = true; settingsPage.backRequested() }
                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Backspace) {
                                    event.accepted = true
                                    settingsPage.backRequested()
                                }
                            }
                        }
                    }
                }

                RowDiv {}

                // Default Runner Download Location (Native system folder picker)
                SettingRow {
                    id: runnerDirRow
                    label: "Runner Download Directory"
                    description: "Folder where Proton-GE and Wine-Staging tarballs are extracted"
                    controlItem: RowLayout {
                        spacing: 8
                        M3TextField {
                            implicitWidth: 320
                            text: appSettings.defaultRunnerLocation
                            onCommit: (val) => appSettings.defaultRunnerLocation = val
                        }
                        M3Button {
                            id: runnerDirBrowseBtn
                            text: "Browse…"
                            iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                            buttonType: "tonal"
                            onClicked: {
                                let p = uiController.selectFolder("Select Runner Download Location", appSettings.defaultRunnerLocation)
                                if (p && p.length > 0) appSettings.defaultRunnerLocation = p
                            }
                            Keys.onLeftPressed: (event) => { event.accepted = true; runnerDirRow.forceActiveFocus() }
                            Keys.onUpPressed: (event) => { event.accepted = true; settingsPage.focusPrevSettingRow() }
                            Keys.onDownPressed: (event) => { event.accepted = true; settingsPage.focusNextSettingRow() }
                            Keys.onEscapePressed: (event) => { event.accepted = true; settingsPage.backRequested() }
                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Backspace) {
                                    event.accepted = true
                                    settingsPage.backRequested()
                                }
                            }
                        }
                    }
                }
            }

            // ── 3. Graphics & Gaming Performance Card ────────────────────────
            SettingsGroup {
                id: secPerf
                Layout.fillWidth: true
                sectionTitle: "Graphics & Performance Defaults"

                // DXVK
                SettingRow {
                    label: "DXVK (Direct3D 9/10/11 → Vulkan)"
                    description: "High-performance translation layer using Vulkan"
                    controlItem: Toggle {
                        checked: appSettings.dxvkDefault
                        onToggled: (c) => appSettings.dxvkDefault = c
                    }
                }

                RowDiv {}

                // VKD3D-Proton
                SettingRow {
                    label: "VKD3D-Proton (Direct3D 12 → Vulkan)"
                    description: "Direct3D 12 mapping layer for modern titles"
                    controlItem: Toggle {
                        checked: appSettings.vkd3dDefault
                        onToggled: (c) => appSettings.vkd3dDefault = c
                    }
                }

                RowDiv {}

                // Esync
                SettingRow {
                    label: "Eventfd Synchronization (Esync)"
                    description: "Replaces wineserver synchronization overhead using Linux eventfd"
                    controlItem: Toggle {
                        checked: appSettings.esyncDefault
                        onToggled: (c) => appSettings.esyncDefault = c
                    }
                }

                RowDiv {}

                // Fsync
                SettingRow {
                    label: "Futex Synchronization (Fsync)"
                    description: "Fast in-kernel futex-based Wine synchronization (requires kernel 5.16+)"
                    controlItem: Toggle {
                        checked: appSettings.fsyncDefault
                        onToggled: (c) => appSettings.fsyncDefault = c
                    }
                }

                RowDiv {}

                // Feral GameMode (Default disabled per request)
                SettingRow {
                    label: "Feral GameMode (gamemoderun)"
                    description: "Requests Linux CPU governor performance mode and I/O prioritization"
                    controlItem: Toggle {
                        checked: appSettings.gamemodeDefault
                        onToggled: (c) => appSettings.gamemodeDefault = c
                    }
                }

                RowDiv {}

                // MangoHud
                SettingRow {
                    label: "MangoHud Performance Overlay"
                    description: "Display Vulkan/OpenGL framerate, frame-times, and hardware metrics"
                    controlItem: Toggle {
                        checked: appSettings.mangohudDefault
                        onToggled: (c) => appSettings.mangohudDefault = c
                    }
                }

                RowDiv {}

                // Gamescope Micro-Compositor (Global Default - disabled by default)
                SettingRow {
                    id: gamescopeDefaultRow
                    objectName: "gamescopeDefaultRow"
                    label: "Gamescope Micro-Compositor (Global Default)"
                    description: Boolean(uiController && uiController.diagnosticsManager && !uiController.diagnosticsManager.gamescopeAvailable)
                        ? "Enable Valve's micro-compositor for resolution scaling, FSR, VRR & HDR (gamescope not detected in PATH)"
                        : "Run games inside Valve's micro-compositor for resolution scaling, FSR, VRR & HDR"
                    controlItem: Toggle {
                        id: settingsGamescopeToggle
                        checked: appSettings.gamescopeDefault
                        onToggled: (c) => appSettings.gamescopeDefault = c
                    }
                }

                RowDiv {}

                // Gamescope Default Parameters
                SettingRow {
                    id: gamescopeDefaultsConfigRow
                    objectName: "gamescopeDefaultsConfigRow"
                    label: "Gamescope Default Parameters"
                    description: "Configure global resolution, FSR upscaling, FPS limit, HDR & input defaults inherited by games"
                    controlItem: M3Button {
                        id: settingsGamescopeConfigBtn
                        text: "Configure Defaults…"
                        iconSource: "qrc:/tsuki_app/icons/actions/settings.svg"
                        buttonType: "tonal"
                        onClicked: {
                            gamescopeSettingsDialog.openWithConfig(appSettings.defaultGamescopeConfig, {
                                isGlobal: true,
                                useMangohud: appSettings.mangohudDefault,
                                targetCommand: "<game>"
                            })
                        }
                    }
                }

                RowDiv {}

                // DXVK HUD
                SettingRow {
                    label: "DXVK HUD Mode"
                    description: "In-game diagnostic overlay configuration for DXVK"
                    controlItem: StyledCombo {
                        comboModel: ["none", "fps", "frametimes", "full", "compiler"]
                        selectedIndex: {
                            let modes = ["none", "fps", "frametimes", "full", "compiler"]
                            let idx = modes.indexOf(appSettings.defaultDxvkHud)
                            return idx >= 0 ? idx : 0
                        }
                        onSelected: (idx) => {
                            let modes = ["none", "fps", "frametimes", "full", "compiler"]
                            if (idx >= 0 && idx < modes.length) appSettings.defaultDxvkHud = modes[idx]
                        }
                    }
                }
            }

            // ── 4. Controller & System Integration Card ──────────────────────
            SettingsGroup {
                id: secSystem
                Layout.fillWidth: true
                sectionTitle: "Controller & System Integration"

                // Xbox Controller Emulation
                SettingRow {
                    label: "Xbox Controller Emulation"
                    description: "Emulate virtual Xbox controller via Linux /dev/uinput for non-XInput devices"
                    controlItem: Toggle {
                        id: settingsXboxToggle
                        checked: appSettings.xboxEmulationDefault
                        Connections {
                            target: appSettings
                            function onControllerDefaultsChanged() {
                                settingsXboxToggle.checked = appSettings.xboxEmulationDefault
                            }
                        }
                        onToggled: (c) => {
                            appSettings.xboxEmulationDefault = c
                        }
                    }
                }

                RowDiv {}

                // Bottom Navigation Hints Bar
                SettingRow {
                    label: "Bottom Navigation Hints Bar"
                    description: "Show control hints shadow bar at the bottom during keyboard/gamepad navigation"
                    controlItem: Toggle {
                        id: settingsNavHudToggle
                        checked: appSettings.showNavigationHud
                        Connections {
                            target: appSettings
                            function onBehaviorChanged() {
                                settingsNavHudToggle.checked = appSettings.showNavigationHud
                            }
                        }
                        onToggled: (c) => {
                            appSettings.showNavigationHud = c
                        }
                    }
                }

                RowDiv {}

                // Verbose Wine Logs
                SettingRow {
                    label: "Verbose Wine Debug Logging (+err,+warn)"
                    description: "Capture comprehensive execution logs for diagnostic troubleshooting"
                    controlItem: Toggle {
                        checked: appSettings.enableWineDebugLogs
                        onToggled: (c) => appSettings.enableWineDebugLogs = c
                    }
                }

                RowDiv {}

                // SteamGridDB API Key
                SettingRow {
                    label: "SteamGridDB API Key"
                    description: "Optional v2 Bearer key for artwork scraping (falls back to Steam CDN automatically)"
                    controlItem: M3TextField {
                        implicitWidth: 340
                        placeholderText: "Enter SteamGridDB API key…"
                        isPassword: true
                        text: appSettings.steamGridDbApiKey
                        onCommit: (val) => appSettings.steamGridDbApiKey = val
                    }
                }
            }

            Item { Layout.preferredHeight: 32 }
        }
    }

    // ── Runner & Platform Tag Colors Dialog ─────────────────────────────────
    Popup {
        id: tagColorsModal
        modal: true
        focus: true
        width: Math.min(settingsPage.width - 48, 600)
        contentWidth: width
        x: Math.round((settingsPage.width - width) / 2)
        y: Math.max(20, Math.round((settingsPage.height - height) / 2))
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property int modalFocusIdx: 1

        function focusModalItem(idx) {
            const items = [modalCloseBtn, tagPickerProton, tagPickerGe, tagPickerCachy, tagPickerLinux, tagModalResetBtn, tagModalDoneBtn]
            const sections = [null, secProtonRow, secGeRow, secCachyRow, secLinuxRow, null, null]
            const safeIdx = ((idx % items.length) + items.length) % items.length
            modalFocusIdx = safeIdx
            const target = items[safeIdx]
            if (target) target.forceActiveFocus()
            const sec = sections[safeIdx]
            if (sec && tagPickerScroll && tagPickerScroll.contentItem) {
                const flick = tagPickerScroll.contentItem
                const topY = sec.y - 8
                const bottomY = sec.y + sec.height + 12
                if (topY < flick.contentY) {
                    flick.contentY = Math.max(0, topY)
                } else if (bottomY > flick.contentY + flick.height) {
                    const maxY = Math.max(0, flick.contentHeight - flick.height)
                    flick.contentY = Math.min(maxY, bottomY - flick.height)
                }
            }
        }

        onAboutToShow: {
            modalFocusIdx = 1
            if (tagPickerScroll && tagPickerScroll.contentItem) {
                tagPickerScroll.contentItem.contentY = 0
            }
        }

        onOpened: {
            Qt.callLater(() => focusModalItem(1))
        }

        onClosed: {
            Qt.callLater(() => tagColorsRow.forceActiveFocus())
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 120; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.96; duration: 120; easing.type: Easing.InCubic }
        }

        background: Rectangle {
            color: appSettings.surfaceColor
            radius: 12
            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.6 : 0.25)
                shadowBlur: 0.8
                shadowVerticalOffset: 8
            }
        }

        contentItem: ColumnLayout {
            width: tagColorsModal.availableWidth
            spacing: 0
            focus: true
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Backspace && !settingsPage.isTextInputActive()) {
                    event.accepted = true
                    tagColorsModal.close()
                }
            }

            // ── Dialog Header ──
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 64

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 16
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        Label {
                            text: "Runner & Platform Tag Colors"
                            color: appSettings.textColor
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                        }
                        Label {
                            text: "Customize badge colors across library and runners"
                            color: appSettings.textSecColor
                            font.pixelSize: 12
                        }
                    }

                    Rectangle {
                        id: modalCloseBtn
                        readonly property bool isKeyFocused: activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 18
                        focus: true
                        activeFocusOnTab: false
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        color: (closeHover.hovered || isKeyFocused)
                            ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
                            : "transparent"
                        border.color: isKeyFocused
                            ? appSettings.accentColor
                            : (closeHover.hovered
                                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
                                : "transparent")
                        border.width: isKeyFocused ? 2 : 1
                        scale: closeMA.pressed ? 0.92 : (isKeyFocused ? 1.06 : 1.0)

                        Keys.onDownPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(1) }
                        Keys.onUpPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(6) }
                        Keys.onReturnPressed: (event) => { event.accepted = true; tagColorsModal.close() }
                        Keys.onEnterPressed: (event) => { event.accepted = true; tagColorsModal.close() }
                        Keys.onSpacePressed: (event) => { event.accepted = true; tagColorsModal.close() }

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        HoverHandler { id: closeHover }

                        YIcon {
                            anchors.centerIn: parent
                            source: "qrc:/tsuki_app/icons/actions/close.svg"
                            color: closeHover.hovered ? appSettings.textColor : appSettings.textSecColor
                            size: 16
                        }

                        MouseArea {
                            id: closeMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tagColorsModal.close()
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                }
            }

            // ── Live Badge Preview ──
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.topMargin: 16
                Layout.bottomMargin: 8
                Layout.preferredHeight: 76
                radius: 10
                color: appSettings.surfaceAltColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Label {
                        text: "LIVE BADGE PREVIEW"
                        color: appSettings.textSecColor
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1.0
                    }

                    RowLayout {
                        spacing: 10
                        Layout.fillWidth: true

                        // Steam Proton Preview Badge
                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: spBadgeText.implicitWidth + 16
                            radius: 6
                            color: {
                                let c = Qt.color(appSettings.tagColorSteamProton)
                                return Qt.rgba(c.r, c.g, c.b, 0.18)
                            }
                            border.color: {
                                let c = Qt.color(appSettings.tagColorSteamProton)
                                return Qt.rgba(c.r, c.g, c.b, 0.45)
                            }
                            border.width: 1
                            Text {
                                id: spBadgeText
                                anchors.centerIn: parent
                                text: "PROTON"
                                color: appSettings.tagColorSteamProton
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }

                        // Proton-GE Preview Badge
                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: geBadgeText.implicitWidth + 16
                            radius: 6
                            color: {
                                let c = Qt.color(appSettings.tagColorProtonGe)
                                return Qt.rgba(c.r, c.g, c.b, 0.18)
                            }
                            border.color: {
                                let c = Qt.color(appSettings.tagColorProtonGe)
                                return Qt.rgba(c.r, c.g, c.b, 0.45)
                            }
                            border.width: 1
                            Text {
                                id: geBadgeText
                                anchors.centerIn: parent
                                text: "PROTON-GE"
                                color: appSettings.tagColorProtonGe
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }

                        // CachyOS Preview Badge
                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: cachyBadgeText.implicitWidth + 16
                            radius: 6
                            color: {
                                let c = Qt.color(appSettings.tagColorCachyos)
                                return Qt.rgba(c.r, c.g, c.b, 0.18)
                            }
                            border.color: {
                                let c = Qt.color(appSettings.tagColorCachyos)
                                return Qt.rgba(c.r, c.g, c.b, 0.45)
                            }
                            border.width: 1
                            Text {
                                id: cachyBadgeText
                                anchors.centerIn: parent
                                text: "CACHYOS"
                                color: appSettings.tagColorCachyos
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }

                        // Linux Preview Badge
                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: linuxBadgeText.implicitWidth + 16
                            radius: 6
                            color: {
                                let c = Qt.color(appSettings.tagColorLinux)
                                return Qt.rgba(c.r, c.g, c.b, 0.18)
                            }
                            border.color: {
                                let c = Qt.color(appSettings.tagColorLinux)
                                return Qt.rgba(c.r, c.g, c.b, 0.45)
                            }
                            border.width: 1
                            Text {
                                id: linuxBadgeText
                                anchors.centerIn: parent
                                text: "LINUX"
                                color: appSettings.tagColorLinux
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }

            // ── Scrollable Picker Body ──
            ScrollView {
                id: tagPickerScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(380, pickerCol.implicitHeight + 24)
                contentWidth: availableWidth
                contentHeight: pickerCol.implicitHeight + 24
                clip: true
                focus: false
                focusPolicy: Qt.NoFocus
                activeFocusOnTab: false
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical: ScrollBar {
                    width: 6
                    policy: parent.contentHeight > parent.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: appSettings.accentColor
                        opacity: 0.5
                    }
                }

                ColumnLayout {
                    id: pickerCol
                    width: parent.width - 48
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Item { Layout.preferredHeight: 8 }

                    // Proton
                    Rectangle {
                        id: secProtonRow
                        Layout.fillWidth: true
                        implicitHeight: protonInnerCol.implicitHeight + 20
                        radius: 10
                        color: (tagPickerProton.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.08)
                            : "transparent"
                        border.color: (tagPickerProton.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? appSettings.accentColor
                            : "transparent"
                        border.width: 1.5
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            id: protonInnerCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            Label {
                                text: "Proton Tag Color"
                                color: appSettings.textColor
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Label {
                                text: "Badge color for system and Steam Proton installations"
                                color: appSettings.textSecColor
                                font.pixelSize: 11
                            }
                            M3ColorPicker {
                                id: tagPickerProton
                                Keys.onDownPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(2) }
                                Keys.onUpPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(0) }
                                presets: [
                                    { name: "Sky",    color: "#38bdf8" },
                                    { name: "Blue",   color: "#3b82f6" },
                                    { name: "Cyan",   color: "#06b6d4" },
                                    { name: "Indigo", color: "#6366f1" },
                                    { name: "Teal",   color: "#14b8a6" }
                                ]
                                currentColor: String(appSettings.tagColorSteamProton)
                                onColorSelected: (hex) => appSettings.tagColorSteamProton = hex
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
                    }

                    // Proton-GE
                    Rectangle {
                        id: secGeRow
                        Layout.fillWidth: true
                        implicitHeight: geInnerCol.implicitHeight + 20
                        radius: 10
                        color: (tagPickerGe.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.08)
                            : "transparent"
                        border.color: (tagPickerGe.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? appSettings.accentColor
                            : "transparent"
                        border.width: 1.5
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            id: geInnerCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            Label {
                                text: "Proton-GE Tag Color"
                                color: appSettings.textColor
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Label {
                                text: "Badge color for GloriousEggroll Proton-GE releases"
                                color: appSettings.textSecColor
                                font.pixelSize: 11
                            }
                            M3ColorPicker {
                                id: tagPickerGe
                                Keys.onUpPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(1) }
                                Keys.onDownPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(3) }
                                presets: [
                                    { name: "Purple", color: "#a855f7" },
                                    { name: "Violet", color: "#8b5cf6" },
                                    { name: "Pink",   color: "#ec4899" },
                                    { name: "Rose",   color: "#f43f5e" },
                                    { name: "Blue",   color: "#3b82f6" }
                                ]
                                currentColor: String(appSettings.tagColorProtonGe)
                                onColorSelected: (hex) => appSettings.tagColorProtonGe = hex
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
                    }

                    // Proton-CachyOS
                    Rectangle {
                        id: secCachyRow
                        Layout.fillWidth: true
                        implicitHeight: cachyInnerCol.implicitHeight + 20
                        radius: 10
                        color: (tagPickerCachy.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.08)
                            : "transparent"
                        border.color: (tagPickerCachy.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? appSettings.accentColor
                            : "transparent"
                        border.width: 1.5
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            id: cachyInnerCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            Label {
                                text: "Proton-CachyOS Tag Color"
                                color: appSettings.textColor
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Label {
                                text: "Badge color for CachyOS optimized Proton builds"
                                color: appSettings.textSecColor
                                font.pixelSize: 11
                            }
                            M3ColorPicker {
                                id: tagPickerCachy
                                Keys.onUpPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(2) }
                                Keys.onDownPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(4) }
                                presets: [
                                    { name: "Teal",    color: "#2dd4bf" },
                                    { name: "Emerald", color: "#10b981" },
                                    { name: "Cyan",    color: "#06b6d4" },
                                    { name: "Green",   color: "#22c55e" },
                                    { name: "Sky",     color: "#38bdf8" }
                                ]
                                currentColor: String(appSettings.tagColorCachyos)
                                onColorSelected: (hex) => appSettings.tagColorCachyos = hex
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
                    }

                    // Linux Native
                    Rectangle {
                        id: secLinuxRow
                        Layout.fillWidth: true
                        implicitHeight: linuxInnerCol.implicitHeight + 20
                        radius: 10
                        color: (tagPickerLinux.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.08)
                            : "transparent"
                        border.color: (tagPickerLinux.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? appSettings.accentColor
                            : "transparent"
                        border.width: 1.5
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            id: linuxInnerCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            Label {
                                text: "Linux Native Tag Color"
                                color: appSettings.textColor
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Label {
                                text: "Badge color for native Linux games in library and details"
                                color: appSettings.textSecColor
                                font.pixelSize: 11
                            }
                            M3ColorPicker {
                                id: tagPickerLinux
                                Keys.onUpPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(3) }
                                Keys.onDownPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(6) }
                                presets: [
                                    { name: "Amber",  color: "#f59e0b" },
                                    { name: "Orange", color: "#f97316" },
                                    { name: "Green",  color: "#10b981" },
                                    { name: "Cyan",   color: "#06b6d4" },
                                    { name: "Blue",   color: "#3b82f6" },
                                    { name: "Purple", color: "#a855f7" },
                                    { name: "Red",    color: "#ef4444" }
                                ]
                                currentColor: String(appSettings.tagColorLinux)
                                onColorSelected: (hex) => appSettings.tagColorLinux = hex
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 12 }
                }
            }

            // ── Dialog Footer ──
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 64

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    spacing: 12

                    M3Button {
                        id: tagModalResetBtn
                        text: "Reset Defaults"
                        buttonType: "outlined"
                        Keys.onUpPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(4) }
                        Keys.onRightPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(6) }
                        Keys.onDownPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(0) }
                        onClicked: {
                            appSettings.tagColorSteamProton = "#38bdf8"
                            appSettings.tagColorProtonGe = "#a855f7"
                            appSettings.tagColorCachyos = "#2dd4bf"
                            appSettings.tagColorLinux = "#f59e0b"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    M3Button {
                        id: tagModalDoneBtn
                        text: "Done"
                        buttonType: "filled"
                        Keys.onUpPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(4) }
                        Keys.onLeftPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(5) }
                        Keys.onDownPressed: (event) => { event.accepted = true; tagColorsModal.focusModalItem(0) }
                        onClicked: tagColorsModal.close()
                    }
                }
            }
        }
    }

    // ── Default Gamescope Parameters Dialog ─────────────────────────────────
    GamescopeDialog {
        id: gamescopeSettingsDialog
        onSaveRequested: (cfgMap) => {
            appSettings.defaultGamescopeConfig = cfgMap
        }
        onClosed: {
            Qt.callLater(() => gamescopeDefaultsConfigRow.forceActiveFocus())
        }
    }
}
