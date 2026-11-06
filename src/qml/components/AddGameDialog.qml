import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects

Popup {
    id: root
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 64 : 620, 620)
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    padding: 24
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string exePath: ""
    property string gameTitle: ""
    property string workDir: ""
    property string launchArgs: ""
    property int runnerIndex: 0
    property bool useDedicatedPrefix: true
    property string customPrefixName: ""
    property string customPrefixLocation: appSettings.defaultPrefixLocation
    property string prefixArch: "win64"
    property int existingPrefixIndex: 0
    property string selectedCategory: "Action"

    function resetAndOpen() {
        exePath = ""
        gameTitle = ""
        workDir = ""
        launchArgs = ""
        runnerIndex = 0
        useDedicatedPrefix = true
        customPrefixName = ""
        customPrefixLocation = appSettings.defaultPrefixLocation
        prefixArch = "win64"
        existingPrefixIndex = 0
        selectedCategory = "Action"
        root.open()
    }

    FileDialog {
        id: exePicker
        title: "Select Windows Game Executable (.exe)"
        nameFilters: ["Windows Executables (*.exe *.EXE *.msi *.MSI *.bat)", "All Files (*)"]
        onAccepted: {
            let local = selectedFile.toString()
            if (local.startsWith("file://")) local = local.substring(7)
            root.exePath = local
            if (root.gameTitle.trim().length === 0) {
                root.gameTitle = uiController.gameManager.guessTitleFromExecutable(local)
                titleInput.text = root.gameTitle
                root.customPrefixName = uiController.prefixManager.suggestShortPrefixName(root.gameTitle)
                pfxNameInput.text = root.customPrefixName
            }
            let lastSlash = local.lastIndexOf("/")
            if (lastSlash > 0 && root.workDir.trim().length === 0) {
                root.workDir = local.substring(0, lastSlash)
                workDirInput.text = root.workDir
            }
        }
    }

    FolderDialog {
        id: prefixDirPicker
        title: "Select Custom Prefix Base Directory"
        onAccepted: {
            let local = selectedFolder.toString()
            if (local.startsWith("file://")) local = local.substring(7)
            root.customPrefixLocation = local
            pfxLocInput.text = local
        }
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

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "Add Local Windows Game"
                color: appSettings.textColor
                font.pixelSize: 20
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            ToolButton {
                implicitWidth: 32; implicitHeight: 32
                background: Rectangle { radius: 16; color: parent.hovered ? appSettings.surfaceAltColor : "transparent" }
                contentItem: YIcon { anchors.centerIn: parent; source: "qrc:/tsuki_app/icons/actions/close.svg"; color: appSettings.textSecColor; size: 18 }
                onClicked: root.close()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.borderColor }

        // Executable Row
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Label { text: "Game Executable (.exe)"; color: appSettings.textSecColor; font.pixelSize: 13 }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: exeInput
                    Layout.fillWidth: true
                    text: root.exePath
                    placeholderText: "/path/to/Game.exe"
                    color: appSettings.textColor
                    placeholderTextColor: appSettings.textTerColor
                    font.pixelSize: 14
                    leftPadding: 12; rightPadding: 12
                    onTextChanged: root.exePath = text
                    background: Rectangle {
                        radius: 8
                        color: appSettings.inputColor
                        border.color: parent.activeFocus ? appSettings.accentColor : appSettings.borderColor
                    }
                }
                Button {
                    text: "Browse…"
                    onClicked: exePicker.open()
                    background: Rectangle {
                        radius: 8
                        color: parent.hovered ? appSettings.accentColor : appSettings.surfaceAltColor
                        border.color: appSettings.accentColor
                        border.width: 1
                    }
                    contentItem: Label {
                        text: parent.text
                        color: parent.hovered ? "#0f0f11" : appSettings.textColor
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 12; rightPadding: 12
                    }
                }
            }
        }

        // Title & Category Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "Game Title (SteamGridDB auto-artwork)"; color: appSettings.textSecColor; font.pixelSize: 13 }
                TextField {
                    id: titleInput
                    Layout.fillWidth: true
                    text: root.gameTitle
                    placeholderText: "e.g. Grand Theft Auto: San Andreas"
                    color: appSettings.textColor
                    placeholderTextColor: appSettings.textTerColor
                    font.pixelSize: 14
                    leftPadding: 12; rightPadding: 12
                    onTextChanged: {
                        root.gameTitle = text
                        if (pfxNameInput.text.trim().length === 0) {
                            pfxNameInput.text = uiController.prefixManager.suggestShortPrefixName(text)
                        }
                    }
                    background: Rectangle {
                        radius: 8
                        color: appSettings.inputColor
                        border.color: parent.activeFocus ? appSettings.accentColor : appSettings.borderColor
                    }
                }
            }
            ColumnLayout {
                Layout.preferredWidth: 160
                spacing: 6
                Label { text: "Category"; color: appSettings.textSecColor; font.pixelSize: 13 }
                ComboBox {
                    id: catCombo
                    Layout.fillWidth: true
                    model: ["Action", "RPG", "Adventure", "Strategy", "Indie", "Racing", "Simulation", "Uncategorized"]
                    onCurrentTextChanged: root.selectedCategory = currentText
                }
            }
        }

        // Working Dir & Launch Arguments
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "Working Directory"; color: appSettings.textSecColor; font.pixelSize: 13 }
                TextField {
                    id: workDirInput
                    Layout.fillWidth: true
                    text: root.workDir
                    placeholderText: "Defaults to executable folder"
                    color: appSettings.textColor
                    placeholderTextColor: appSettings.textTerColor
                    font.pixelSize: 13
                    leftPadding: 12; rightPadding: 12
                    onTextChanged: root.workDir = text
                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                }
            }
            ColumnLayout {
                Layout.preferredWidth: 200
                spacing: 6
                Label { text: "Launch Arguments"; color: appSettings.textSecColor; font.pixelSize: 13 }
                TextField {
                    id: argsInput
                    Layout.fillWidth: true
                    text: root.launchArgs
                    placeholderText: "e.g. -windowed -skipintro"
                    color: appSettings.textColor
                    placeholderTextColor: appSettings.textTerColor
                    font.pixelSize: 13
                    leftPadding: 12; rightPadding: 12
                    onTextChanged: root.launchArgs = text
                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                }
            }
        }

        // Runner Selection
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Label { text: "Wine / Proton Runner"; color: appSettings.textSecColor; font.pixelSize: 13 }
            ComboBox {
                id: runnerCombo
                Layout.fillWidth: true
                property var runnerList: {
                    let arr = [{ id: "", name: "Global Default Runner" }]
                    let installed = uiController.runnerManager.installedRunners
                    for (let i = 0; i < installed.length; ++i) {
                        arr.push(installed[i])
                    }
                    return arr
                }
                model: runnerList
                textRole: "name"
            }
        }

        // Prefix Mode (Dedicated vs Existing)
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: pfxCol.implicitHeight + 24
            radius: 10
            color: appSettings.surfaceAltColor
            border.color: appSettings.borderColor

            ColumnLayout {
                id: pfxCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label {
                        text: "Wine Prefix Configuration"
                        color: appSettings.textColor
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    Button {
                        text: "Dedicated Prefix"
                        onClicked: root.useDedicatedPrefix = true
                        background: Rectangle {
                            radius: 6
                            color: root.useDedicatedPrefix ? appSettings.accentColor : "transparent"
                            border.color: appSettings.accentColor
                        }
                        contentItem: Label {
                            text: parent.text
                            color: root.useDedicatedPrefix ? "#0f0f11" : appSettings.textColor
                            font.pixelSize: 12; leftPadding: 8; rightPadding: 8
                        }
                    }
                    Button {
                        text: "Existing Prefix"
                        onClicked: root.useDedicatedPrefix = false
                        background: Rectangle {
                            radius: 6
                            color: !root.useDedicatedPrefix ? appSettings.accentColor : "transparent"
                            border.color: appSettings.accentColor
                        }
                        contentItem: Label {
                            text: parent.text
                            color: !root.useDedicatedPrefix ? "#0f0f11" : appSettings.textColor
                            font.pixelSize: 12; leftPadding: 8; rightPadding: 8
                        }
                    }
                }

                // Dedicated Prefix Options
                ColumnLayout {
                    visible: root.useDedicatedPrefix
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label { text: "Custom Prefix Name (independent of title)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            TextField {
                                id: pfxNameInput
                                Layout.fillWidth: true
                                text: root.customPrefixName
                                placeholderText: "e.g. GTASA"
                                color: appSettings.textColor
                                placeholderTextColor: appSettings.textTerColor
                                font.pixelSize: 13
                                leftPadding: 10; rightPadding: 10
                                onTextChanged: root.customPrefixName = text
                                background: Rectangle { radius: 6; color: appSettings.inputColor; border.color: appSettings.borderColor }
                            }
                        }
                        ColumnLayout {
                            Layout.preferredWidth: 130
                            spacing: 4
                            Label { text: "Architecture"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            ComboBox {
                                Layout.fillWidth: true
                                model: ["win64", "win32"]
                                onCurrentTextChanged: root.prefixArch = currentText
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: "Prefix Base Directory"; color: appSettings.textSecColor; font.pixelSize: 12 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                id: pfxLocInput
                                Layout.fillWidth: true
                                text: root.customPrefixLocation
                                color: appSettings.textColor
                                font.pixelSize: 12
                                leftPadding: 10; rightPadding: 10
                                onTextChanged: root.customPrefixLocation = text
                                background: Rectangle { radius: 6; color: appSettings.inputColor; border.color: appSettings.borderColor }
                            }
                            Button {
                                text: "Folder…"
                                onClicked: prefixDirPicker.open()
                            }
                        }
                    }
                }

                // Existing Prefix Selector
                ColumnLayout {
                    visible: !root.useDedicatedPrefix
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: "Select Existing Prefix"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    ComboBox {
                        id: existingPfxCombo
                        Layout.fillWidth: true
                        model: uiController.prefixManager.prefixes
                        textRole: "name"
                    }
                }
            }
        }

        // Bottom Action Buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 12
            Item { Layout.fillWidth: true }

            Button {
                text: "Cancel"
                onClicked: root.close()
                background: Rectangle { radius: 20; color: appSettings.surfaceAltColor; implicitWidth: 100; implicitHeight: 40 }
                contentItem: Label { text: parent.text; color: appSettings.textColor; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }

            Button {
                text: "Add to Library"
                enabled: root.exePath.trim().length > 0
                onClicked: {
                    let chosenRunnerId = ""
                    if (runnerCombo.currentIndex > 0 && runnerCombo.currentIndex < runnerCombo.runnerList.length) {
                        chosenRunnerId = runnerCombo.runnerList[runnerCombo.currentIndex].id
                    }
                    let pfxMode = "dedicated"
                    if (!root.useDedicatedPrefix) {
                        let pfxs = uiController.prefixManager.prefixes
                        if (existingPfxCombo.currentIndex >= 0 && existingPfxCombo.currentIndex < pfxs.length) {
                            pfxMode = pfxs[existingPfxCombo.currentIndex].id
                        } else {
                            pfxMode = "default-prefix"
                        }
                    }
                    uiController.gameManager.addGame(
                        root.gameTitle,
                        root.exePath,
                        root.workDir,
                        root.launchArgs,
                        chosenRunnerId,
                        pfxMode,
                        root.customPrefixName,
                        root.customPrefixLocation,
                        root.prefixArch,
                        root.selectedCategory
                    )
                    root.close()
                }
                background: Rectangle {
                    radius: 20
                    color: parent.enabled ? appSettings.accentColor : appSettings.surfaceAltColor
                    implicitWidth: 150; implicitHeight: 40
                }
                contentItem: Label {
                    text: parent.text
                    color: parent.enabled ? "#0f0f11" : appSettings.textTerColor
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}

