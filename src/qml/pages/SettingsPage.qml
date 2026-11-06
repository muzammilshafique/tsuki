import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../components"

Item {
    id: root

    FolderDialog {
        id: defaultPrefixDirPicker
        title: "Select Default Wine Prefix Location"
        onAccepted: {
            let p = selectedFolder.toString()
            if (p.startsWith("file://")) p = p.substring(7)
            appSettings.defaultPrefixLocation = p
        }
    }

    FolderDialog {
        id: defaultRunnerDirPicker
        title: "Select Default Runner Download Location"
        onAccepted: {
            let p = selectedFolder.toString()
            if (p.startsWith("file://")) p = p.substring(7)
            appSettings.defaultRunnerLocation = p
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 20

            Item { Layout.preferredHeight: 6 }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                spacing: 12
                YIcon { source: "qrc:/tsuki_app/icons/actions/settings.svg"; color: appSettings.accentColor; size: 28 }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { text: "Global Settings"; color: appSettings.textColor; font.pixelSize: 22; font.weight: Font.Bold }
                    Label { text: "Global settings act as defaults across Tsuki; individual game configurations override them."; color: appSettings.textSecColor; font.pixelSize: 13 }
                }
            }

            // 1. Default Runner & Locations
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 32; Layout.rightMargin: 32
                implicitHeight: sec1.implicitHeight + 36
                radius: 16
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

                ColumnLayout {
                    id: sec1
                    anchors.fill: parent; anchors.margins: 18; spacing: 14

                    Label { text: "Runners & Storage Directories (XDG)"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 14
                        Label { text: "Default Wine / Proton Runner:"; color: appSettings.textSecColor; font.pixelSize: 13; Layout.preferredWidth: 230 }
                        ComboBox {
                            Layout.fillWidth: true
                            model: uiController.runnerManager.installedRunners
                            textRole: "name"
                            onActivated: (idx) => {
                                let r = uiController.runnerManager.installedRunners
                                if (idx >= 0 && idx < r.length) appSettings.defaultRunnerId = r[idx].id
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        Label { text: "Default Prefix Location:"; color: appSettings.textSecColor; font.pixelSize: 13; Layout.preferredWidth: 230 }
                        TextField {
                            Layout.fillWidth: true
                            text: appSettings.defaultPrefixLocation
                            color: appSettings.textColor
                            onEditingFinished: appSettings.defaultPrefixLocation = text
                            background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                        }
                        Button { text: "Browse…"; onClicked: defaultPrefixDirPicker.open() }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        Label { text: "Default Runner Download Location:"; color: appSettings.textSecColor; font.pixelSize: 13; Layout.preferredWidth: 230 }
                        TextField {
                            Layout.fillWidth: true
                            text: appSettings.defaultRunnerLocation
                            color: appSettings.textColor
                            onEditingFinished: appSettings.defaultRunnerLocation = text
                            background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                        }
                        Button { text: "Browse…"; onClicked: defaultRunnerDirPicker.open() }
                    }
                }
            }

            // 2. Performance, Graphics & Controller Defaults
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 32; Layout.rightMargin: 32
                implicitHeight: sec2.implicitHeight + 36
                radius: 16
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

                ColumnLayout {
                    id: sec2
                    anchors.fill: parent; anchors.margins: 18; spacing: 14

                    Label { text: "Gaming Performance, Graphics & Controller Defaults"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: 20
                        rowSpacing: 10

                        CheckBox {
                            text: "Enable DXVK by default"
                            checked: appSettings.dxvkDefault
                            onToggled: appSettings.dxvkDefault = checked
                        }
                        CheckBox {
                            text: "Enable VKD3D-Proton by default"
                            checked: appSettings.vkd3dDefault
                            onToggled: appSettings.vkd3dDefault = checked
                        }
                        CheckBox {
                            text: "Enable Esync by default"
                            checked: appSettings.esyncDefault
                            onToggled: appSettings.esyncDefault = checked
                        }
                        CheckBox {
                            text: "Enable Fsync by default"
                            checked: appSettings.fsyncDefault
                            onToggled: appSettings.fsyncDefault = checked
                        }
                        CheckBox {
                            text: "Enable Feral GameMode by default"
                            checked: appSettings.gamemodeDefault
                            onToggled: appSettings.gamemodeDefault = checked
                        }
                        CheckBox {
                            text: "Enable MangoHud by default"
                            checked: appSettings.mangohudDefault
                            onToggled: appSettings.mangohudDefault = checked
                        }
                        CheckBox {
                            text: "Enable Xbox Controller Emulation by default"
                            checked: appSettings.xboxEmulationDefault
                            onToggled: appSettings.xboxEmulationDefault = checked
                        }
                        CheckBox {
                            text: "Verbose Wine Debug Logs (+err,+warn)"
                            checked: appSettings.enableWineDebugLogs
                            onToggled: appSettings.enableWineDebugLogs = checked
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 14
                        Label { text: "Default DXVK HUD:"; color: appSettings.textSecColor; font.pixelSize: 13; Layout.preferredWidth: 160 }
                        ComboBox {
                            Layout.preferredWidth: 220
                            model: ["none", "fps", "devinfo,fps,frametimes", "full"]
                            currentIndex: Math.max(0, model.indexOf(appSettings.defaultDxvkHud))
                            onActivated: (idx) => appSettings.defaultDxvkHud = model[idx]
                        }
                    }
                }
            }

            // 3. SteamGridDB API & Appearance
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 32; Layout.rightMargin: 32
                Layout.bottomMargin: 32
                implicitHeight: sec3.implicitHeight + 36
                radius: 16
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

                ColumnLayout {
                    id: sec3
                    anchors.fill: parent; anchors.margins: 18; spacing: 14

                    Label { text: "SteamGridDB Integration & Appearance"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        Label { text: "SteamGridDB API Key:"; color: appSettings.textSecColor; font.pixelSize: 13; Layout.preferredWidth: 200 }
                        TextField {
                            Layout.fillWidth: true
                            text: appSettings.steamGridDbApiKey
                            echoMode: TextInput.PasswordEchoOnEdit
                            placeholderText: "Optional API v2 Bearer key (falls back to Steam Store CDN automatically)"
                            color: appSettings.textColor
                            placeholderTextColor: appSettings.textTerColor
                            onEditingFinished: appSettings.steamGridDbApiKey = text
                            background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 16
                        Label { text: "Theme Mode:"; color: appSettings.textSecColor; font.pixelSize: 13; Layout.preferredWidth: 200 }
                        ComboBox {
                            model: ["Yoru Dark (Default)", "Light Mode", "Midnight OLED Black"]
                            currentIndex: appSettings.themeMode
                            onActivated: (idx) => appSettings.themeMode = idx
                        }

                        Label { text: "Left-Click Poster Action:"; color: appSettings.textSecColor; font.pixelSize: 13 }
                        ComboBox {
                            model: ["Launch Game Immediately", "Open Game Details Screen"]
                            currentIndex: appSettings.leftClickBehavior
                            onActivated: (idx) => appSettings.leftClickBehavior = idx
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        Label { text: "Accent Color:"; color: appSettings.textSecColor; font.pixelSize: 13; Layout.preferredWidth: 200 }
                        Repeater {
                            model: ["#a855f7", "#38bdf8", "#34d399", "#f43f5e", "#f59e0b", "#6366f1"]
                            delegate: Rectangle {
                                required property string modelData
                                width: 32; height: 32; radius: 16
                                color: modelData
                                border.color: "#ffffff"
                                border.width: String(appSettings.accentColor).toLowerCase() === modelData ? 2.5 : 0
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: appSettings.accentColor = modelData
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Label { text: "Poster Size:"; color: appSettings.textSecColor; font.pixelSize: 13 }
                        Slider {
                            from: 150; to: 260; stepSize: 5
                            value: appSettings.thumbScaleTarget
                            onMoved: appSettings.thumbScaleTarget = Math.round(value)
                        }
                    }
                }
            }
        }
    }
}

