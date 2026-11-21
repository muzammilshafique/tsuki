import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    objectName: "cloudSaveConflictDialog"
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 48 : 560, 560)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 0
    closePolicy: Popup.NoAutoClose

    property string gameId: ""
    property var conflictDetails: ({})

    signal resolutionChosen(string gameId, string choice)

    function formatEpoch(ep) {
        const n = Number(ep || 0)
        if (n <= 0) return "No timestamp"
        const d = new Date(n * 1000)
        return d.toLocaleString()
    }

    function openConflict(targetGameId, details) {
        root.gameId = targetGameId || ""
        root.conflictDetails = details || ({})
        root.open()
        openFocusTimer.restart()
    }

    function resolve(choice) {
        const gid = root.gameId
        root.close()
        root.resolutionChosen(gid, choice)
        if (uiController && uiController.launchPipeline && gid.length > 0) {
            uiController.launchPipeline.resolveCloudConflictAndLaunch(gid, choice)
        }
    }

    Timer {
        id: openFocusTimer
        interval: 0
        repeat: false
        onTriggered: downloadCloudBtn.forceActiveFocus()
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 140; easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; from: 1.0; to: 0.96; duration: 140; easing.type: Easing.InCubic }
    }

    background: Rectangle {
        color: appSettings.surfaceColor
        radius: 12
        border.color: appSettings.borderColor
        border.width: 1
        layer.enabled: root.visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.62 : 0.24)
            shadowBlur: 0.75
            shadowVerticalOffset: 8
        }
    }

    contentItem: ColumnLayout {
        id: col
        focus: true
        spacing: 0

        Keys.onEscapePressed: (event) => { event.accepted = true; root.resolve("cancel") }
        Keys.onBackPressed: (event) => { event.accepted = true; root.resolve("cancel") }

        // Header
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 62

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12

                Rectangle {
                    width: 36
                    height: 36
                    radius: 10
                    color: Qt.rgba(0.96, 0.62, 0.04, 0.16)
                    YIcon {
                        anchors.centerIn: parent
                        symbol: "warning"
                        color: "#f59e0b"
                        size: 20
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: "Cloud Save Conflict Detected"
                        color: appSettings.textColor
                        font.family: "Rubik"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }
                    Label {
                        text: String(root.conflictDetails.gameTitle || "Epic Game")
                        color: appSettings.textSecColor
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: appSettings.borderColor
            }
        }

        // Body
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 20
            spacing: 14

            Label {
                Layout.fillWidth: true
                text: "Both your local save files and Epic Cloud Saves have changed since the last sync. Choose which version to keep before launching."
                color: appSettings.textColor
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                lineHeight: 1.35
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Local Card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: localCardCol.implicitHeight + 24
                    radius: 10
                    color: appSettings.surfaceContainerLow
                    border.color: appSettings.borderColor
                    border.width: 1

                    ColumnLayout {
                        id: localCardCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Label {
                            text: "LOCAL SAVES"
                            color: appSettings.accentColor
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                        Label {
                            text: (Number(root.conflictDetails.localFileCount || 0)) + " file(s)"
                            color: appSettings.textColor
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Label {
                            text: root.formatEpoch(root.conflictDetails.localLatestEpoch)
                            color: appSettings.textSecColor
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                // Cloud Card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: cloudCardCol.implicitHeight + 24
                    radius: 10
                    color: appSettings.surfaceContainerLow
                    border.color: appSettings.borderColor
                    border.width: 1

                    ColumnLayout {
                        id: cloudCardCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Label {
                            text: "EPIC CLOUD SAVES"
                            color: "#38bdf8"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                        Label {
                            text: "Remote Snapshot"
                            color: appSettings.textColor
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Label {
                            text: root.formatEpoch(root.conflictDetails.remoteLatestEpoch)
                            color: appSettings.textSecColor
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: safeLbl.implicitHeight + 16
                radius: 8
                color: Qt.rgba(34/255, 197/255, 94/255, 0.12)
                border.color: Qt.rgba(34/255, 197/255, 94/255, 0.35)
                border.width: 1

                Label {
                    id: safeLbl
                    anchors.fill: parent
                    anchors.margins: 8
                    text: "Safety backup: Downloading cloud saves automatically creates a local .tar.gz snapshot you can restore anytime from Game Details."
                    color: appSettings.textColor
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            // Action Buttons (Vertical stack for crisp readability & gamepad nav)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                M3Button {
                    id: downloadCloudBtn
                    objectName: "conflictDownloadCloudBtn"
                    Layout.fillWidth: true
                    text: "Download Cloud Saves & Play"
                    iconSymbol: "download"
                    buttonType: "filled"
                    onClicked: root.resolve("download")
                    Keys.onDownPressed: (event) => { event.accepted = true; uploadLocalBtn.forceActiveFocus() }
                }

                M3Button {
                    id: uploadLocalBtn
                    objectName: "conflictUploadLocalBtn"
                    Layout.fillWidth: true
                    text: "Keep Local Saves, Upload to Cloud & Play"
                    iconSymbol: "refresh"
                    buttonType: "tonal"
                    onClicked: root.resolve("upload")
                    Keys.onUpPressed: (event) => { event.accepted = true; downloadCloudBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { event.accepted = true; skipSyncBtn.forceActiveFocus() }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    M3Button {
                        id: skipSyncBtn
                        objectName: "conflictSkipSyncBtn"
                        Layout.fillWidth: true
                        text: "Launch Without Syncing"
                        buttonType: "tonal"
                        onClicked: root.resolve("skip")
                        Keys.onUpPressed: (event) => { event.accepted = true; uploadLocalBtn.forceActiveFocus() }
                        Keys.onRightPressed: (event) => { event.accepted = true; cancelConflictBtn.forceActiveFocus() }
                    }

                    M3Button {
                        id: cancelConflictBtn
                        objectName: "conflictCancelBtn"
                        text: "Cancel"
                        buttonType: "destructive"
                        onClicked: root.resolve("cancel")
                        Keys.onUpPressed: (event) => { event.accepted = true; uploadLocalBtn.forceActiveFocus() }
                        Keys.onLeftPressed: (event) => { event.accepted = true; skipSyncBtn.forceActiveFocus() }
                    }
                }
            }
        }
    }
}

