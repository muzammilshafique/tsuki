import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property string selectedReleaseCat: "proton-ge"

    Component.onCompleted: {
        uiController.runnerManager.fetchAvailableReleases(root.selectedReleaseCat)
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
            YIcon { source: "qrc:/tsuki_app/icons/nav/runner.svg"; color: appSettings.accentColor; size: 28 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Label { text: "Wine & Proton Runners"; color: appSettings.textColor; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                Label { text: "Manage installed Wine, Wine-Staging, Proton, Proton-GE, or download GitHub releases"; color: appSettings.textSecColor; font.pixelSize: 13 }
            }
            M3Button {
                text: "Re-scan System"
                iconSource: "qrc:/tsuki_app/icons/actions/refresh.svg"
                buttonType: "tonal"
                onClicked: uiController.runnerManager.detectInstalledRunners()
            }
        }

        // ── Split 2-Column Layout ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20

            // Left Column: Installed Runners Card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 20
                color: appSettings.surfaceColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "Installed Runners (" + uiController.runnerManager.installedRunners.length + ")"
                            color: appSettings.textColor
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 10
                        model: uiController.runnerManager.installedRunners
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: runnerDelegate
                            required property var modelData
                            width: ListView.view.width
                            height: 76
                            radius: 14
                            color: runnerHover.containsMouse
                                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03))
                            border.color: modelData.isDefault ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                            border.width: modelData.isDefault ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        spacing: 8
                                        Label {
                                            text: runnerDelegate.modelData.name
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                        }
                                        Rectangle {
                                            visible: runnerDelegate.modelData.isDefault
                                            height: 18
                                            implicitWidth: defLbl.implicitWidth + 12
                                            width: implicitWidth
                                            radius: 4
                                            color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.2)
                                            Label {
                                                id: defLbl
                                                anchors.centerIn: parent
                                                text: "DEFAULT"
                                                color: appSettings.accentColor
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                            }
                                        }
                                        Rectangle {
                                            height: 18
                                            implicitWidth: rTypeLbl.implicitWidth + 12
                                            width: implicitWidth
                                            radius: 4
                                            color: Qt.rgba(56/255, 189/255, 248/255, 0.15)
                                            Label {
                                                id: rTypeLbl
                                                anchors.centerIn: parent
                                                text: {
                                                    let t = (runnerDelegate.modelData.type || "").toUpperCase()
                                                    if (t === "PROTON-GE" || t === "PROTON") return "PROTON"
                                                    return t
                                                }
                                                color: "#38bdf8"
                                                font.pixelSize: 10
                                                font.weight: Font.Medium
                                            }
                                        }
                                    }
                                    Label {
                                        text: runnerDelegate.modelData.path
                                        color: appSettings.textSecColor
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                }

                                RowLayout {
                                    spacing: 8
                                    M3Button {
                                        visible: !runnerDelegate.modelData.isDefault
                                        text: "Set Default"
                                        buttonType: "tonal"
                                        onClicked: appSettings.defaultRunnerId = runnerDelegate.modelData.id
                                    }
                                    M3Button {
                                        visible: !runnerDelegate.modelData.isSystem
                                        text: "Remove"
                                        buttonType: "destructive"
                                        onClicked: uiController.runnerManager.uninstallRunner(runnerDelegate.modelData.id)
                                    }
                                }
                            }

                            MouseArea {
                                id: runnerHover
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }
                    }
                }
            }

            // Right Column: GitHub Releases & Custom Runner
            Rectangle {
                Layout.preferredWidth: 440
                Layout.fillHeight: true
                radius: 20
                color: appSettings.surfaceColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Label {
                        text: "Download Runner Releases"
                        color: appSettings.textColor
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    // Release Category Pills
                    M3SegmentedButton {
                        Layout.fillWidth: true
                        model: [
                            { label: "Proton-GE", val: 0 },
                            { label: "Wine-GE", val: 1 },
                            { label: "Wine-Staging", val: 2 }
                        ]
                        selectedValue: root.selectedReleaseCat === "proton-ge" ? 0 : (root.selectedReleaseCat === "wine-ge" ? 1 : 2)
                        onSelectionChanged: (val) => {
                            root.selectedReleaseCat = (val === 0 ? "proton-ge" : (val === 1 ? "wine-ge" : "wine-staging"))
                            uiController.runnerManager.fetchAvailableReleases(root.selectedReleaseCat)
                        }
                    }

                    // Releases List
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: uiController.runnerManager.availableReleases
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: relRow
                            required property var modelData
                            width: ListView.view.width
                            height: 52
                            radius: 12
                            color: relMA.containsMouse 
                                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03))
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 10

                                Label {
                                    text: relRow.modelData.name
                                    color: appSettings.textColor
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                M3Button {
                                    text: relRow.modelData.isInstalled ? "Installed ✓" : "Download"
                                    iconSource: relRow.modelData.isInstalled ? "qrc:/tsuki_app/icons/actions/check.svg" : "qrc:/tsuki_app/icons/actions/download.svg"
                                    buttonType: relRow.modelData.isInstalled ? "tonal" : "filled"
                                    enabled: !relRow.modelData.isInstalled
                                    opacity: relRow.modelData.isInstalled ? 0.6 : 1.0
                                    onClicked: {
                                        uiController.runnerManager.downloadRelease(
                                            root.selectedReleaseCat,
                                            relRow.modelData.tagName,
                                            relRow.modelData.downloadUrl
                                        )
                                    }
                                }
                            }

                            MouseArea {
                                id: relMA
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }
                    }

                    // Add Custom Runner Directory Box
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 14
                        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                        border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                        implicitHeight: customCol.implicitHeight + 24

                        ColumnLayout {
                            id: customCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Label { text: "Add Custom Runner Directory"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.DemiBold }

                            M3TextField {
                                id: customNameField
                                Layout.fillWidth: true
                                placeholderText: "Runner Label (e.g. Proton-TKG-9.2)"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                M3TextField {
                                    id: customPathField
                                    Layout.fillWidth: true
                                    placeholderText: "/path/to/custom/runner"
                                }
                                M3Button {
                                    text: "Browse…"
                                    buttonType: "tonal"
                                    onClicked: {
                                        let p = uiController.selectFolder("Select Custom Wine or Proton Directory", customPathField.text)
                                        if (p && p.length > 0) {
                                            customPathField.text = p
                                        }
                                    }
                                }
                            }

                            M3Button {
                                Layout.alignment: Qt.AlignRight
                                text: "Add Runner"
                                iconSource: "qrc:/tsuki_app/icons/actions/add.svg"
                                buttonType: "filled"
                                onClicked: {
                                    if (customNameField.text.trim().length > 0 && customPathField.text.trim().length > 0) {
                                        uiController.runnerManager.addCustomRunner(customNameField.text.trim(), customPathField.text.trim())
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
    }
}
