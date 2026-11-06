import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root

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
            YIcon { source: "qrc:/tsuki_app/icons/nav/diagnostics.svg"; color: appSettings.accentColor; size: 28 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Label { text: "System & Gaming Diagnostics"; color: appSettings.textColor; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                Label { text: "Verify system dependencies, Vulkan drivers, /dev/uinput permissions, and Wine environment integrity"; color: appSettings.textSecColor; font.pixelSize: 13 }
            }
            M3Button {
                text: "Run System Checks"
                iconSource: "qrc:/tsuki_app/icons/actions/refresh.svg"
                buttonType: "filled"
                onClicked: uiController.diagnosticsManager.runSystemDiagnostics()
            }
        }

        // ── Split Columns ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20

            // Left Column: Environment & Dependency Checks Card
            Rectangle {
                Layout.preferredWidth: 460
                Layout.fillHeight: true
                radius: 20
                color: appSettings.surfaceColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 14

                    Label { text: "System Dependency Status"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: uiController.diagnosticsManager.systemChecks

                        delegate: Rectangle {
                            id: checkCard
                            required property var modelData
                            width: ListView.view.width
                            height: 60
                            radius: 12
                            color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                            border.color: checkCard.modelData.ok 
                                ? Qt.rgba(34/255, 197/255, 94/255, 0.25) 
                                : Qt.rgba(245/255, 158/255, 11/255, 0.35)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12

                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    color: checkCard.modelData.ok ? "#22c55e" : "#f59e0b"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Label {
                                        text: checkCard.modelData.name
                                        color: appSettings.textColor
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }
                                    Label {
                                        text: checkCard.modelData.detail
                                        color: appSettings.textSecColor
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                YIcon {
                                    size: 16
                                    source: checkCard.modelData.ok ? "qrc:/tsuki_app/icons/actions/check.svg" : "qrc:/tsuki_app/icons/actions/close.svg"
                                    color: checkCard.modelData.ok ? "#22c55e" : "#f59e0b"
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                }
            }

            // Right Column: System Hardware & Driver Info
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

                    Label { text: "System & Driver Summary"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        color: appSettings.isEffectiveDark ? "#09090c" : "#f4f4f5"
                        border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 16
                            clip: true

                            ColumnLayout {
                                width: parent.width
                                spacing: 12

                                Label {
                                    text: "Linux Architecture: x86_64\n" +
                                          "Vulkan API: Active (DirectX Translation via DXVK & VKD3D-Proton)\n" +
                                          "Graphics Compositor: Wayland / XWayland\n" +
                                          "Audio Server: PipeWire / PulseAudio\n" +
                                          "XInput Subsystem: Standalone SDL2 Virtual Controller Driver (/dev/uinput)\n" +
                                          "Package Tools: Winetricks & Cabextract"
                                    color: appSettings.textColor
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    lineHeight: 1.4
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        M3Button {
                            text: "Export System Report"
                            iconSource: "qrc:/tsuki_app/icons/actions/shortcut.svg"
                            buttonType: "tonal"
                            onClicked: uiController.diagnosticsManager.exportSystemDiagnostics("")
                        }
                    }
                }
            }
        }
    }
}
