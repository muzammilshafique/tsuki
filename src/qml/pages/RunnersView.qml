import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../components"

Item {
    id: root
    property string selectedReleaseCat: "proton-ge"

    FolderDialog {
        id: customRunnerDirDialog
        title: "Select Custom Wine or Proton Directory"
        onAccepted: {
            let p = selectedFolder.toString()
            if (p.startsWith("file://")) p = p.substring(7)
            customPathField.text = p
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 24
        anchors.bottomMargin: 24
        spacing: 20

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            YIcon { source: "qrc:/tsuki_app/icons/nav/runner.svg"; color: appSettings.accentColor; size: 28 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Label { text: "Wine & Proton Runner Management"; color: appSettings.textColor; font.pixelSize: 22; font.weight: Font.Bold }
                Label { text: "Manage installed Wine, Wine-Staging, Proton, Proton-GE, and custom builds or download releases from GitHub"; color: appSettings.textSecColor; font.pixelSize: 13 }
            }
            Button {
                text: "Re-scan System Runners"
                onClicked: uiController.runnerManager.detectInstalledRunners()
                background: Rectangle { radius: 18; color: appSettings.surfaceColor; border.color: appSettings.accentColor }
                contentItem: Label { text: parent.text; color: appSettings.accentColor; font.pixelSize: 13; font.weight: Font.DemiBold; leftPadding: 14; rightPadding: 14 }
            }
        }

        // Split 2-Column Layout: Installed Runners (Left) & Downloadable Releases / Custom Runner (Right)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20

            // Left Column: Installed Runners
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    Label {
                        text: "Installed Runners (" + uiController.runnerManager.installedRunners.length + ")"
                        color: appSettings.textColor
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 10
                        model: uiController.runnerManager.installedRunners
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 78
                            radius: 12
                            color: appSettings.surfaceAltColor
                            border.color: modelData.isDefault ? appSettings.accentColor : appSettings.borderColor
                            border.width: modelData.isDefault ? 2 : 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        spacing: 8
                                        Label {
                                            text: modelData.name
                                            color: appSettings.textColor
                                            font.pixelSize: 15
                                            font.weight: Font.DemiBold
                                        }
                                        Rectangle {
                                            radius: 4
                                            color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.18)
                                            implicitWidth: rTypeLbl.implicitWidth + 10; implicitHeight: 20
                                            Label {
                                                id: rTypeLbl
                                                anchors.centerIn: parent
                                                text: modelData.type.toUpperCase()
                                                color: appSettings.accentColor
                                                font.pixelSize: 10; font.weight: Font.Bold
                                            }
                                        }
                                        Rectangle {
                                            visible: modelData.isDefault
                                            radius: 4
                                            color: "#34d399"
                                            implicitWidth: defLbl.implicitWidth + 10; implicitHeight: 20
                                            Label {
                                                id: defLbl
                                                anchors.centerIn: parent
                                                text: "GLOBAL DEFAULT"
                                                color: "#0f0f11"
                                                font.pixelSize: 10; font.weight: Font.Bold
                                            }
                                        }
                                    }
                                    Label {
                                        text: modelData.binaryPath
                                        color: appSettings.textSecColor
                                        font.pixelSize: 11
                                        font.family: "monospace"
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                }

                                Button {
                                    visible: !modelData.isDefault
                                    text: "Set Default"
                                    onClicked: {
                                        appSettings.defaultRunnerId = modelData.id
                                        uiController.runnerManager.detectInstalledRunners()
                                    }
                                }

                                Button {
                                    visible: !modelData.isSystem
                                    text: "Remove"
                                    onClicked: uiController.runnerManager.removeRunner(modelData.id, true)
                                    background: Rectangle { radius: 8; color: Qt.rgba(239/255, 68/255, 68/255, 0.16); border.color: "#ef4444" }
                                    contentItem: Label { text: "Remove"; color: "#ef4444"; font.pixelSize: 12; leftPadding: 10; rightPadding: 10 }
                                }
                            }
                        }
                    }

                    // Add Custom Build Box
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: customCol.implicitHeight + 20
                        radius: 10
                        color: appSettings.inputColor
                        border.color: appSettings.borderColor

                        ColumnLayout {
                            id: customCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Label { text: "Register Custom Wine / Proton Build"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                TextField {
                                    id: customNameField
                                    Layout.preferredWidth: 150
                                    placeholderText: "Build Name"
                                    color: appSettings.textColor
                                    placeholderTextColor: appSettings.textTerColor
                                    font.pixelSize: 12
                                    background: Rectangle { radius: 6; color: appSettings.surfaceColor; border.color: appSettings.borderColor }
                                }
                                TextField {
                                    id: customPathField
                                    Layout.fillWidth: true
                                    placeholderText: "/path/to/runner/folder or wine binary"
                                    color: appSettings.textColor
                                    placeholderTextColor: appSettings.textTerColor
                                    font.pixelSize: 12
                                    background: Rectangle { radius: 6; color: appSettings.surfaceColor; border.color: appSettings.borderColor }
                                }
                                Button { text: "Browse…"; onClicked: customRunnerDirDialog.open() }
                                Button {
                                    text: "Add"
                                    onClicked: {
                                        if (uiController.runnerManager.addCustomRunner(customNameField.text, "custom", "Custom", customPathField.text)) {
                                            customNameField.text = ""
                                            customPathField.text = ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Right Column: Download Runners, DXVK & VKD3D
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "Download Runners & Vulkan Layers"
                            color: appSettings.textColor
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                        BusyIndicator {
                            running: uiController.runnerManager.isFetchingReleases
                            visible: running
                            implicitWidth: 24; implicitHeight: 24
                        }
                    }

                    // Category Switcher
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [
                                { label: "Proton-GE", key: "proton-ge" },
                                { label: "Wine-Staging", key: "wine-staging" },
                                { label: "Wine", key: "wine" },
                                { label: "DXVK", key: "dxvk" },
                                { label: "VKD3D-Proton", key: "vkd3d" }
                            ]
                            delegate: Button {
                                required property var modelData
                                text: modelData.label
                                onClicked: {
                                    root.selectedReleaseCat = modelData.key
                                    uiController.runnerManager.fetchAvailableReleases(modelData.key)
                                }
                                background: Rectangle {
                                    radius: 14
                                    color: root.selectedReleaseCat === modelData.key ? appSettings.accentColor : appSettings.surfaceAltColor
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: root.selectedReleaseCat === modelData.key ? "#0f0f11" : appSettings.textColor
                                    font.pixelSize: 12
                                    font.weight: root.selectedReleaseCat === modelData.key ? Font.DemiBold : Font.Normal
                                    leftPadding: 10; rightPadding: 10
                                }
                            }
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: uiController.runnerManager.availableReleases
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 64
                            radius: 10
                            color: appSettings.surfaceAltColor
                            border.color: appSettings.borderColor

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Label {
                                        text: modelData.name
                                        color: appSettings.textColor
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }
                                    Label {
                                        text: modelData.publishedAt + "  •  " + modelData.sizeFormatted
                                        color: appSettings.textSecColor
                                        font.pixelSize: 12
                                    }
                                }

                                Button {
                                    text: "Download & Install"
                                    onClicked: {
                                        uiController.runnerManager.downloadAndInstallRunner(
                                            modelData.tagName,
                                            modelData.category,
                                            modelData.downloadUrl,
                                            modelData.fileName
                                        )
                                    }
                                    background: Rectangle { radius: 16; color: appSettings.accentColor }
                                    contentItem: Label {
                                        text: parent.text
                                        color: "#0f0f11"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        leftPadding: 14; rightPadding: 14
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

