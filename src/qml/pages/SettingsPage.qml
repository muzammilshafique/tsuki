import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Page {
    id: settingsPage
    signal backRequested()

    background: Rectangle {
        color: appSettings.bgColor
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    focus: true

    Keys.onEscapePressed: (event) => {
        event.accepted = true
        settingsPage.backRequested()
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
            let p = targetItem.mapToItem(settingsCol, 0, 0)
            let maxScrollY = Math.max(0, settingsScroll.contentHeight - settingsScroll.height)
            let desiredY = Math.min(Math.max(0, p.y - 20), maxScrollY)
            settingsScroll.ScrollBar.vertical.position = (maxScrollY > 0 && settingsScroll.contentHeight > 0)
                ? (desiredY / settingsScroll.contentHeight)
                : 0
            if (typeof targetItem.highlight === "function") {
                targetItem.highlight()
            }
        })
    }

    Component.onCompleted: {
        Qt.callLater(buildIndex)
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

                readonly property bool isBtnActive: backBtn.hovered || backBtn.activeFocus
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
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            // Center: Material 3 Search Bar Pill
            Rectangle {
                id: searchTile
                anchors.centerIn: parent
                width: Math.min(420, Math.max(260, parent.width - 320))
                height: 40
                radius: 20
                color: searchField.activeFocus
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                    : (searchTileHover.hovered
                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06))
                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)))

                border.color: searchField.activeFocus
                    ? appSettings.accentColor
                    : (searchTileHover.hovered
                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14))
                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)))
                border.width: searchField.activeFocus ? 2 : 1

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                HoverHandler { id: searchTileHover; cursorShape: Qt.IBeamCursor }

                YIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    size: 16
                    source: "qrc:/tsuki_app/icons/actions/search.svg"
                    color: searchField.activeFocus ? appSettings.accentColor : appSettings.textSecColor
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
                    rightPadding: (clearSearchBtn.visible ? 34 : 14)
                    selectByMouse: true
                    background: null
                    renderType: Text.QtRendering
                    verticalAlignment: Text.AlignVCenter

                    onTextChanged: settingsPage.updateSearchResults(text)

                    Keys.onDownPressed: (event) => {
                        if (searchResultsPopup.visible && settingsPage.searchResults.length > 0) {
                            event.accepted = true
                            settingsPage.focusedResultIndex = (settingsPage.focusedResultIndex + 1) % settingsPage.searchResults.length
                            sResListView.positionViewAtIndex(settingsPage.focusedResultIndex, ListView.Contain)
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
                            searchField.focus = false
                        }
                    }
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

    // ── Settings Scroll Content ──────────────────────────────────────────────
    ScrollView {
        id: settingsScroll
        anchors.top: settingsHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: availableWidth
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

                // Theme Mode
                SettingRow {
                    label: "Theme Mode"
                    description: "Select light, dark, or system mode to follow the OS desktop appearance"
                    controlItem: M3SegmentedButton {
                        model: [
                            { label: "Dark", val: 0 },
                            { label: "Light", val: 1 },
                            { label: "System", val: 2 }
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
                        presets: [
                            { name: "Blue",   color: "#5b9cf6" },
                            { name: "Purple", color: "#9c27b0" },
                            { name: "Pink",   color: "#ec4899" },
                            { name: "Red",    color: "#ef4444" },
                            { name: "Orange", color: "#f97316" },
                            { name: "Green",  color: "#10b981" },
                            { name: "Slate",  color: "#94a3b8" }
                        ]
                        currentColor: String(appSettings.accentColor)
                        onColorSelected: (hex) => appSettings.accentColor = hex
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
                            text: "Browse…"
                            iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                            buttonType: "tonal"
                            onClicked: {
                                let p = uiController.selectFolder("Select Default Prefix Location", appSettings.defaultPrefixLocation)
                                if (p && p.length > 0) appSettings.defaultPrefixLocation = p
                            }
                        }
                    }
                }

                RowDiv {}

                // Default Runner Download Location (Native system folder picker)
                SettingRow {
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
                            text: "Browse…"
                            iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                            buttonType: "tonal"
                            onClicked: {
                                let p = uiController.selectFolder("Select Runner Download Location", appSettings.defaultRunnerLocation)
                                if (p && p.length > 0) appSettings.defaultRunnerLocation = p
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
                            uiController.gameManager.syncXboxEmulationToAllGames(c)
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
}
