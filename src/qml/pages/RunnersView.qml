import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    objectName: "runnersView"
    signal focusSidebarRequested()
    property string selectedReleaseCat: "proton-ge"

    function focusUmuButton() {
        if (umuActionBtn.visible && umuActionBtn.enabled) {
            umuActionBtn.forceActiveFocus()
            return true
        }
        if (umuRemoveBtn.visible && umuRemoveBtn.enabled) {
            umuRemoveBtn.forceActiveFocus()
            return true
        }
        return false
    }

    function focusLeftColumnTop() {
        if (focusUmuButton()) return
        if (installedList.count > 0) {
            if (installedList.currentIndex < 0) installedList.currentIndex = 0
            installedList.forceActiveFocus()
            return
        }
        if (dlSection.visible && dlRepeater.count > 0) {
            dlSection.focusedDlIndex = 0
            dlSection.forceActiveFocus()
            return
        }
        root.focusSidebarRequested()
    }

    function focusLeftColumnFromRight() {
        if (installedList.count > 0) {
            if (installedList.currentIndex < 0) installedList.currentIndex = 0
            installedList.forceActiveFocus()
            return
        }
        if (focusUmuButton()) return
        if (dlSection.visible && dlRepeater.count > 0) {
            dlSection.focusedDlIndex = 0
            dlSection.forceActiveFocus()
            return
        }
        root.focusSidebarRequested()
    }

    function forceFocus() {
        if (installedList.count > 0) {
            if (installedList.currentIndex < 0) installedList.currentIndex = 0
            installedList.forceActiveFocus()
        } else if (!focusUmuButton()) {
            releaseCatSeg.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        uiController.runnerManager.fetchAvailableReleases(root.selectedReleaseCat)
    }

    Keys.onEscapePressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
    Keys.onBackPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
    Keys.onPressed: (event) => {
        event.accepted = false
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
                    text: "Manage installed Wine, Proton, Proton-GE, Proton-CachyOS, Proton-Sarek, Proton-EM & UMU runtime"
                    color: appSettings.textSecColor
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // Top-Right Refresh Button: Icon-only, circular, smooth hover & rotation
            Rectangle {
                id: scanBtn
                objectName: "runnersScanBtn"
                focus: true
                readonly property bool kbFocused: scanBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                implicitWidth: 38
                implicitHeight: 38
                radius: 19
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                color: (scanHover.hovered || scanBtn.kbFocused)
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                    : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
                border.color: (scanHover.hovered || scanBtn.kbFocused) ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                border.width: scanBtn.kbFocused ? 2 : 1
                scale: scanMA.pressed ? 0.94 : ((scanHover.hovered || scanBtn.kbFocused) ? 1.05 : 1.0)

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 120 } }

                Keys.onReturnPressed: (event) => { event.accepted = true; scanRotateAnim.restart(); uiController.runnerManager.detectInstalledRunners(); uiController.runnerManager.fetchAvailableReleases(root.selectedReleaseCat, true) }
                Keys.onEnterPressed: (event) => { event.accepted = true; scanRotateAnim.restart(); uiController.runnerManager.detectInstalledRunners(); uiController.runnerManager.fetchAvailableReleases(root.selectedReleaseCat, true) }
                Keys.onSpacePressed: (event) => { event.accepted = true; scanRotateAnim.restart(); uiController.runnerManager.detectInstalledRunners(); uiController.runnerManager.fetchAvailableReleases(root.selectedReleaseCat, true) }
                Keys.onDownPressed: (event) => {
                    event.accepted = true
                    releaseCatSeg.forceActiveFocus()
                }
                Keys.onLeftPressed: (event) => {
                    event.accepted = true
                    root.focusLeftColumnTop()
                }
                Keys.onEscapePressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                Keys.onBackPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                Keys.onPressed: (event) => {
                    event.accepted = false
                    if (event.key === Qt.Key_Backspace) {
                        event.accepted = true
                        root.focusSidebarRequested()
                    }
                }

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
                        uiController.runnerManager.fetchAvailableReleases(root.selectedReleaseCat, true)
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

                    // UMU Launcher & Steam Linux Runtime Status Strip
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: umuBarRow.implicitHeight + 18
                        radius: 12
                        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                        border.color: (uiController.runnerManager && uiController.runnerManager.umuAvailable)
                            ? Qt.rgba(34/255, 197/255, 94/255, 0.35)
                            : appSettings.borderColor
                        border.width: 1

                        RowLayout {
                            id: umuBarRow
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 9
                            anchors.bottomMargin: 9
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    spacing: 6
                                    Label {
                                        text: "UMU Launcher (Protonfixes)"
                                        color: appSettings.textColor
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }
                                    Rectangle {
                                        height: 18
                                        implicitWidth: umuStatusLbl.implicitWidth + 10
                                        radius: 9
                                        color: (uiController.runnerManager && uiController.runnerManager.umuAvailable)
                                            ? Qt.rgba(34/255, 197/255, 94/255, 0.18)
                                            : Qt.rgba(0.58, 0.64, 0.72, 0.18)
                                        Label {
                                            id: umuStatusLbl
                                            anchors.centerIn: parent
                                            text: (uiController.runnerManager && uiController.runnerManager.isInstallingUmu)
                                                ? "INSTALLING"
                                                : ((uiController.runnerManager && uiController.runnerManager.umuAvailable) ? "READY" : "NOT INSTALLED")
                                            color: (uiController.runnerManager && uiController.runnerManager.umuAvailable) ? "#22c55e" : appSettings.textSecColor
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                                Label {
                                    text: {
                                        const rm = uiController.runnerManager
                                        if (!rm) return ""
                                        const slr = rm.steamRuntimeAvailable ? "Steam Runtime 3.0 (sniper) detected" : "Standalone mode"
                                        if (rm.umuAvailable) {
                                            const ver = rm.umuVersion ? (" · " + rm.umuVersion) : ""
                                            return "umu-run ready" + ver + " · " + slr
                                        }
                                        return "Install umu-launcher for Valve Protonfixes & Steam Runtime support · " + slr
                                    }
                                    color: appSettings.textSecColor
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            M3Button {
                                id: umuActionBtn
                                objectName: "runnersUmuInstallBtn"
                                visible: Boolean(uiController.runnerManager && !uiController.runnerManager.umuAvailable)
                                enabled: Boolean(uiController.runnerManager && !uiController.runnerManager.isInstallingUmu)
                                text: (uiController.runnerManager && uiController.runnerManager.isInstallingUmu) ? "Installing…" : "Install UMU"
                                iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                                buttonType: "filled"
                                implicitHeight: 30
                                onClicked: uiController.runnerManager.installUmuLauncher()
                                Keys.onUpPressed: (event) => { event.accepted = true; scanBtn.forceActiveFocus() }
                                Keys.onDownPressed: (event) => {
                                    event.accepted = true
                                    if (installedList.count > 0) {
                                        if (installedList.currentIndex < 0) installedList.currentIndex = 0
                                        installedList.forceActiveFocus()
                                    } else if (dlSection.visible && dlRepeater.count > 0) {
                                        dlSection.focusedDlIndex = 0
                                        dlSection.forceActiveFocus()
                                    }
                                }
                                Keys.onLeftPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                                Keys.onRightPressed: (event) => { event.accepted = true; releaseCatSeg.forceActiveFocus() }
                            }

                            M3Button {
                                id: umuRemoveBtn
                                objectName: "runnersUmuRemoveBtn"
                                visible: Boolean(uiController.runnerManager && uiController.runnerManager.umuAvailable)
                                text: "Remove"
                                buttonType: "tonal"
                                implicitHeight: 30
                                onClicked: uiController.runnerManager.removeUmuLauncher()
                                Keys.onUpPressed: (event) => { event.accepted = true; scanBtn.forceActiveFocus() }
                                Keys.onDownPressed: (event) => {
                                    event.accepted = true
                                    if (installedList.count > 0) {
                                        if (installedList.currentIndex < 0) installedList.currentIndex = 0
                                        installedList.forceActiveFocus()
                                    } else if (dlSection.visible && dlRepeater.count > 0) {
                                        dlSection.focusedDlIndex = 0
                                        dlSection.forceActiveFocus()
                                    }
                                }
                                Keys.onLeftPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                                Keys.onRightPressed: (event) => { event.accepted = true; releaseCatSeg.forceActiveFocus() }
                            }
                        }
                    }

                    ListView {
                        id: installedList
                        focus: true
                        keyNavigationEnabled: false
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 10
                        model: uiController.runnerManager.installedRunners
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        onActiveFocusChanged: {
                            if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0
                        }

                        Keys.onUpPressed: (event) => {
                            event.accepted = true
                            if (currentIndex > 0) {
                                currentIndex--
                                positionViewAtIndex(currentIndex, ListView.Contain)
                            } else if (!root.focusUmuButton()) {
                                scanBtn.forceActiveFocus()
                            }
                        }
                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            if (currentIndex < count - 1) {
                                currentIndex++
                                positionViewAtIndex(currentIndex, ListView.Contain)
                            } else if (dlSection.visible && dlRepeater.count > 0) {
                                dlSection.focusedDlIndex = 0
                                dlSection.forceActiveFocus()
                            }
                        }
                        Keys.onLeftPressed: (event) => {
                            event.accepted = true
                            root.focusSidebarRequested()
                        }
                        Keys.onRightPressed: (event) => {
                            event.accepted = true
                            if (currentItem) {
                                if (currentItem.setDefBtn && currentItem.setDefBtn.visible) {
                                    currentItem.setDefBtn.forceActiveFocus()
                                    return
                                }
                                if (currentItem.remBtn && currentItem.remBtn.visible) {
                                    currentItem.remBtn.forceActiveFocus()
                                    return
                                }
                            }
                            if (releasesList.count > 0) releasesList.forceActiveFocus()
                            else releaseCatSeg.forceActiveFocus()
                        }
                        Keys.onReturnPressed: (event) => {
                            event.accepted = true
                            if (currentItem) {
                                if (currentItem.setDefBtn && currentItem.setDefBtn.visible) currentItem.setDefBtn.clicked()
                                else if (currentItem.remBtn && currentItem.remBtn.visible) currentItem.remBtn.clicked()
                            }
                        }
                        Keys.onEnterPressed: (event) => {
                            event.accepted = true
                            if (currentItem) {
                                if (currentItem.setDefBtn && currentItem.setDefBtn.visible) currentItem.setDefBtn.clicked()
                                else if (currentItem.remBtn && currentItem.remBtn.visible) currentItem.remBtn.clicked()
                            }
                        }
                        Keys.onSpacePressed: (event) => {
                            event.accepted = true
                            if (currentItem) {
                                if (currentItem.setDefBtn && currentItem.setDefBtn.visible) currentItem.setDefBtn.clicked()
                                else if (currentItem.remBtn && currentItem.remBtn.visible) currentItem.remBtn.clicked()
                            }
                        }

                        delegate: Rectangle {
                            id: runnerDelegate
                            required property var modelData
                            required property int index
                            property alias setDefBtn: setDefBtnItem
                            property alias remBtn: remBtnItem
                            readonly property bool isCurrentRow: Boolean(uiController && uiController.isKeyboardNavActive) && installedList.activeFocus && installedList.currentIndex === index
                            width: ListView.view.width
                            height: 76
                            radius: 14
                            color: (runnerHover.hovered || isCurrentRow)
                                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03))
                            border.color: isCurrentRow ? appSettings.accentColor : (modelData.isDefault ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)))
                            border.width: (isCurrentRow || modelData.isDefault) ? 2 : 1
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
                                        id: setDefBtnItem
                                        visible: !runnerDelegate.modelData.isDefault
                                        text: "Set Default"
                                        buttonType: "tonal"
                                        Layout.preferredHeight: 30
                                        onClicked: appSettings.defaultRunnerId = runnerDelegate.modelData.id
                                        Keys.onLeftPressed: (event) => {
                                            event.accepted = true
                                            installedList.forceActiveFocus()
                                        }
                                        Keys.onRightPressed: (event) => {
                                            event.accepted = true
                                            if (remBtnItem.visible) remBtnItem.forceActiveFocus()
                                            else if (releasesList.count > 0) releasesList.forceActiveFocus()
                                            else releaseCatSeg.forceActiveFocus()
                                        }
                                        Keys.onUpPressed: (event) => {
                                            event.accepted = true
                                            if (installedList.currentIndex > 0) {
                                                installedList.forceActiveFocus()
                                                installedList.currentIndex--
                                                installedList.positionViewAtIndex(installedList.currentIndex, ListView.Contain)
                                            } else if (!root.focusUmuButton()) {
                                                scanBtn.forceActiveFocus()
                                            }
                                        }
                                        Keys.onDownPressed: (event) => {
                                            event.accepted = true
                                            if (installedList.currentIndex < installedList.count - 1) {
                                                installedList.forceActiveFocus()
                                                installedList.currentIndex++
                                                installedList.positionViewAtIndex(installedList.currentIndex, ListView.Contain)
                                            } else if (dlSection.visible && dlRepeater.count > 0) {
                                                dlSection.focusedDlIndex = 0
                                                dlSection.forceActiveFocus()
                                            }
                                        }
                                        Keys.onEscapePressed: (event) => { event.accepted = true; installedList.forceActiveFocus() }
                                        Keys.onBackPressed: (event) => { event.accepted = true; installedList.forceActiveFocus() }
                                    }

                                    M3Button {
                                        id: remBtnItem
                                        visible: !runnerDelegate.modelData.isSystem && (!runnerDelegate.modelData.isSteam || appSettings.allowDeleteSteamRunners)
                                        text: "Remove"
                                        buttonType: "destructive"
                                        Layout.preferredHeight: 30
                                        onClicked: uiController.runnerManager.uninstallRunner(runnerDelegate.modelData.id)
                                        Keys.onLeftPressed: (event) => {
                                            event.accepted = true
                                            if (setDefBtnItem.visible) setDefBtnItem.forceActiveFocus()
                                            else installedList.forceActiveFocus()
                                        }
                                        Keys.onRightPressed: (event) => {
                                            event.accepted = true
                                            if (releasesList.count > 0) releasesList.forceActiveFocus()
                                            else releaseCatSeg.forceActiveFocus()
                                        }
                                        Keys.onUpPressed: (event) => {
                                            event.accepted = true
                                            if (installedList.currentIndex > 0) {
                                                installedList.forceActiveFocus()
                                                installedList.currentIndex--
                                                installedList.positionViewAtIndex(installedList.currentIndex, ListView.Contain)
                                            } else if (!root.focusUmuButton()) {
                                                scanBtn.forceActiveFocus()
                                            }
                                        }
                                        Keys.onDownPressed: (event) => {
                                            event.accepted = true
                                            if (installedList.currentIndex < installedList.count - 1) {
                                                installedList.forceActiveFocus()
                                                installedList.currentIndex++
                                                installedList.positionViewAtIndex(installedList.currentIndex, ListView.Contain)
                                            } else if (dlSection.visible && dlRepeater.count > 0) {
                                                dlSection.focusedDlIndex = 0
                                                dlSection.forceActiveFocus()
                                            }
                                        }
                                        Keys.onEscapePressed: (event) => { event.accepted = true; installedList.forceActiveFocus() }
                                        Keys.onBackPressed: (event) => { event.accepted = true; installedList.forceActiveFocus() }
                                    }
                                }
                            }
                        }
                    }

                    // ── Active Runner Downloads Section (Strictly runner/runtime/tool downloads — excludes games) ──
                    Rectangle {
                        id: dlSection
                        visible: (uiController.downloadManager ? uiController.downloadManager.runnerDownloadCount : 0) > 0
                        Layout.fillWidth: true
                        implicitHeight: dlCol.implicitHeight + 20
                        radius: 14
                        focus: true
                        activeFocusOnTab: false
                        property int focusedDlIndex: 0
                        property int focusedDlAction: 0 // 0 = Pause/Resume, 1 = Cancel
                        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                        border.color: dlSection.activeFocus
                            ? appSettings.accentColor
                            : Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.4)
                        border.width: dlSection.activeFocus ? 2 : 1

                        function syncActionForRow() {
                            const item = dlRepeater.itemAt(focusedDlIndex)
                            if (item && !item.canPause) {
                                focusedDlAction = 1
                            }
                        }

                        onActiveFocusChanged: {
                            if (activeFocus) {
                                const cnt = dlRepeater.count
                                if (cnt > 0) {
                                    if (focusedDlIndex < 0) focusedDlIndex = 0
                                    if (focusedDlIndex >= cnt) focusedDlIndex = cnt - 1
                                    syncActionForRow()
                                }
                            }
                        }

                        onVisibleChanged: {
                            if (!visible && activeFocus) {
                                if (installedList.count > 0) installedList.forceActiveFocus()
                                else scanBtn.forceActiveFocus()
                            }
                        }

                        Keys.onUpPressed: (event) => {
                            event.accepted = true
                            if (focusedDlIndex > 0) {
                                focusedDlIndex--
                                syncActionForRow()
                            } else if (installedList.count > 0) {
                                installedList.currentIndex = installedList.count - 1
                                installedList.positionViewAtIndex(installedList.currentIndex, ListView.Contain)
                                installedList.forceActiveFocus()
                            } else if (!root.focusUmuButton()) {
                                scanBtn.forceActiveFocus()
                            }
                        }
                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            if (focusedDlIndex < dlRepeater.count - 1) {
                                focusedDlIndex++
                                syncActionForRow()
                            }
                        }
                        Keys.onLeftPressed: (event) => {
                            event.accepted = true
                            const item = dlRepeater.itemAt(focusedDlIndex)
                            if (focusedDlAction === 1 && item && item.canPause) {
                                focusedDlAction = 0
                            } else {
                                root.focusSidebarRequested()
                            }
                        }
                        Keys.onRightPressed: (event) => {
                            event.accepted = true
                            const item = dlRepeater.itemAt(focusedDlIndex)
                            if (focusedDlAction === 0) {
                                focusedDlAction = 1
                            } else if (releasesList.count > 0) {
                                releasesList.forceActiveFocus()
                            } else {
                                releaseCatSeg.forceActiveFocus()
                            }
                        }
                        Keys.onReturnPressed: (event) => {
                            event.accepted = true
                            const item = dlRepeater.itemAt(focusedDlIndex)
                            if (item) item.triggerFocusedAction()
                        }
                        Keys.onEnterPressed: (event) => {
                            event.accepted = true
                            const item = dlRepeater.itemAt(focusedDlIndex)
                            if (item) item.triggerFocusedAction()
                        }
                        Keys.onSpacePressed: (event) => {
                            event.accepted = true
                            const item = dlRepeater.itemAt(focusedDlIndex)
                            if (item) item.triggerFocusedAction()
                        }
                        Keys.onEscapePressed: (event) => {
                            event.accepted = true
                            if (installedList.count > 0) installedList.forceActiveFocus()
                            else root.focusSidebarRequested()
                        }
                        Keys.onBackPressed: (event) => {
                            event.accepted = true
                            if (installedList.count > 0) installedList.forceActiveFocus()
                            else root.focusSidebarRequested()
                        }
                        Keys.onPressed: (event) => {
                            event.accepted = false
                            if (event.key === Qt.Key_Backspace) {
                                event.accepted = true
                                if (installedList.count > 0) installedList.forceActiveFocus()
                                else root.focusSidebarRequested()
                            }
                        }

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
                                    text: "Active Runner Downloads (" + (uiController.downloadManager ? uiController.downloadManager.runnerDownloadCount : 0) + ")"
                                    color: appSettings.textColor
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                }
                            }

                            Repeater {
                                id: dlRepeater
                                model: uiController.downloadManager ? uiController.downloadManager.runnerDownloads : []

                                delegate: Rectangle {
                                    id: dlItemDelegate
                                    required property int index
                                    required property var modelData
                                    readonly property bool isRowFocused: dlSection.activeFocus && dlSection.focusedDlIndex === index
                                    readonly property bool canPause: !Boolean(modelData.isExtracting)
                                    readonly property bool isPauseFocused: isRowFocused && canPause && dlSection.focusedDlAction === 0
                                    readonly property bool isCancelFocused: isRowFocused && (!canPause || dlSection.focusedDlAction === 1)

                                    function triggerFocusedAction() {
                                        if (!uiController.downloadManager) return
                                        if (canPause && dlSection.focusedDlAction === 0) {
                                            uiController.downloadManager.togglePauseDownload(modelData.id)
                                        } else {
                                            uiController.downloadManager.cancelDownload(modelData.id)
                                        }
                                    }

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    radius: 10
                                    color: isRowFocused
                                        ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.10)
                                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.03))
                                    border.color: isRowFocused ? appSettings.accentColor : "transparent"
                                    border.width: isRowFocused ? 1.5 : 0

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Label {
                                                text: dlItemDelegate.modelData.title || "Downloading…"
                                                color: appSettings.textColor
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Label {
                                                text: (dlItemDelegate.modelData.downloadedSizeStr || "0 B") +
                                                      (dlItemDelegate.modelData.totalSizeStr ? " / " + dlItemDelegate.modelData.totalSizeStr : "") +
                                                      (dlItemDelegate.modelData.eta ? " • " + dlItemDelegate.modelData.eta : "")
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
                                                    visible: !Boolean(dlItemDelegate.modelData.isExtracting)
                                                    height: 26
                                                    width: actionBtnsRow.isCompact ? 26 : (pauseRow.implicitWidth + 20)
                                                    radius: 13
                                                    clip: true
                                                    color: (pauseHover.hovered || dlItemDelegate.isPauseFocused)
                                                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
                                                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                                                    border.color: (pauseHover.hovered || dlItemDelegate.isPauseFocused) ? appSettings.accentColor : "transparent"
                                                    border.width: dlItemDelegate.isPauseFocused ? 2 : 1
                                                    scale: pauseMA.pressed ? 0.94 : (dlItemDelegate.isPauseFocused ? 1.05 : 1.0)

                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                    Behavior on scale { NumberAnimation { duration: 100 } }

                                                    HoverHandler { id: pauseHover }

                                                    Row {
                                                        id: pauseRow
                                                        anchors.centerIn: parent
                                                        spacing: 5
                                                        YIcon {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            source: Boolean(dlItemDelegate.modelData.isPaused) ? "qrc:/tsuki_app/icons/actions/play.svg" : "qrc:/tsuki_app/icons/actions/pause.svg"
                                                            color: appSettings.textColor
                                                            size: 13
                                                        }
                                                        Label {
                                                            visible: !actionBtnsRow.isCompact
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: Boolean(dlItemDelegate.modelData.isPaused) ? "Resume" : "Pause"
                                                            color: appSettings.textColor
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                        }
                                                    }

                                                    ToolTip.visible: pauseHover.hovered
                                                    ToolTip.text: Boolean(dlItemDelegate.modelData.isPaused) ? "Resume download" : "Pause download"
                                                    ToolTip.delay: 300

                                                    MouseArea {
                                                        id: pauseMA
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: uiController.downloadManager.togglePauseDownload(dlItemDelegate.modelData.id)
                                                    }
                                                }

                                                // Cancel Button
                                                Rectangle {
                                                    id: cancelBtn
                                                    height: 26
                                                    width: actionBtnsRow.isCompact ? 26 : (cancelRow.implicitWidth + 20)
                                                    radius: 13
                                                    clip: true
                                                    color: (cancelHover.hovered || dlItemDelegate.isCancelFocused)
                                                        ? "#ef4444"
                                                        : (appSettings.isEffectiveDark ? Qt.rgba(0.93, 0.27, 0.27, 0.15) : Qt.rgba(0.93, 0.27, 0.27, 0.09))
                                                    border.color: dlItemDelegate.isCancelFocused
                                                        ? "#ffffff"
                                                        : (cancelHover.hovered ? "#ef4444" : Qt.rgba(0.93, 0.27, 0.27, 0.3))
                                                    border.width: dlItemDelegate.isCancelFocused ? 2 : 1
                                                    scale: cancelMA.pressed ? 0.94 : (dlItemDelegate.isCancelFocused ? 1.05 : 1.0)

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
                                                            color: (cancelHover.hovered || dlItemDelegate.isCancelFocused) ? "#ffffff" : "#ef4444"
                                                            size: 12
                                                        }
                                                        Label {
                                                            visible: !actionBtnsRow.isCompact
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "Cancel"
                                                            color: (cancelHover.hovered || dlItemDelegate.isCancelFocused) ? "#ffffff" : "#ef4444"
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
                                                        onClicked: uiController.downloadManager.cancelDownload(dlItemDelegate.modelData.id)
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
                                                width: parent.width * Math.max(0.0, Math.min(1.0, (dlItemDelegate.modelData.progress || 0) / 100.0))
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

                    // Release Category Pills (Proton-GE, CachyOS, Sarek, Proton-EM)
                    M3SegmentedButton {
                        id: releaseCatSeg
                        objectName: "runnersReleaseCatSeg"
                        Layout.fillWidth: true
                        model: [
                            { label: "Proton-GE", val: 0 },
                            { label: "CachyOS",   val: 1 },
                            { label: "Sarek",     val: 2 },
                            { label: "Proton-EM", val: 3 }
                        ]
                        selectedValue: {
                            if (root.selectedReleaseCat === "proton-cachyos") return 1
                            if (root.selectedReleaseCat === "proton-sarek") return 2
                            if (root.selectedReleaseCat === "proton-em") return 3
                            return 0
                        }
                        onSelectionChanged: (val) => {
                            const cats = ["proton-ge", "proton-cachyos", "proton-sarek", "proton-em"]
                            root.selectedReleaseCat = cats[val] || "proton-ge"
                            uiController.runnerManager.fetchAvailableReleases(root.selectedReleaseCat)
                        }
                        onEdgeLeft: root.focusLeftColumnFromRight()
                        Keys.onUpPressed: (event) => {
                            event.accepted = true
                            scanBtn.forceActiveFocus()
                        }
                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            if (cachyV3Row.visible) cachyV3Toggle.forceActiveFocus()
                            else if (releasesList.count > 0) releasesList.forceActiveFocus()
                        }
                    }

                    // CachyOS x86-64-v3 CPU Optimization Bar
                    RowLayout {
                        id: cachyV3Row
                        visible: root.selectedReleaseCat === "proton-cachyos"
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            Layout.fillWidth: true
                            text: (uiController.runnerManager && uiController.runnerManager.cpuSupportsX86_64V3)
                                ? "Prefer x86-64-v3 optimized builds (CPU supported)"
                                : "Prefer x86-64-v3 builds (CPU uses baseline x86-64)"
                            color: appSettings.textSecColor
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Toggle {
                            id: cachyV3Toggle
                            objectName: "runnersCachyV3Toggle"
                            checked: appSettings ? appSettings.preferX86_64V3Runners : false
                            onToggled: (c) => {
                                if (appSettings) {
                                    appSettings.preferX86_64V3Runners = c
                                    uiController.runnerManager.fetchAvailableReleases("proton-cachyos", true)
                                }
                            }
                            Keys.onUpPressed: (event) => { event.accepted = true; releaseCatSeg.forceActiveFocus() }
                            Keys.onDownPressed: (event) => {
                                event.accepted = true
                                if (releasesList.count > 0) releasesList.forceActiveFocus()
                            }
                            Keys.onLeftPressed: (event) => { event.accepted = true; root.focusLeftColumnFromRight() }
                        }
                    }

                    // Releases List (Fills the entire remaining card area)
                    ListView {
                        id: releasesList
                        focus: true
                        keyNavigationEnabled: false
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: uiController.runnerManager.availableReleases
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        onActiveFocusChanged: {
                            if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0
                        }

                        Keys.onUpPressed: (event) => {
                            event.accepted = true
                            if (currentIndex > 0) {
                                currentIndex--
                                positionViewAtIndex(currentIndex, ListView.Contain)
                            } else if (cachyV3Row.visible) {
                                cachyV3Toggle.forceActiveFocus()
                            } else {
                                releaseCatSeg.forceActiveFocus()
                            }
                        }
                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            if (currentIndex < count - 1) {
                                currentIndex++
                                positionViewAtIndex(currentIndex, ListView.Contain)
                            } else if (dlSection.visible && dlRepeater.count > 0) {
                                dlSection.focusedDlIndex = 0
                                dlSection.forceActiveFocus()
                            }
                        }
                        Keys.onLeftPressed: (event) => {
                            event.accepted = true
                            root.focusLeftColumnFromRight()
                        }
                        Keys.onReturnPressed: (event) => {
                            event.accepted = true
                            if (currentItem && currentItem.dlBtn && currentItem.dlBtn.enabled) currentItem.dlBtn.clicked()
                        }
                        Keys.onEnterPressed: (event) => {
                            event.accepted = true
                            if (currentItem && currentItem.dlBtn && currentItem.dlBtn.enabled) currentItem.dlBtn.clicked()
                        }
                        Keys.onSpacePressed: (event) => {
                            event.accepted = true
                            if (currentItem && currentItem.dlBtn && currentItem.dlBtn.enabled) currentItem.dlBtn.clicked()
                        }

                        delegate: Rectangle {
                            id: relRow
                            required property var modelData
                            required property int index
                            property alias dlBtn: dlBtnItem
                            readonly property bool isCurrentRow: Boolean(uiController && uiController.isKeyboardNavActive) && releasesList.activeFocus && releasesList.currentIndex === index
                            readonly property bool isDownloading: (uiController.downloadManager && uiController.downloadManager.isMediaDownloading("runner-dl-" + relRow.modelData.tagName)) || false
                            width: ListView.view.width
                            height: 52
                            radius: 12
                            color: (relMA.hovered || isCurrentRow)
                                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03))
                            border.color: isCurrentRow ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
                            border.width: isCurrentRow ? 2 : 1

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
                                    id: dlBtnItem
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
                                            relRow.modelData.fileName || "",
                                            relRow.modelData.sha512Url || ""
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
