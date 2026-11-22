import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    objectName: "downloadsView"
    Layout.fillWidth: true
    Layout.fillHeight: true

    signal focusSidebarRequested()
    signal openGameDetailsRequested(string gameId, string epicAppName)

    readonly property var dlMgr: uiController ? uiController.downloadManager : null
    readonly property int pendingCount: dlMgr ? dlMgr.totalPendingCount : 0
    readonly property int activeCount: dlMgr ? dlMgr.activeDownloadCount : 0
    readonly property int queuedCount: dlMgr ? dlMgr.queuedDownloadCount : 0
    readonly property bool pausedForGameplay: dlMgr ? dlMgr.pausedForGameplay : false
    readonly property var historyList: dlMgr ? dlMgr.completedDownloads : []

    readonly property var speedOptions: [
        { label: "Unlimited", kbps: 0 },
        { label: "2 MB/s",    kbps: 2048 },
        { label: "5 MB/s",    kbps: 5120 },
        { label: "15 MB/s",   kbps: 15360 },
        { label: "50 MB/s",   kbps: 51200 }
    ]

    function focusFirstEnabledControl() {
        if (dlList.count > 0) {
            if (dlList.currentIndex < 0) dlList.currentIndex = 0
            dlList.forceActiveFocus()
            return
        }
        if (pauseAllBtn.enabled) {
            pauseAllBtn.forceActiveFocus()
            return
        }
        speedLimitCombo.forceActiveFocus()
    }

    function focusBelowControlsBar() {
        if (dlList.count > 0) {
            if (dlList.currentIndex < 0) dlList.currentIndex = 0
            dlList.forceActiveFocus()
        } else if (historySection.visible) {
            clearHistoryBtn.forceActiveFocus()
        }
    }

    function focusBelowDlList() {
        if (historySection.visible) {
            clearHistoryBtn.forceActiveFocus()
        }
    }

    function focusAboveHistory() {
        if (dlList.count > 0) {
            dlList.currentIndex = Math.max(0, dlList.count - 1)
            dlList.positionViewAtIndex(dlList.currentIndex, ListView.Contain)
            dlList.forceActiveFocus()
        } else {
            speedLimitCombo.forceActiveFocus()
        }
    }

    function forceFocus() {
        focusFirstEnabledControl()
    }

    function currentSpeedLimitIndex() {
        const cur = appSettings ? appSettings.downloadSpeedLimitKBps : 0
        for (let i = 0; i < speedOptions.length; ++i) {
            if (speedOptions[i].kbps === cur) return i
        }
        return 0
    }

    function handleViewCancel(event) {
        if (speedLimitCombo.popup.visible) {
            event.accepted = true
            speedLimitCombo.popup.close()
            speedLimitCombo.forceActiveFocus()
            return
        }
        event.accepted = true
        root.focusSidebarRequested()
    }

    Keys.onEscapePressed: (event) => root.handleViewCancel(event)
    Keys.onBackPressed: (event) => root.handleViewCancel(event)
    Keys.onPressed: (event) => {
        event.accepted = false
        if (event.key === Qt.Key_Backspace) {
            root.handleViewCancel(event)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 24
        anchors.bottomMargin: 24
        spacing: 18

        // ── Header ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            YIcon {
                source: "qrc:/tsuki_app/icons/actions/download.svg"
                color: appSettings.accentColor
                size: 28
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                RowLayout {
                    spacing: 10
                    Label {
                        text: "Downloads"
                        color: appSettings.textColor
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        font.letterSpacing: -0.4
                    }

                    Rectangle {
                        visible: root.dlMgr && root.dlMgr.aggregateSpeedText && root.dlMgr.aggregateSpeedText.length > 0
                        height: 22
                        implicitWidth: aggSpeedLbl.implicitWidth + 14
                        radius: 11
                        color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.16)
                        Label {
                            id: aggSpeedLbl
                            anchors.centerIn: parent
                            text: root.dlMgr ? root.dlMgr.aggregateSpeedText : ""
                            color: appSettings.accentColor
                            font.family: "JetBrains Mono NF"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        visible: root.pausedForGameplay
                        height: 22
                        implicitWidth: gpPauseLbl.implicitWidth + 14
                        radius: 11
                        color: Qt.rgba(0.96, 0.62, 0.04, 0.18)
                        border.color: Qt.rgba(0.96, 0.62, 0.04, 0.5)
                        border.width: 1
                        Label {
                            id: gpPauseLbl
                            anchors.centerIn: parent
                            text: "Paused while gaming"
                            color: "#f59e0b"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Label {
                    text: root.pendingCount > 0
                        ? (root.activeCount + " active · " + root.queuedCount + " queued · Managed across Epic Games, runners, and runtimes")
                        : "Manage game downloads, runner updates, bandwidth limits, and download queue"
                    color: appSettings.textSecColor
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                M3Button {
                    id: pauseAllBtn
                    objectName: "downloadsPauseAllBtn"
                    text: "Pause All"
                    iconSource: "qrc:/tsuki_app/icons/actions/pause.svg"
                    buttonType: "tonal"
                    enabled: root.pendingCount > 0
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: if (root.dlMgr) root.dlMgr.pauseAll()
                    Keys.onLeftPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                    Keys.onRightPressed: (event) => { event.accepted = true; if (resumeAllBtn.enabled) resumeAllBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { event.accepted = true; speedLimitCombo.forceActiveFocus() }
                }

                M3Button {
                    id: resumeAllBtn
                    objectName: "downloadsResumeAllBtn"
                    text: "Resume All"
                    iconSource: "qrc:/tsuki_app/icons/actions/play.svg"
                    buttonType: "filled"
                    enabled: root.pendingCount > 0
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: if (root.dlMgr) root.dlMgr.resumeAll()
                    Keys.onLeftPressed: (event) => { event.accepted = true; if (pauseAllBtn.enabled) pauseAllBtn.forceActiveFocus(); else root.focusSidebarRequested() }
                    Keys.onDownPressed: (event) => { event.accepted = true; gameplayPauseToggle.forceActiveFocus() }
                }
            }
        }

        // ── Quick Bandwidth & Gameplay Auto-Pause Control Bar ────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: controlsRow.implicitHeight + 22
            radius: 16
            color: appSettings.surfaceColor
            border.color: appSettings.borderColor
            border.width: 1

            RowLayout {
                id: controlsRow
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 11
                anchors.bottomMargin: 11
                spacing: 16

                Label {
                    text: "Speed Limit:"
                    color: appSettings.textSecColor
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                StyledCombo {
                    id: speedLimitCombo
                    objectName: "downloadsSpeedLimitCombo"
                    upDownNavigatesFocus: true
                    Layout.preferredWidth: 150
                    comboModel: {
                        let out = []
                        for (let i = 0; i < root.speedOptions.length; ++i) out.push(root.speedOptions[i].label)
                        return out
                    }
                    selectedIndex: root.currentSpeedLimitIndex()
                    onSelected: (idx) => {
                        if (appSettings && idx >= 0 && idx < root.speedOptions.length) {
                            appSettings.downloadSpeedLimitKBps = root.speedOptions[idx].kbps
                        }
                    }
                    Keys.onLeftPressed: (event) => {
                        if (popup.visible) { event.accepted = true; return }
                        event.accepted = true
                        root.focusSidebarRequested()
                    }
                    Keys.onRightPressed: (event) => {
                        if (popup.visible) { event.accepted = true; return }
                        event.accepted = true
                        gameplayPauseToggle.forceActiveFocus()
                    }
                    Keys.onUpPressed: (event) => {
                        if (popup.visible) { event.accepted = true; handleUp(); return }
                        event.accepted = true
                        if (pauseAllBtn.enabled) pauseAllBtn.forceActiveFocus()
                    }
                    Keys.onDownPressed: (event) => {
                        if (popup.visible) { event.accepted = true; handleDown(); return }
                        event.accepted = true
                        root.focusBelowControlsBar()
                    }
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: "Pause while gaming"
                    color: appSettings.textSecColor
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Toggle {
                    id: gameplayPauseToggle
                    objectName: "downloadsGameplayPauseToggle"
                    checked: appSettings ? appSettings.pauseDownloadsOnGameLaunch : true
                    onToggled: (c) => { if (appSettings) appSettings.pauseDownloadsOnGameLaunch = c }
                    Keys.onLeftPressed: (event) => { event.accepted = true; speedLimitCombo.forceActiveFocus() }
                    Keys.onUpPressed: (event) => { event.accepted = true; if (resumeAllBtn.enabled) resumeAllBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { event.accepted = true; root.focusBelowControlsBar() }
                }
            }
        }

        // ── Active & Queued Downloads List ───────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 200
            radius: 20
            color: appSettings.surfaceColor
            border.color: appSettings.borderColor
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "Active & Queued (" + root.pendingCount + ")"
                        color: appSettings.textColor
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: dlList
                        objectName: "downloadsActiveList"
                        anchors.fill: parent
                        focus: true
                        keyNavigationEnabled: false
                        clip: true
                        spacing: 10
                        model: root.dlMgr
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        onActiveFocusChanged: {
                            if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0
                        }

                        Keys.onUpPressed: (event) => {
                            event.accepted = true
                            if (currentIndex > 0) {
                                currentIndex--
                                positionViewAtIndex(currentIndex, ListView.Contain)
                            } else {
                                speedLimitCombo.forceActiveFocus()
                            }
                        }
                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            if (currentIndex < count - 1) {
                                currentIndex++
                                positionViewAtIndex(currentIndex, ListView.Contain)
                            } else {
                                root.focusBelowDlList()
                            }
                        }
                        Keys.onLeftPressed: (event) => {
                            event.accepted = true
                            root.focusSidebarRequested()
                        }
                        Keys.onRightPressed: (event) => {
                            event.accepted = true
                            if (currentItem && currentItem.focusFirstActionBtn) {
                                currentItem.focusFirstActionBtn()
                            }
                        }
                        Keys.onReturnPressed: (event) => {
                            event.accepted = true
                            if (currentItem && currentItem.togglePauseFn) currentItem.togglePauseFn()
                        }
                        Keys.onEnterPressed: (event) => {
                            event.accepted = true
                            if (currentItem && currentItem.togglePauseFn) currentItem.togglePauseFn()
                        }
                        Keys.onSpacePressed: (event) => {
                            event.accepted = true
                            if (currentItem && currentItem.togglePauseFn) currentItem.togglePauseFn()
                        }

                        delegate: Rectangle {
                            id: dlRow
                            required property int index
                            required property var model
                            readonly property bool isCurrentRow: Boolean(uiController && uiController.isKeyboardNavActive) && dlList.activeFocus && dlList.currentIndex === index
                            readonly property bool isQueuedItem: Boolean(model.isQueued)
                            readonly property bool isPausedItem: Boolean(model.isPaused)
                            readonly property bool isExtractingItem: Boolean(model.isExtracting)

                            function visibleActionButtons() {
                                const all = [dlStartNowBtn, dlMoveUpBtn, dlMoveDownBtn, dlPauseResumeBtn, dlCancelBtn]
                                let out = []
                                for (let i = 0; i < all.length; ++i) {
                                    if (all[i] && all[i].visible && all[i].enabled) out.push(all[i])
                                }
                                return out
                            }

                            function focusFirstActionBtn() {
                                const btns = visibleActionButtons()
                                if (btns.length > 0) btns[0].forceActiveFocus()
                            }

                            function stepActionButton(fromBtn, delta) {
                                const btns = visibleActionButtons()
                                const idx = btns.indexOf(fromBtn)
                                if (idx < 0) {
                                    dlList.forceActiveFocus()
                                    return
                                }
                                const next = idx + delta
                                if (next < 0) {
                                    dlList.forceActiveFocus()
                                } else if (next < btns.length) {
                                    btns[next].forceActiveFocus()
                                }
                            }

                            function stepRowFromButton(delta) {
                                const next = dlRow.index + delta
                                if (next < 0) {
                                    speedLimitCombo.forceActiveFocus()
                                } else if (next >= dlList.count) {
                                    root.focusBelowDlList()
                                } else {
                                    dlList.currentIndex = next
                                    dlList.positionViewAtIndex(next, ListView.Contain)
                                    dlList.forceActiveFocus()
                                }
                            }

                            function togglePauseFn() {
                                if (!root.dlMgr || isExtractingItem) return
                                if (isQueuedItem) root.dlMgr.prioritizeDownload(model.id)
                                else root.dlMgr.togglePauseDownload(model.id)
                            }

                            width: ListView.view.width
                            implicitHeight: rowInner.implicitHeight + 24
                            radius: 14
                            color: isCurrentRow
                                ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.10)
                                : appSettings.surfaceContainerLow
                            border.color: isCurrentRow ? appSettings.accentColor : appSettings.borderColor
                            border.width: isCurrentRow ? 2 : 1

                            RowLayout {
                                id: rowInner
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 14

                                // Cover or Kind Icon
                                Rectangle {
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 56
                                    radius: 8
                                    color: appSettings.surfaceContainerHigh
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: model.coverPath || ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        visible: Boolean(model.coverPath && String(model.coverPath).length > 0)
                                    }

                                    YIcon {
                                        anchors.centerIn: parent
                                        size: 20
                                        source: {
                                            const k = String(model.kind || "")
                                            if (k.indexOf("epic") === 0) return "qrc:/tsuki_app/icons/nav/epic-filled.svg"
                                            if (k === "runner") return "qrc:/tsuki_app/icons/nav/runner.svg"
                                            return "qrc:/tsuki_app/icons/actions/download.svg"
                                        }
                                        color: appSettings.accentColor
                                        visible: !model.coverPath || String(model.coverPath).length === 0
                                    }
                                }

                                // Details & Progress Bar
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Label {
                                            text: model.title || "Downloading…"
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Rectangle {
                                            height: 20
                                            implicitWidth: statusPillLbl.implicitWidth + 12
                                            radius: 10
                                            color: dlRow.isExtractingItem
                                                ? Qt.rgba(0.38, 0.65, 0.98, 0.18)
                                                : (dlRow.isQueuedItem
                                                    ? Qt.rgba(0.58, 0.64, 0.72, 0.18)
                                                    : (dlRow.isPausedItem
                                                        ? Qt.rgba(0.96, 0.62, 0.04, 0.18)
                                                        : Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.18)))
                                            Label {
                                                id: statusPillLbl
                                                anchors.centerIn: parent
                                                text: model.stageText || model.status || "Active"
                                                color: dlRow.isExtractingItem
                                                    ? "#60a5fa"
                                                    : (dlRow.isQueuedItem
                                                        ? appSettings.textSecColor
                                                        : (dlRow.isPausedItem ? "#f59e0b" : appSettings.accentColor))
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }

                                    // Progress Track
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 6
                                        radius: 3
                                        color: appSettings.surfaceContainerHighest

                                        Rectangle {
                                            height: parent.height
                                            width: parent.width * Math.max(0.0, Math.min(1.0, Number(model.progress || 0) / 100.0))
                                            radius: 3
                                            color: dlRow.isPausedItem ? "#f59e0b" : (dlRow.isQueuedItem ? appSettings.textTerColor : appSettings.accentColor)
                                            Behavior on width { NumberAnimation { duration: 150 } }
                                        }
                                    }

                                    // Stats Row
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        Label {
                                            text: Math.round(Number(model.progress || 0)) + "%  ·  " +
                                                  (model.downloadedSizeStr || "0 B") +
                                                  (model.totalSizeStr ? (" / " + model.totalSizeStr) : "")
                                            color: appSettings.textSecColor
                                            font.family: "JetBrains Mono NF"
                                            font.pixelSize: 11
                                        }

                                        Label {
                                            visible: Boolean(model.speedText && String(model.speedText).length > 0 && !dlRow.isPausedItem && !dlRow.isQueuedItem)
                                            text: String(model.speedText || "")
                                            color: appSettings.accentColor
                                            font.family: "JetBrains Mono NF"
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }

                                        Item { Layout.fillWidth: true }

                                        Label {
                                            visible: Boolean(model.eta && String(model.eta).length > 0 && !dlRow.isPausedItem && !dlRow.isQueuedItem)
                                            text: "ETA " + String(model.eta || "")
                                            color: appSettings.textTerColor
                                            font.pixelSize: 11
                                        }
                                    }
                                }

                                // Queue & Action Buttons
                                RowLayout {
                                    spacing: 6
                                    Layout.alignment: Qt.AlignVCenter

                                    M3Button {
                                        id: dlStartNowBtn
                                        visible: dlRow.isQueuedItem
                                        text: "Start Now"
                                        iconSource: "qrc:/tsuki_app/icons/actions/play.svg"
                                        buttonType: "filled"
                                        implicitHeight: 32
                                        onClicked: if (root.dlMgr) root.dlMgr.prioritizeDownload(model.id)
                                        Keys.onLeftPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlStartNowBtn, -1) }
                                        Keys.onRightPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlStartNowBtn, 1) }
                                        Keys.onUpPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(-1) }
                                        Keys.onDownPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(1) }
                                        Keys.onEscapePressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                        Keys.onBackPressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                    }

                                    M3Button {
                                        id: dlMoveUpBtn
                                        visible: dlList.count > 1 && dlRow.index > 0
                                        text: "↑"
                                        buttonType: "tonal"
                                        implicitHeight: 32
                                        implicitWidth: 34
                                        onClicked: if (root.dlMgr) root.dlMgr.moveQueueItemUp(model.id)
                                        Keys.onLeftPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlMoveUpBtn, -1) }
                                        Keys.onRightPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlMoveUpBtn, 1) }
                                        Keys.onUpPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(-1) }
                                        Keys.onDownPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(1) }
                                        Keys.onEscapePressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                        Keys.onBackPressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                    }

                                    M3Button {
                                        id: dlMoveDownBtn
                                        visible: dlList.count > 1 && dlRow.index < dlList.count - 1
                                        text: "↓"
                                        buttonType: "tonal"
                                        implicitHeight: 32
                                        implicitWidth: 34
                                        onClicked: if (root.dlMgr) root.dlMgr.moveQueueItemDown(model.id)
                                        Keys.onLeftPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlMoveDownBtn, -1) }
                                        Keys.onRightPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlMoveDownBtn, 1) }
                                        Keys.onUpPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(-1) }
                                        Keys.onDownPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(1) }
                                        Keys.onEscapePressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                        Keys.onBackPressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                    }

                                    M3Button {
                                        id: dlPauseResumeBtn
                                        visible: !dlRow.isExtractingItem && !dlRow.isQueuedItem
                                        text: dlRow.isPausedItem ? "Resume" : "Pause"
                                        iconSource: dlRow.isPausedItem
                                            ? "qrc:/tsuki_app/icons/actions/play.svg"
                                            : "qrc:/tsuki_app/icons/actions/pause.svg"
                                        buttonType: "tonal"
                                        implicitHeight: 32
                                        onClicked: if (root.dlMgr) root.dlMgr.togglePauseDownload(model.id)
                                        Keys.onLeftPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlPauseResumeBtn, -1) }
                                        Keys.onRightPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlPauseResumeBtn, 1) }
                                        Keys.onUpPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(-1) }
                                        Keys.onDownPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(1) }
                                        Keys.onEscapePressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                        Keys.onBackPressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                    }

                                    M3Button {
                                        id: dlCancelBtn
                                        text: "Cancel"
                                        iconSource: "qrc:/tsuki_app/icons/actions/close.svg"
                                        buttonType: "destructive"
                                        implicitHeight: 32
                                        onClicked: if (root.dlMgr) root.dlMgr.cancelDownload(model.id)
                                        Keys.onLeftPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlCancelBtn, -1) }
                                        Keys.onRightPressed: (event) => { event.accepted = true; dlRow.stepActionButton(dlCancelBtn, 1) }
                                        Keys.onUpPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(-1) }
                                        Keys.onDownPressed: (event) => { event.accepted = true; dlRow.stepRowFromButton(1) }
                                        Keys.onEscapePressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                        Keys.onBackPressed: (event) => { event.accepted = true; dlList.forceActiveFocus() }
                                    }
                                }
                            }
                        }
                    }

                    // Empty Queue State
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        visible: dlList.count === 0

                        YIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            source: "qrc:/tsuki_app/icons/actions/download.svg"
                            color: appSettings.textTerColor
                            size: 40
                            opacity: 0.55
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No Active Downloads"
                            color: appSettings.textColor
                            font.pixelSize: 17
                            font.weight: Font.Medium
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Downloads from Epic Games, Proton runners, and runtimes appear here."
                            color: appSettings.textSecColor
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }

        // ── Completed Downloads History ──────────────────────────────────────
        Rectangle {
            id: historySection
            visible: root.historyList && root.historyList.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(220, historyCol.implicitHeight + 28)
            radius: 18
            color: appSettings.surfaceColor
            border.color: appSettings.borderColor
            border.width: 1

            ColumnLayout {
                id: historyCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "Recent History (" + (root.historyList ? root.historyList.length : 0) + ")"
                        color: appSettings.textColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }

                    M3Button {
                        id: clearHistoryBtn
                        objectName: "downloadsClearHistoryBtn"
                        text: "Clear History"
                        buttonType: "tonal"
                        implicitHeight: 28
                        onClicked: {
                            if (root.dlMgr) root.dlMgr.clearCompletedHistory()
                            root.focusFirstEnabledControl()
                        }
                        Keys.onLeftPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                        Keys.onUpPressed: (event) => { event.accepted = true; root.focusAboveHistory() }
                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            if (historyListView.count > 0) {
                                if (historyListView.currentIndex < 0) historyListView.currentIndex = 0
                                historyListView.forceActiveFocus()
                            }
                        }
                    }
                }

                ListView {
                    id: historyListView
                    objectName: "downloadsHistoryList"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 60
                    focus: true
                    keyNavigationEnabled: false
                    clip: true
                    spacing: 6
                    model: root.historyList
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    onActiveFocusChanged: {
                        if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0
                    }

                    Keys.onUpPressed: (event) => {
                        event.accepted = true
                        if (currentIndex > 0) {
                            currentIndex--
                            positionViewAtIndex(currentIndex, ListView.Contain)
                        } else {
                            clearHistoryBtn.forceActiveFocus()
                        }
                    }
                    Keys.onDownPressed: (event) => {
                        event.accepted = true
                        if (currentIndex < count - 1) {
                            currentIndex++
                            positionViewAtIndex(currentIndex, ListView.Contain)
                        }
                    }
                    Keys.onLeftPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                    Keys.onRightPressed: (event) => {
                        event.accepted = true
                        if (currentItem && currentItem.openBtnItem && currentItem.openBtnItem.visible) {
                            currentItem.openBtnItem.forceActiveFocus()
                        }
                    }
                    Keys.onReturnPressed: (event) => {
                        event.accepted = true
                        if (currentItem && currentItem.activateHistoryRow) currentItem.activateHistoryRow()
                    }
                    Keys.onEnterPressed: (event) => {
                        event.accepted = true
                        if (currentItem && currentItem.activateHistoryRow) currentItem.activateHistoryRow()
                    }
                    Keys.onSpacePressed: (event) => {
                        event.accepted = true
                        if (currentItem && currentItem.activateHistoryRow) currentItem.activateHistoryRow()
                    }

                    delegate: Rectangle {
                        id: histRow
                        required property int index
                        required property var modelData
                        readonly property bool isCurrentRow: Boolean(uiController && uiController.isKeyboardNavActive) && historyListView.activeFocus && historyListView.currentIndex === index
                        readonly property Item openBtnItem: historyOpenBtn

                        function activateHistoryRow() {
                            if (modelData && modelData.success && modelData.targetGameId && String(modelData.targetGameId).length > 0) {
                                root.openGameDetailsRequested(String(modelData.targetGameId), String(modelData.appName || ""))
                            }
                        }

                        width: ListView.view.width
                        height: 44
                        radius: 10
                        color: isCurrentRow
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.10)
                            : appSettings.surfaceContainerLow
                        border.color: isCurrentRow ? appSettings.accentColor : "transparent"
                        border.width: isCurrentRow ? 1.5 : 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            YIcon {
                                size: 16
                                source: modelData.success
                                    ? "qrc:/tsuki_app/icons/actions/check.svg"
                                    : "qrc:/tsuki_app/icons/actions/close.svg"
                                color: modelData.success ? "#22c55e" : "#ef4444"
                            }

                            Label {
                                text: modelData.title || ""
                                color: appSettings.textColor
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                Layout.preferredWidth: 220
                            }

                            Label {
                                text: modelData.message || (modelData.success ? "Completed" : "Failed")
                                color: appSettings.textSecColor
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            M3Button {
                                id: historyOpenBtn
                                visible: Boolean(modelData.success && modelData.targetGameId && String(modelData.targetGameId).length > 0)
                                text: "Open"
                                buttonType: "tonal"
                                implicitHeight: 28
                                onClicked: histRow.activateHistoryRow()
                                Keys.onLeftPressed: (event) => { event.accepted = true; historyListView.forceActiveFocus() }
                                Keys.onUpPressed: (event) => {
                                    event.accepted = true
                                    if (histRow.index > 0) {
                                        historyListView.currentIndex = histRow.index - 1
                                        historyListView.positionViewAtIndex(historyListView.currentIndex, ListView.Contain)
                                        historyListView.forceActiveFocus()
                                    } else {
                                        clearHistoryBtn.forceActiveFocus()
                                    }
                                }
                                Keys.onDownPressed: (event) => {
                                    event.accepted = true
                                    if (histRow.index < historyListView.count - 1) {
                                        historyListView.currentIndex = histRow.index + 1
                                        historyListView.positionViewAtIndex(historyListView.currentIndex, ListView.Contain)
                                        historyListView.forceActiveFocus()
                                    }
                                }
                                Keys.onEscapePressed: (event) => { event.accepted = true; historyListView.forceActiveFocus() }
                                Keys.onBackPressed: (event) => { event.accepted = true; historyListView.forceActiveFocus() }
                            }
                        }
                    }
                }
            }
        }
    }
}

