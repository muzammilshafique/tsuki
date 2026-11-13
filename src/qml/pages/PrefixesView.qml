import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    signal winetricksRequested(string prefixId, string prefixName)
    signal focusSidebarRequested()

    property string targetPrefixForInstaller: "default-prefix"

    function forceFocus() {
        if (prefixesList.count > 0) {
            if (prefixesList.currentIndex < 0) prefixesList.currentIndex = 0
            prefixesList.forceActiveFocus()
        } else {
            newPfxNameField.forceActiveFocus()
        }
    }

    Keys.onEscapePressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
    Keys.onBackPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Backspace) {
            event.accepted = true
            root.focusSidebarRequested()
        }
    }

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
                    id: importPfxBtn
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
                    Keys.onLeftPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                    Keys.onRightPressed: (event) => { event.accepted = true; restoreBackupBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { event.accepted = true; newPfxNameField.forceActiveFocus() }
                }

                M3Button {
                    id: restoreBackupBtn
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
                    Keys.onLeftPressed: (event) => { event.accepted = true; importPfxBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { event.accepted = true; createPfxBtn.forceActiveFocus() }
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
                    twoStageFocus: true
                    Layout.preferredWidth: 200
                    placeholderText: "Prefix Name (e.g. gta-v)"
                    Layout.alignment: Qt.AlignVCenter
                    Keys.onLeftPressed: (event) => { if (!isEditing) { event.accepted = true; root.focusSidebarRequested() } }
                    Keys.onRightPressed: (event) => { if (!isEditing) { event.accepted = true; archSegBtn.forceActiveFocus() } }
                    Keys.onUpPressed: (event) => { if (!isEditing) { event.accepted = true; importPfxBtn.forceActiveFocus() } }
                    Keys.onDownPressed: (event) => { if (!isEditing && prefixesList.count > 0) { event.accepted = true; prefixesList.forceActiveFocus() } }
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
                    Keys.onUpPressed: (event) => { event.accepted = true; importPfxBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { if (prefixesList.count > 0) { event.accepted = true; prefixesList.forceActiveFocus() } }
                    Keys.onRightPressed: (event) => {
                        if (selectedValue === 1) {
                            event.accepted = true
                            newPfxPathField.forceActiveFocus()
                        }
                    }
                    Keys.onLeftPressed: (event) => {
                        if (selectedValue === 0) {
                            event.accepted = true
                            newPfxNameField.forceActiveFocus()
                        }
                    }
                }

                M3TextField {
                    id: newPfxPathField
                    twoStageFocus: true
                    Layout.fillWidth: true
                    text: appSettings.defaultPrefixLocation
                    Layout.alignment: Qt.AlignVCenter
                    Keys.onLeftPressed: (event) => { if (!isEditing) { event.accepted = true; archSegBtn.forceActiveFocus() } }
                    Keys.onRightPressed: (event) => { if (!isEditing) { event.accepted = true; folderCreateBtn.forceActiveFocus() } }
                    Keys.onUpPressed: (event) => { if (!isEditing) { event.accepted = true; importPfxBtn.forceActiveFocus() } }
                    Keys.onDownPressed: (event) => { if (!isEditing && prefixesList.count > 0) { event.accepted = true; prefixesList.forceActiveFocus() } }
                }

                M3Button {
                    id: folderCreateBtn
                    text: "Folder…"
                    buttonType: "tonal"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        let p = uiController.selectFolder("Select Custom Prefix Location", newPfxPathField.text)
                        if (p && p.length > 0) {
                            newPfxPathField.text = p
                        }
                    }
                    Keys.onLeftPressed: (event) => { event.accepted = true; newPfxPathField.forceActiveFocus() }
                    Keys.onRightPressed: (event) => { event.accepted = true; createPfxBtn.forceActiveFocus() }
                    Keys.onUpPressed: (event) => { event.accepted = true; restoreBackupBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { if (prefixesList.count > 0) { event.accepted = true; prefixesList.forceActiveFocus() } }
                }

                M3Button {
                    id: createPfxBtn
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
                    Keys.onLeftPressed: (event) => { event.accepted = true; folderCreateBtn.forceActiveFocus() }
                    Keys.onUpPressed: (event) => { event.accepted = true; restoreBackupBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { if (prefixesList.count > 0) { event.accepted = true; prefixesList.forceActiveFocus() } }
                }
            }
        }

        // ── Prefixes List ────────────────────────────────────────────────────
        ListView {
            id: prefixesList
            focus: true
            keyNavigationEnabled: false
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 12
            model: uiController.prefixManager.prefixes
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            onActiveFocusChanged: {
                if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0
            }

            Keys.onUpPressed: (event) => {
                event.accepted = true
                if (currentIndex > 0) {
                    currentIndex--
                    positionViewAtIndex(currentIndex, ListView.Contain)
                } else {
                    newPfxNameField.forceActiveFocus()
                }
            }
            Keys.onDownPressed: (event) => {
                event.accepted = true
                if (currentIndex < count - 1) {
                    currentIndex++
                    positionViewAtIndex(currentIndex, ListView.Contain)
                }
            }
            Keys.onLeftPressed: (event) => {
                event.accepted = true
                root.focusSidebarRequested()
            }
            Keys.onRightPressed: (event) => {
                event.accepted = true
                if (currentItem && currentItem.runExeBtn) currentItem.runExeBtn.forceActiveFocus()
            }
            Keys.onReturnPressed: (event) => {
                event.accepted = true
                if (currentItem && currentItem.runExeBtn) currentItem.runExeBtn.forceActiveFocus()
            }
            Keys.onEnterPressed: (event) => {
                event.accepted = true
                if (currentItem && currentItem.runExeBtn) currentItem.runExeBtn.forceActiveFocus()
            }
            Keys.onSpacePressed: (event) => {
                event.accepted = true
                if (currentItem && currentItem.runExeBtn) currentItem.runExeBtn.forceActiveFocus()
            }

            delegate: Rectangle {
                id: pfxCard
                required property var modelData
                required property int index
                property alias runExeBtn: runExeBtnItem
                readonly property bool isCurrentRow: prefixesList.activeFocus && prefixesList.currentIndex === index
                width: ListView.view.width
                implicitHeight: cardInner.implicitHeight + 28
                radius: 16
                color: appSettings.surfaceColor
                border.color: isCurrentRow ? appSettings.accentColor : (Boolean(modelData.isDefault) ? appSettings.accentColor : appSettings.borderColor)
                border.width: (isCurrentRow || Boolean(modelData.isDefault)) ? 2 : 1

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
                            id: runExeBtnItem
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
                            Keys.onLeftPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onRightPressed: (event) => { event.accepted = true; winetricksBtnItem.forceActiveFocus() }
                            Keys.onUpPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex > 0) { prefixesList.currentIndex--; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onDownPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex < prefixesList.count - 1) { prefixesList.currentIndex++; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onEscapePressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onBackPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onPressed: (event) => { if (event.key === Qt.Key_Backspace) { event.accepted = true; prefixesList.forceActiveFocus() } }
                        }

                        M3Button {
                            id: winetricksBtnItem
                            text: "Winetricks"
                            iconSource: "qrc:/tsuki_app/icons/actions/wrench.svg"
                            buttonType: "tonal"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: root.winetricksRequested(pfxCard.modelData.id, pfxCard.modelData.name)
                            Keys.onLeftPressed: (event) => { event.accepted = true; runExeBtnItem.forceActiveFocus() }
                            Keys.onRightPressed: (event) => { event.accepted = true; folderBtnItem.forceActiveFocus() }
                            Keys.onUpPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex > 0) { prefixesList.currentIndex--; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onDownPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex < prefixesList.count - 1) { prefixesList.currentIndex++; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onEscapePressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onBackPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onPressed: (event) => { if (event.key === Qt.Key_Backspace) { event.accepted = true; prefixesList.forceActiveFocus() } }
                        }

                        M3Button {
                            id: folderBtnItem
                            text: "Folder"
                            iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                            buttonType: "tonal"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: uiController.prefixManager.openPrefixInFileManager(pfxCard.modelData.id)
                            Keys.onLeftPressed: (event) => { event.accepted = true; winetricksBtnItem.forceActiveFocus() }
                            Keys.onRightPressed: (event) => { event.accepted = true; backupBtnItem.forceActiveFocus() }
                            Keys.onUpPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex > 0) { prefixesList.currentIndex--; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onDownPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex < prefixesList.count - 1) { prefixesList.currentIndex++; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onEscapePressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onBackPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onPressed: (event) => { if (event.key === Qt.Key_Backspace) { event.accepted = true; prefixesList.forceActiveFocus() } }
                        }

                        M3Button {
                            id: backupBtnItem
                            text: "Backup"
                            buttonType: "tonal"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: uiController.prefixManager.backupPrefix(pfxCard.modelData.id, "")
                            Keys.onLeftPressed: (event) => { event.accepted = true; folderBtnItem.forceActiveFocus() }
                            Keys.onRightPressed: (event) => { if (deleteBtnItem.visible) { event.accepted = true; deleteBtnItem.forceActiveFocus() } }
                            Keys.onUpPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex > 0) { prefixesList.currentIndex--; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onDownPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex < prefixesList.count - 1) { prefixesList.currentIndex++; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onEscapePressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onBackPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onPressed: (event) => { if (event.key === Qt.Key_Backspace) { event.accepted = true; prefixesList.forceActiveFocus() } }
                        }

                        M3Button {
                            id: deleteBtnItem
                            visible: !pfxCard.modelData.isDefault
                            text: "Delete"
                            buttonType: "destructive"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: uiController.prefixManager.deletePrefix(pfxCard.modelData.id, true)
                            Keys.onLeftPressed: (event) => { event.accepted = true; backupBtnItem.forceActiveFocus() }
                            Keys.onUpPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex > 0) { prefixesList.currentIndex--; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onDownPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus(); if (prefixesList.currentIndex < prefixesList.count - 1) { prefixesList.currentIndex++; prefixesList.positionViewAtIndex(prefixesList.currentIndex, ListView.Contain) } }
                            Keys.onEscapePressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onBackPressed: (event) => { event.accepted = true; prefixesList.forceActiveFocus() }
                            Keys.onPressed: (event) => { if (event.key === Qt.Key_Backspace) { event.accepted = true; prefixesList.forceActiveFocus() } }
                        }
                    }
                }
            }
        }
    }
}
