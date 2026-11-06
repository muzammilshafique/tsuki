import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property int selectedProfileIndex: 0
    property var currentProfileData: {
        let p = uiController.controllerManager.profiles
        if (selectedProfileIndex >= 0 && selectedProfileIndex < p.length) return p[selectedProfileIndex]
        return { id: "default-xbox", name: "Xbox 360 Standard (XInput)", xboxEmulation: true, deadzone: 4000, buttonMappings: {} }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 24
        anchors.bottomMargin: 24
        spacing: 20

        // ── Header ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            YIcon { source: "qrc:/tsuki_app/icons/nav/controller.svg"; color: appSettings.accentColor; size: 28 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Label { text: "Controllers & Xbox 360 Emulation"; color: appSettings.textColor; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                Label { text: "Standalone SDL2 + /dev/uinput virtual Xbox 360 controller emulation (no Steam Input needed)"; color: appSettings.textSecColor; font.pixelSize: 13 }
            }
            M3Button {
                text: "Refresh Gamepads"
                iconSource: "qrc:/tsuki_app/icons/actions/refresh.svg"
                buttonType: "tonal"
                onClicked: uiController.controllerManager.refreshControllers()
            }
            M3Button {
                text: uiController.controllerManager.isEmulationActive ? "Stop Virtual Pad" : "Start Virtual Pad"
                buttonType: uiController.controllerManager.isEmulationActive ? "destructive" : "filled"
                onClicked: {
                    if (uiController.controllerManager.isEmulationActive) {
                        uiController.controllerManager.stopXboxEmulation()
                    } else {
                        uiController.controllerManager.startXboxEmulation(root.currentProfileData.id)
                    }
                }
            }
        }

        // ── Status Bar ───────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 48
            radius: 14
            color: appSettings.surfaceColor
            border.color: uiController.controllerManager.isEmulationActive ? "#22c55e" : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: uiController.controllerManager.isEmulationActive ? "#22c55e" : (uiController.controllerManager.isConnected ? appSettings.accentColor : appSettings.textTerColor)
                }

                Label {
                    text: "Emulation Status: " + uiController.controllerManager.uinputStatus
                    color: appSettings.textColor
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    Layout.fillWidth: true
                }

                Label {
                    text: "Connected Gamepads: " + uiController.controllerManager.detectedControllers.length
                    color: appSettings.textSecColor
                    font.pixelSize: 13
                }
            }
        }

        // ── Split Columns ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20

            // Left Column: Detected Controllers & Live Input
            Rectangle {
                Layout.preferredWidth: 420
                Layout.fillHeight: true
                radius: 20
                color: appSettings.surfaceColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 14

                    Label { text: "Connected Controllers"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }

                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 140
                        clip: true
                        spacing: 8
                        model: uiController.controllerManager.detectedControllers

                        delegate: Rectangle {
                            id: padItem
                            required property var modelData
                            width: ListView.view.width
                            height: 52
                            radius: 12
                            color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10
                                YIcon { source: "qrc:/tsuki_app/icons/nav/controller.svg"; color: appSettings.accentColor; size: 20 }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Label { text: padItem.modelData.name; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
                                    Label { text: "Index: " + padItem.modelData.index + "  •  " + (padItem.modelData.isGamepad ? "Standard Gamepad" : "Joystick"); color: appSettings.textSecColor; font.pixelSize: 11 }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06) }

                    Label { text: "Live Input Visualizer"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.DemiBold }

                    // Gamepad Buttons Grid Visualizer
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 10
                        rowSpacing: 10

                        Repeater {
                            model: ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "Back", "Start", "Guide", "LS", "RS", "D-Up", "D-Down", "D-Left"]
                            delegate: Rectangle {
                                required property string modelData
                                height: 32
                                radius: 8
                                Layout.fillWidth: true
                                color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
                                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                                Label {
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    color: appSettings.textColor
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Right Column: Controller Profiles & Tuning
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 20
                color: appSettings.surfaceColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Controller Profiles"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        M3Button {
                            text: "New Profile"
                            iconSource: "qrc:/tsuki_app/icons/actions/add.svg"
                            buttonType: "tonal"
                            onClicked: {
                                let id = "profile-" + Date.now()
                                uiController.controllerManager.saveProfile(id, "Custom Pad Profile", true, 4000, {})
                            }
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        clip: true
                        spacing: 8
                        model: uiController.controllerManager.profiles

                        delegate: Rectangle {
                            id: profRow
                            required property int index
                            required property var modelData
                            readonly property bool isSelected: root.selectedProfileIndex === profRow.index
                            width: ListView.view.width
                            height: 48
                            radius: 12
                            color: isSelected 
                                ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.15) 
                                : (pMA.containsMouse ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)) : "transparent")
                            border.color: isSelected ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                Label {
                                    text: profRow.modelData.name
                                    color: profRow.isSelected ? appSettings.accentColor : appSettings.textColor
                                    font.pixelSize: 13
                                    font.weight: profRow.isSelected ? Font.DemiBold : Font.Normal
                                    Layout.fillWidth: true
                                }
                            }

                            MouseArea {
                                id: pMA
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.selectedProfileIndex = profRow.index
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06) }

                    Label { text: "Profile Settings"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.DemiBold }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Xbox 360 Emulation"; color: appSettings.textColor; font.pixelSize: 13; Layout.fillWidth: true }
                        Toggle {
                            checked: root.currentProfileData.xboxEmulation !== undefined ? root.currentProfileData.xboxEmulation : true
                            onToggled: (c) => {
                                uiController.controllerManager.saveProfile(
                                    root.currentProfileData.id,
                                    root.currentProfileData.name,
                                    c,
                                    root.currentProfileData.deadzone || 4000,
                                    root.currentProfileData.buttonMappings || {}
                                )
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Stick Deadzone Threshold"; color: appSettings.textColor; font.pixelSize: 13; Layout.fillWidth: true }
                        StyledSlider {
                            from: 0; to: 12000; stepSize: 500
                            value: root.currentProfileData.deadzone || 4000
                            suffix: ""
                            slider.onMoved: {
                                uiController.controllerManager.saveProfile(
                                    root.currentProfileData.id,
                                    root.currentProfileData.name,
                                    root.currentProfileData.xboxEmulation !== undefined ? root.currentProfileData.xboxEmulation : true,
                                    Math.round(slider.value),
                                    root.currentProfileData.buttonMappings || {}
                                )
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
