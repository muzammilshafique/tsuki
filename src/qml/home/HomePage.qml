import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../pages"

Page {
    id: page

    signal gameDetailsRequested(string gameId)
    signal settingsRequested()
    property string activeSection: "library"

    function openWinetricks(prefixId, title) {
        winetricksModal.openForPrefix(prefixId, title)
    }

    function isAnyModalOpen() {
        return addGameDialog.visible || winetricksModal.visible
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

    function focusActiveSectionContent() {
        if (page.activeSection === "library") grid.forceFocus()
        else if (page.activeSection === "runners") runnersView.forceFocus()
        else if (page.activeSection === "prefixes") prefixesView.forceFocus()
        else if (page.activeSection === "diagnostics") diagnosticsView.forceFocus()
    }

    function cycleTab(delta) {
        const tabs = [
            { navIdx: 0, section: "library",     filter: -1 },
            { navIdx: 1, section: "library",     filter: 3 },
            { navIdx: 2, section: "library",     filter: 4 },
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

    Shortcut {
        sequences: ["Ctrl+N"]
        enabled: page.visible
        onActivated: addGameDialog.resetAndOpen()
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
                onSearchRequested: (query) => {
                    uiController.search(query, sidebar.currentFilter)
                }
                onAddGameRequested: addGameDialog.resetAndOpen()
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
                    onGameDetailsRequested: (gameId) => page.gameDetailsRequested(gameId)
                    onWinetricksRequested: (prefixId, title) => winetricksModal.openForPrefix(prefixId, title)
                    onAddGameRequested: addGameDialog.resetAndOpen()
                    onFocusSidebarRequested: sidebar.forceActiveFocus()
                    onFocusTopBarRequested: topBar.forceSearchFocus()
                }

                RunnersView {
                    id: runnersView
                    visible: page.activeSection === "runners"
                    anchors.fill: parent
                    onFocusSidebarRequested: sidebar.forceActiveFocus()
                }

                PrefixesView {
                    id: prefixesView
                    visible: page.activeSection === "prefixes"
                    anchors.fill: parent
                    onWinetricksRequested: (prefixId, name) => winetricksModal.openForPrefix(prefixId, name)
                    onFocusSidebarRequested: sidebar.forceActiveFocus()
                }

                DiagnosticsView {
                    id: diagnosticsView
                    visible: page.activeSection === "diagnostics"
                    anchors.fill: parent
                    onFocusSidebarRequested: sidebar.forceActiveFocus()
                }
            }
        }
    }

    AddGameDialog {
        id: addGameDialog
    }

    WinetricksModal {
        id: winetricksModal
    }
}

