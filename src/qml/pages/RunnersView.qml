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

            YIcon {
                source: "qrc:/tsuki_app/icons/nav/runner.svg"
                color: appSettings.accentColor
                size: 28
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Label {
                    text: "Wine & Proton Runners"
                    color: appSettings.textColor
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                }
                Label {
                    text: "Manage installed Wine, Proton, Proton-GE, Proton-CachyOS, or download GitHub releases"
                    color: appSettings.textSecColor
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // Top-Right Refresh Button: Icon-only, circular, smooth hover & rotation
            Rectangle {
                id: scanBtn
                implicitWidth: 38
                implicitHeight: 38
                radius: 19
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                color: scanHover.hovered 
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                    : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
                border.color: scanHover.hovered ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                border.width: 1
                scale: scanMA.pressed ? 0.94 : (scanHover.hovered ? 1.05 : 1.0)

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 120 } }

                HoverHandler { id: scanHover }

                YIcon {
                    id: scanIcon
                    anchors.centerIn: parent
                    source: "qrc:/tsuki_app/icons/actions/refresh.svg"
                    color: scanHover.hovered ? appSettings.accentColor : appSettings.textColor
                    size: 18

                    RotationAnimation on rotation {
                        id: scanRotateAnim
                        from: 0
                        to: 360
                        duration: 600
                        running: false
                    }
                }

                ToolTip.visible: scanHover.hovered
                ToolTip.text: "Re-scan system for runners"
                ToolTip.delay: 300

                MouseArea {
                    id: scanMA
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        scanRotateAnim.restart()
                        uiController.runnerManager.detectInstalledRunners()
                    }
                }
            }
        }

        // ── Main 2-Column Responsive Layout ──────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20

            // Left Column: Installed Runners Card
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 480
                Layout.fillHeight: true
                radius: 20
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

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
                            color: runnerHover.hovered
                                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03))
                            border.color: modelData.isDefault ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                            border.width: modelData.isDefault ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            HoverHandler {
                                id: runnerHover
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 8

                                        Label {
                                            text: runnerDelegate.modelData.name
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 50
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
                                            color: {
                                                let t = (runnerDelegate.modelData.type || "").toUpperCase()
                                                if (t === "PROTON-CACHYOS") return Qt.rgba(appSettings.tagColorCachyos.r, appSettings.tagColorCachyos.g, appSettings.tagColorCachyos.b, 0.15)
                                                if (t === "PROTON-GE") return Qt.rgba(appSettings.tagColorProtonGe.r, appSettings.tagColorProtonGe.g, appSettings.tagColorProtonGe.b, 0.15)
                                                if (t === "PROTON") return Qt.rgba(appSettings.tagColorSteamProton.r, appSettings.tagColorSteamProton.g, appSettings.tagColorSteamProton.b, 0.15)
                                                return Qt.rgba(156/255, 163/255, 175/255, 0.15)
                                            }
                                            Label {
                                                id: rTypeLbl
                                                anchors.centerIn: parent
                                                text: {
                                                    let t = (runnerDelegate.modelData.type || "").toUpperCase()
                                                    if (t === "PROTON-CACHYOS") return "CACHYOS"
                                                    if (t === "PROTON-GE") return "PROTON-GE"
                                                    if (t === "PROTON") return "PROTON"
                                                    return t
                                                }
                                                color: {
                                                    let t = (runnerDelegate.modelData.type || "").toUpperCase()
                                                    if (t === "PROTON-CACHYOS") return appSettings.tagColorCachyos
                                                    if (t === "PROTON-GE") return appSettings.tagColorProtonGe
                                                    if (t === "PROTON") return appSettings.tagColorSteamProton
                                                    return "#9ca3af"
                                                }
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
                                        Layout.minimumWidth: 50
                                    }
                                }

                                RowLayout {
                                    spacing: 8
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                                    M3Button {
                                        visible: !runnerDelegate.modelData.isDefault
                                        text: "Set Default"
                                        buttonType: "tonal"
                                        Layout.preferredHeight: 30
                                        onClicked: appSettings.defaultRunnerId = runnerDelegate.modelData.id
                                    }

                                    M3Button {
                                        visible: !runnerDelegate.modelData.isSystem
                                        text: "Remove"
                                        buttonType: "destructive"
                                        Layout.preferredHeight: 30
                                        onClicked: uiController.runnerManager.uninstallRunner(runnerDelegate.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // ── Active Downloads Section (Lower portion of Installed Runners area) ──
                    Rectangle {
                        id: dlSection
                        visible: (uiController.downloadManager ? uiController.downloadManager.activeDownloadCount : 0) > 0
                        Layout.fillWidth: true
                        implicitHeight: dlCol.implicitHeight + 20
                        radius: 14
                        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                        border.color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.4)
                        border.width: 1

                        ColumnLayout {
                            id: dlCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                YIcon {
                                    source: "qrc:/tsuki_app/icons/actions/download.svg"
                                    color: appSettings.accentColor
                                    size: 16
                                }
                                Label {
                                    text: "Active Downloads (" + (uiController.downloadManager ? uiController.downloadManager.activeDownloadCount : 0) + ")"
                                    color: appSettings.textColor
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                }
                            }

                            Repeater {
                                model: uiController.downloadManager

                                delegate: Rectangle {
                                    id: dlItemDelegate
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    radius: 10
                                    color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.03)

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Label {
                                                text: model.title || "Downloading…"
                                                color: appSettings.textColor
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Label {
                                                text: (model.downloadedSizeStr || "0 B") + 
                                                      (model.totalSizeStr ? " / " + model.totalSizeStr : "") +
                                                      (model.eta ? " • " + model.eta : "")
                                                color: appSettings.textSecColor
                                                font.pixelSize: 11
                                            }

                                            Row {
                                                id: actionBtnsRow
                                                spacing: 6
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                                readonly property bool isCompact: dlItemDelegate.width < 450

                                                // Pause / Resume Button
                                                Rectangle {
                                                    id: pauseBtn
                                                    visible: !model.isExtracting
                                                    height: 26
                                                    width: actionBtnsRow.isCompact ? 26 : (pauseRow.implicitWidth + 20)
                                                    radius: 13
                                                    clip: true
                                                    color: pauseHover.hovered 
                                                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
                                                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                                                    border.color: pauseHover.hovered ? appSettings.accentColor : "transparent"
                                                    border.width: 1
                                                    scale: pauseMA.pressed ? 0.94 : 1.0

                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                    Behavior on scale { NumberAnimation { duration: 100 } }

                                                    HoverHandler { id: pauseHover }

                                                    Row {
                                                        id: pauseRow
                                                        anchors.centerIn: parent
                                                        spacing: 5
                                                        YIcon {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            source: model.isPaused ? "qrc:/tsuki_app/icons/actions/play.svg" : "qrc:/tsuki_app/icons/actions/pause.svg"
                                                            color: appSettings.textColor
                                                            size: 13
                                                        }
                                                        Label {
                                                            visible: !actionBtnsRow.isCompact
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: model.isPaused ? "Resume" : "Pause"
                                                            color: appSettings.textColor
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                        }
                                                    }

                                                    ToolTip.visible: pauseHover.hovered
                                                    ToolTip.text: model.isPaused ? "Resume download" : "Pause download"
                                                    ToolTip.delay: 300

                                                    MouseArea {
                                                        id: pauseMA
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: uiController.downloadManager.togglePauseDownload(model.id)
                                                    }
                                                }

                                                // Cancel Button
                                                Rectangle {
                                                    id: cancelBtn
                                                    height: 26
                                                    width: actionBtnsRow.isCompact ? 26 : (cancelRow.implicitWidth + 20)
                                                    radius: 13
                                                    clip: true
                                                    color: cancelHover.hovered 
                                                        ? "#ef4444"
                                                        : (appSettings.isEffectiveDark ? Qt.rgba(0.93, 0.27, 0.27, 0.15) : Qt.rgba(0.93, 0.27, 0.27, 0.09))
                                                    border.color: cancelHover.hovered ? "#ef4444" : Qt.rgba(0.93, 0.27, 0.27, 0.3)
                                                    border.width: 1
                                                    scale: cancelMA.pressed ? 0.94 : 1.0

                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                    Behavior on scale { NumberAnimation { duration: 100 } }

                                                    HoverHandler { id: cancelHover }

                                                    Row {
                                                        id: cancelRow
                                                        anchors.centerIn: parent
                                                        spacing: 5
                                                        YIcon {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            source: "qrc:/tsuki_app/icons/actions/close.svg"
                                                            color: cancelHover.hovered ? "#ffffff" : "#ef4444"
                                                            size: 12
                                                        }
                                                        Label {
                                                            visible: !actionBtnsRow.isCompact
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "Cancel"
                                                            color: cancelHover.hovered ? "#ffffff" : "#ef4444"
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                        }
                                                    }

                                                    ToolTip.visible: cancelHover.hovered
                                                    ToolTip.text: "Cancel download"
                                                    ToolTip.delay: 300

                                                    MouseArea {
                                                        id: cancelMA
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: uiController.downloadManager.cancelDownload(model.id)
                                                    }
                                                }
                                            }
                                        }

                                        // Progress bar
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 5
                                            radius: 2.5
                                            color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)

                                            Rectangle {
                                                height: parent.height
                                                width: parent.width * Math.max(0.0, Math.min(1.0, (model.progress || 0) / 100.0))
                                                radius: 2.5
                                                color: appSettings.accentColor
                                                Behavior on width { NumberAnimation { duration: 150 } }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Right Column: GitHub Releases Card
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 380
                Layout.fillHeight: true
                radius: 20
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

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

                    // Release Category Pills: 2 options only (Proton-GE and Proton-CachyOS)
                    M3SegmentedButton {
                        Layout.fillWidth: true
                        model: [
                            { label: "Proton-GE", val: 0 },
                            { label: "Proton-CachyOS", val: 1 }
                        ]
                        selectedValue: root.selectedReleaseCat === "proton-ge" ? 0 : 1
                        onSelectionChanged: (val) => {
                            root.selectedReleaseCat = (val === 0 ? "proton-ge" : "proton-cachyos")
                            uiController.runnerManager.fetchAvailableReleases(root.selectedReleaseCat)
                        }
                    }

                    // Releases List (Fills the entire remaining card area)
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
                            readonly property bool isDownloading: (uiController.downloadManager && uiController.downloadManager.isMediaDownloading("runner-dl-" + relRow.modelData.tagName)) || false
                            width: ListView.view.width
                            height: 52
                            radius: 12
                            color: relMA.hovered 
                                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03))
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)

                            HoverHandler {
                                id: relMA
                            }

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
                                    text: relRow.isDownloading ? "Downloading…" : (relRow.modelData.isInstalled ? "Installed ✓" : "Download")
                                    iconSource: relRow.modelData.isInstalled ? "qrc:/tsuki_app/icons/actions/check.svg" : "qrc:/tsuki_app/icons/actions/download.svg"
                                    buttonType: relRow.modelData.isInstalled ? "tonal" : "filled"
                                    enabled: !relRow.modelData.isInstalled && !relRow.isDownloading
                                    opacity: (relRow.modelData.isInstalled || relRow.isDownloading) ? 0.6 : 1.0
                                    onClicked: {
                                        uiController.runnerManager.downloadRelease(
                                            root.selectedReleaseCat,
                                            relRow.modelData.tagName,
                                            relRow.modelData.downloadUrl,
                                            relRow.modelData.fileName || ""
                                        )
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
