import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Page {
    id: page

    signal gameDetailsRequested(string gameId, string epicAppName)
    signal settingsRequested()
    signal winetricksRequested(string prefixId, string title)
    property string activeSection: "library"
    property bool externalModalOpen: false
    property string _pendingFocusSection: ""
    property string _pendingAddGamePlatform: "windows"
    property string _runnersCategory: "proton-ge"

    readonly property bool isAddGameOpen: Boolean(addGameDialogLoader.item && addGameDialogLoader.item.visible)

    function openWinetricks(prefixId, title) {
        page.winetricksRequested(prefixId, title)
    }

    function openAddGameDialog(platform) {
        _pendingAddGamePlatform = (platform === "linux") ? "linux" : "windows"
        if (addGameDialogLoader.item) {
            addGameDialogLoader.item.resetAndOpen(_pendingAddGamePlatform)
        } else {
            addGameDialogLoader.active = true
        }
    }

    function isAnyModalOpen() {
        return page.isAddGameOpen || page.externalModalOpen || (topBar.visible && topBar.isAddMenuOpen)
    }

    function isTextInputActive() {
        const fi = page.Window.activeFocusItem
        if (!fi) return false
        const s = fi.toString()
        if (s.indexOf("M3TextField") !== -1) {
            return Boolean(fi.isEditing)
        }
        return s.indexOf("TextInput") !== -1 || s.indexOf("TextField") !== -1 || s.indexOf("TextArea") !== -1 || s.indexOf("TextEdit") !== -1
    }

    function _focusLoaderSection(sec, loader) {
        if (loader && loader.item && typeof loader.item.forceFocus === "function") {
            _pendingFocusSection = ""
            loader.item.forceFocus()
        } else {
            _pendingFocusSection = sec
        }
    }

    function focusActiveSectionContent() {
        if (page.activeSection === "library") {
            _pendingFocusSection = ""
            grid.forceFocus()
        } else if (page.activeSection === "epic") {
            _focusLoaderSection("epic", epicLoader)
        } else if (page.activeSection === "runners") {
            _focusLoaderSection("runners", runnersLoader)
        } else if (page.activeSection === "prefixes") {
            _focusLoaderSection("prefixes", prefixesLoader)
        } else if (page.activeSection === "diagnostics") {
            _focusLoaderSection("diagnostics", diagnosticsLoader)
        }
    }

    function cycleTab(delta) {
        const tabs = [
            { navIdx: 0, section: "library",     filter: -1 },
            { navIdx: 1, section: "library",     filter: 3 },
            { navIdx: 2, section: "epic",        filter: -1 },
            { navIdx: 4, section: "prefixes",    filter: -1 },
            { navIdx: 5, section: "runners",     filter: -1 },
            { navIdx: 6, section: "diagnostics", filter: -1 }
        ]
        let cur = 0
        for (let i = 0; i < tabs.length; ++i) {
            if (page.activeSection === "library") {
                if (tabs[i].section === "library" && tabs[i].filter === uiController.searchModel.filterType) {
                    cur = i
                    break
                }
            } else if (tabs[i].section === page.activeSection) {
                cur = i
                break
            }
        }
        const next = (cur + delta + tabs.length) % tabs.length
        const t = tabs[next]
        sidebar.focusedNavIndex = t.navIdx
        if (t.section === "library") {
            page.activeSection = "library"
            uiController.searchModel.filterType = t.filter
        } else {
            page.activeSection = t.section
        }
        Qt.callLater(focusActiveSectionContent)
    }

    background: Rectangle {
        color: appSettings.bgColor
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Component.onCompleted: {
        sidebar.filterRequested(appSettings.defaultFilter)
        grid.forceFocus()
    }

    StackView.onStatusChanged: {
        if (StackView.status === StackView.Active && !isAnyModalOpen()) {
            focusActiveSectionContent()
        }
    }

    Connections {
        target: uiController ? uiController.controllerManager : null
        function onSearchActionRequested() {
            if (page.StackView.status !== StackView.Active || page.isAnyModalOpen()) return
            page.activeSection = "library"
            uiController.setKeyboardNavActive(true)
            topBar.activateSearch()
        }
        function onTabLeftRequested() {
            if (page.StackView.status !== StackView.Active || page.isAnyModalOpen()) return
            page.cycleTab(-1)
        }
        function onTabRightRequested() {
            if (page.StackView.status !== StackView.Active || page.isAnyModalOpen()) return
            page.cycleTab(1)
        }
    }

    Keys.onPressed: (event) => {
        if (page.isAnyModalOpen() || page.isTextInputActive()) return
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_BracketLeft) {
            event.accepted = true
            page.cycleTab(-1)
        } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_BracketRight) {
            event.accepted = true
            page.cycleTab(1)
        }
    }

    Shortcut {
        sequences: ["/", "Ctrl+F"]
        enabled: page.visible && page.StackView.status === StackView.Active && !page.isAnyModalOpen() && !page.isTextInputActive()
        onActivated: {
            page.activeSection = "library"
            topBar.activateSearch()
        }
    }

    Timer {
        id: topBarOpenTimer
        interval: 0
        repeat: false
        onTriggered: topBar.openAddMenu()
    }

    Shortcut {
        sequences: ["Ctrl+N"]
        enabled: page.visible && !page.isAddGameOpen && !page.externalModalOpen
        onActivated: {
            if (page.activeSection !== "library") {
                page.activeSection = "library"
            }
            topBarOpenTimer.restart()
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            id: sidebar
            currentFilter: uiController.searchModel.filterType
            currentSection: page.activeSection
            onFilterRequested: (type) => {
                page.activeSection = "library"
                uiController.searchModel.filterType = type
            }
            onSectionRequested: (sec) => {
                page.activeSection = sec
            }
            onSettingsRequested: {
                page.settingsRequested()
            }
            onFocusContentRequested: {
                page.focusActiveSectionContent()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            TopBar {
                id: topBar
                visible: page.activeSection === "library"
                onVisibleChanged: if (!visible) closeAddMenu()
                onSearchRequested: (query) => {
                    uiController.search(query, sidebar.currentFilter)
                }
                onAddGameRequested: (platform) => page.openAddGameDialog(platform)
                onFocusGridRequested: grid.forceFocus()
                onFocusSidebarRequested: sidebar.forceActiveFocus()
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                MediaGrid {
                    id: grid
                    visible: page.activeSection === "library"
                    anchors.fill: parent
                    anchors.leftMargin: 32
                    anchors.rightMargin: 32
                    anchors.topMargin: 16
                    anchors.bottomMargin: 24
                    model: uiController.searchModel
                    onGameDetailsRequested: (gameId) => page.gameDetailsRequested(gameId, "")
                    onWinetricksRequested: (prefixId, title) => page.openWinetricks(prefixId, title)
                    onAddGameRequested: topBar.openAddMenu()
                    onFocusSidebarRequested: sidebar.forceActiveFocus()
                    onFocusTopBarRequested: topBar.forceSearchFocus()
                }

                Loader {
                    id: epicLoader
                    anchors.fill: parent
                    active: page.activeSection === "epic"
                    visible: active
                    source: active ? Qt.resolvedUrl("../pages/EpicLibraryView.qml") : ""
                    onLoaded: {
                        if (page._pendingFocusSection === "epic" && item) {
                            page._pendingFocusSection = ""
                            Qt.callLater(function() { if (epicLoader.item) epicLoader.item.forceFocus() })
                        }
                    }
                }
                Connections {
                    target: epicLoader.item
                    function onGameDetailsRequested(gameId, epicAppName) {
                        page.gameDetailsRequested(gameId, epicAppName)
                    }
                    function onFocusSidebarRequested() { sidebar.forceActiveFocus() }
                }

                Loader {
                    id: runnersLoader
                    anchors.fill: parent
                    active: page.activeSection === "runners"
                    visible: active
                    onActiveChanged: {
                        if (active) {
                            setSource(Qt.resolvedUrl("../pages/RunnersView.qml"), {
                                selectedReleaseCat: page._runnersCategory
                            })
                        } else {
                            setSource("")
                        }
                    }
                    onLoaded: {
                        if (page._pendingFocusSection === "runners" && item) {
                            page._pendingFocusSection = ""
                            Qt.callLater(function() { if (runnersLoader.item) runnersLoader.item.forceFocus() })
                        }
                    }
                }
                Connections {
                    target: runnersLoader.item
                    function onFocusSidebarRequested() { sidebar.forceActiveFocus() }
                    function onSelectedReleaseCatChanged() {
                        if (runnersLoader.item) {
                            page._runnersCategory = runnersLoader.item.selectedReleaseCat
                        }
                    }
                }

                Loader {
                    id: prefixesLoader
                    anchors.fill: parent
                    active: page.activeSection === "prefixes"
                    visible: active
                    source: active ? Qt.resolvedUrl("../pages/PrefixesView.qml") : ""
                    onLoaded: {
                        if (page._pendingFocusSection === "prefixes" && item) {
                            page._pendingFocusSection = ""
                            Qt.callLater(function() { if (prefixesLoader.item) prefixesLoader.item.forceFocus() })
                        }
                    }
                }
                Connections {
                    target: prefixesLoader.item
                    function onWinetricksRequested(prefixId, name) { page.openWinetricks(prefixId, name) }
                    function onFocusSidebarRequested() { sidebar.forceActiveFocus() }
                }

                Loader {
                    id: diagnosticsLoader
                    anchors.fill: parent
                    active: page.activeSection === "diagnostics"
                    visible: active
                    source: active ? Qt.resolvedUrl("../pages/DiagnosticsView.qml") : ""
                    onLoaded: {
                        if (page._pendingFocusSection === "diagnostics" && item) {
                            page._pendingFocusSection = ""
                            Qt.callLater(function() { if (diagnosticsLoader.item) diagnosticsLoader.item.forceFocus() })
                        }
                    }
                }
                Connections {
                    target: diagnosticsLoader.item
                    function onFocusSidebarRequested() { sidebar.forceActiveFocus() }
                }
            }
        }
    }

    Loader {
        id: addGameDialogLoader
        anchors.fill: parent
        active: false
        source: active ? Qt.resolvedUrl("../components/AddGameDialog.qml") : ""
        onLoaded: {
            if (item) {
                item.resetAndOpen(page._pendingAddGamePlatform)
            }
        }
    }

    Connections {
        target: addGameDialogLoader.item
        function onClosed() {
            Qt.callLater(function() {
                if (!addGameDialogLoader.item || !addGameDialogLoader.item.visible) {
                    addGameDialogLoader.active = false
                }
                if (!page.externalModalOpen && !topBar.isAddMenuOpen) {
                    page.focusActiveSectionContent()
                }
            })
        }
    }
}

