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

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            YIcon { source: "qrc:/tsuki_app/icons/nav/controller.svg"; color: appSettings.accentColor; size: 28 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Label { text: "Controller Management & Xbox 360 XInput Emulation"; color: appSettings.textColor; font.pixelSize: 22; font.weight: Font.Bold }
                Label { text: "SC-Controller-inspired standalone SDL2 + /dev/uinput virtual Microsoft X-Box 360 pad emulation (no Steam Input required)"; color: appSettings.textSecColor; font.pixelSize: 13 }
            }
            Button {
                text: "Refresh Controllers"
                onClicked: uiController.controllerManager.refreshControllers()
            }
            Button {
                text: uiController.controllerManager.isEmulationActive ? "Stop Virtual Xbox Pad" : "Test Virtual Xbox Pad"
                onClicked: {
                    if (uiController.controllerManager.isEmulationActive) {
                        uiController.controllerManager.stopXboxEmulation()
                    } else {
                        uiController.controllerManager.startXboxEmulation(root.currentProfileData.id)
                    }
                }
                background: Rectangle {
                    radius: 18
                    color: uiController.controllerManager.isEmulationActive ? "#ef4444" : appSettings.accentColor
                }
                contentItem: Label {
                    text: parent.text
                    color: uiController.controllerManager.isEmulationActive ? "#ffffff" : "#0f0f11"
                    font.pixelSize: 13; font.weight: Font.DemiBold
                    leftPadding: 14; rightPadding: 14
                }
            }
        }

        // Status Bar
        Rectangle {
            Layout.fillWidth: true
            height: 48
            radius: 12
            color: appSettings.surfaceColor
            border.color: uiController.controllerManager.isEmulationActive ? "#34d399" : appSettings.borderColor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: uiController.controllerManager.isEmulationActive ? "#34d399" : (uiController.controllerManager.isConnected ? appSettings.accentColor : appSettings.textTerColor)
                }

                Label {
                    text: "Emulation Status: " + uiController.controllerManager.uinputStatus
                    color: appSettings.textColor
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    Layout.fillWidth: true
                }

                Label {
                    text: "Connected SDL2 Gamepads: " + uiController.controllerManager.detectedControllers.length
                    color: appSettings.textSecColor
                    font.pixelSize: 13
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20

            // Left Column: Detected Hardware & Live Input Monitor
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    Label { text: "Detected Controllers"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }

                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        clip: true
                        spacing: 8
                        model: uiController.controllerManager.detectedControllers

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 62
                            radius: 10
                            color: appSettings.surfaceAltColor
                            border.color: appSettings.accentColor

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 3
                                Label {
                                    text: modelData.name + " (" + modelData.vendorId + ":" + modelData.productId + ")"
                                    color: appSettings.textColor
                                    font.pixelSize: 14; font.weight: Font.DemiBold
                                }
                                Label {
                                    text: "GUID: " + modelData.guid
                                    color: appSettings.textSecColor
                                    font.pixelSize: 11; font.family: "monospace"
                                }
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: parent.count === 0
                            text: "No physical controller detected via SDL2.\nPlug in any USB or Bluetooth controller to test or remap."
                            horizontalAlignment: Text.AlignHCenter
                            color: appSettings.textSecColor
                            font.pixelSize: 13
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.borderColor }

                    Label { text: "Live Input State Telemetry"; color: appSettings.textColor; font.pixelSize: 15; font.weight: Font.DemiBold }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 10
                        rowSpacing: 10

                        Repeater {
                            model: [
                                { key: "a", label: "A (South)" },
                                { key: "b", label: "B (East)" },
                                { key: "x", label: "X (West)" },
                                { key: "y", label: "Y (North)" },
                                { key: "lb", label: "LB (L1)" },
                                { key: "rb", label: "RB (R1)" },
                                { key: "back", label: "Back / Select" },
                                { key: "start", label: "Start / Menu" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool pressed: Boolean(uiController.controllerManager.liveInputState[modelData.key])
                                Layout.fillWidth: true
                                height: 38
                                radius: 8
                                color: pressed ? appSettings.accentColor : appSettings.surfaceAltColor
                                border.color: pressed ? appSettings.accentColor : appSettings.borderColor

                                Label {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: parent.pressed ? "#0f0f11" : appSettings.textColor
                                    font.pixelSize: 12; font.weight: Font.Medium
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Label {
                            text: "Left Stick: (" + (uiController.controllerManager.liveInputState.lx || 0) + ", " + (uiController.controllerManager.liveInputState.ly || 0) + ")"
                            color: appSettings.textSecColor; font.family: "monospace"; font.pixelSize: 12
                        }
                        Label {
                            text: "Right Stick: (" + (uiController.controllerManager.liveInputState.rx || 0) + ", " + (uiController.controllerManager.liveInputState.ry || 0) + ")"
                            color: appSettings.textSecColor; font.family: "monospace"; font.pixelSize: 12
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Right Column: Controller Profiles & Custom Button Mappings
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
                        Label { text: "Controller Profiles & Button Mapping"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        ComboBox {
                            id: profileSelector
                            Layout.preferredWidth: 200
                            model: uiController.controllerManager.profiles
                            textRole: "name"
                            onCurrentIndexChanged: root.selectedProfileIndex = currentIndex
                        }
                        Button {
                            text: "+ New Profile"
                            onClicked: uiController.controllerManager.createProfile("Custom Xbox Profile", true, 4000)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        TextField {
                            id: profNameInput
                            Layout.fillWidth: true
                            text: root.currentProfileData.name || ""
                            color: appSettings.textColor
                            background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                        }
                        CheckBox {
                            id: profXboxCheck
                            text: "Enable Xbox/XInput Emulation"
                            checked: root.currentProfileData.xboxEmulation !== false
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Label { text: "Analog Stick Deadzone: " + deadzoneSlider.value; color: appSettings.textSecColor; font.pixelSize: 13 }
                        Slider {
                            id: deadzoneSlider
                            Layout.fillWidth: true
                            from: 0; to: 16000; stepSize: 500
                            value: root.currentProfileData.deadzone || 4000
                        }
                    }

                    // Button Remapping List
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        GridLayout {
                            width: parent.width
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 8

                            Repeater {
                                id: mapRepeater
                                model: [
                                    { key: "a", label: "A Button →", defVal: "BTN_SOUTH" },
                                    { key: "b", label: "B Button →", defVal: "BTN_EAST" },
                                    { key: "x", label: "X Button →", defVal: "BTN_WEST" },
                                    { key: "y", label: "Y Button →", defVal: "BTN_NORTH" },
                                    { key: "lb", label: "LB Shoulder →", defVal: "BTN_TL" },
                                    { key: "rb", label: "RB Shoulder →", defVal: "BTN_TR" },
                                    { key: "back", label: "Back / View →", defVal: "BTN_SELECT" },
                                    { key: "start", label: "Start / Menu →", defVal: "BTN_START" }
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    property string mapKey: modelData.key
                                    property alias selectedTarget: btnTargetCombo.currentText
                                    Layout.fillWidth: true

                                    Label {
                                        text: modelData.label
                                        color: appSettings.textColor
                                        font.pixelSize: 13
                                        Layout.preferredWidth: 110
                                    }
                                    ComboBox {
                                        id: btnTargetCombo
                                        Layout.fillWidth: true
                                        model: ["BTN_SOUTH", "BTN_EAST", "BTN_WEST", "BTN_NORTH", "BTN_TL", "BTN_TR", "BTN_SELECT", "BTN_START", "BTN_MODE", "BTN_THUMBL", "BTN_THUMBR"]
                                        Component.onCompleted: {
                                            let curMap = root.currentProfileData.buttonMappings || {}
                                            let v = curMap[modelData.key] || modelData.defVal
                                            let idx = model.indexOf(v)
                                            if (idx >= 0) currentIndex = idx
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        Button {
                            visible: root.currentProfileData.id !== "default-xbox"
                            text: "Delete Profile"
                            onClicked: uiController.controllerManager.deleteProfile(root.currentProfileData.id)
                        }
                        Button {
                            text: "Save Profile Mappings"
                            onClicked: {
                                let newMappings = Object.assign({}, root.currentProfileData.buttonMappings || {})
                                for (let i = 0; i < mapRepeater.count; ++i) {
                                    let item = mapRepeater.itemAt(i)
                                    if (item) newMappings[item.mapKey] = item.selectedTarget
                                }
                                uiController.controllerManager.saveProfile(
                                    root.currentProfileData.id,
                                    profNameInput.text,
                                    profXboxCheck.checked,
                                    Math.round(deadzoneSlider.value),
                                    newMappings
                                )
                            }
                            background: Rectangle { radius: 18; color: appSettings.accentColor }
                            contentItem: Label { text: parent.text; color: "#0f0f11"; font.pixelSize: 13; font.weight: Font.DemiBold; leftPadding: 16; rightPadding: 16 }
                        }
                    }
                }
            }
        }
    }
}

