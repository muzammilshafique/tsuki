import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Page {
    id: settingsPage
    objectName: "settingsPage"
    signal backRequested()

    property int activeTab: 0
    property bool railCollapsed: false
    property bool suppressNextTabScrollReset: false

    readonly property var tabMeta: [
        { idx: 0, label: "Style",       symbol: "palette" },
        { idx: 1, label: "Library",     symbol: "grid_view" },
        { idx: 2, label: "Performance", symbol: "speed" },
        { idx: 3, label: "Runners",     symbol: "folder_open" },
        { idx: 4, label: "System",      symbol: "tune" },
        { idx: 5, label: "About",       symbol: "info" }
    ]

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

    // Inline Reusable Expressive Color Palette Selector (Accent / Canvas / Sidebar)
    component ColorPillSelector : ColumnLayout {
        id: cps
        property var presets: []
        property string currentColor: ""
        property string autoLabel: ""
        property bool showCustomInput: false
        signal colorSelected(string hex)

        spacing: 8

        readonly property bool isMatchingPreset: {
            const cur = (cps.currentColor || "").toLowerCase()
            if (cps.autoLabel !== "" && cur === "") return true
            if (!cps.presets) return false
            for (let i = 0; i < cps.presets.length; ++i) {
                if ((cps.presets[i].color || "").toLowerCase() === cur) return true
            }
            return false
        }
        readonly property bool isCustomSelected: !isMatchingPreset && (cps.currentColor !== "")

        readonly property var pillModel: {
            let list = []
            if (cps.presets) {
                for (let i = 0; i < cps.presets.length; ++i) {
                    const p = cps.presets[i]
                    if (p.color === "") {
                        list.push({
                            label: p.name,
                            val: "",
                            iconSymbol: "auto_awesome"
                        })
                    } else {
                        list.push({
                            label: p.name,
                            val: p.color,
                            dotColor: p.color
                        })
                    }
                }
            }
            if (cps.isCustomSelected) {
                list.push({
                    label: "Custom",
                    val: "__custom__",
                    dotColor: cps.currentColor
                })
            } else {
                list.push({
                    label: "Custom",
                    val: "__custom__",
                    iconSymbol: "colorize"
                })
            }
            return list
        }

        function adjustLeft() { palettePills.adjustLeft() }
        function adjustRight() { palettePills.adjustRight() }
        function activate() {
            if (cps.showCustomInput || cps.isCustomSelected) {
                customHexFocusTimer.restart()
            } else {
                palettePills.activate()
            }
        }

        Timer {
            id: customHexFocusTimer
            interval: 0
            repeat: false
            onTriggered: {
                hexField.forceActiveFocus()
                hexField.selectAll()
            }
        }

        M3PillGroup {
            id: palettePills
            Layout.fillWidth: true
            wrap: true
            pillHeight: 34
            fontSize: 12
            model: cps.pillModel
            selectedValue: (cps.showCustomInput || cps.isCustomSelected) ? "__custom__" : cps.currentColor
            onSelectionChanged: (val) => {
                if (val === "__custom__") {
                    cps.showCustomInput = true
                    customHexFocusTimer.restart()
                } else {
                    cps.showCustomInput = false
                    cps.colorSelected(String(val))
                }
            }
        }

        // Inline Custom Hex Pill Row
        RowLayout {
            visible: cps.showCustomInput || cps.isCustomSelected
            spacing: 8

            Rectangle {
                width: 24
                height: 24
                radius: 12
                color: cps.currentColor !== "" ? cps.currentColor : appSettings.accentColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)
                border.width: 1
            }

            Rectangle {
                width: 136
                height: 34
                radius: 17
                color: appSettings.surfaceContainerHigh
                border.color: hexField.activeFocus ? appSettings.accentColor : appSettings.borderColor
                border.width: hexField.activeFocus ? 2 : 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 4

                    Label {
                        text: "#"
                        color: appSettings.textSecColor
                        font.family: "JetBrains Mono NF"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextField {
                        id: hexField
                        activeFocusOnTab: false
                        width: parent.width - 18
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter
                        color: appSettings.textColor
                        font.family: "JetBrains Mono NF"
                        font.pixelSize: 12
                        font.capitalization: Font.AllUppercase
                        placeholderText: (cps.currentColor || "5B9CF6").replace("#", "")
                        placeholderTextColor: appSettings.textTerColor
                        selectByMouse: true
                        background: null
                        padding: 0

                        function commitHex() {
                            let hex = text.replace("#", "").trim()
                            if (/^[0-9a-fA-F]{3}$/.test(hex)) {
                                hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2]
                            }
                            if (/^[0-9a-fA-F]{6}$/.test(hex)) {
                                cps.colorSelected("#" + hex.toLowerCase())
                                text = ""
                            }
                            cps.showCustomInput = false
                            palettePills.forceActiveFocus()
                        }

                        onEditingFinished: commitHex()
                        Keys.onReturnPressed: (event) => { event.accepted = true; commitHex() }
                        Keys.onEnterPressed: (event) => { event.accepted = true; commitHex() }
                        Keys.onEscapePressed: (event) => {
                            event.accepted = true
                            cps.showCustomInput = false
                            palettePills.forceActiveFocus()
                        }
                    }
                }
            }

            M3Button {
                text: "Apply"
                buttonType: "tonal"
                implicitHeight: 32
                onClicked: hexField.commitHex()
            }
        }
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
        if (settingsPage.isAnyModalOpen() || settingsPage.isTextInputActive()) return
        if (event.key === Qt.Key_Backspace) {
            event.accepted = true
            settingsPage.backRequested()
        } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_BracketLeft) {
            event.accepted = true
            settingsPage.cycleTab(-1)
        } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_BracketRight) {
            event.accepted = true
            settingsPage.cycleTab(1)
        } else if (event.key === Qt.Key_Down && settingsPage.activeFocus) {
            event.accepted = true
            focusFirstControlInActiveTab()
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

    // ── Search Index & Cross-Tab Navigation Helpers ─────────────────────────
    property var settingsCatalog: []
    property var searchResults: []
    property int focusedResultIndex: 0
    property var pendingJumpTarget: null

    function collectTilesRecursive(node, sectionTitle, tabIdx, tabLabel, outList) {
        if (!node || !node.children) return
        const ch = node.children
        for (let i = 0; i < ch.length; ++i) {
            const child = ch[i]
            if (!child) continue
            if (child.label !== undefined && child.controlItem !== undefined) {
                outList.push({
                    name: child.label,
                    description: child.description || "",
                    section: tabLabel + (sectionTitle !== "" ? (" · " + sectionTitle) : ""),
                    tabIdx: tabIdx,
                    item: child
                })
            } else {
                const nextSec = (child.sectionTitle !== undefined && child.sectionTitle !== "")
                    ? child.sectionTitle
                    : sectionTitle
                collectTilesRecursive(child, nextSec, tabIdx, tabLabel, outList)
            }
        }
    }

    function buildIndex() {
        let list = []
        const pages = tabStack.children
        for (let t = 0; t < pages.length && t < tabMeta.length; ++t) {
            collectTilesRecursive(pages[t], "", t, tabMeta[t].label, list)
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
                    tabIdx: entry.tabIdx,
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

    function selectTab(idx) {
        const clamped = Math.max(0, Math.min(tabMeta.length - 1, idx))
        if (settingsPage.activeTab === clamped) return
        settingsPage.activeTab = clamped
    }

    function cycleTab(delta) {
        const count = tabMeta.length
        const next = ((settingsPage.activeTab + delta) % count + count) % count
        selectTab(next)
    }

    onActiveTabChanged: {
        tabFadeAnim.restart()
        if (!suppressNextTabScrollReset) {
            const flick = settingsScroll.contentItem
            if (flick && flick.contentY !== undefined) {
                flick.contentY = 0
            }
        }
        suppressNextTabScrollReset = false
    }

    Timer {
        id: jumpToSettingTimer
        interval: 0
        repeat: false
        onTriggered: {
            const targetItem = settingsPage.pendingJumpTarget
            settingsPage.pendingJumpTarget = null
            if (!targetItem) return
            scrollToSettingRow(targetItem, true)
            targetItem.forceActiveFocus()
            if (typeof targetItem.highlight === "function") {
                targetItem.highlight()
            }
        }
    }

    function scrollToSetting(targetItem, targetTabIdx) {
        if (!targetItem) return
        if (targetTabIdx !== undefined && targetTabIdx >= 0 && targetTabIdx !== settingsPage.activeTab) {
            settingsPage.suppressNextTabScrollReset = true
            settingsPage.activeTab = targetTabIdx
        }
        pendingJumpTarget = targetItem
        jumpToSettingTimer.restart()
    }

    function collectVisibleTilesIn(node, outList) {
        if (!node || !node.visible || !node.children) return
        const ch = node.children
        for (let i = 0; i < ch.length; ++i) {
            const child = ch[i]
            if (!child || !child.visible) continue
            if (child.label !== undefined && child.controlItem !== undefined) {
                outList.push(child)
            } else {
                collectVisibleTilesIn(child, outList)
            }
        }
    }

    function getVisibleRows() {
        let rows = [searchTile]
        const activePage = tabStack.children[settingsPage.activeTab]
        if (activePage) {
            collectVisibleTilesIn(activePage, rows)
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
        let p = targetItem.mapToItem(contentScrollWrapper, 0, 0)
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

    function focusFirstControlInActiveTab() {
        let rows = getVisibleRows()
        if (rows.length > 1) {
            rows[1].forceActiveFocus()
            scrollToSettingRow(rows[1], false)
        } else {
            navRail.forceActiveFocus()
        }
    }

    function focusRailFromContent() {
        navRail.forceActiveFocus()
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

    Timer {
        id: initPageTimer
        interval: 0
        repeat: false
        onTriggered: {
            settingsPage.buildIndex()
            if (uiController && uiController.isKeyboardNavActive) {
                settingsPage.focusFirstControlInActiveTab()
            }
        }
    }

    Component.onCompleted: initPageTimer.restart()

    NumberAnimation {
        id: rowScrollAnim
        target: settingsScroll.contentItem
        property: "contentY"
        duration: 180
        easing.type: Easing.OutCubic
    }

    // ── Main Two-Pane Shell (Top Header + Rail + Rounded Content Surface) ───
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top Header Bar
        Item {
            id: settingsHeader
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            z: 100

            Item {
                id: headerInner
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20

                RowLayout {
                    id: leftHeaderRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    // Back Button (Expanding Spring Pill)
                    Button {
                        id: backBtn
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        padding: 0

                        readonly property bool isBtnActive: backBtn.hovered || (backBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                        property real expandedWidth: 10 + 18 + 8 + backLabel.implicitWidth + 14
                        implicitWidth: isBtnActive ? expandedWidth : 38
                        implicitHeight: 38

                        Behavior on implicitWidth {
                            SpringAnimation { spring: 4; damping: 0.25; epsilon: 0.25 }
                        }

                        background: Rectangle {
                            property color accent: appSettings.accentColor
                            radius: 19
                            color: Qt.rgba(accent.r, accent.g, accent.b, backBtn.isBtnActive ? 1.0 : 0.0)
                            border.color: Qt.rgba(accent.r, accent.g, accent.b, backBtn.isBtnActive ? 0.0 : 1.0)
                            border.width: backBtn.isBtnActive ? 0 : 1.5
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }

                        contentItem: Item {
                            clip: true
                            implicitWidth: backBtn.implicitWidth
                            implicitHeight: 38

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
                                        color: backBtn.isBtnActive ? appSettings.onPrimary : appSettings.accentColor
                                    }
                                }

                                Label {
                                    id: backLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Back"
                                    color: backBtn.isBtnActive ? appSettings.onPrimary : appSettings.accentColor
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
                        Keys.onDownPressed: (event) => { event.accepted = true; navRail.forceActiveFocus() }
                        Keys.onReturnPressed: (event) => { event.accepted = true; settingsPage.backRequested() }
                        Keys.onEnterPressed: (event) => { event.accepted = true; settingsPage.backRequested() }
                        Keys.onSpacePressed: (event) => { event.accepted = true; settingsPage.backRequested() }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }

                    Label {
                        text: "Settings"
                        color: appSettings.textColor
                        font.family: "Rubik"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        renderType: Text.QtRendering
                    }
                }

                // Centered Search Bar Pill
                Rectangle {
                    id: searchTile
                    focus: true
                    activeFocusOnTab: false
                    y: Math.round((parent.height - height) / 2)
                    width: Math.min(380, Math.max(220, headerInner.width - 420))
                    x: Math.max(leftHeaderRow.x + leftHeaderRow.width + 16, Math.round((headerInner.width - width) / 2))
                    height: 38
                    radius: 19
                    readonly property bool isEditing: searchField.activeFocus
                    readonly property bool isTileFocused: searchTile.activeFocus && (uiController ? uiController.isKeyboardNavActive : false)
                    color: (searchField.activeFocus || searchTile.isTileFocused)
                        ? appSettings.surfaceContainerHigh
                        : (searchTileHover.hovered ? appSettings.surfaceContainer : appSettings.surfaceContainerLow)

                    border.color: (searchField.activeFocus || searchTile.isTileFocused)
                        ? appSettings.accentColor
                        : appSettings.borderColor
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
                            settingsPage.focusFirstControlInActiveTab()
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
                        anchors.leftMargin: 13
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
                        font.family: "Rubik"
                        font.pixelSize: 13
                        leftPadding: 36
                        rightPadding: (clearSearchBtn.visible ? 32 : 40)
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
                                settingsPage.focusFirstControlInActiveTab()
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
                                    settingsPage.scrollToSetting(entry.item, entry.tabIdx)
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
                                    settingsPage.scrollToSetting(entry.item, entry.tabIdx)
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

                        background: Item {
                            Rectangle {
                                anchors.fill: parent
                                radius: 13
                                color: appSettings.surfaceContainerHighest
                                opacity: clearSearchBtn.hovered ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
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

                    // Search Results Popup
                    Popup {
                        id: searchResultsPopup
                        y: searchTile.height + 6
                        x: 0
                        width: Math.max(searchTile.width, 380)
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

                        readonly property real fullContentHeight: Math.min(300, settingsPage.searchResults.length * 46 + 12)
                        implicitHeight: fullContentHeight * unfoldProgress
                        height: implicitHeight

                        background: Rectangle {
                            color: appSettings.surfaceContainerHigh
                            radius: 16
                            border.color: appSettings.borderColor
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

                                delegate: Item {
                                    id: sResRow
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    height: 44
                                    readonly property bool isRowFocused: sResMA.containsMouse || settingsPage.focusedResultIndex === index

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: appSettings.secondaryContainer
                                        border.color: appSettings.accentColor
                                        border.width: 1
                                        opacity: sResRow.isRowFocused ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        Label {
                                            text: sResRow.modelData.name
                                            color: sResRow.isRowFocused ? appSettings.onSecondaryContainer : appSettings.textColor
                                            font.family: "Rubik"
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Rectangle {
                                            Layout.alignment: Qt.AlignVCenter
                                            height: 22
                                            radius: 11
                                            implicitWidth: secTagLbl.implicitWidth + 14
                                            color: sResRow.isRowFocused
                                                ? appSettings.accentColor
                                                : appSettings.surfaceContainer
                                            Label {
                                                id: secTagLbl
                                                anchors.centerIn: parent
                                                text: sResRow.modelData.section
                                                color: sResRow.isRowFocused ? appSettings.onPrimary : appSettings.textSecColor
                                                font.family: "Rubik"
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
                                            settingsPage.scrollToSetting(sResRow.modelData.item, sResRow.modelData.tabIdx)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Body: Left Navigation Rail (Adapts to Sidebar Color) + Right Rounded Elevated Surface
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // ── Left Navigation Rail (Strictly Tabs + Collapse Toggle) ─────
            Rectangle {
                id: navRail
                objectName: "settingsNavRail"
                focus: true
                activeFocusOnTab: false
                readonly property bool isRailFocused: navRail.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                readonly property bool isSidebarDark: (0.2126 * appSettings.sidebarColor.r + 0.7152 * appSettings.sidebarColor.g + 0.0722 * appSettings.sidebarColor.b) < 0.5
                readonly property color sidebarPrimaryText: isSidebarDark ? "#f4f4f5" : "#0f172a"

                Layout.preferredWidth: settingsPage.railCollapsed ? 68 : 196
                Layout.fillHeight: true
                Layout.leftMargin: 16
                Layout.bottomMargin: 16
                Layout.topMargin: 4
                radius: 20
                color: appSettings.sidebarColor
                border.color: appSettings.sidebarDividerColor
                border.width: 1
                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Keys.onUpPressed: (event) => {
                    event.accepted = true
                    if (settingsPage.activeTab > 0) {
                        settingsPage.selectTab(settingsPage.activeTab - 1)
                    } else {
                        backBtn.forceActiveFocus()
                    }
                }
                Keys.onDownPressed: (event) => {
                    event.accepted = true
                    if (settingsPage.activeTab < settingsPage.tabMeta.length - 1) {
                        settingsPage.selectTab(settingsPage.activeTab + 1)
                    }
                }
                Keys.onRightPressed: (event) => {
                    event.accepted = true
                    settingsPage.focusFirstControlInActiveTab()
                }
                Keys.onReturnPressed: (event) => {
                    event.accepted = true
                    settingsPage.focusFirstControlInActiveTab()
                }
                Keys.onEnterPressed: (event) => {
                    event.accepted = true
                    settingsPage.focusFirstControlInActiveTab()
                }
                Keys.onSpacePressed: (event) => {
                    event.accepted = true
                    settingsPage.focusFirstControlInActiveTab()
                }
                Keys.onLeftPressed: (event) => {
                    event.accepted = true
                    settingsPage.railCollapsed = !settingsPage.railCollapsed
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    anchors.topMargin: 12
                    anchors.bottomMargin: 12
                    spacing: 6

                    // Collapse Rail Button (opacity-only hover so it never flashes)
                    Item {
                        id: railCollapseBtn
                        width: 46
                        height: 40

                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: appSettings.sidebarHoverColor
                            opacity: collapseHover.hovered ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }

                        scale: collapseTap.pressed ? 0.93 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        YIcon {
                            anchors.centerIn: parent
                            symbol: settingsPage.railCollapsed ? "menu" : "menu_open"
                            size: 20
                            color: collapseHover.hovered ? navRail.sidebarPrimaryText : appSettings.sidebarTextSecColor
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        HoverHandler {
                            id: collapseHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        M3ToolTip {
                            visible: collapseHover.hovered
                            text: settingsPage.railCollapsed ? "Expand sidebar" : "Collapse sidebar"
                        }

                        TapHandler {
                            id: collapseTap
                            onTapped: {
                                if (uiController) uiController.setKeyboardNavActive(false)
                                settingsPage.railCollapsed = !settingsPage.railCollapsed
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 4 }

                    // Primary 5 Category Tabs + Divider + About Tab
                    Repeater {
                        model: settingsPage.tabMeta
                        delegate: ColumnLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                visible: index === 5
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                Layout.rightMargin: 8
                                Layout.topMargin: 4
                                Layout.bottomMargin: 4
                                height: 1
                                color: appSettings.sidebarDividerColor
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Item {
                                id: railTabPill
                                readonly property bool isSelected: settingsPage.activeTab === modelData.idx
                                readonly property bool isFocusedTab: isSelected && navRail.isRailFocused

                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                scale: tabTap.pressed ? 0.96 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                // Hover fill (opacity-only: zero RGB/alpha flash)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 22
                                    color: appSettings.sidebarHoverColor
                                    opacity: (!railTabPill.isSelected && tabHover.hovered) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }

                                // Selected M3 pill container (opacity-only: zero flash through #00000000)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 22
                                    color: appSettings.secondaryContainer
                                    opacity: railTabPill.isSelected ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                }

                                // Keyboard/Gamepad focus outline
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 22
                                    color: "transparent"
                                    border.color: appSettings.accentColor
                                    border.width: 2
                                    opacity: railTabPill.isFocusedTab ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 110 } }
                                }

                                Item {
                                    anchors.fill: parent
                                    clip: true

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 13
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 12

                                        YIcon {
                                            symbol: modelData.symbol
                                            filled: railTabPill.isSelected
                                            size: 20
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: railTabPill.isSelected
                                                ? appSettings.onSecondaryContainer
                                                : (tabHover.hovered ? navRail.sidebarPrimaryText : appSettings.sidebarTextSecColor)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }

                                        Label {
                                            text: modelData.label
                                            anchors.verticalCenter: parent.verticalCenter
                                            font.family: "Rubik"
                                            font.pixelSize: 14
                                            font.weight: railTabPill.isSelected ? Font.DemiBold : Font.Medium
                                            color: railTabPill.isSelected
                                                ? appSettings.onSecondaryContainer
                                                : (tabHover.hovered ? navRail.sidebarPrimaryText : appSettings.sidebarTextSecColor)
                                            opacity: settingsPage.railCollapsed ? 0.0 : 1.0
                                            visible: opacity > 0.01
                                            renderType: Text.QtRendering
                                            Behavior on opacity { NumberAnimation { duration: 140 } }
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }
                                    }
                                }

                                HoverHandler {
                                    id: tabHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                M3ToolTip {
                                    visible: settingsPage.railCollapsed && tabHover.hovered
                                    text: modelData.label
                                }

                                TapHandler {
                                    id: tabTap
                                    onTapped: {
                                        if (uiController) uiController.setKeyboardNavActive(false)
                                        settingsPage.selectTab(modelData.idx)
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ── Right Rounded Elevated Content Surface ─────────────────────
            Rectangle {
                id: contentCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.rightMargin: 16
                Layout.bottomMargin: 16
                Layout.topMargin: 4
                radius: 20
                clip: true
                color: appSettings.surfaceContainerLow
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : appSettings.borderColor
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                ScrollView {
                    id: settingsScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    contentHeight: contentScrollWrapper.implicitHeight
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
                            opacity: settingsVBar.hovered || settingsVBar.pressed ? 0.85 : 0.40
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }

                    Item {
                        id: contentScrollWrapper
                        width: settingsScroll.availableWidth
                        implicitHeight: settingsCol.implicitHeight + 52

                        ColumnLayout {
                            id: settingsCol
                            width: Math.min(parent.width - 56, 860)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 24
                            spacing: 0

                            readonly property bool useTwoCols: width >= 640

                            NumberAnimation {
                                id: tabFadeAnim
                                target: settingsCol
                                property: "opacity"
                                from: 0.65
                                to: 1.0
                                duration: 150
                                easing.type: Easing.OutCubic
                            }

                            Item {
                                id: tabStack
                                Layout.fillWidth: true
                                Layout.preferredHeight: (children[settingsPage.activeTab] && children[settingsPage.activeTab].implicitHeight > 0)
                                    ? children[settingsPage.activeTab].implicitHeight : 200

                                // ══ TAB 0: STYLE ══════════════════════════
                                ColumnLayout {
                                    id: tabStyle
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    visible: settingsPage.activeTab === 0
                                    spacing: 14

                                    readonly property var accentPresets: [
                                        { name: "Blue",   color: "#5b9cf6" },
                                        { name: "Purple", color: "#9c27b0" },
                                        { name: "Pink",   color: "#ec4899" },
                                        { name: "Red",    color: "#d71920" },
                                        { name: "Orange", color: "#f97316" },
                                        { name: "Green",  color: "#10b981" },
                                        { name: "Slate",  color: "#94a3b8" }
                                    ]

                                    readonly property var bgPresets: appSettings.isEffectiveDark ? [
                                        { name: "Auto",     color: "" },
                                        { name: "OLED",     color: "#000000" },
                                        { name: "Midnight", color: "#0b0f19" },
                                        { name: "Charcoal", color: "#121215" },
                                        { name: "Slate",    color: "#161c24" },
                                        { name: "Violet",   color: "#120e1c" }
                                    ] : [
                                        { name: "Auto",     color: "" },
                                        { name: "White",    color: "#ffffff" },
                                        { name: "Pearl",    color: "#f4f4f5" },
                                        { name: "Cream",    color: "#f5f0e8" },
                                        { name: "Slate",    color: "#eef2f6" },
                                        { name: "Linen",    color: "#f5f5f4" }
                                    ]

                                    readonly property var sidebarPresets: appSettings.isEffectiveDark ? [
                                        { name: "Auto",     color: "" },
                                        { name: "OLED",     color: "#000000" },
                                        { name: "Onyx",     color: "#18181b" },
                                        { name: "Midnight", color: "#0f172a" },
                                        { name: "Slate",    color: "#1e232d" },
                                        { name: "Plum",     color: "#1a1020" }
                                    ] : [
                                        { name: "Auto",     color: "" },
                                        { name: "White",    color: "#ffffff" },
                                        { name: "Gray",     color: "#f0f2f5" },
                                        { name: "Cream",    color: "#ede8df" },
                                        { name: "Ice",      color: "#e8eef5" },
                                        { name: "Contrast", color: "#18181b" }
                                    ]

                                    SettingsSection {
                                        sectionTitle: "Theme"

                                        SettingTile {
                                            label: "Mode"
                                            infoTip: "Follow system dark/light theme or pick a fixed appearance"
                                            searchKeywords: "Appearance Dark Light System AMOLED theme mode"
                                            tabIndex: 0
                                            inlineControl: false
                                            fillControlWidth: true
                                            controlItem: ThemePreviewCards {
                                                selectedMode: appSettings.themeMode
                                                onModeSelected: (mode) => appSettings.themeMode = mode
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Palette & Surfaces"
                                        showDivider: true

                                        SettingTile {
                                            label: "Accent"
                                            searchKeywords: "Accent Color Blue Purple Pink Red Orange Green Slate primary"
                                            tabIndex: 0
                                            inlineControl: false
                                            fillControlWidth: true
                                            controlItem: ColorPillSelector {
                                                presets: tabStyle.accentPresets
                                                currentColor: String(appSettings.accentColor)
                                                onColorSelected: (hex) => appSettings.setAccentColor(hex)
                                            }
                                        }

                                        SettingTile {
                                            label: "Sync Sidebar"
                                            infoTip: "Match the navigation sidebar color to the window backdrop"
                                            searchKeywords: "Match Sidebar & Canvas"
                                            tabIndex: 0
                                            inlineControl: true
                                            controlItem: Toggle {
                                                checked: appSettings.syncSidebarColor
                                                onToggled: (c) => appSettings.setSyncSidebarColor(c)
                                            }
                                        }

                                        SettingTile {
                                            label: appSettings.syncSidebarColor ? "Backdrop & Sidebar" : "Backdrop"
                                            searchKeywords: "Background Canvas Color OLED Charcoal Midnight"
                                            tabIndex: 0
                                            inlineControl: false
                                            fillControlWidth: true
                                            controlItem: ColorPillSelector {
                                                autoLabel: "Auto"
                                                presets: tabStyle.bgPresets
                                                currentColor: appSettings.customBgColor
                                                onColorSelected: (hex) => {
                                                    if (hex === "") appSettings.resetBgColor()
                                                    else appSettings.setCustomBgColor(hex)
                                                }
                                            }
                                        }

                                        SettingTile {
                                            visible: !appSettings.syncSidebarColor
                                            label: "Sidebar"
                                            searchKeywords: "Sidebar Color navigation Onyx Midnight Plum"
                                            tabIndex: 0
                                            inlineControl: false
                                            fillControlWidth: true
                                            controlItem: ColorPillSelector {
                                                autoLabel: "Auto"
                                                presets: tabStyle.sidebarPresets
                                                currentColor: appSettings.customSidebarColor
                                                onColorSelected: (hex) => {
                                                    if (hex === "") appSettings.resetSidebarColor()
                                                    else appSettings.setCustomSidebarColor(hex)
                                                }
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Runner Tags"
                                        showDivider: true

                                        SettingTile {
                                            id: tagColorsRow
                                            label: "Tag Colors"
                                            infoTip: "Customize badge colors for Proton, Proton-GE, CachyOS, and Linux"
                                            tabIndex: 0
                                            inlineControl: true
                                            controlItem: RowLayout {
                                                spacing: 10

                                                Row {
                                                    spacing: 6
                                                    Layout.alignment: Qt.AlignVCenter
                                                    Repeater {
                                                        model: [
                                                            appSettings.tagColorSteamProton,
                                                            appSettings.tagColorProtonGe,
                                                            appSettings.tagColorCachyos,
                                                            appSettings.tagColorLinux
                                                        ]
                                                        delegate: Rectangle {
                                                            required property color modelData
                                                            width: 12
                                                            height: 12
                                                            radius: 6
                                                            color: modelData
                                                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.18)
                                                            border.width: 1
                                                        }
                                                    }
                                                }

                                                M3Button {
                                                    text: "Customize"
                                                    iconSymbol: "palette"
                                                    buttonType: "tonal"
                                                    onClicked: tagColorsModal.open()
                                                }
                                            }
                                        }
                                    }
                                }

                                // ══ TAB 1: LIBRARY ════════════════════════
                                ColumnLayout {
                                    id: tabLibrary
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    visible: settingsPage.activeTab === 1
                                    spacing: 14

                                    SettingsSection {
                                        sectionTitle: "Cards & Grid"

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: settingsCol.useTwoCols ? 2 : 1
                                            columnSpacing: 16
                                            rowSpacing: 8

                                            SettingTile {
                                                label: "Poster Size"
                                                infoTip: "Target thumbnail width in the library grid (px)"
                                                tabIndex: 1
                                                inlineControl: false
                                                fillControlWidth: true
                                                controlItem: StyledSlider {
                                                    from: 150; to: 280; stepSize: 5
                                                    value: appSettings.thumbScaleTarget
                                                    suffix: " px"
                                                    slider.onMoved: appSettings.thumbScaleTarget = Math.round(slider.value)
                                                }
                                            }

                                            SettingTile {
                                                label: "Corner Radius"
                                                infoTip: "Squircle corner roundness on poster tiles"
                                                tabIndex: 1
                                                inlineControl: false
                                                fillControlWidth: true
                                                controlItem: StyledSlider {
                                                    from: 4; to: 28; stepSize: 2
                                                    value: appSettings.cardRadius
                                                    suffix: " px"
                                                    slider.onMoved: appSettings.cardRadius = Math.round(slider.value)
                                                }
                                            }
                                        }

                                        SettingTile {
                                            label: "Card Title"
                                            infoTip: "Position of title text on library poster cards"
                                            searchKeywords: "Game Title Display below hover hidden"
                                            tabIndex: 1
                                            inlineControl: false
                                            controlItem: M3PillGroup {
                                                model: [
                                                    { label: "Below",  val: 0 },
                                                    { label: "Hover",  val: 1 },
                                                    { label: "Hidden", val: 2 }
                                                ]
                                                selectedValue: appSettings.titleVisibility
                                                onSelectionChanged: (val) => appSettings.titleVisibility = val
                                            }
                                        }

                                        SettingTile {
                                            label: "Runner Badge"
                                            infoTip: "Where to place the Proton / Wine runner badge"
                                            searchKeywords: "Runner Tag Position"
                                            tabIndex: 1
                                            inlineControl: false
                                            controlItem: M3PillGroup {
                                                model: [
                                                    { label: "Below Title", val: 0 },
                                                    { label: "Above Title", val: 1 },
                                                    { label: "On Poster", val: 2 },
                                                    { label: "Hidden", val: 3 }
                                                ]
                                                selectedValue: appSettings.tagPosition
                                                onSelectionChanged: (val) => appSettings.tagPosition = val
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Behavior"
                                        showDivider: true

                                        SettingTile {
                                            label: "Card Click"
                                            infoTip: "Default action when clicking a game poster card"
                                            searchKeywords: "Card Left-Click Action launch details"
                                            tabIndex: 1
                                            inlineControl: false
                                            controlItem: M3PillGroup {
                                                model: [
                                                    { label: "Launch Game", val: 0, iconSymbol: "play_arrow" },
                                                    { label: "Open Details", val: 1, iconSymbol: "article" }
                                                ]
                                                selectedValue: appSettings.leftClickBehavior
                                                onSelectionChanged: (val) => appSettings.leftClickBehavior = val
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: settingsCol.useTwoCols ? 2 : 1
                                            columnSpacing: 16
                                            rowSpacing: 4

                                            SettingTile {
                                                label: "Release Year"
                                                infoTip: "Display release year alongside card titles"
                                                searchKeywords: "Show Release Year"
                                                tabIndex: 1
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.showYear
                                                    onToggled: (c) => appSettings.showYear = c
                                                }
                                            }

                                            SettingTile {
                                                label: "Details Title"
                                                infoTip: "Display game text title on the Game Details header"
                                                searchKeywords: "Details Header Title showGameName"
                                                tabIndex: 1
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.showGameName
                                                    onToggled: (c) => appSettings.showGameName = c
                                                }
                                            }

                                            SettingTile {
                                                label: "Minimize on Launch"
                                                infoTip: "Minimize Tsuki window when launching a game"
                                                tabIndex: 1
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.minimizeOnLaunch
                                                    onToggled: (c) => appSettings.minimizeOnLaunch = c
                                                }
                                            }

                                            SettingTile {
                                                label: "Epic Badge"
                                                infoTip: "Display Epic Games icon badge on installed Epic library cards"
                                                searchKeywords: "Epic Games Badge Icon Library Card"
                                                tabIndex: 1
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.showEpicBadge
                                                    onToggled: (c) => appSettings.showEpicBadge = c
                                                }
                                            }
                                        }
                                    }
                                }

                                // ══ TAB 2: PERFORMANCE ════════════════════
                                ColumnLayout {
                                    id: tabPerformance
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    visible: settingsPage.activeTab === 2
                                    spacing: 14

                                    SettingsSection {
                                        sectionTitle: "Translation & Sync"

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: settingsCol.useTwoCols ? 2 : 1
                                            columnSpacing: 16
                                            rowSpacing: 4

                                            SettingTile {
                                                label: "DXVK"
                                                infoTip: "Direct3D 9 / 10 / 11 to Vulkan translation layer"
                                                tabIndex: 2
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.dxvkDefault
                                                    onToggled: (c) => appSettings.dxvkDefault = c
                                                }
                                            }

                                            SettingTile {
                                                label: "VKD3D-Proton"
                                                infoTip: "Direct3D 12 to Vulkan translation layer"
                                                tabIndex: 2
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.vkd3dDefault
                                                    onToggled: (c) => appSettings.vkd3dDefault = c
                                                }
                                            }

                                            SettingTile {
                                                label: "Esync"
                                                infoTip: "Eventfd-based Wine synchronization reducing wineserver overhead"
                                                tabIndex: 2
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.esyncDefault
                                                    onToggled: (c) => appSettings.esyncDefault = c
                                                }
                                            }

                                            SettingTile {
                                                label: "Fsync"
                                                infoTip: "In-kernel futex Wine synchronization (requires Linux kernel 5.16+)"
                                                tabIndex: 2
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.fsyncDefault
                                                    onToggled: (c) => appSettings.fsyncDefault = c
                                                }
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Runtime & Overlays"
                                        showDivider: true

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: settingsCol.useTwoCols ? 2 : 1
                                            columnSpacing: 16
                                            rowSpacing: 4

                                            SettingTile {
                                                label: "GameMode"
                                                infoTip: "Feral GameMode CPU governor & I/O priority (gamemoderun)"
                                                searchKeywords: "Feral GameMode CPU"
                                                tabIndex: 2
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.gamemodeDefault
                                                    onToggled: (c) => appSettings.gamemodeDefault = c
                                                }
                                            }

                                            SettingTile {
                                                label: "MangoHud"
                                                infoTip: "Vulkan/OpenGL framerate, frametimes & hardware overlay"
                                                searchKeywords: "MangoHud Overlay FPS"
                                                tabIndex: 2
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.mangohudDefault
                                                    onToggled: (c) => appSettings.mangohudDefault = c
                                                }
                                            }

                                            SettingTile {
                                                id: gamescopeDefaultRow
                                                objectName: "gamescopeDefaultRow"
                                                label: "Gamescope"
                                                badgeText: Boolean(uiController && uiController.diagnosticsManager && !uiController.diagnosticsManager.gamescopeAvailable)
                                                    ? "Missing" : ""
                                                infoTip: "Valve micro-compositor for resolution scaling, FSR, VRR & HDR"
                                                tabIndex: 2
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    id: settingsGamescopeToggle
                                                    checked: appSettings.gamescopeDefault
                                                    onToggled: (c) => appSettings.gamescopeDefault = c
                                                }
                                            }

                                            SettingTile {
                                                id: gamescopeDefaultsConfigRow
                                                objectName: "gamescopeDefaultsConfigRow"
                                                label: "Gamescope Preset"
                                                infoTip: "Configure global resolution, FSR upscaling, FPS limit, HDR & input presets"
                                                searchKeywords: "Gamescope Defaults Config resolution FSR"
                                                tabIndex: 2
                                                inlineControl: true
                                                controlItem: M3Button {
                                                    id: settingsGamescopeConfigBtn
                                                    text: "Configure"
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
                                        }

                                        SettingTile {
                                            label: "DXVK HUD"
                                            infoTip: "In-game diagnostic overlay rendered by DXVK"
                                            searchKeywords: "DXVK HUD Mode FPS Frametimes Compiler"
                                            tabIndex: 2
                                            inlineControl: false
                                            controlItem: M3PillGroup {
                                                model: [
                                                    { label: "Off",        val: "none" },
                                                    { label: "FPS",        val: "fps" },
                                                    { label: "Frametimes", val: "frametimes" },
                                                    { label: "Full",       val: "full" },
                                                    { label: "Compiler",   val: "compiler" }
                                                ]
                                                selectedValue: appSettings.defaultDxvkHud
                                                onSelectionChanged: (val) => appSettings.defaultDxvkHud = String(val)
                                            }
                                        }
                                    }
                                }

                                // ══ TAB 3: RUNNERS ════════════════════════
                                ColumnLayout {
                                    id: tabRunners
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    visible: settingsPage.activeTab === 3
                                    spacing: 14

                                    SettingsSection {
                                        sectionTitle: "Default Runner"

                                        SettingTile {
                                            label: "Runner"
                                            infoTip: "Fallback Wine or Proton version assigned to newly added games"
                                            searchKeywords: "Global Default Compatibility Runner Wine Proton"
                                            tabIndex: 3
                                            inlineControl: false
                                            fillControlWidth: true
                                            controlItem: M3PillGroup {
                                                readonly property var installed: (uiController && uiController.runnerManager && uiController.runnerManager.installedRunners)
                                                    ? uiController.runnerManager.installedRunners : []
                                                wrap: true
                                                model: {
                                                    let list = [{ label: "Auto", val: "", iconSymbol: "auto_awesome" }]
                                                    for (let i = 0; i < installed.length; ++i) {
                                                        list.push({ label: installed[i].name, val: installed[i].id })
                                                    }
                                                    return list
                                                }
                                                selectedValue: appSettings.defaultRunnerId
                                                onSelectionChanged: (val) => appSettings.defaultRunnerId = String(val)
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Directories"
                                        showDivider: true

                                        SettingTile {
                                            id: prefixDirRow
                                            label: "Prefixes Folder"
                                            infoTip: "Base folder where newly created Wine prefixes are initialized"
                                            searchKeywords: "Wine Prefixes Directory folder path"
                                            tabIndex: 3
                                            inlineControl: false
                                            fillControlWidth: true
                                            controlItem: RowLayout {
                                                spacing: 8
                                                M3TextField {
                                                    Layout.fillWidth: true
                                                    text: appSettings.defaultPrefixLocation
                                                    onCommit: (val) => appSettings.defaultPrefixLocation = val
                                                }
                                                M3Button {
                                                    id: prefixDirBrowseBtn
                                                    text: "Browse…"
                                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                                    buttonType: "tonal"
                                                    onClicked: {
                                                        if (!uiController) return
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

                                        SettingTile {
                                            id: runnerDirRow
                                            label: "Runners Folder"
                                            infoTip: "Folder where Proton-GE and Wine tarballs are extracted"
                                            searchKeywords: "Runner Downloads Directory folder path"
                                            tabIndex: 3
                                            inlineControl: false
                                            fillControlWidth: true
                                            controlItem: RowLayout {
                                                spacing: 8
                                                M3TextField {
                                                    Layout.fillWidth: true
                                                    text: appSettings.defaultRunnerLocation
                                                    onCommit: (val) => appSettings.defaultRunnerLocation = val
                                                }
                                                M3Button {
                                                    id: runnerDirBrowseBtn
                                                    text: "Browse…"
                                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                                    buttonType: "tonal"
                                                    onClicked: {
                                                        if (!uiController) return
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

                                        SettingTile {
                                            id: epicDirRow
                                            label: "Epic Games Folder"
                                            infoTip: "Default installation folder for downloaded Epic Games titles"
                                            searchKeywords: "Epic Games Install Directory folder path"
                                            tabIndex: 3
                                            inlineControl: false
                                            fillControlWidth: true
                                            controlItem: RowLayout {
                                                spacing: 8
                                                M3TextField {
                                                    Layout.fillWidth: true
                                                    text: appSettings.defaultEpicInstallLocation
                                                    onCommit: (val) => appSettings.defaultEpicInstallLocation = val
                                                }
                                                M3Button {
                                                    id: epicDirBrowseBtn
                                                    text: "Browse…"
                                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                                    buttonType: "tonal"
                                                    onClicked: {
                                                        if (!uiController) return
                                                        let p = uiController.selectFolder("Select Default Epic Games Folder", appSettings.defaultEpicInstallLocation)
                                                        if (p && p.length > 0) appSettings.defaultEpicInstallLocation = p
                                                    }
                                                    Keys.onLeftPressed: (event) => { event.accepted = true; epicDirRow.forceActiveFocus() }
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

                                    SettingsSection {
                                        sectionTitle: "Online & Anti-Cheat Runtimes"
                                        showDivider: true

                                        SettingTile {
                                            label: "EOS Overlay"
                                            infoTip: "Epic Online Services overlay for friends list, invites, and cross-play"
                                            searchKeywords: "Epic EOS Overlay Online Multiplayer Friends"
                                            tabIndex: 3
                                            inlineControl: true
                                            controlItem: RowLayout {
                                                spacing: 8
                                                Label {
                                                    text: (uiController && uiController.epicService && uiController.epicService.isInstallingEosOverlay)
                                                        ? (Math.round(Number(uiController.epicService.eosOverlayProgress || 0)) + "%")
                                                        : ((uiController && uiController.epicService && uiController.epicService.eosOverlayInstalled)
                                                            ? (uiController.epicService.eosOverlayVersion || "Installed")
                                                            : "Not Installed")
                                                    color: (uiController && uiController.epicService && uiController.epicService.eosOverlayInstalled) ? appSettings.accentColor : appSettings.textSecColor
                                                    font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                }
                                                M3Button {
                                                    text: (uiController && uiController.epicService && uiController.epicService.eosOverlayInstalled) ? "Update" : "Install"
                                                    enabled: Boolean(uiController && uiController.epicService && !uiController.epicService.isInstallingEosOverlay)
                                                    buttonType: "tonal"
                                                    onClicked: if (uiController && uiController.epicService) uiController.epicService.installEosOverlay()
                                                }
                                                M3Button {
                                                    visible: Boolean(uiController && uiController.epicService && uiController.epicService.eosOverlayInstalled)
                                                    text: "Remove"
                                                    buttonType: "destructive"
                                                    onClicked: if (uiController && uiController.epicService) uiController.epicService.removeEosOverlay()
                                                }
                                            }
                                        }

                                        SettingTile {
                                            label: "EAC Runtime"
                                            infoTip: "Proton EasyAntiCheat runtime (detected from Steam/Heroic or installed directly)"
                                            searchKeywords: "EasyAntiCheat EAC Proton Runtime Online Multiplayer"
                                            tabIndex: 3
                                            inlineControl: true
                                            controlItem: RowLayout {
                                                spacing: 8
                                                Label {
                                                    text: (uiController && uiController.runnerManager && uiController.runnerManager.isInstallingEac)
                                                        ? "Downloading…"
                                                        : ((uiController && uiController.runnerManager && uiController.runnerManager.eacRuntimeAvailable)
                                                            ? "Ready"
                                                            : "Not Found")
                                                    color: (uiController && uiController.runnerManager && uiController.runnerManager.eacRuntimeAvailable) ? appSettings.accentColor : appSettings.textSecColor
                                                    font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                }
                                                M3Button {
                                                    text: (uiController && uiController.runnerManager && uiController.runnerManager.eacRuntimeAvailable) ? "Reinstall" : "Install"
                                                    enabled: Boolean(uiController && uiController.runnerManager && !uiController.runnerManager.isInstallingEac)
                                                    buttonType: "tonal"
                                                    onClicked: if (uiController && uiController.runnerManager) uiController.runnerManager.installAntiCheatRuntime("eac_runtime")
                                                }
                                            }
                                        }

                                        SettingTile {
                                            label: "BattlEye"
                                            infoTip: "Proton BattlEye runtime (detected from Steam/Heroic or installed directly)"
                                            searchKeywords: "BattlEye Proton Runtime AntiCheat Online Multiplayer"
                                            tabIndex: 3
                                            inlineControl: true
                                            controlItem: RowLayout {
                                                spacing: 8
                                                Label {
                                                    text: (uiController && uiController.runnerManager && uiController.runnerManager.isInstallingBattleye)
                                                        ? "Downloading…"
                                                        : ((uiController && uiController.runnerManager && uiController.runnerManager.battleyeRuntimeAvailable)
                                                            ? "Ready"
                                                            : "Not Found")
                                                    color: (uiController && uiController.runnerManager && uiController.runnerManager.battleyeRuntimeAvailable) ? appSettings.accentColor : appSettings.textSecColor
                                                    font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                }
                                                M3Button {
                                                    text: (uiController && uiController.runnerManager && uiController.runnerManager.battleyeRuntimeAvailable) ? "Reinstall" : "Install"
                                                    enabled: Boolean(uiController && uiController.runnerManager && !uiController.runnerManager.isInstallingBattleye)
                                                    buttonType: "tonal"
                                                    onClicked: if (uiController && uiController.runnerManager) uiController.runnerManager.installAntiCheatRuntime("battleye_runtime")
                                                }
                                            }
                                        }
                                    }
                                }

                                // ══ TAB 4: SYSTEM ═════════════════════════
                                ColumnLayout {
                                    id: tabSystem
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    visible: settingsPage.activeTab === 4
                                    spacing: 14

                                    SettingsSection {
                                        sectionTitle: "Controller & Logs"

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: settingsCol.useTwoCols ? 2 : 1
                                            columnSpacing: 16
                                            rowSpacing: 4

                                            SettingTile {
                                                label: "Xbox Emulation"
                                                infoTip: "Emulate virtual Xbox controller via Linux /dev/uinput for non-XInput pads"
                                                tabIndex: 4
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    id: settingsXboxToggle
                                                    checked: appSettings.xboxEmulationDefault
                                                    Connections {
                                                        target: appSettings
                                                        function onControllerDefaultsChanged() {
                                                            settingsXboxToggle.checked = appSettings.xboxEmulationDefault
                                                        }
                                                    }
                                                    onToggled: (c) => appSettings.xboxEmulationDefault = c
                                                }
                                            }

                                            SettingTile {
                                                label: "Navigation HUD"
                                                infoTip: "Show control hints bar during keyboard/gamepad navigation"
                                                tabIndex: 4
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    id: settingsNavHudToggle
                                                    checked: appSettings.showNavigationHud
                                                    Connections {
                                                        target: appSettings
                                                        function onBehaviorChanged() {
                                                            settingsNavHudToggle.checked = appSettings.showNavigationHud
                                                        }
                                                    }
                                                    onToggled: (c) => appSettings.showNavigationHud = c
                                                }
                                            }

                                            SettingTile {
                                                label: "Debug Logs"
                                                infoTip: "Verbose +err,+warn Wine execution logs for diagnostics"
                                                searchKeywords: "Wine Debug Logs"
                                                tabIndex: 4
                                                inlineControl: true
                                                controlItem: Toggle {
                                                    checked: appSettings.enableWineDebugLogs
                                                    onToggled: (c) => appSettings.enableWineDebugLogs = c
                                                }
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Metadata"
                                        showDivider: true

                                        SettingTile {
                                            label: "SteamGridDB Key"
                                            infoTip: "Optional v2 Bearer key for artwork scraping (Steam CDN fallback runs automatically)"
                                            searchKeywords: "SteamGridDB API Key artwork"
                                            tabIndex: 4
                                            inlineControl: false
                                            fillControlWidth: true
                                            controlItem: M3TextField {
                                                Layout.fillWidth: true
                                                Layout.maximumWidth: 460
                                                placeholderText: "Enter SteamGridDB API key…"
                                                isPassword: true
                                                text: appSettings.steamGridDbApiKey
                                                onCommit: (val) => appSettings.steamGridDbApiKey = val
                                            }
                                        }
                                    }
                                }

                                // ══ TAB 5: ABOUT ══════════════════════════
                                ColumnLayout {
                                    id: tabAbout
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    visible: settingsPage.activeTab === 5
                                    spacing: 14

                                    // Compact Hero Card
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: heroRow.implicitHeight + 28
                                        radius: 16
                                        color: appSettings.surfaceContainer

                                        RowLayout {
                                            id: heroRow
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 14

                                            Rectangle {
                                                width: 48
                                                height: 48
                                                radius: 14
                                                color: appSettings.secondaryContainer

                                                YIcon {
                                                    anchors.centerIn: parent
                                                    source: "qrc:/tsuki_app/icons/brand/tsuki-sidebar.svg"
                                                    size: 28
                                                    color: appSettings.accentColor
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3

                                                RowLayout {
                                                    spacing: 8
                                                    Label {
                                                        text: "Tsuki"
                                                        color: appSettings.textColor
                                                        font.family: "Rubik"
                                                        font.pixelSize: 18
                                                        font.weight: Font.Bold
                                                        renderType: Text.QtRendering
                                                    }
                                                    Rectangle {
                                                        height: 20
                                                        radius: 10
                                                        implicitWidth: verLbl.implicitWidth + 14
                                                        color: appSettings.secondaryContainer
                                                        Label {
                                                            id: verLbl
                                                            objectName: "aboutVersionLabel"
                                                            anchors.centerIn: parent
                                                            text: "v" + (Qt.application.version || "0.1.1")
                                                            color: appSettings.onSecondaryContainer
                                                            font.family: "JetBrains Mono NF"
                                                            font.pixelSize: 11
                                                            font.weight: Font.Medium
                                                        }
                                                    }
                                                }

                                                Label {
                                                    text: "Native Linux Game Launcher · By Muzammil Shafique"
                                                    color: appSettings.textSecColor
                                                    font.family: "Rubik"
                                                    font.pixelSize: 13
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Project & Links"
                                        showDivider: true

                                        SettingTile {
                                            objectName: "aboutAuthorRow"
                                            label: "Muzammil Shafique"
                                            badgeText: "Author"
                                            badgeColor: appSettings.accentColor
                                            infoTip: "Creator and maintainer of Tsuki"
                                            searchKeywords: "Author GitHub repository source muzammilshafique link"
                                            tabIndex: 5
                                            inlineControl: true
                                            controlItem: RowLayout {
                                                spacing: 8

                                                Item {
                                                    implicitWidth: ghProfileBtn.implicitWidth
                                                    implicitHeight: ghProfileBtn.implicitHeight

                                                    M3Button {
                                                        id: ghProfileBtn
                                                        objectName: "githubAccountBtn"
                                                        text: "@muzammilshafique"
                                                        iconSymbol: "person"
                                                        buttonType: "tonal"
                                                        implicitHeight: 34
                                                        onClicked: Qt.openUrlExternally("https://github.com/muzammilshafique")
                                                    }
                                                    HoverHandler { id: ghProfileHover }
                                                    M3ToolTip {
                                                        visible: ghProfileHover.hovered
                                                        text: "https://github.com/muzammilshafique"
                                                    }
                                                }

                                                Item {
                                                    implicitWidth: ghRepoBtn.implicitWidth
                                                    implicitHeight: ghRepoBtn.implicitHeight

                                                    M3Button {
                                                        id: ghRepoBtn
                                                        objectName: "githubRepoBtn"
                                                        text: "Repository"
                                                        iconSymbol: "open_in_new"
                                                        buttonType: "outlined"
                                                        implicitHeight: 34
                                                        onClicked: Qt.openUrlExternally("https://github.com/muzammilshafique/tsuki")
                                                    }
                                                    HoverHandler { id: ghRepoHover }
                                                    M3ToolTip {
                                                        visible: ghRepoHover.hovered
                                                        text: "https://github.com/muzammilshafique/tsuki"
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Environment Checks"
                                        infoTip: "Live runtime capability checks from Diagnostics"
                                        showDivider: true

                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Repeater {
                                                model: (uiController && uiController.diagnosticsManager && uiController.diagnosticsManager.systemChecks)
                                                    ? uiController.diagnosticsManager.systemChecks : []
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    height: 32
                                                    radius: 16
                                                    implicitWidth: chkRow.implicitWidth + 20
                                                    color: appSettings.surfaceContainer

                                                    Row {
                                                        id: chkRow
                                                        anchors.centerIn: parent
                                                        spacing: 7
                                                        Rectangle {
                                                            width: 8
                                                            height: 8
                                                            radius: 4
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            color: modelData.ok ? "#22c55e" : "#f59e0b"
                                                        }
                                                        Label {
                                                            text: modelData.name || ""
                                                            color: appSettings.textColor
                                                            font.family: "Rubik"
                                                            font.pixelSize: 12
                                                            font.weight: Font.Medium
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }

                                                    HoverHandler { id: chkHover }
                                                    M3ToolTip {
                                                        visible: chkHover.hovered && Boolean(modelData.detail)
                                                        text: String(modelData.detail || "")
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Data Locations"
                                        showDivider: true

                                        Repeater {
                                            model: [
                                                { label: "Config", path: appSettings.configDirPath() },
                                                { label: "Data",   path: appSettings.dataDirPath() },
                                                { label: "Logs",   path: appSettings.logsDirPath() }
                                            ]
                                            delegate: SettingTile {
                                                required property var modelData
                                                label: modelData.label
                                                infoTip: modelData.path
                                                tabIndex: 5
                                                inlineControl: true
                                                controlItem: RowLayout {
                                                    spacing: 10
                                                    Label {
                                                        text: modelData.path
                                                        color: appSettings.textSecColor
                                                        font.family: "JetBrains Mono NF"
                                                        font.pixelSize: 12
                                                        elide: Text.ElideMiddle
                                                        Layout.maximumWidth: Math.max(160, settingsCol.width - 240)
                                                    }
                                                    M3Button {
                                                        text: "Open"
                                                        iconSymbol: "open_in_new"
                                                        buttonType: "tonal"
                                                        implicitHeight: 32
                                                        onClicked: if (uiController) uiController.openDirectory(modelData.path)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    SettingsSection {
                                        sectionTitle: "Shortcuts"
                                        showDivider: true

                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 10

                                            Repeater {
                                                model: [
                                                    { keys: "/  or  Ctrl+F", action: "Search settings" },
                                                    { keys: "[ / ]  or  L1 / R1", action: "Switch tabs" },
                                                    { keys: "↑ ↓ ← →", action: "Navigate & adjust" },
                                                    { keys: "Esc", action: "Close / Back" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    height: 34
                                                    radius: 17
                                                    implicitWidth: scRow.implicitWidth + 20
                                                    color: appSettings.surfaceContainer

                                                    Row {
                                                        id: scRow
                                                        anchors.centerIn: parent
                                                        spacing: 8
                                                        Rectangle {
                                                            height: 22
                                                            radius: 6
                                                            implicitWidth: scKeyLbl.implicitWidth + 12
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            color: appSettings.surfaceContainerHighest
                                                            border.color: appSettings.borderColor
                                                            border.width: 1
                                                            Label {
                                                                id: scKeyLbl
                                                                anchors.centerIn: parent
                                                                text: modelData.keys
                                                                color: appSettings.textColor
                                                                font.family: "JetBrains Mono NF"
                                                                font.pixelSize: 11
                                                                font.weight: Font.Medium
                                                            }
                                                        }
                                                        Label {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: modelData.action
                                                            color: appSettings.textSecColor
                                                            font.family: "Rubik"
                                                            font.pixelSize: 12
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
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

        Timer {
            id: tagModalOpenTimer
            interval: 0
            repeat: false
            onTriggered: tagColorsModal.focusModalItem(1)
        }

        Timer {
            id: tagModalCloseTimer
            interval: 0
            repeat: false
            onTriggered: tagColorsRow.forceActiveFocus()
        }

        onAboutToShow: {
            modalFocusIdx = 1
            if (tagPickerScroll && tagPickerScroll.contentItem) {
                tagPickerScroll.contentItem.contentY = 0
            }
        }

        onOpened: tagModalOpenTimer.restart()
        onClosed: tagModalCloseTimer.restart()

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
            radius: 16
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

            // Dialog Header
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 60

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 16
                    spacing: 12

                    Label {
                        text: "Runner & Platform Tag Colors"
                        color: appSettings.textColor
                        font.family: "Rubik"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        id: modalCloseBtn
                        readonly property bool isKeyFocused: activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 17
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

            // Live Badge Preview
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.topMargin: 14
                Layout.bottomMargin: 6
                Layout.preferredHeight: 68
                radius: 12
                color: appSettings.surfaceAltColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Label {
                        text: "PREVIEW"
                        color: appSettings.textSecColor
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1.0
                    }

                    RowLayout {
                        spacing: 10
                        Layout.fillWidth: true

                        Repeater {
                            model: [
                                { text: "PROTON",    col: appSettings.tagColorSteamProton },
                                { text: "PROTON-GE", col: appSettings.tagColorProtonGe },
                                { text: "CACHYOS",   col: appSettings.tagColorCachyos },
                                { text: "LINUX",     col: appSettings.tagColorLinux }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                implicitHeight: 24
                                implicitWidth: bdgTxt.implicitWidth + 16
                                radius: 6
                                color: Qt.rgba(Qt.color(modelData.col).r, Qt.color(modelData.col).g, Qt.color(modelData.col).b, 0.18)
                                border.color: Qt.rgba(Qt.color(modelData.col).r, Qt.color(modelData.col).g, Qt.color(modelData.col).b, 0.45)
                                border.width: 1
                                Text {
                                    id: bdgTxt
                                    anchors.centerIn: parent
                                    text: modelData.text
                                    color: modelData.col
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }

            // Scrollable Picker Body
            ScrollView {
                id: tagPickerScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(360, pickerCol.implicitHeight + 24)
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
                    spacing: 10

                    Item { Layout.preferredHeight: 6 }

                    Rectangle {
                        id: secProtonRow
                        Layout.fillWidth: true
                        implicitHeight: protonInnerCol.implicitHeight + 16
                        radius: 10
                        color: (tagPickerProton.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.08)
                            : "transparent"
                        border.color: (tagPickerProton.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? appSettings.accentColor : "transparent"
                        border.width: 1.5

                        ColumnLayout {
                            id: protonInnerCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6
                            Label {
                                text: "Proton"
                                color: appSettings.textColor
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
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
                        id: secGeRow
                        Layout.fillWidth: true
                        implicitHeight: geInnerCol.implicitHeight + 16
                        radius: 10
                        color: (tagPickerGe.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.08)
                            : "transparent"
                        border.color: (tagPickerGe.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? appSettings.accentColor : "transparent"
                        border.width: 1.5

                        ColumnLayout {
                            id: geInnerCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6
                            Label {
                                text: "Proton-GE"
                                color: appSettings.textColor
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
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
                        id: secCachyRow
                        Layout.fillWidth: true
                        implicitHeight: cachyInnerCol.implicitHeight + 16
                        radius: 10
                        color: (tagPickerCachy.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.08)
                            : "transparent"
                        border.color: (tagPickerCachy.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? appSettings.accentColor : "transparent"
                        border.width: 1.5

                        ColumnLayout {
                            id: cachyInnerCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6
                            Label {
                                text: "Proton-CachyOS"
                                color: appSettings.textColor
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
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
                        id: secLinuxRow
                        Layout.fillWidth: true
                        implicitHeight: linuxInnerCol.implicitHeight + 16
                        radius: 10
                        color: (tagPickerLinux.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.08)
                            : "transparent"
                        border.color: (tagPickerLinux.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                            ? appSettings.accentColor : "transparent"
                        border.width: 1.5

                        ColumnLayout {
                            id: linuxInnerCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6
                            Label {
                                text: "Linux Native"
                                color: appSettings.textColor
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
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

                    Item { Layout.preferredHeight: 8 }
                }
            }

            // Dialog Footer
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 60

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

    Timer {
        id: gsRestoreFocusTimer
        interval: 0
        repeat: false
        onTriggered: gamescopeDefaultsConfigRow.forceActiveFocus()
    }

    // ── Default Gamescope Parameters Dialog ─────────────────────────────────
    GamescopeDialog {
        id: gamescopeSettingsDialog
        onSaveRequested: (cfgMap) => {
            appSettings.defaultGamescopeConfig = cfgMap
        }
        onClosed: gsRestoreFocusTimer.restart()
    }
}
