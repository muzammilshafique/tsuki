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

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            YIcon { source: "qrc:/tsuki_app/icons/nav/terminal.svg"; color: appSettings.accentColor; size: 28 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Label { text: "Logging, Environment & Prefix Diagnostics"; color: appSettings.textColor; font.pixelSize: 22; font.weight: Font.Bold }
                Label { text: "Verify system gaming dependencies, inspect live Wine/Proton game logs, and diagnose launch issues"; color: appSettings.textSecColor; font.pixelSize: 13 }
            }
            Button {
                text: "Run System Checks"
                onClicked: uiController.diagnosticsManager.runSystemDiagnostics()
                background: Rectangle { radius: 18; color: appSettings.accentColor }
                contentItem: Label { text: parent.text; color: "#0f0f11"; font.pixelSize: 13; font.weight: Font.DemiBold; leftPadding: 16; rightPadding: 16 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20

            // Left Column: System Environment & Detected Error Analyzer
            Rectangle {
                Layout.preferredWidth: 420
                Layout.fillHeight: true
                radius: 16
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    Label { text: "Environment & Dependency Checks"; color: appSettings.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: uiController.diagnosticsManager.systemChecks

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 58
                            radius: 10
                            color: appSettings.surfaceAltColor
                            border.color: modelData.ok ? Qt.rgba(52/255, 211/255, 153/255, 0.4) : "#f59e0b"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    color: modelData.ok ? "#34d399" : "#f59e0b"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Label {
                                        text: modelData.name
                                        color: appSettings.textColor
                                        font.pixelSize: 13; font.weight: Font.DemiBold
                                    }
                                    Label {
                                        text: modelData.detail
                                        color: appSettings.textSecColor
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    // Detected Wine Error Diagnostics
                    Label {
                        visible: uiController.diagnosticsManager.detectedIssues.length > 0
                        text: "Recent Wine / Launch Error Diagnostics"
                        color: "#ef4444"
                        font.pixelSize: 14; font.weight: Font.DemiBold
                    }

                    ListView {
                        visible: uiController.diagnosticsManager.detectedIssues.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 140
                        clip: true
                        spacing: 6
                        model: uiController.diagnosticsManager.detectedIssues

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 64
                            radius: 8
                            color: Qt.rgba(239/255, 68/255, 68/255, 0.12)
                            border.color: "#ef4444"

                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 8; spacing: 2
                                Label { text: modelData.summary; color: "#ef4444"; font.pixelSize: 12; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { text: modelData.recommendation; color: appSettings.textColor; font.pixelSize: 11; wrapMode: Text.Wrap; maximumLineCount: 2; Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }

            // Right Column: Live Game Launch Log Viewer
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
                            text: "Live Game Execution Logs"
                            color: appSettings.textColor
                            font.pixelSize: 16; font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                        Button {
                            text: "Export Log"
                            onClicked: uiController.diagnosticsManager.exportGameLog(uiController.diagnosticsManager.selectedLogGameId, "")
                        }
                        Button {
                            text: "Clear"
                            onClicked: uiController.diagnosticsManager.clearGameLog(uiController.diagnosticsManager.selectedLogGameId)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        color: "#08080b"
                        border.color: appSettings.borderColor

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 12
                            clip: true
                            TextArea {
                                readOnly: true
                                text: uiController.diagnosticsManager.activeGameLog
                                color: "#e4e4e7"
                                font.family: "monospace"
                                font.pixelSize: 12
                                wrapMode: TextEdit.Wrap
                                background: null
                            }
                        }
                    }
                }
            }
        }
    }
}

