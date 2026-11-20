import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    objectName: "epicImportDialog"
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 48 : 600, 600)
    readonly property real maxBodyHeight: Math.max(220, (parent ? parent.height : 760) - 180)
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
    property string sourceDir: ""
    property string customExecutable: ""
    property string transferMode: "copy" // "copy", "move", "in_place"
    property string targetBaseDir: appSettings ? appSettings.defaultEpicInstallLocation : ""
    property bool verifyAfterImport: false

    property int runnerIndex: 0
    property bool useDedicatedPrefix: false
    property int existingPrefixIndex: 0
    property string customPrefixName: ""
    property string customPrefixLocation: appSettings ? appSettings.defaultPrefixLocation : ""
    property string prefixArch: "win64"

    property var sourceInfo: ({
        valid: false,
        exists: false,
        fileCount: 0,
        totalBytes: 0,
        totalSizeFormatted: "0 B",
        suggestedExe: "",
        sameFilesystem: false,
        sameDestination: false,
        error: ""
    })

    readonly property string resolvedDestPreview: {
        if (root.transferMode === "in_place") return root.sourceDir
        return (uiController && uiController.epicService && root.gameTitle.length > 0)
            ? uiController.epicService.suggestInstallDirectory(root.targetBaseDir, root.gameTitle)
            : root.targetBaseDir
    }

    readonly property double sourceBytes: Number(root.sourceInfo.totalBytes || 0)

    readonly property double freeSpaceBytes: (uiController && uiController.epicService)
        ? uiController.epicService.getFreeDiskSpace(root.transferMode === "in_place" ? root.sourceDir : root.targetBaseDir)
        : -1

    readonly property string freeSpaceStr: (uiController && uiController.epicService)
        ? uiController.epicService.getFreeDiskSpaceFormatted(root.transferMode === "in_place" ? root.sourceDir : root.targetBaseDir)
        : "Unknown"

    readonly property bool needsExtraDiskSpace: {
        if (root.transferMode === "in_place") return false
        if (Boolean(root.sourceInfo.sameDestination)) return false
        if (root.transferMode === "move" && Boolean(root.sourceInfo.sameFilesystem)) return false
        return true
    }

    readonly property bool hasInsufficientDiskSpace: root.needsExtraDiskSpace
        && root.sourceBytes > 0
        && root.freeSpaceBytes >= 0
        && root.freeSpaceBytes < root.sourceBytes

    readonly property bool hasValidExecutable: root.customExecutable.trim().length > 0
        || String(root.sourceInfo.suggestedExe || "").length > 0

    readonly property bool canStartImport: root.appName.length > 0
        && root.sourceDir.trim().length > 0
        && Boolean(root.sourceInfo.exists)
        && Number(root.sourceInfo.fileCount || 0) > 0
        && root.hasValidExecutable
        && (root.transferMode === "in_place" || root.targetBaseDir.trim().length > 0)
        && !root.hasInsufficientDiskSpace

    signal importStarted(string appName)

    function findDefaultPrefixIndex() {
        const pfxs = (uiController && uiController.prefixManager && uiController.prefixManager.prefixes)
            ? uiController.prefixManager.prefixes : []
        for (let i = 0; i < pfxs.length; i++) {
            if (pfxs[i].id === "default-prefix") return i
        }
        return 0
    }

    function refreshSourceInfo() {
        if (!uiController || !uiController.epicService) return
        root.sourceInfo = uiController.epicService.inspectImportSource(
            root.appName,
            root.sourceDir,
            root.targetBaseDir
        )
    }

    function openForApp(targetAppName) {
        root.appName = targetAppName || ""
        const epicMap = (uiController && uiController.epicService && root.appName.length > 0)
            ? uiController.epicService.getEpicGameMap(root.appName) : ({})
        root.gameTitle = epicMap.title || root.appName

        root.sourceDir = ""
        root.customExecutable = ""
        root.transferMode = "copy"
        root.targetBaseDir = appSettings ? appSettings.defaultEpicInstallLocation : ""
        root.verifyAfterImport = false

        root.runnerIndex = 0
        root.useDedicatedPrefix = false
        root.existingPrefixIndex = findDefaultPrefixIndex()
        root.customPrefixName = (uiController && uiController.prefixManager)
            ? uiController.prefixManager.suggestShortPrefixName(root.gameTitle) : ""
        root.customPrefixLocation = appSettings ? appSettings.defaultPrefixLocation : ""
        root.prefixArch = "win64"

        refreshSourceInfo()
        root.open()
        openFocusTimer.restart()
    }

    function isAnyComboPopupOpen() {
        return impRunnerCombo.popup.visible || impPrefixCombo.popup.visible
    }

    function closeOpenComboPopup() {
        const combos = [impRunnerCombo, impPrefixCombo]
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
        return sourceDirField.isEditing
            || customExeField.isEditing
            || destDirField.isEditing
            || customPfxNameField.isEditing
            || customPfxLocField.isEditing
    }

    function getFocusGrid() {
        let rows = [
            [sourceDirField, browseSrcBtn],
            [customExeField, browseExeBtn],
            [transferModePills]
        ]
        if (root.transferMode !== "in_place") {
            rows.push([destDirField, browseDestBtn])
        }
        rows.push([impRunnerCombo])
        rows.push([pfxModePills])
        if (root.useDedicatedPrefix) {
            rows.push([customPfxNameField, archModePills])
            rows.push([customPfxLocField, customPfxBrowseBtn])
        } else {
            rows.push([impPrefixCombo])
        }
        rows.push([verifyAfterImportToggle])
        rows.push([cancelImpBtn, startImpBtn])
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
            browseSrcBtn.forceActiveFocus()
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
        onTriggered: browseSrcBtn.forceActiveFocus()
    }

    background: Rectangle {
        color: appSettings.surfaceColor
        radius: 20
        border.color: appSettings.borderColor
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
                    symbol: "folder_open"
                    color: appSettings.accentColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Label {
                        objectName: "epicImportDialogTitle"
                        text: "Import Installed Game"
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
                    radius: 11
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
                        radius: 16
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

                    // Card 1: Existing Game Folder + Executable
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 14
                        color: appSettings.surfaceContainerLow
                        border.color: appSettings.borderColor
                        border.width: 1
                        implicitHeight: srcCardCol.implicitHeight + 28

                        ColumnLayout {
                            id: srcCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 8

                            Label {
                                text: "Existing Game Folder"
                                color: appSettings.textSecColor
                                font.family: "Rubik"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                M3TextField {
                                    id: sourceDirField
                                    objectName: "epicImportSourceField"
                                    twoStageFocus: true
                                    Layout.fillWidth: true
                                    text: root.sourceDir
                                    placeholderText: "e.g. ~/Games/Heroic/GhostwireTokyo"
                                    onTextChanged: {
                                        root.sourceDir = text
                                        root.refreshSourceInfo()
                                    }
                                    onCommit: (val) => {
                                        root.sourceDir = val
                                        root.refreshSourceInfo()
                                    }
                                    onMoveUp: root.navigateStep(-1, 0)
                                    onMoveDown: root.navigateStep(1, 0)
                                }

                                M3Button {
                                    id: browseSrcBtn
                                    objectName: "epicImportSourceBrowseBtn"
                                    text: "Browse"
                                    iconSymbol: "folder_open"
                                    buttonType: "tonal"
                                    onClicked: {
                                        if (!uiController) return
                                        const initial = root.sourceDir.trim().length > 0
                                            ? root.sourceDir
                                            : (appSettings ? appSettings.defaultEpicInstallLocation : "")
                                        const d = uiController.selectFolder("Select Installed Game Folder", initial)
                                        if (d && d.length > 0) {
                                            root.sourceDir = d
                                            root.customExecutable = ""
                                            root.refreshSourceInfo()
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                visible: root.sourceDir.trim().length > 0
                                Layout.fillWidth: true
                                spacing: 10

                                Label {
                                    text: Boolean(root.sourceInfo.exists)
                                        ? (root.sourceInfo.totalSizeFormatted + "  •  " + Number(root.sourceInfo.fileCount || 0) + " files")
                                        : String(root.sourceInfo.error || "Folder not found")
                                    color: Boolean(root.sourceInfo.exists) ? appSettings.textSecColor : "#ef4444"
                                    font.pixelSize: 12
                                    Layout.fillWidth: true
                                }

                                Label {
                                    visible: Boolean(root.sourceInfo.hasEpicMetadata)
                                    text: "Epic/Heroic Files Detected"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }

                            Label {
                                text: "Executable Override (optional)"
                                color: appSettings.textSecColor
                                font.family: "Rubik"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                M3TextField {
                                    id: customExeField
                                    objectName: "epicImportExeField"
                                    twoStageFocus: true
                                    Layout.fillWidth: true
                                    text: root.customExecutable
                                    placeholderText: root.sourceInfo.suggestedExe
                                        ? ("Auto-detected: " + root.sourceInfo.suggestedExe)
                                        : "Auto-detect from Epic manifest / folder"
                                    onTextChanged: root.customExecutable = text
                                    onCommit: (val) => root.customExecutable = val
                                    onMoveUp: root.navigateStep(-1, 0)
                                    onMoveDown: root.navigateStep(1, 0)
                                }

                                M3Button {
                                    id: browseExeBtn
                                    text: "Select .exe"
                                    buttonType: "tonal"
                                    onClicked: {
                                        if (!uiController) return
                                        const start = root.sourceDir.trim().length > 0
                                            ? root.sourceDir
                                            : (appSettings ? appSettings.defaultEpicInstallLocation : "")
                                        const p = uiController.selectFile("Select Game Executable", "Windows Executables (*.exe);;All Files (*)", start)
                                        if (p && p.length > 0) {
                                            root.customExecutable = p
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Card 2: Folder Transfer Mode & Destination
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 14
                        color: appSettings.surfaceContainerLow
                        border.color: appSettings.borderColor
                        border.width: 1
                        implicitHeight: transferCardCol.implicitHeight + 28

                        ColumnLayout {
                            id: transferCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Label {
                                    text: "Location Action"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }

                                Item { Layout.fillWidth: true }

                                M3PillGroup {
                                    id: transferModePills
                                    objectName: "epicImportTransferPills"
                                    pillHeight: 34
                                    fontSize: 13
                                    model: [
                                        { label: "Copy",          val: "copy" },
                                        { label: "Move",          val: "move" },
                                        { label: "Keep in Place", val: "in_place" }
                                    ]
                                    selectedValue: root.transferMode
                                    onSelectionChanged: (val) => {
                                        root.transferMode = String(val)
                                        root.refreshSourceInfo()
                                    }
                                }
                            }

                            Label {
                                text: {
                                    if (root.transferMode === "move") {
                                        return Boolean(root.sourceInfo.sameFilesystem)
                                            ? "Moves the game folder directly into your Tsuki Epic Games folder (instant on the same drive) and removes the old folder."
                                            : "Copies the game files to your Tsuki Epic Games folder, then removes the original folder once complete."
                                    }
                                    if (root.transferMode === "in_place") {
                                        return "Registers the game directly at its current folder without copying or moving files."
                                    }
                                    return "Copies the game files into your Tsuki Epic Games folder, keeping your original folder untouched."
                                }
                                color: appSettings.textTerColor
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ColumnLayout {
                                visible: root.transferMode !== "in_place"
                                Layout.fillWidth: true
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    M3TextField {
                                        id: destDirField
                                        objectName: "epicImportDestField"
                                        twoStageFocus: true
                                        Layout.fillWidth: true
                                        text: root.targetBaseDir
                                        placeholderText: "~/Games/Epic"
                                        onTextChanged: {
                                            root.targetBaseDir = text
                                            root.refreshSourceInfo()
                                        }
                                        onCommit: (val) => {
                                            root.targetBaseDir = val
                                            root.refreshSourceInfo()
                                        }
                                        onMoveUp: root.navigateStep(-1, 0)
                                        onMoveDown: root.navigateStep(1, 0)
                                    }

                                    M3Button {
                                        id: browseDestBtn
                                        text: "Browse"
                                        iconSymbol: "folder_open"
                                        buttonType: "tonal"
                                        onClicked: {
                                            if (!uiController) return
                                            const d = uiController.selectFolder("Select Destination Directory", root.targetBaseDir)
                                            if (d && d.length > 0) {
                                                root.targetBaseDir = d
                                                root.refreshSourceInfo()
                                            }
                                        }
                                    }
                                }

                                Label {
                                    text: "Destination: " + root.resolvedDestPreview
                                    color: appSettings.textTerColor
                                    font.family: "JetBrains Mono NF"
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Label {
                                        visible: root.sourceBytes > 0
                                        text: "Required: " + root.sourceInfo.totalSizeFormatted
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

                    // Card 3: Proton Runner, Prefix & Verification
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 14
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
                                    id: impRunnerCombo
                                    objectName: "epicImportRunnerCombo"
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

                            RowLayout {
                                visible: !root.useDedicatedPrefix
                                Layout.fillWidth: true
                                spacing: 12
                                Label {
                                    Layout.preferredWidth: 100
                                    text: "Select Prefix"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                StyledCombo {
                                    id: impPrefixCombo
                                    objectName: "epicImportPrefixCombo"
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

                            ColumnLayout {
                                visible: root.useDedicatedPrefix
                                Layout.fillWidth: true
                                spacing: 10

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

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: appSettings.borderColor
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Label {
                                        text: "Verify files after import"
                                        color: appSettings.textColor
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }
                                    Label {
                                        text: "Check imported files against the Epic manifest and repair missing chunks"
                                        color: appSettings.textSecColor
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                                Toggle {
                                    id: verifyAfterImportToggle
                                    checked: root.verifyAfterImport
                                    onToggled: (c) => root.verifyAfterImport = c
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
                    id: cancelImpBtn
                    objectName: "epicImportCancelBtn"
                    text: "Cancel"
                    buttonType: "tonal"
                    onClicked: root.close()
                }

                M3Button {
                    id: startImpBtn
                    objectName: "epicImportStartBtn"
                    text: root.transferMode === "move"
                        ? "Move & Import"
                        : (root.transferMode === "copy" ? "Copy & Import" : "Import")
                    iconSymbol: "folder_open"
                    buttonType: "filled"
                    enabled: root.canStartImport
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

                        uiController.epicService.importGame(
                            root.appName,
                            root.sourceDir.trim(),
                            root.transferMode,
                            root.targetBaseDir.trim(),
                            chosenRunnerId,
                            pfxMode,
                            root.customPrefixName,
                            root.customPrefixLocation,
                            root.prefixArch,
                            root.verifyAfterImport,
                            root.customExecutable.trim()
                        )
                        root.importStarted(root.appName)
                        root.close()
                    }
                }
            }
        }
    }
}

