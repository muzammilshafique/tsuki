import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Popup {
    id: root
    focus: true

    property int focusedIndex: 0
    property int focusedActionIndex: 0 // 0: Pause/Resume, 1: Cancel
    readonly property int activeCount: downloadManager ? downloadManager.activeDownloadCount : 0
    readonly property bool isPopupHovered: bgHover.hovered || contentHover.hovered
    property real scrollTargetY: 0

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 B"
        let b = Number(bytes)
        if (b < 1024) return b + " B"
        b /= 1024
        if (b < 1024) return b.toFixed(1) + " KB"
        b /= 1024
        if (b < 1024) return b.toFixed(1) + " MB"
        b /= 1024
        return b.toFixed(2) + " GB"
    }

    function scrollToIndex(idx) {
        if (idx < 0 || !dlListView || dlListView.count === 0) return
        let rowHeight = 76 + dlListView.spacing
        let itemTop = idx * rowHeight
        let itemBottom = itemTop + 76
        let maxScroll = Math.max(0, dlListView.contentHeight - dlListView.height)
        if (maxScroll <= 0) return

        let curTarget = dropdownScrollAnim.running ? scrollTargetY : dlListView.contentY
        let newTarget = curTarget

        let pad = 24
        if (itemTop - pad < curTarget) {
            newTarget = Math.max(0, itemTop - pad)
        } else if (itemBottom + pad > curTarget + dlListView.height) {
            newTarget = Math.min(maxScroll, itemBottom + pad - dlListView.height)
        }

        if (Math.abs(newTarget - dlListView.contentY) > 0.5) {
            scrollTargetY = newTarget
            dropdownScrollAnim.stop()
            dropdownScrollAnim.from = dlListView.contentY
            dropdownScrollAnim.to = newTarget
            dropdownScrollAnim.restart()
        }
    }

    function navigateDown() {
        if (dlListView && dlListView.count > 0) {
            root.focusedIndex = Math.min(dlListView.count - 1, root.focusedIndex + 1)
            scrollToIndex(root.focusedIndex)
        }
    }

    function navigateUp() {
        if (dlListView && dlListView.count > 0) {
            root.focusedIndex = Math.max(0, root.focusedIndex - 1)
            scrollToIndex(root.focusedIndex)
        }
    }

    function navigateLeft() { root.focusedActionIndex = 0 }
    function navigateRight() { root.focusedActionIndex = 1 }

    function triggerAction() {
        if (!downloadManager || !downloadManager.activeDownloads || root.focusedIndex < 0 || root.focusedIndex >= downloadManager.activeDownloads.length) {
            return
        }
        let item = downloadManager.activeDownloads[root.focusedIndex]
        if (!item || !item.id) return
        if (root.focusedActionIndex === 1) {
            downloadManager.cancelDownload(item.id)
        } else {
            downloadManager.togglePauseDownload(item.id)
        }
    }

    y: parent ? (parent.height + 8) : 52
    x: parent ? (parent.width - width) : 0
    width: 410
    padding: 16
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    transformOrigin: Popup.TopRight

    onAboutToShow: {
        root.focusedIndex = 0
        root.focusedActionIndex = 0
        root.scrollTargetY = 0
        if (dlListView) dlListView.contentY = 0
    }

    onOpened: contentCol.forceActiveFocus()
    onClosed: {
        if (parent && parent.forceActiveFocus) {
            parent.forceActiveFocus()
        }
    }

    NumberAnimation {
        id: dropdownScrollAnim
        target: dlListView
        property: "contentY"
        duration: 220
        easing.type: Easing.OutCubic
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.94; to: 1.0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
            NumberAnimation { property: "y"; from: parent ? (parent.height - 4) : 40; to: parent ? (parent.height + 8) : 52; duration: 200; easing.type: Easing.OutCubic }
        }
    }

    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 160; easing.type: Easing.InQuad }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 160; easing.type: Easing.InQuad }
            NumberAnimation { property: "y"; from: parent ? (parent.height + 8) : 52; to: parent ? (parent.height + 2) : 46; duration: 160; easing.type: Easing.InQuad }
        }
    }

    background: Rectangle {
        color: appSettings.surfaceColor
        radius: 16
        border.color: appSettings.borderColor
        border.width: 1

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.6 : 0.25)
            shadowBlur: 0.85
            shadowVerticalOffset: 6
        }

        HoverHandler { id: bgHover }
    }

    contentItem: ColumnLayout {
        id: contentCol
        focus: true
        spacing: 12
        width: parent.width

        Keys.onDownPressed: (event) => { event.accepted = true; root.navigateDown() }
        Keys.onUpPressed: (event) => { event.accepted = true; root.navigateUp() }
        Keys.onLeftPressed: (event) => { event.accepted = true; root.navigateLeft() }
        Keys.onRightPressed: (event) => { event.accepted = true; root.navigateRight() }
        Keys.onReturnPressed: (event) => { event.accepted = true; root.triggerAction() }
        Keys.onEnterPressed: (event) => { event.accepted = true; root.triggerAction() }
        Keys.onSpacePressed: (event) => { event.accepted = true; root.triggerAction() }
        Keys.onEscapePressed: (event) => {
            event.accepted = true
            root.close()
            if (parent && parent.forceActiveFocus) parent.forceActiveFocus()
        }

        HoverHandler { id: contentHover }

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            YIcon {
                size: 18
                source: "qrc:/tsuki_app/icons/actions/download.svg"
                color: appSettings.accentColor
            }

            Label {
                text: "Runner & Tool Downloads"
                color: appSettings.textColor
                font.pixelSize: 17
                font.weight: Font.Medium
                renderType: Text.QtRendering
                Layout.fillWidth: true
            }

            Rectangle {
                visible: root.activeCount > 0
                implicitWidth: Math.max(22, badgeText.implicitWidth + 12)
                implicitHeight: 22
                radius: 11
                color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.16)
                border.color: appSettings.accentColor
                border.width: 1

                Label {
                    id: badgeText
                    anchors.centerIn: parent
                    text: String(root.activeCount)
                    color: appSettings.accentColor
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    renderType: Text.QtRendering
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: appSettings.borderColor
            opacity: 0.6
        }

        // Empty state
        Item {
            visible: root.activeCount === 0
            Layout.fillWidth: true
            Layout.preferredHeight: 110

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                YIcon {
                    Layout.alignment: Qt.AlignHCenter
                    size: 30
                    source: "qrc:/tsuki_app/icons/actions/download.svg"
                    color: appSettings.textTerColor
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No active downloads"
                    color: appSettings.textColor
                    font.pixelSize: 16
                    font.weight: Font.Normal
                    renderType: Text.QtRendering
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Proton-GE, Wine, DXVK, and VKD3D downloads appear here"
                    color: appSettings.textTerColor
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    renderType: Text.QtRendering
                }
            }
        }

        // Active downloads list
        ListView {
            id: dlListView
            visible: root.activeCount > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(320, count * 84)
            clip: true
            spacing: 8
            currentIndex: root.focusedIndex
            boundsBehavior: Flickable.StopAtBounds
            model: downloadManager ? downloadManager.activeDownloads : []

            ScrollBar.vertical: ScrollBar {
                policy: dlListView.contentHeight > dlListView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                width: 5
                contentItem: Rectangle {
                    implicitWidth: 5
                    radius: 2.5
                    color: appSettings.accentColor
                    opacity: 0.5
                }
            }

            delegate: Rectangle {
                id: taskCard
                required property int index
                required property var modelData

                readonly property string itemId: modelData ? (modelData.id || "") : ""
                readonly property bool isDlFocused: root.visible && (root.focusedIndex === index)

                property real rawProgress: (modelData && modelData.progress !== undefined) ? modelData.progress : 0.0
                property real progressValue: rawProgress
                Behavior on progressValue { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                property string dlSizeStr: (modelData && modelData.downloadedSizeStr) ? modelData.downloadedSizeStr : "0 B"
                property string totalSizeStr: (modelData && modelData.totalSizeStr) ? modelData.totalSizeStr : ""
                property string etaStr: (modelData && modelData.eta) ? modelData.eta : ""
                property bool isPausedValue: (modelData && modelData.isPaused !== undefined) ? modelData.isPaused : false

                readonly property string itemTitle: {
                    if (!modelData) return ""
                    if (modelData.title && String(modelData.title).trim().length > 0) return String(modelData.title).trim()
                    return modelData.displayName || "Download"
                }

                Connections {
                    target: downloadManager
                    function onDownloadProgress(id, prog) {
                        if (taskCard.itemId === id) taskCard.rawProgress = prog
                    }
                    function onDownloadProgressDetailed(id, prog, bytesDl, totalB, spd, eta) {
                        if (taskCard.itemId === id) {
                            taskCard.rawProgress = prog
                            taskCard.dlSizeStr = root.formatBytes(bytesDl)
                            if (totalB > 0) taskCard.totalSizeStr = root.formatBytes(totalB)
                            taskCard.etaStr = eta
                        }
                    }
                    function onDownloadPaused(id) {
                        if (taskCard.itemId === id) {
                            taskCard.isPausedValue = true
                            taskCard.etaStr = "Paused"
                        }
                    }
                    function onDownloadResumed(id) {
                        if (taskCard.itemId === id) taskCard.isPausedValue = false
                    }
                }

                width: dlListView.width
                height: 76
                radius: 12

                HoverHandler {
                    id: cardHover
                    onHoveredChanged: { if (hovered) root.focusedIndex = taskCard.index }
                }

                readonly property bool isCardHovered: cardHover.hovered || cardMA.containsMouse || (pauseMA && pauseMA.containsMouse) || (cancelMA && cancelMA.containsMouse)

                color: {
                    if (isCardHovered) return appSettings.isEffectiveDark ? Qt.rgba(255, 255, 255, 0.05) : Qt.rgba(0, 0, 0, 0.04)
                    if (isDlFocused) return Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.12)
                    return appSettings.isEffectiveDark ? Qt.rgba(255, 255, 255, 0.02) : Qt.rgba(0, 0, 0, 0.02)
                }

                border.color: (isCardHovered || isDlFocused) ? appSettings.accentColor : appSettings.borderColor
                border.width: 1

                MouseArea {
                    id: cardMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.focusedIndex = taskCard.index
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Item {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        Layout.alignment: Qt.AlignVCenter

                        Canvas {
                            id: ringCanvas
                            anchors.fill: parent
                            antialiasing: true
                            property real progress: taskCard.progressValue
                            property bool isPaused: taskCard.isPausedValue
                            property color accent: appSettings.accentColor
                            onProgressChanged: requestPaint()
                            onIsPausedChanged: requestPaint()
                            onAccentChanged: requestPaint()

                            onPaint: {
                                let ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                let cx = width / 2
                                let cy = height / 2
                                let radius = (width / 2) - 3.5
                                let lineWidth = 3.2

                                ctx.beginPath()
                                ctx.arc(cx, cy, radius, 0, 2 * Math.PI)
                                ctx.lineWidth = lineWidth
                                ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.16)
                                ctx.stroke()

                                if (progress > 0) {
                                    ctx.beginPath()
                                    let startAngle = -0.5 * Math.PI
                                    let sweep = (Math.min(100.0, Math.max(0.0, progress)) / 100.0) * (2 * Math.PI)
                                    ctx.arc(cx, cy, radius, startAngle, startAngle + sweep)
                                    ctx.lineWidth = lineWidth
                                    ctx.strokeStyle = isPaused ? Qt.rgba(accent.r, accent.g, accent.b, 0.45) : accent
                                    ctx.lineCap = "round"
                                    ctx.stroke()
                                }
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            text: Math.round(taskCard.progressValue) + "%"
                            color: taskCard.isPausedValue ? appSettings.textSecColor : appSettings.accentColor
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            renderType: Text.QtRendering
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 3

                        Label {
                            text: taskCard.itemTitle
                            color: appSettings.textColor
                            font.pixelSize: 15
                            font.weight: Font.Normal
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            renderType: Text.QtRendering
                        }

                        RowLayout {
                            spacing: 5
                            Layout.fillWidth: true

                            Label {
                                text: taskCard.totalSizeStr.length > 0
                                      ? (taskCard.dlSizeStr + " / " + taskCard.totalSizeStr)
                                      : taskCard.dlSizeStr
                                color: appSettings.textSecColor
                                font.pixelSize: 12
                                renderType: Text.QtRendering
                            }

                            Label {
                                text: taskCard.isPausedValue ? "• Paused" : (taskCard.etaStr.length > 0 ? ("• " + taskCard.etaStr) : "")
                                color: taskCard.isPausedValue ? "#f59e0b" : appSettings.textTerColor
                                font.pixelSize: 12
                                renderType: Text.QtRendering
                                visible: text.length > 0
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 8

                        Rectangle {
                            id: pauseBtn
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 15
                            color: pauseMA.containsMouse ? appSettings.surfaceAltColor : "transparent"
                            border.color: pauseMA.containsMouse ? appSettings.accentColor : appSettings.borderColor
                            border.width: 1

                            YIcon {
                                anchors.centerIn: parent
                                size: 14
                                source: taskCard.isPausedValue
                                        ? "qrc:/tsuki_app/icons/actions/play.svg"
                                        : "qrc:/tsuki_app/icons/actions/pause.svg"
                                color: taskCard.isPausedValue ? appSettings.accentColor : appSettings.textSecColor
                            }

                            MouseArea {
                                id: pauseMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (downloadManager && taskCard.itemId.length > 0) {
                                        downloadManager.togglePauseDownload(taskCard.itemId)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: cancelBtn
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 15
                            color: cancelMA.containsMouse ? "#ef4444" : Qt.rgba(239/255, 68/255, 68/255, 0.12)
                            border.color: "#ef4444"
                            border.width: 1

                            YIcon {
                                anchors.centerIn: parent
                                size: 14
                                source: "qrc:/tsuki_app/icons/actions/close.svg"
                                color: cancelMA.containsMouse ? "#ffffff" : "#ef4444"
                            }

                            MouseArea {
                                id: cancelMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (downloadManager && taskCard.itemId.length > 0) {
                                        downloadManager.cancelDownload(taskCard.itemId)
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

