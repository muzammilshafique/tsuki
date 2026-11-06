import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 48 : 800, 800)
    height: Math.min(parent ? parent.height - 48 : 660, 660)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string prefixId: "default-prefix"
    property string prefixName: "Default"
    property string activeCategory: "all"
    property string searchQuery: ""
    property var filteredItems: []

    function openForPrefix(id, name) {
        prefixId = id || "default-prefix"
        prefixName = name || "Default"
        activeCategory = "all"
        searchQuery = ""
        refreshList()
        root.open()
    }

    function refreshList() {
        filteredItems = uiController.winetricksManager.filterCatalog(activeCategory, searchQuery, prefixId)
    }

    Connections {
        target: uiController.winetricksManager
        function onCatalogChanged() { root.refreshList() }
    }

    background: Rectangle {
        color: appSettings.surfaceColor
        radius: 24
        border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.65)
            shadowBlur: 0.8
            shadowVerticalOffset: 8
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Header Row ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 70

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 20
                spacing: 12

                YIcon {
                    size: 24
                    source: "qrc:/tsuki_app/icons/actions/wrench.svg"
                    color: "#38bdf8"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: "Winetricks — " + root.prefixName
                        color: appSettings.textColor
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.3
                    }
                    Label {
                        text: "Install Visual C++, DirectX, .NET, and Windows system components directly into this prefix"
                        color: appSettings.textSecColor
                        font.pixelSize: 12
                    }
                }

                M3Button {
                    text: "Native GUI"
                    buttonType: "outlined"
                    onClicked: uiController.winetricksManager.launchWinetricksGui(root.prefixId)
                }

                ToolButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    background: Rectangle {
                        radius: 18
                        color: parent.hovered ? appSettings.surfaceAltColor : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    contentItem: YIcon {
                        anchors.centerIn: parent
                        source: "qrc:/tsuki_app/icons/actions/close.svg"
                        color: appSettings.textSecColor
                        size: 18
                    }
                    onClicked: root.close()
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

        // ── Filter Toolbar (Pill Chips + Search) ─────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 8

                Repeater {
                    model: [
                        { label: "All Packages", key: "all" },
                        { label: "Visual C++", key: "vcpp" },
                        { label: "DirectX & Audio", key: "directx" },
                        { label: "DLLs & .NET", key: "dlls" },
                        { label: "Fonts", key: "fonts" }
                    ]
                    delegate: Rectangle {
                        id: catTabDelegate
                        required property var modelData
                        readonly property bool isSelected: root.activeCategory === modelData.key
                        height: 32
                        width: catLabel.implicitWidth + 24
                        radius: 16
                        color: isSelected 
                            ? appSettings.accentColor 
                            : (catMA.containsMouse ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)) : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)))
                        border.color: isSelected ? appSettings.accentColor : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Label {
                            id: catLabel
                            anchors.centerIn: parent
                            text: (catTabDelegate.modelData && catTabDelegate.modelData.label) ? catTabDelegate.modelData.label : ""
                            color: catTabDelegate.isSelected ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : appSettings.textColor
                            font.pixelSize: 12
                            font.weight: catTabDelegate.isSelected ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            id: catMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.activeCategory = catTabDelegate.modelData.key
                                root.refreshList()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                M3TextField {
                    implicitWidth: 230
                    placeholderText: "Search verbs (e.g. vcrun2022)…"
                    leadingIcon: "qrc:/tsuki_app/icons/actions/search.svg"
                    onCommit: (val) => {
                        root.searchQuery = val
                        root.refreshList()
                    }
                    onCleared: {
                        root.searchQuery = ""
                        root.refreshList()
                    }
                }
            }
        }

        // ── Package Verb List ────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: verbListView
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.bottomMargin: 12
                spacing: 6
                clip: true
                model: root.filteredItems

                delegate: Rectangle {
                    id: verbRow
                    required property var modelData
                    readonly property bool isVerbInstalling: uiController.winetricksManager.isRunning && uiController.winetricksManager.currentVerb === verbRow.modelData.verb
                    readonly property bool isVerbInstalled: Boolean(verbRow.modelData.isInstalled)
                    width: verbListView.width
                    height: 52
                    radius: 12
                    color: rowMA.containsMouse 
                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03))
                    border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        // Verb Name
                        Label {
                            text: verbRow.modelData.verb
                            color: appSettings.textColor
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            Layout.preferredWidth: 160
                            elide: Text.ElideRight
                        }

                        // Category Pill
                        Rectangle {
                            height: 20
                            radius: 4
                            width: catText.implicitWidth + 12
                            color: Qt.rgba(56/255, 189/255, 248/255, 0.15)
                            border.color: Qt.rgba(56/255, 189/255, 248/255, 0.4)
                            border.width: 1

                            Label {
                                id: catText
                                anchors.centerIn: parent
                                text: verbRow.modelData.category
                                color: "#38bdf8"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }
                        }

                        // Description
                        Label {
                            Layout.fillWidth: true
                            text: verbRow.modelData.description
                            color: appSettings.textSecColor
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        // Status / Action
                        Item {
                            implicitWidth: 110
                            implicitHeight: 34

                            // 1. Installed Badge (Clean Pill)
                            Rectangle {
                                anchors.centerIn: parent
                                visible: verbRow.isVerbInstalled && !verbRow.isVerbInstalling
                                height: 28
                                radius: 14
                                implicitWidth: instRow.implicitWidth + 18
                                color: Qt.rgba(34/255, 197/255, 94/255, 0.12)
                                border.color: Qt.rgba(34/255, 197/255, 94/255, 0.35)
                                border.width: 1

                                RowLayout {
                                    id: instRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    YIcon {
                                        size: 14
                                        source: "qrc:/tsuki_app/icons/actions/check.svg"
                                        color: "#22c55e"
                                    }
                                    Label {
                                        text: "Installed"
                                        color: "#22c55e"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            // 2. Installing Spinner
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                visible: verbRow.isVerbInstalling

                                BusyIndicator {
                                    width: 18; height: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    running: verbRow.isVerbInstalling
                                }
                                Label {
                                    text: "Installing…"
                                    color: appSettings.accentColor
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // 3. Install Button
                            M3Button {
                                anchors.centerIn: parent
                                visible: !verbRow.isVerbInstalled && !verbRow.isVerbInstalling
                                text: "Install"
                                buttonType: "tonal"
                                implicitHeight: 32
                                enabled: !uiController.winetricksManager.isRunning
                                onClicked: {
                                    uiController.winetricksManager.installVerb(root.prefixId, verbRow.modelData.verb)
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: rowMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {}
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }

        // ── Footer ───────────────────────────────────────────────────────────
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

                Label {
                    text: (uiController && uiController.winetricksManager && uiController.winetricksManager.lastStatus) ? uiController.winetricksManager.lastStatus : ""
                    color: appSettings.textSecColor
                    font.pixelSize: 12
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                M3Button {
                    text: "Close"
                    buttonType: "tonal"
                    onClicked: root.close()
                }
            }
        }
    }
}
