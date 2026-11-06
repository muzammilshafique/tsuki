import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../components"

Item {
    id: root
    signal winetricksRequested(string prefixId, string prefixName)

    property string targetPrefixForInstaller: "default-prefix"

    FileDialog {
        id: exeInstallerDialog
        title: "Run Windows Installer (.exe / .msi) in Prefix"
        nameFilters: ["Windows Installers (*.exe *.EXE *.msi *.MSI *.bat)", "All Files (*)"]
        onAccepted: {
            let p = selectedFile.toString()
            if (p.startsWith("file://")) p = p.substring(7)
            uiController.prefixManager.runExecutableInPrefix(root.targetPrefixForInstaller, p, [])
        }
    }

    FolderDialog {
        id: importPrefixFolderDialog
        title: "Select Existing Wine or Proton Prefix Folder to Import"
        onAccepted: {
            let p = selectedFolder.toString()
            if (p.startsWith("file://")) p = p.substring(7)
            let name = p.substring(p.lastIndexOf("/") + 1)
            uiController.prefixManager.importPrefix(name, p)
        }
    }

    FileDialog {
        id: restoreArchiveDialog
        title: "Select Prefix Backup Archive (.tar.gz / .tar.zst)"
        nameFilters: ["Tar Archives (*.tar.gz *.tar.zst *.tar.xz *.tar)", "All Files (*)"]
        onAccepted: {
            let p = selectedFile.toString()
            if (p.startsWith("file://")) p = p.substring(7)
            uiController.prefixManager.restorePrefix(p, "", "")
        }
    }

    FolderDialog {
        id: newPrefixBaseDirDialog
        title: "Select Custom Prefix Location"
        onAccepted: {
            let p = selectedFolder.toString()
            if (p.startsWith("file://")) p = p.substring(7)
            newPfxPathField.text = p
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 24
        anchors.bottomMargin: 24
        spacing: 18

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            YIcon { source: "qrc:/tsuki_app/icons/nav/prefix.svg"; color: appSettings.accentColor; size: 28 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Label { text: "Wine Prefix Management (Bottles-Style Isolation)"; color: appSettings.textColor; font.pixelSize: 22; font.weight: Font.Bold }
                Label { text: "Create, import, clone, backup, restore, configure Windows versions, DLL overrides, and run installers inside isolated prefixes"; color: appSettings.textSecColor; font.pixelSize: 13 }
            }
            Button {
                text: "Import Prefix…"
                onClicked: importPrefixFolderDialog.open()
            }
            Button {
                text: "Restore Backup…"
                onClicked: restoreArchiveDialog.open()
            }
        }

        // Create New Prefix Bar
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: createRow.implicitHeight + 24
            radius: 12
            color: appSettings.surfaceColor
            border.color: appSettings.borderColor

            RowLayout {
                id: createRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Label { text: "New Prefix:"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.DemiBold }

                TextField {
                    id: newPfxNameField
                    Layout.preferredWidth: 180
                    placeholderText: "Custom Name (e.g. GTASA)"
                    color: appSettings.textColor
                    placeholderTextColor: appSettings.textTerColor
                    font.pixelSize: 13
                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                }

                TextField {
                    id: newPfxPathField
                    Layout.fillWidth: true
                    text: appSettings.defaultPrefixLocation
                    placeholderText: "Base folder path"
                    color: appSettings.textColor
                    font.pixelSize: 12
                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                }

                Button { text: "Browse…"; onClicked: newPrefixBaseDirDialog.open() }

                ComboBox {
                    id: newPfxArchCombo
                    Layout.preferredWidth: 100
                    model: ["win64", "win32"]
                }

                ComboBox {
                    id: newPfxWinVerCombo
                    Layout.preferredWidth: 110
                    model: ["win10", "win11", "win7"]
                }

                Button {
                    text: "+ Create Prefix"
                    enabled: newPfxNameField.text.trim().length > 0 && !uiController.prefixManager.isBusy
                    onClicked: {
                        uiController.prefixManager.createPrefix(
                            newPfxNameField.text,
                            newPfxPathField.text,
                            newPfxArchCombo.currentText,
                            newPfxWinVerCombo.currentText,
                            "",
                            true
                        )
                        newPfxNameField.text = ""
                    }
                    background: Rectangle { radius: 18; color: parent.enabled ? appSettings.accentColor : appSettings.surfaceAltColor }
                    contentItem: Label {
                        text: parent.text
                        color: parent.enabled ? "#0f0f11" : appSettings.textTerColor
                        font.pixelSize: 13; font.weight: Font.DemiBold
                        leftPadding: 14; rightPadding: 14
                    }
                }
            }
        }

        // Busy Banner
        Rectangle {
            visible: uiController.prefixManager.isBusy
            Layout.fillWidth: true
            height: 38
            radius: 8
            color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.16)
            border.color: appSettings.accentColor
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                BusyIndicator { running: true; implicitWidth: 22; implicitHeight: 22 }
                Label { text: uiController.prefixManager.currentOperation; color: appSettings.accentColor; font.pixelSize: 13; font.weight: Font.Medium }
            }
        }

        // Prefix Cards List
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 12
            model: uiController.prefixManager.prefixes
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                implicitHeight: cardCol.implicitHeight + 28
                radius: 14
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // Top Row: Name, Badges, Windows Version Selector, DXVK/VKD3D Toggles
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: modelData.name
                            color: appSettings.textColor
                            font.pixelSize: 17
                            font.weight: Font.Bold
                        }

                        Rectangle {
                            radius: 4
                            color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.18)
                            implicitWidth: archLbl.implicitWidth + 10; implicitHeight: 20
                            Label {
                                id: archLbl
                                anchors.centerIn: parent
                                text: modelData.arch.toUpperCase()
                                color: appSettings.accentColor
                                font.pixelSize: 10; font.weight: Font.Bold
                            }
                        }

                        Label {
                            text: modelData.path
                            color: appSettings.textSecColor
                            font.pixelSize: 12
                            font.family: "monospace"
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }

                        Label { text: "Windows:"; color: appSettings.textSecColor; font.pixelSize: 12 }
                        ComboBox {
                            Layout.preferredWidth: 100
                            model: ["win11", "win10", "win7"]
                            currentIndex: modelData.windowsVersion === "win11" ? 0 : (modelData.windowsVersion === "win7" ? 2 : 1)
                            onActivated: (idx) => {
                                let vers = ["win11", "win10", "win7"]
                                uiController.prefixManager.setWindowsVersion(modelData.id, vers[idx])
                            }
                        }

                        CheckBox {
                            text: "DXVK"
                            checked: modelData.dxvkInstalled
                            onToggled: uiController.prefixManager.installDxvk(modelData.id, checked)
                        }

                        CheckBox {
                            text: "VKD3D"
                            checked: modelData.vkd3dInstalled
                            onToggled: uiController.prefixManager.installVkd3d(modelData.id, checked)
                        }
                    }

                    // Bottom Row: Action & Utility Buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Button {
                            text: "Run EXE / MSI…"
                            onClicked: {
                                root.targetPrefixForInstaller = modelData.id
                                exeInstallerDialog.open()
                            }
                        }
                        Button {
                            text: "Winetricks"
                            onClicked: root.winetricksRequested(modelData.id, modelData.name)
                        }
                        Button {
                            text: "winecfg"
                            onClicked: uiController.prefixManager.runWineTool(modelData.id, "winecfg")
                        }
                        Button {
                            text: "regedit"
                            onClicked: uiController.prefixManager.runWineTool(modelData.id, "regedit")
                        }
                        Button {
                            text: "uninstaller"
                            onClicked: uiController.prefixManager.runWineTool(modelData.id, "uninstaller")
                        }
                        Button {
                            text: "Browse Files"
                            onClicked: uiController.prefixManager.openPrefixInFileManager(modelData.id)
                        }
                        Button {
                            text: "Terminal"
                            onClicked: uiController.prefixManager.openPrefixInTerminal(modelData.id)
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: "Clone"
                            onClicked: uiController.prefixManager.clonePrefix(modelData.id, modelData.name + "_Clone", "")
                        }
                        Button {
                            text: "Backup"
                            onClicked: uiController.prefixManager.backupPrefix(modelData.id, "")
                        }
                        Button {
                            text: "Repair"
                            onClicked: uiController.diagnosticsManager.repairPrefix(modelData.id)
                        }
                        Button {
                            visible: modelData.id !== "default-prefix"
                            text: "Delete"
                            onClicked: uiController.prefixManager.deletePrefix(modelData.id, true)
                            background: Rectangle { radius: 8; color: Qt.rgba(239/255, 68/255, 68/255, 0.16); border.color: "#ef4444" }
                            contentItem: Label { text: "Delete"; color: "#ef4444"; font.pixelSize: 12; leftPadding: 10; rightPadding: 10 }
                        }
                    }
                }
            }
        }
    }
}

