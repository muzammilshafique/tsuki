import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 64 : 760, 760)
    height: Math.min(parent ? parent.height - 64 : 640, 640)
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    padding: 24
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
        wtSearchInput.text = ""
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
        radius: 16
        border.color: appSettings.borderColor
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.65)
            shadowBlur: 0.9
            shadowVerticalOffset: 8
        }
    }

    contentItem: ColumnLayout {
        spacing: 14

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            YIcon { source: "qrc:/tsuki_app/icons/actions/wrench.svg"; color: appSettings.accentColor; size: 22 }
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                Label {
                    text: "Winetricks — Prefix: " + root.prefixName
                    color: appSettings.textColor
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
                Label {
                    text: "Install Visual C++ runtimes, DirectX, .NET, DLLs, and Windows fonts directly into this prefix"
                    color: appSettings.textSecColor
                    font.pixelSize: 12
                }
            }
            Button {
                text: "Native Winetricks GUI"
                onClicked: uiController.winetricksManager.launchWinetricksGui(root.prefixId)
                background: Rectangle { radius: 16; color: appSettings.surfaceAltColor; border.color: appSettings.borderColor }
                contentItem: Label { text: parent.text; color: appSettings.textColor; font.pixelSize: 12; leftPadding: 12; rightPadding: 12 }
            }
            ToolButton {
                implicitWidth: 32; implicitHeight: 32
                background: Rectangle { radius: 16; color: parent.hovered ? appSettings.surfaceAltColor : "transparent" }
                contentItem: YIcon { anchors.centerIn: parent; source: "qrc:/tsuki_app/icons/actions/close.svg"; color: appSettings.textSecColor; size: 18 }
                onClicked: root.close()
            }
        }

        // Category Filter + Search Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { label: "All Packages", key: "all" },
                    { label: "Visual C++", key: "vcpp" },
                    { label: "DirectX & Audio", key: "directx" },
                    { label: "DLLs & .NET", key: "dlls" },
                    { label: "Fonts", key: "fonts" }
                ]
                delegate: Button {
                    required property var modelData
                    text: modelData.label
                    onClicked: {
                        root.activeCategory = modelData.key
                        root.refreshList()
                    }
                    background: Rectangle {
                        radius: 16
                        color: root.activeCategory === modelData.key ? appSettings.accentColor : appSettings.surfaceAltColor
                    }
                    contentItem: Label {
                        text: parent.text
                        color: root.activeCategory === modelData.key ? "#0f0f11" : appSettings.textColor
                        font.pixelSize: 12
                        font.weight: root.activeCategory === modelData.key ? Font.DemiBold : Font.Normal
                        leftPadding: 12; rightPadding: 12
                    }
                }
            }

            Item { Layout.fillWidth: true }

            TextField {
                id: wtSearchInput
                Layout.preferredWidth: 220
                placeholderText: "Filter verbs (e.g. vcrun2022)…"
                color: appSettings.textColor
                placeholderTextColor: appSettings.textTerColor
                font.pixelSize: 13
                leftPadding: 12; rightPadding: 12
                onTextChanged: {
                    root.searchQuery = text
                    root.refreshList()
                }
                background: Rectangle {
                    radius: 16
                    color: appSettings.inputColor
                    border.color: parent.activeFocus ? appSettings.accentColor : appSettings.borderColor
                }
            }
        }

        // Verb List
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: root.filteredItems
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 62
                radius: 10
                color: appSettings.surfaceAltColor
                border.color: modelData.isInstalled ? appSettings.accentColor : appSettings.borderColor
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        RowLayout {
                            spacing: 8
                            Label {
                                text: modelData.title
                                color: appSettings.textColor
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                            Rectangle {
                                radius: 4
                                color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.16)
                                implicitWidth: verbCodeLbl.implicitWidth + 10
                                implicitHeight: 20
                                Label {
                                    id: verbCodeLbl
                                    anchors.centerIn: parent
                                    text: modelData.verb
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                }
                            }
                        }
                        Label {
                            text: modelData.description
                            color: appSettings.textSecColor
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Button {
                        visible: modelData.isInstalled
                        text: "Remove"
                        onClicked: uiController.winetricksManager.removeComponent(root.prefixId, modelData.verb)
                        background: Rectangle { radius: 16; color: Qt.rgba(239/255, 68/255, 68/255, 0.16); border.color: "#ef4444" }
                        contentItem: Label { text: parent.text; color: "#ef4444"; font.pixelSize: 12; leftPadding: 12; rightPadding: 12 }
                    }

                    Button {
                        enabled: !uiController.winetricksManager.isRunning
                        text: modelData.isInstalled ? "Reinstall" : "Install"
                        onClicked: uiController.winetricksManager.installVerb(root.prefixId, modelData.verb)
                        background: Rectangle {
                            radius: 16
                            color: parent.enabled ? appSettings.accentColor : appSettings.inputColor
                        }
                        contentItem: Label {
                            text: parent.text
                            color: parent.enabled ? "#0f0f11" : appSettings.textTerColor
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            leftPadding: 14; rightPadding: 14
                        }
                    }
                }
            }
        }

        // Live Operation Output Console
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            radius: 10
            color: "#09090c"
            border.color: appSettings.borderColor

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: uiController.winetricksManager.isRunning
                              ? ("Running winetricks: " + uiController.winetricksManager.currentVerb + "…")
                              : "Winetricks Operation Output"
                        color: uiController.winetricksManager.isRunning ? appSettings.accentColor : appSettings.textSecColor
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    Button {
                        visible: uiController.winetricksManager.isRunning
                        text: "Cancel"
                        onClicked: uiController.winetricksManager.cancelCurrentOperation()
                    }
                    Button {
                        text: "Clear"
                        onClicked: uiController.winetricksManager.clearLiveOutput()
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    TextArea {
                        readOnly: true
                        text: uiController.winetricksManager.liveOutput
                        color: "#d4d4d8"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: TextEdit.Wrap
                        background: null
                    }
                }
            }
        }
    }
}

