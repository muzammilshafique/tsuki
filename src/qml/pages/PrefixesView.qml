import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    signal winetricksRequested(string prefixId, string prefixName)

    property string targetPrefixForInstaller: "default-prefix"

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 24
        anchors.bottomMargin: 24
        spacing: 18

        // ── Header ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            YIcon {
                source: "qrc:/tsuki_app/icons/nav/prefixes.svg"
                color: appSettings.accentColor
                size: 28
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Label {
                    text: "Wine Prefixes"
                    color: appSettings.textColor
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                }
                Label {
                    text: "Manage isolated Wine environments, DLL overrides, Windows versions, backups, and installers"
                    color: appSettings.textSecColor
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                M3Button {
                    text: "Import Prefix…"
                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                    buttonType: "tonal"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        let p = uiController.selectFolder("Select Existing Wine or Proton Prefix Folder to Import", "")
                        if (p && p.length > 0) {
                            let name = p.substring(p.lastIndexOf("/") + 1)
                            uiController.prefixManager.importPrefix(name, p)
                        }
                    }
                }

                M3Button {
                    text: "Restore Backup…"
                    iconSource: "qrc:/tsuki_app/icons/actions/refresh.svg"
                    buttonType: "tonal"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        let p = uiController.selectFile("Select Prefix Backup Archive (.tar.gz / .tar.zst)", "Tar Archives (*.tar.gz *.tar.zst *.tar.xz *.tar);;All Files (*)", "")
                        if (p && p.length > 0) {
                            uiController.prefixManager.restorePrefix(p, "", "")
                        }
                    }
                }
            }
        }

        // ── Create New Prefix Card ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: createRow.implicitHeight + 24
            radius: 16
            color: appSettings.surfaceColor
            border.color: appSettings.borderColor

            RowLayout {
                id: createRow
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Label {
                    text: "Create Prefix:"
                    color: appSettings.textColor
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignVCenter
                }

                M3TextField {
                    id: newPfxNameField
                    Layout.preferredWidth: 200
                    placeholderText: "Prefix Name (e.g. gta-v)"
                    Layout.alignment: Qt.AlignVCenter
                }

                M3SegmentedButton {
                    id: archSegBtn
                    Layout.preferredWidth: 150
                    model: [
                        { label: "win64", val: 0 },
                        { label: "win32", val: 1 }
                    ]
                    selectedValue: 0
                    Layout.alignment: Qt.AlignVCenter
                }

                M3TextField {
                    id: newPfxPathField
                    Layout.fillWidth: true
                    text: appSettings.defaultPrefixLocation
                    Layout.alignment: Qt.AlignVCenter
                }

                M3Button {
                    text: "Folder…"
                    buttonType: "tonal"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        let p = uiController.selectFolder("Select Custom Prefix Location", newPfxPathField.text)
                        if (p && p.length > 0) {
                            newPfxPathField.text = p
                        }
                    }
                }

                M3Button {
                    text: "Create"
                    iconSource: "qrc:/tsuki_app/icons/actions/add.svg"
                    buttonType: "filled"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        if (newPfxNameField.text.trim().length > 0) {
                            let arch = archSegBtn.selectedValue === 0 ? "win64" : "win32"
                            uiController.prefixManager.createPrefix(
                                newPfxNameField.text.trim(),
                                newPfxPathField.text.trim(),
                                arch,
                                "win10"
                            )
                            newPfxNameField.text = ""
                        }
                    }
                }
            }
        }

        // ── Prefixes List ────────────────────────────────────────────────────
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 12
            model: uiController.prefixManager.prefixes
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: pfxCard
                required property var modelData
                width: ListView.view.width
                implicitHeight: cardInner.implicitHeight + 28
                radius: 16
                color: appSettings.surfaceColor
                border.color: Boolean(modelData.isDefault) ? appSettings.accentColor : appSettings.borderColor
                border.width: Boolean(modelData.isDefault) ? 2 : 1

                RowLayout {
                    id: cardInner
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.topMargin: 14
                    anchors.bottomMargin: 14
                    spacing: 16

                    // Left Column: Prefix Name + Badges, and Path underneath
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6

                        RowLayout {
                            spacing: 8
                            Layout.alignment: Qt.AlignVCenter

                            Label {
                                text: (pfxCard.modelData && pfxCard.modelData.name) || ""
                                color: appSettings.textColor
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Rectangle {
                                visible: Boolean(pfxCard.modelData && pfxCard.modelData.isDefault)
                                height: 20
                                width: 62
                                radius: 4
                                Layout.alignment: Qt.AlignVCenter
                                color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.2)
                                Label { anchors.centerIn: parent; text: "DEFAULT"; color: appSettings.accentColor; font.pixelSize: 10; font.weight: Font.Bold }
                            }

                            Rectangle {
                                height: 20
                                width: 48
                                radius: 4
                                Layout.alignment: Qt.AlignVCenter
                                color: Qt.rgba(56/255, 189/255, 248/255, 0.15)
                                Label {
                                    anchors.centerIn: parent
                                    text: (pfxCard.modelData && pfxCard.modelData.arch) ? String(pfxCard.modelData.arch).toUpperCase() : "WIN64"
                                    color: "#38bdf8"
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                }
                            }
                        }

                        Label {
                            text: pfxCard.modelData.path
                            color: appSettings.textSecColor
                            font.pixelSize: 12
                            font.family: "monospace"
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }

                    // Right Column: Action Buttons, centered vertically
                    RowLayout {
                        spacing: 8
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                        M3Button {
                            text: "Run .EXE"
                            iconSource: "qrc:/tsuki_app/icons/actions/play.svg"
                            buttonType: "tonal"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: {
                                root.targetPrefixForInstaller = pfxCard.modelData.id
                                let p = uiController.selectFile("Run Windows Installer (.exe / .msi) in Prefix", "Windows Installers (*.exe *.EXE *.msi *.MSI *.bat);;All Files (*)", "")
                                if (p && p.length > 0) {
                                    uiController.prefixManager.runExecutableInPrefix(pfxCard.modelData.id, p, [])
                                }
                            }
                        }

                        M3Button {
                            text: "Winetricks"
                            iconSource: "qrc:/tsuki_app/icons/actions/wrench.svg"
                            buttonType: "tonal"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: root.winetricksRequested(pfxCard.modelData.id, pfxCard.modelData.name)
                        }

                        M3Button {
                            text: "Folder"
                            iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                            buttonType: "tonal"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: uiController.prefixManager.openPrefixInFileManager(pfxCard.modelData.id)
                        }

                        M3Button {
                            text: "Backup"
                            buttonType: "tonal"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: uiController.prefixManager.backupPrefix(pfxCard.modelData.id, "")
                        }

                        M3Button {
                            visible: !pfxCard.modelData.isDefault
                            text: "Delete"
                            buttonType: "destructive"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: uiController.prefixManager.deletePrefix(pfxCard.modelData.id, true)
                        }
                    }
                }
            }
        }
    }
}
