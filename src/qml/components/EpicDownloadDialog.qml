import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    objectName: "epicDownloadDialog"
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 48 : 580, 580)
    readonly property real maxBodyHeight: Math.max(200, (parent ? parent.height : 720) - 180)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 140; easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; from: 1.0; to: 0.96; duration: 140; easing.type: Easing.InCubic }
    }

    property string appName: ""
    property string gameTitle: ""
    property double downloadSizeBytes: 0
    property double installSizeBytes: 0
    property string downloadSizeStr: ""
    property string installSizeStr: ""

    property string installBaseDir: appSettings ? appSettings.defaultEpicInstallLocation : ""
    property int runnerIndex: 0
    property bool useDedicatedPrefix: false
    property int existingPrefixIndex: 0
    property string customPrefixName: ""
    property string customPrefixLocation: appSettings ? appSettings.defaultPrefixLocation : ""
    property string prefixArch: "win64"
    property bool allowBodyHeightAnim: false

    property var availableInstallTags: []
    property var selectedInstallTags: []
    property var availableDlcs: []
    property var selectedDlcAppNames: []

    function toggleInstallTag(tag) {
        let arr = Array.from(root.selectedInstallTags || [])
        const idx = arr.indexOf(tag)
        if (idx >= 0) arr.splice(idx, 1)
        else arr.push(tag)
        root.selectedInstallTags = arr
    }

    function toggleDlc(dlcApp) {
        let arr = Array.from(root.selectedDlcAppNames || [])
        const idx = arr.indexOf(dlcApp)
        if (idx >= 0) arr.splice(idx, 1)
        else arr.push(dlcApp)
        root.selectedDlcAppNames = arr
    }

    readonly property string resolvedInstallPreview: (uiController && uiController.epicService && root.gameTitle.length > 0)
        ? uiController.epicService.suggestInstallDirectory(root.installBaseDir, root.gameTitle)
        : root.installBaseDir

    readonly property double freeSpaceBytes: (uiController && uiController.epicService)
        ? uiController.epicService.getFreeDiskSpace(root.installBaseDir)
        : -1

    readonly property string freeSpaceStr: (uiController && uiController.epicService)
        ? uiController.epicService.getFreeDiskSpaceFormatted(root.installBaseDir)
        : "Unknown"

    readonly property bool hasInsufficientDiskSpace: root.installSizeBytes > 0 && root.freeSpaceBytes >= 0 && root.freeSpaceBytes < root.installSizeBytes

    signal downloadStarted(string appName)

    function findDefaultPrefixIndex() {
        const pfxs = (uiController && uiController.prefixManager && uiController.prefixManager.prefixes)
            ? uiController.prefixManager.prefixes : []
        for (let i = 0; i < pfxs.length; i++) {
            if (pfxs[i].id === "default-prefix") return i
        }
        return 0
    }

    function openForApp(targetAppName) {
        root.allowBodyHeightAnim = false
        root.appName = targetAppName || ""
        const epicMap = (uiController && uiController.epicService && root.appName.length > 0)
            ? uiController.epicService.getEpicGameMap(root.appName) : ({})
        root.gameTitle = epicMap.title || root.appName
        root.downloadSizeBytes = Number(epicMap.downloadSize || 0)
        root.installSizeBytes = Number(epicMap.installSize || 0)
        root.downloadSizeStr = epicMap.downloadSizeFormatted || ""
        root.installSizeStr = epicMap.installSizeFormatted || ""

        root.installBaseDir = appSettings ? appSettings.defaultEpicInstallLocation : ""
        root.runnerIndex = 0 // Global Default runner
        root.useDedicatedPrefix = false // Default to existing Default prefix
        root.existingPrefixIndex = findDefaultPrefixIndex()
        root.customPrefixName = (uiController && uiController.prefixManager)
            ? uiController.prefixManager.suggestShortPrefixName(root.gameTitle) : ""
        root.customPrefixLocation = appSettings ? appSettings.defaultPrefixLocation : ""
        root.prefixArch = "win64"

        root.availableInstallTags = (uiController && uiController.epicService && root.appName.length > 0)
            ? uiController.epicService.getInstallTagsForGame(root.appName) : []
        root.selectedInstallTags = []
        root.availableDlcs = (uiController && uiController.epicService && root.appName.length > 0)
            ? uiController.epicService.getDlcsForGame(root.appName) : []
        root.selectedDlcAppNames = []

        if (uiController && uiController.epicService && root.appName.length > 0) {
            uiController.epicService.fetchInstallInfo(root.appName)
        }

        root.open()
        openFocusTimer.restart()
    }

    Connections {
        target: (uiController && uiController.epicService) ? uiController.epicService : null
        function onInstallInfoReady(app, dlSize, instSize) {
            if (app === root.appName && root.visible) {
                const epicMap = uiController.epicService.getEpicGameMap(root.appName)
                root.downloadSizeBytes = Number(dlSize || 0)
                root.installSizeBytes = Number(instSize || 0)
                root.downloadSizeStr = epicMap.downloadSizeFormatted || ""
                root.installSizeStr = epicMap.installSizeFormatted || ""
            }
        }
        function onInstallDetailsReady(app, installTags, dlcs) {
            if (app === root.appName && root.visible) {
                root.availableInstallTags = installTags || []
                root.availableDlcs = dlcs || []
            }
        }
    }

    function isAnyComboPopupOpen() {
        return dlRunnerCombo.popup.visible || dlPrefixCombo.popup.visible
    }

    function closeOpenComboPopup() {
        const combos = [dlRunnerCombo, dlPrefixCombo]
        for (let i = 0; i < combos.length; i++) {
            if (combos[i] && combos[i].popup.visible) {
                combos[i].popup.close()
                combos[i].forceActiveFocus()
                return true
            }
        }
        return false
    }

    function isAnyTextEditing() {
        return installDirField.isEditing
            || customPfxNameField.isEditing
            || customPfxLocField.isEditing
    }

    function getFocusGrid() {
        let rows = [
            [installDirField, browseDirBtn],
            [dlRunnerCombo],
            [pfxModePills]
        ]
        if (root.useDedicatedPrefix) {
            rows.push([customPfxNameField, archModePills])
            rows.push([customPfxLocField, customPfxBrowseBtn])
        } else {
            rows.push([dlPrefixCombo])
        }
        if (typeof dlInstallTagsRepeater !== "undefined" && dlInstallTagsRepeater) {
            for (let ti = 0; ti < dlInstallTagsRepeater.count; ++ti) {
                const tagItem = dlInstallTagsRepeater.itemAt(ti)
                if (tagItem && tagItem.visible) rows.push([tagItem])
            }
        }
        if (typeof dlAvailableDlcsRepeater !== "undefined" && dlAvailableDlcsRepeater) {
            for (let di = 0; di < dlAvailableDlcsRepeater.count; ++di) {
                const dlcItem = dlAvailableDlcsRepeater.itemAt(di)
                if (dlcItem && dlcItem.visible) rows.push([dlcItem])
            }
        }
        rows.push([cancelDlBtn, startDlBtn])
        return rows
    }

    function findFocusCoords(rows) {
        const fi = dialogContentCol.Window ? dialogContentCol.Window.activeFocusItem : null
        for (let r = 0; r < rows.length; r++) {
            for (let c = 0; c < rows[r].length; c++) {
                const it = rows[r][c]
                if (it && (it.activeFocus || fi === it)) {
                    return { r: r, c: c }
                }
            }
        }
        return { r: -1, c: 0 }
    }

    function navigateStep(dr, dc) {
        if (isAnyComboPopupOpen()) return false
        const rows = getFocusGrid()
        const pos = findFocusCoords(rows)
        if (pos.r < 0) {
            startDlBtn.forceActiveFocus()
            return true
        }
        if (dr !== 0) {
            const nr = pos.r + dr
            if (nr >= 0 && nr < rows.length) {
                const nextRow = rows[nr]
                const target = nextRow[Math.min(pos.c, nextRow.length - 1)]
                if (target) {
                    target.forceActiveFocus()
                    return true
                }
            }
            return false
        }
        if (dc !== 0) {
            const nc = pos.c + dc
            if (nc >= 0 && nc < rows[pos.r].length) {
                const target = rows[pos.r][nc]
                if (target) {
                    target.forceActiveFocus()
                    return true
                }
            }
        }
        return false
    }

    function handleDialogCancelKey(event) {
        if (root.closeOpenComboPopup()) {
            event.accepted = true
            return true
        }
        if (root.isAnyTextEditing()) {
            event.accepted = false
            return false
        }
        event.accepted = true
        root.close()
        return true
    }

    function handleDialogKeyPress(event) {
        event.accepted = false
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
            handleDialogCancelKey(event)
            return
        }
        if (root.isAnyComboPopupOpen() || root.isAnyTextEditing()) return

        if (event.key === Qt.Key_Up) {
            event.accepted = true
            root.navigateStep(-1, 0)
        } else if (event.key === Qt.Key_Down) {
            event.accepted = true
            root.navigateStep(1, 0)
        } else if (event.key === Qt.Key_Left) {
            event.accepted = true
            root.navigateStep(0, -1)
        } else if (event.key === Qt.Key_Right) {
            event.accepted = true
            root.navigateStep(0, 1)
        }
    }

    Timer {
        id: openFocusTimer
        interval: 0
        repeat: false
        onTriggered: startDlBtn.forceActiveFocus()
    }

    onOpened: Qt.callLater(() => { root.allowBodyHeightAnim = true })
    onClosed: root.allowBodyHeightAnim = false

    background: Rectangle {
        objectName: "epicDownloadDialogBg"
        color: appSettings.surfaceColor
        radius: 12
        border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
        border.width: 1
        layer.enabled: root.visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.60 : 0.22)
            shadowBlur: 0.75
            shadowVerticalOffset: 8
        }
    }

    contentItem: ColumnLayout {
        id: dialogContentCol
        focus: true
        spacing: 0
        Keys.onEscapePressed: (event) => root.handleDialogCancelKey(event)
        Keys.onBackPressed: (event) => root.handleDialogCancelKey(event)
        Keys.onPressed: (event) => root.handleDialogKeyPress(event)

        // ── Header ───────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 60

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 10

                YIcon {
                    size: 20
                    symbol: "download"
                    color: appSettings.accentColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Label {
                        objectName: "epicDownloadDialogTitle"
                        text: "Download Game"
                        color: appSettings.textColor
                        font.family: "Rubik"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        renderType: Text.QtRendering
                    }

                    Label {
                        text: root.gameTitle
                        color: appSettings.textSecColor
                        font.family: "Rubik"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    height: 22
                    radius: 6
                    implicitWidth: epicBadgeLbl.implicitWidth + 14
                    color: appSettings.secondaryContainer
                    Label {
                        id: epicBadgeLbl
                        anchors.centerIn: parent
                        text: "Epic Games"
                        color: appSettings.onSecondaryContainer
                        font.family: "JetBrains Mono NF"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }

                Item {
                    width: 32
                    height: 32
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: appSettings.surfaceContainerHighest
                        opacity: closeBtnHover.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    }
                    YIcon {
                        anchors.centerIn: parent
                        symbol: "close"
                        color: closeBtnHover.hovered ? appSettings.textColor : appSettings.textSecColor
                        size: 17
                    }
                    HoverHandler { id: closeBtnHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
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

        // ── Body ─────────────────────────────────────────────────────────────
        ScrollView {
            id: dialogScroll
            focus: false
            activeFocusOnTab: false
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(root.maxBodyHeight, dialogFormCol.implicitHeight + 28)
            Behavior on Layout.preferredHeight {
                enabled: root.allowBodyHeightAnim
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            contentWidth: availableWidth
            clip: true

            Item {
                width: dialogScroll.availableWidth
                implicitHeight: dialogFormCol.implicitHeight + 28

                ColumnLayout {
                    id: dialogFormCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.topMargin: 14
                    spacing: 12
                    Keys.onEscapePressed: (event) => root.handleDialogCancelKey(event)
                    Keys.onBackPressed: (event) => root.handleDialogCancelKey(event)
                    Keys.onPressed: (event) => root.handleDialogKeyPress(event)

                    // Card 1: Install Location
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 10
                        color: appSettings.surfaceContainerLow
                        border.color: appSettings.borderColor
                        border.width: 1
                        implicitHeight: locCardCol.implicitHeight + 28

                        ColumnLayout {
                            id: locCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 8

                            Label {
                                text: "Download Location"
                                color: appSettings.textSecColor
                                font.family: "Rubik"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                M3TextField {
                                    id: installDirField
                                    objectName: "epicDlPathField"
                                    fieldRadius: 10
                                    twoStageFocus: true
                                    Layout.fillWidth: true
                                    text: root.installBaseDir
                                    placeholderText: "~/Games/Epic"
                                    onTextChanged: root.installBaseDir = text
                                    onCommit: (val) => root.installBaseDir = val
                                    onMoveUp: root.navigateStep(-1, 0)
                                    onMoveDown: root.navigateStep(1, 0)
                                }

                                M3Button {
                                    id: browseDirBtn
                                    objectName: "epicDlBrowseBtn"
                                    text: "Browse"
                                    iconSymbol: "folder_open"
                                    buttonType: "tonal"
                                    onClicked: {
                                        if (!uiController) return
                                        const d = uiController.selectFolder("Select Game Install Location", root.installBaseDir)
                                        if (d && d.length > 0) {
                                            root.installBaseDir = d
                                        }
                                    }
                                }
                            }

                            Label {
                                text: "Install Folder: " + root.resolvedInstallPreview
                                color: appSettings.textTerColor
                                font.family: "JetBrains Mono NF"
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: statsStripRow.implicitHeight + 14
                                radius: 8
                                color: appSettings.surfaceContainer
                                border.color: appSettings.borderColor
                                border.width: 1

                                RowLayout {
                                    id: statsStripRow
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12

                                    Label {
                                        visible: root.downloadSizeStr.length > 0
                                        text: "Download: " + root.downloadSizeStr
                                        color: appSettings.textSecColor
                                        font.pixelSize: 12
                                    }

                                    Label {
                                        visible: root.installSizeStr.length > 0
                                        text: "Required: " + root.installSizeStr
                                        color: appSettings.textSecColor
                                        font.pixelSize: 12
                                    }

                                    Item { Layout.fillWidth: true }

                                    Label {
                                        text: "Free Space: " + root.freeSpaceStr
                                        color: root.hasInsufficientDiskSpace ? "#ef4444" : appSettings.accentColor
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }

                    // Card 2: Wine Prefix & Proton Runner
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 10
                        color: appSettings.surfaceContainerLow
                        border.color: appSettings.borderColor
                        border.width: 1
                        implicitHeight: compatCardCol.implicitHeight + 28

                        ColumnLayout {
                            id: compatCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10

                            // Proton / Runner selector (defaults to Global Default)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Label {
                                    Layout.preferredWidth: 100
                                    text: "Proton / Runner"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                StyledCombo {
                                    id: dlRunnerCombo
                                    objectName: "epicDlRunnerCombo"
                                    upDownNavigatesFocus: true
                                    Layout.fillWidth: true
                                    readonly property var runnerList: (uiController && uiController.runnerManager)
                                        ? uiController.runnerManager.installedRunners : []
                                    comboModel: {
                                        let defName = "System Wine"
                                        for (let i = 0; i < runnerList.length; i++) {
                                            if (appSettings && runnerList[i].id === appSettings.defaultRunnerId) {
                                                defName = runnerList[i].name
                                                break
                                            }
                                        }
                                        if (defName === "System Wine" && runnerList.length > 0) {
                                            defName = runnerList[0].name
                                        }
                                        let list = ["Default (" + defName + ")"]
                                        for (let i = 0; i < runnerList.length; i++) {
                                            list.push(runnerList[i].name)
                                        }
                                        return list
                                    }
                                    selectedIndex: root.runnerIndex
                                    onSelected: (idx) => root.runnerIndex = idx
                                }
                            }

                            // Wine Prefix mode (defaults to Existing -> Default prefix)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Label {
                                    Layout.preferredWidth: 100
                                    text: "Wine Prefix"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }

                                Item { Layout.fillWidth: true }

                                M3PillGroup {
                                    id: pfxModePills
                                    pillHeight: 34
                                    fontSize: 13
                                    model: [
                                        { label: "Existing",  val: 0, iconSymbol: "folder_open" },
                                        { label: "Dedicated", val: 1, iconSymbol: "add" }
                                    ]
                                    selectedValue: root.useDedicatedPrefix ? 1 : 0
                                    onSelectionChanged: (val) => root.useDedicatedPrefix = (Number(val) === 1)
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: appSettings.borderColor
                            }

                            // Smoothly animated Existing vs Dedicated Prefix options container
                            Item {
                                id: dlPrefixModeStack
                                Layout.fillWidth: true
                                clip: true
                                implicitHeight: root.useDedicatedPrefix ? dedicatedPrefixCol.implicitHeight : existingPrefixRow.implicitHeight
                                Behavior on implicitHeight {
                                    enabled: root.allowBodyHeightAnim
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }

                                // Existing Prefix selector (defaults to Default prefix)
                                RowLayout {
                                    id: existingPrefixRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 12
                                    opacity: !root.useDedicatedPrefix ? 1.0 : 0.0
                                    enabled: !root.useDedicatedPrefix
                                    visible: opacity > 0.01
                                    Behavior on opacity {
                                        enabled: root.allowBodyHeightAnim
                                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }
                                    Label {
                                        Layout.preferredWidth: 100
                                        text: "Select Prefix"
                                        color: appSettings.textSecColor
                                        font.family: "Rubik"
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }
                                    StyledCombo {
                                        id: dlPrefixCombo
                                        objectName: "epicDlPrefixCombo"
                                        upDownNavigatesFocus: true
                                        openUpward: true
                                        Layout.fillWidth: true
                                        readonly property var pfxList: (uiController && uiController.prefixManager)
                                            ? uiController.prefixManager.prefixes : []
                                        comboModel: {
                                            let list = []
                                            for (let i = 0; i < pfxList.length; i++) {
                                                list.push(pfxList[i].name)
                                            }
                                            return list.length > 0 ? list : ["Default"]
                                        }
                                        selectedIndex: root.existingPrefixIndex
                                        onSelected: (idx) => root.existingPrefixIndex = idx
                                    }
                                }

                                // Dedicated Prefix options
                                ColumnLayout {
                                    id: dedicatedPrefixCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 10
                                    opacity: root.useDedicatedPrefix ? 1.0 : 0.0
                                    enabled: root.useDedicatedPrefix
                                    visible: opacity > 0.01
                                    Behavior on opacity {
                                        enabled: root.allowBodyHeightAnim
                                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Label {
                                                text: "Prefix Name"
                                                color: appSettings.textSecColor
                                                font.family: "Rubik"
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                            }
                                            M3TextField {
                                                id: customPfxNameField
                                                fieldRadius: 10
                                                twoStageFocus: true
                                                Layout.fillWidth: true
                                                text: root.customPrefixName
                                                onTextChanged: root.customPrefixName = text
                                                onCommit: (val) => root.customPrefixName = val
                                                onMoveUp: root.navigateStep(-1, 0)
                                                onMoveDown: root.navigateStep(1, 0)
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.alignment: Qt.AlignBottom
                                            spacing: 4
                                            Label {
                                                text: "Arch"
                                                color: appSettings.textSecColor
                                                font.family: "Rubik"
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                            }
                                            M3PillGroup {
                                                id: archModePills
                                                pillHeight: 46
                                                fontSize: 13
                                                model: [
                                                    { label: "64-bit", val: "win64" },
                                                    { label: "32-bit", val: "win32" }
                                                ]
                                                selectedValue: root.prefixArch
                                                onSelectionChanged: (val) => root.prefixArch = String(val)
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Label {
                                            text: "Prefix Folder"
                                            color: appSettings.textSecColor
                                            font.family: "Rubik"
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            M3TextField {
                                                id: customPfxLocField
                                                fieldRadius: 10
                                                twoStageFocus: true
                                                Layout.fillWidth: true
                                                text: root.customPrefixLocation
                                                onTextChanged: root.customPrefixLocation = text
                                                onCommit: (val) => root.customPrefixLocation = val
                                                onMoveUp: root.navigateStep(-1, 0)
                                                onMoveDown: root.navigateStep(1, 0)
                                            }
                                            M3Button {
                                                id: customPfxBrowseBtn
                                                text: "Folder"
                                                iconSymbol: "folder_open"
                                                buttonType: "tonal"
                                                onClicked: {
                                                    if (!uiController) return
                                                    const d = uiController.selectFolder("Select Custom Prefix Base Directory", root.customPrefixLocation)
                                                    if (d && d.length > 0) root.customPrefixLocation = d
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Card 3: Optional Components (Install Tags) & Owned DLCs
                    Rectangle {
                        visible: (root.availableInstallTags && root.availableInstallTags.length > 0)
                              || (root.availableDlcs && root.availableDlcs.length > 0)
                        Layout.fillWidth: true
                        radius: 10
                        color: appSettings.surfaceContainerLow
                        border.color: appSettings.borderColor
                        border.width: 1
                        implicitHeight: dlcTagsCol.implicitHeight + 28

                        ColumnLayout {
                            id: dlcTagsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 8

                            Label {
                                text: "Optional Components & DLCs"
                                color: appSettings.textSecColor
                                font.family: "Rubik"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                id: dlInstallTagsRepeater
                                model: root.availableInstallTags || []
                                delegate: Rectangle {
                                    id: dlTagRow
                                    required property var modelData
                                    readonly property bool isChecked: root.selectedInstallTags.indexOf(modelData.tag) !== -1
                                    readonly property bool kbFocused: dlTagRow.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                                    focus: true
                                    activeFocusOnTab: false
                                    Layout.fillWidth: true
                                    height: 34
                                    radius: 8
                                    color: isChecked ? appSettings.secondaryContainer : appSettings.surfaceContainer
                                    border.color: kbFocused ? appSettings.accentColor : "transparent"
                                    border.width: kbFocused ? 2 : 0
                                    Keys.onReturnPressed: (event) => { event.accepted = true; root.toggleInstallTag(String(modelData.tag || "")) }
                                    Keys.onEnterPressed: (event) => { event.accepted = true; root.toggleInstallTag(String(modelData.tag || "")) }
                                    Keys.onSpacePressed: (event) => { event.accepted = true; root.toggleInstallTag(String(modelData.tag || "")) }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 8
                                        YIcon {
                                            size: 16
                                            symbol: isChecked ? "check" : "add"
                                            color: isChecked ? appSettings.onSecondaryContainer : appSettings.textSecColor
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: String(modelData.tag || "")
                                            color: isChecked ? appSettings.onSecondaryContainer : appSettings.textColor
                                            font.pixelSize: 12
                                            font.weight: isChecked ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            text: String(modelData.installSizeFormatted || "")
                                            color: isChecked ? appSettings.onSecondaryContainer : appSettings.textTerColor
                                            font.family: "JetBrains Mono NF"
                                            font.pixelSize: 11
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleInstallTag(String(modelData.tag || ""))
                                    }
                                }
                            }

                            Repeater {
                                id: dlAvailableDlcsRepeater
                                model: root.availableDlcs || []
                                delegate: Rectangle {
                                    id: dlDlcRow
                                    required property var modelData
                                    readonly property string dlcId: String(modelData.appName || modelData.dlcAppName || "")
                                    readonly property bool isChecked: dlcId.length > 0 && root.selectedDlcAppNames.indexOf(dlcId) !== -1
                                    readonly property bool kbFocused: dlDlcRow.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                                    focus: true
                                    activeFocusOnTab: false
                                    Layout.fillWidth: true
                                    height: 34
                                    radius: 8
                                    color: isChecked ? appSettings.secondaryContainer : appSettings.surfaceContainer
                                    border.color: kbFocused ? appSettings.accentColor : "transparent"
                                    border.width: kbFocused ? 2 : 0
                                    Keys.onReturnPressed: (event) => { event.accepted = true; if (dlcId.length > 0) root.toggleDlc(dlcId) }
                                    Keys.onEnterPressed: (event) => { event.accepted = true; if (dlcId.length > 0) root.toggleDlc(dlcId) }
                                    Keys.onSpacePressed: (event) => { event.accepted = true; if (dlcId.length > 0) root.toggleDlc(dlcId) }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 8
                                        YIcon {
                                            size: 16
                                            symbol: isChecked ? "check" : "download"
                                            color: isChecked ? appSettings.onSecondaryContainer : appSettings.accentColor
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: "DLC: " + String(modelData.title || dlcId)
                                            color: isChecked ? appSettings.onSecondaryContainer : appSettings.textColor
                                            font.pixelSize: 12
                                            font.weight: isChecked ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (dlcId.length > 0) root.toggleDlc(dlcId)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Footer ───────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 58

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: appSettings.borderColor
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 10
                Keys.onEscapePressed: (event) => root.handleDialogCancelKey(event)
                Keys.onBackPressed: (event) => root.handleDialogCancelKey(event)
                Keys.onPressed: (event) => root.handleDialogKeyPress(event)

                Item { Layout.fillWidth: true }

                M3Button {
                    id: cancelDlBtn
                    objectName: "epicDlCancelBtn"
                    text: "Cancel"
                    buttonType: "tonal"
                    onClicked: root.close()
                }

                M3Button {
                    id: startDlBtn
                    objectName: "epicDlStartBtn"
                    text: "Download"
                    iconSymbol: "download"
                    buttonType: "filled"
                    enabled: root.appName.length > 0 && root.installBaseDir.trim().length > 0 && !root.hasInsufficientDiskSpace
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: {
                        if (!uiController || !uiController.epicService) return
                        const runners = uiController.runnerManager ? uiController.runnerManager.installedRunners : []
                        let chosenRunnerId = ""
                        if (root.runnerIndex > 0 && root.runnerIndex - 1 < runners.length) {
                            chosenRunnerId = runners[root.runnerIndex - 1].id
                        }

                        let pfxMode = "dedicated"
                        if (!root.useDedicatedPrefix) {
                            const pfxs = uiController.prefixManager ? uiController.prefixManager.prefixes : []
                            if (root.existingPrefixIndex >= 0 && root.existingPrefixIndex < pfxs.length) {
                                pfxMode = pfxs[root.existingPrefixIndex].id
                            } else {
                                pfxMode = "default-prefix"
                            }
                        }

                        uiController.epicService.startDownload(
                            root.appName,
                            root.installBaseDir.trim(),
                            chosenRunnerId,
                            pfxMode,
                            root.customPrefixName,
                            root.customPrefixLocation,
                            root.prefixArch,
                            root.selectedInstallTags || [],
                            root.selectedDlcAppNames || []
                        )
                        root.downloadStarted(root.appName)
                        root.close()
                    }
                }
            }
        }
    }
}
