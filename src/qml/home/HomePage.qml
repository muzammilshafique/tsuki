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

    background: Rectangle {
        color: appSettings.bgColor
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Component.onCompleted: {
        sidebar.filterRequested(appSettings.defaultFilter)
        grid.forceFocus()
    }

    StackView.onStatusChanged: {
        if (StackView.status === StackView.Active && page.activeSection === "library") {
            grid.forceFocus()
        }
    }

    Shortcut {
        sequences: ["/", "Ctrl+F"]
        enabled: page.visible && page.activeSection === "library"
        onActivated: topBar.activateSearch()
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
                if (page.activeSection === "library") grid.forceFocus()
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
                    visible: page.activeSection === "runners"
                    anchors.fill: parent
                }

                PrefixesView {
                    visible: page.activeSection === "prefixes"
                    anchors.fill: parent
                    onWinetricksRequested: (prefixId, name) => winetricksModal.openForPrefix(prefixId, name)
                }

                DiagnosticsView {
                    visible: page.activeSection === "diagnostics"
                    anchors.fill: parent
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

