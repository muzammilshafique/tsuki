import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    objectName: "addGameDialog"
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

    property string exePath: ""
    property string platform: "windows"
    property string gameTitle: ""
    property string workDir: ""
    property string launchArgs: ""
    property int runnerIndex: 0
    property bool useDedicatedPrefix: true
    property string customPrefixName: ""
    property string customPrefixLocation: appSettings.defaultPrefixLocation
    property string prefixArch: "win64"
    property int existingPrefixIndex: 0

    function isAnyComboPopupOpen() {
        return runnerCombo.popup.visible || existingPfxCombo.popup.visible
    }

    function closeOpenComboPopup() {
        const combos = [runnerCombo, existingPfxCombo]
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
        return exeInputField.isEditing
            || titleInputField.isEditing
            || customPfxNameField.isEditing
            || customPfxLocField.isEditing
            || workDirInputField.isEditing
            || argsInputField.isEditing
    }

    function isFocusInsideDialog() {
        if (isAnyComboPopupOpen()) return true
        const fi = dialogContentCol.Window ? dialogContentCol.Window.activeFocusItem : null
        if (!fi) return false
        let p = fi
        while (p) {
            if (p === dialogContentCol) return true
            p = p.parent
        }
        return false
    }

    function focusDialogInitial() {
        if (!root.visible) return
        exeInputField.forceActiveFocus()
    }

    NumberAnimation {
        id: dialogScrollAnim
        target: dialogScroll.contentItem
        property: "contentY"
        duration: 150
        easing.type: Easing.OutCubic
    }

    function scrollToItem(ctrl) {
        if (!ctrl || !dialogScroll || !dialogScroll.contentItem || !dialogFormCol) return
        if (ctrl === cancelAddBtn || ctrl === addSubmitBtn) return
        let flick = dialogScroll.contentItem
        if (!flick || flick.contentY === undefined) return
        let pos = ctrl.mapToItem(dialogFormCol, 0, 0)
        let maxY = Math.max(0, flick.contentHeight - dialogScroll.height)
        let viewTop = flick.contentY
        let viewBottom = flick.contentY + dialogScroll.height
        let desiredY = flick.contentY
        if (pos.y - 24 < viewTop) {
            desiredY = Math.max(0, pos.y - 24)
        } else if (pos.y + ctrl.height + 24 > viewBottom) {
            desiredY = Math.min(maxY, pos.y + ctrl.height + 24 - dialogScroll.height)
        }
        if (Math.abs(desiredY - flick.contentY) > 1) {
            dialogScrollAnim.to = desiredY
            dialogScrollAnim.restart()
        }
    }

    function getFocusGrid() {
        let rows = [
            [exeInputField, browseExeBtn],
            [titleInputField]
        ]
        if (root.platform === "windows") {
            rows.push([runnerCombo])
            rows.push([pfxModePills])
            if (root.useDedicatedPrefix) {
                rows.push([customPfxNameField, archModePills])
                rows.push([customPfxLocField, customPfxBrowseBtn])
            } else {
                rows.push([existingPfxCombo])
            }
        }
        rows.push([workDirInputField, argsInputField])
        let footer = [cancelAddBtn]
        if (addSubmitBtn.enabled) {
            footer.push(addSubmitBtn)
        }
        rows.push(footer)
        return rows
    }

    function findFocusCoords(rows) {
        const fi = dialogContentCol.Window ? dialogContentCol.Window.activeFocusItem : null
        for (let r = 0; r < rows.length; r++) {
            for (let c = 0; c < rows[r].length; c++) {
                let it = rows[r][c]
                if (!it) continue
                if (it.activeFocus || (fi && fi === it)) {
                    return { r: r, c: c }
                }
            }
        }
        return { r: -1, c: 0 }
    }

    function navigateStep(dr, dc) {
        if (isAnyComboPopupOpen()) return false
        let rows = getFocusGrid()
        let pos = findFocusCoords(rows)
        if (pos.r < 0) {
            focusDialogInitial()
            scrollToItem(exeInputField)
            return true
        }
        if (dr !== 0) {
            let nr = pos.r + dr
            if (nr >= 0 && nr < rows.length) {
                let nextRow = rows[nr]
                let target = nextRow[Math.min(pos.c, nextRow.length - 1)]
                if (target) {
                    target.forceActiveFocus()
                    scrollToItem(target)
                    return true
                }
            }
            return false
        }
        if (dc !== 0) {
            let nc = pos.c + dc
            if (nc >= 0 && nc < rows[pos.r].length) {
                let target = rows[pos.r][nc]
                if (target) {
                    target.forceActiveFocus()
                    scrollToItem(target)
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
        onTriggered: root.focusDialogInitial()
    }

    onOpened: {
        if (!isFocusInsideDialog()) {
            focusDialogInitial()
        }
    }

    function resetAndOpen(initialPlatform) {
        exePath = ""
        platform = (initialPlatform === "linux") ? "linux" : "windows"
        gameTitle = ""
        workDir = ""
        launchArgs = ""
        runnerIndex = 0
        useDedicatedPrefix = true
        customPrefixName = ""
        customPrefixLocation = appSettings.defaultPrefixLocation
        prefixArch = "win64"
        existingPrefixIndex = 0
        if (dialogScrollAnim.running) dialogScrollAnim.stop()
        if (dialogScroll && dialogScroll.contentItem) {
            dialogScroll.contentItem.contentY = 0
        }
        root.open()
        focusDialogInitial()
        openFocusTimer.restart()
    }

    background: Rectangle {
        objectName: "addGameDialogBg"
        color: appSettings.surfaceColor
        radius: 20
        border.color: appSettings.borderColor
        border.width: 1
        layer.enabled: true
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

        // ── Compact Header ───────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 54

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 10

                YIcon {
                    size: 20
                    symbol: root.platform === "linux" ? "terminal" : "desktop_windows"
                    color: appSettings.accentColor
                }

                Label {
                    objectName: "addGameHeaderTitle"
                    text: root.platform === "linux" ? "Add Linux Game" : "Add Windows Game"
                    color: appSettings.textColor
                    font.family: "Rubik"
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    font.letterSpacing: -0.2
                    renderType: Text.QtRendering
                }

                Rectangle {
                    height: 20
                    radius: 10
                    implicitWidth: badgeLbl.implicitWidth + 14
                    color: appSettings.secondaryContainer
                    Label {
                        id: badgeLbl
                        anchors.centerIn: parent
                        text: root.platform === "linux" ? "Native" : "Wine · Proton"
                        color: appSettings.onSecondaryContainer
                        font.family: "JetBrains Mono NF"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        renderType: Text.QtRendering
                    }
                }

                Item { Layout.fillWidth: true }

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

                    HoverHandler {
                        id: closeBtnHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }

                    M3ToolTip {
                        visible: closeBtnHover.hovered
                        text: "Close"
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

        // ── Compact Scrollable Body ──────────────────────────────────────────
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
                    spacing: 10
                    Keys.onEscapePressed: (event) => root.handleDialogCancelKey(event)
                    Keys.onBackPressed: (event) => root.handleDialogCancelKey(event)
                    Keys.onPressed: (event) => root.handleDialogKeyPress(event)

                    // ── Card 1: Executable & Title ───────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 14
                        color: appSettings.surfaceContainerLow
                        border.color: appSettings.borderColor
                        border.width: 1
                        implicitHeight: gameCardCol.implicitHeight + 28

                        ColumnLayout {
                            id: gameCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                Label {
                                    text: root.platform === "linux" ? "Executable / Script" : "Executable (.exe)"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    renderType: Text.QtRendering
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    M3TextField {
                                        id: exeInputField
                                        objectName: "addGameExeField"
                                        twoStageFocus: true
                                        Layout.fillWidth: true
                                        text: root.exePath
                                        placeholderText: root.platform === "linux"
                                            ? "/path/to/game.x86_64 or run.sh"
                                            : "/path/to/game.exe"
                                        onTextChanged: root.exePath = text
                                        onCommit: (val) => root.exePath = val
                                        onMoveUp: root.navigateStep(-1, 0)
                                        onMoveDown: root.navigateStep(1, 0)
                                        onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                    }

                                    M3Button {
                                        id: browseExeBtn
                                        objectName: "addGameBrowseExeBtn"
                                        text: "Browse"
                                        iconSymbol: "folder_open"
                                        buttonType: "tonal"
                                        onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                        onClicked: {
                                            let filter = root.platform === "linux"
                                                ? "All Files (*);;Executables & Scripts (*.sh *.AppImage *.x86_64 *.x86 *.bin)"
                                                : "Windows Executables (*.exe *.EXE *.msi *.MSI *.bat);;All Files (*)"
                                            let prompt = root.platform === "linux"
                                                ? "Select Linux Game Executable"
                                                : "Select Windows Game Executable (.exe)"
                                            let f = uiController.selectFile(prompt, filter, root.exePath)
                                            if (f && f.length > 0) {
                                                root.exePath = f
                                                let guessed = uiController.gameManager.guessTitleFromExecutable(f)
                                                if (guessed && guessed.length > 0) {
                                                    root.gameTitle = guessed
                                                    if (root.platform === "windows") {
                                                        root.customPrefixName = uiController.prefixManager.suggestShortPrefixName(guessed)
                                                    }
                                                }
                                                let lastSlash = f.lastIndexOf("/")
                                                if (lastSlash > 0 && root.workDir.trim().length === 0) {
                                                    root.workDir = f.substring(0, lastSlash)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                Label {
                                    text: "Title"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    renderType: Text.QtRendering
                                }
                                M3TextField {
                                    id: titleInputField
                                    objectName: "addGameTitleField"
                                    twoStageFocus: true
                                    Layout.fillWidth: true
                                    text: root.gameTitle
                                    placeholderText: "e.g. Cyberpunk 2077"
                                    onTextChanged: root.gameTitle = text
                                    onCommit: (val) => {
                                        root.gameTitle = val
                                        if (root.platform === "windows" && root.customPrefixName.length === 0 && val.length > 0) {
                                            root.customPrefixName = uiController.prefixManager.suggestShortPrefixName(val)
                                        }
                                    }
                                    onMoveUp: root.navigateStep(-1, 0)
                                    onMoveDown: root.navigateStep(1, 0)
                                    onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                }
                            }
                        }
                    }

                    // ── Card 2: Wine & Prefix (Windows only) ─────────────────
                    Rectangle {
                        id: windowsPrefixCard
                        objectName: "addGameWindowsCard"
                        visible: root.platform === "windows"
                        Layout.fillWidth: true
                        radius: 14
                        color: appSettings.surfaceContainerLow
                        border.color: appSettings.borderColor
                        border.width: 1
                        implicitHeight: pfxCardCol.implicitHeight + 28

                        ColumnLayout {
                            id: pfxCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10

                            // Inline Runner row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Label {
                                    Layout.preferredWidth: 96
                                    text: "Runner"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    renderType: Text.QtRendering
                                }
                                StyledCombo {
                                    id: runnerCombo
                                    upDownNavigatesFocus: true
                                    Layout.fillWidth: true
                                    readonly property var runnerList: uiController.runnerManager.installedRunners
                                    comboModel: {
                                        let list = ["Default System Wine"]
                                        for (let i = 0; i < runnerList.length; i++) {
                                            list.push(runnerList[i].name)
                                        }
                                        return list
                                    }
                                    selectedIndex: root.runnerIndex
                                    onSelected: (idx) => root.runnerIndex = idx
                                    onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                }
                            }

                            // Inline Prefix Mode row using M3PillGroup
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Label {
                                    Layout.preferredWidth: 96
                                    text: "Wine Prefix"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    renderType: Text.QtRendering
                                }

                                Item { Layout.fillWidth: true }

                                M3PillGroup {
                                    id: pfxModePills
                                    pillHeight: 34
                                    fontSize: 13
                                    model: [
                                        { label: "Dedicated", val: 1, iconSymbol: "add" },
                                        { label: "Existing",  val: 0, iconSymbol: "folder_open" }
                                    ]
                                    selectedValue: root.useDedicatedPrefix ? 1 : 0
                                    onSelectionChanged: (val) => root.useDedicatedPrefix = (Number(val) === 1)
                                    onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: appSettings.borderColor
                            }

                            // Dedicated Prefix options
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
                                            renderType: Text.QtRendering
                                        }
                                        M3TextField {
                                            id: customPfxNameField
                                            twoStageFocus: true
                                            Layout.fillWidth: true
                                            text: root.customPrefixName
                                            placeholderText: "e.g. cyberpunk"
                                            onTextChanged: root.customPrefixName = text
                                            onCommit: (val) => root.customPrefixName = val
                                            onMoveUp: root.navigateStep(-1, 0)
                                            onMoveDown: root.navigateStep(1, 0)
                                            onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
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
                                            renderType: Text.QtRendering
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
                                            onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
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
                                        renderType: Text.QtRendering
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
                                            onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                        }
                                        M3Button {
                                            id: customPfxBrowseBtn
                                            text: "Folder"
                                            iconSymbol: "folder_open"
                                            buttonType: "tonal"
                                            onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                            onClicked: {
                                                let d = uiController.selectFolder("Select Custom Prefix Base Directory", root.customPrefixLocation)
                                                if (d && d.length > 0) {
                                                    root.customPrefixLocation = d
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Existing Prefix selector
                            RowLayout {
                                visible: !root.useDedicatedPrefix
                                Layout.fillWidth: true
                                spacing: 12
                                Label {
                                    Layout.preferredWidth: 96
                                    text: "Select Prefix"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    renderType: Text.QtRendering
                                }
                                StyledCombo {
                                    id: existingPfxCombo
                                    upDownNavigatesFocus: true
                                    Layout.fillWidth: true
                                    readonly property var pfxList: uiController.prefixManager.prefixes
                                    comboModel: {
                                        let list = []
                                        for (let i = 0; i < pfxList.length; i++) {
                                            list.push(pfxList[i].name)
                                        }
                                        return list.length > 0 ? list : ["Default Prefix"]
                                    }
                                    selectedIndex: root.existingPrefixIndex
                                    onSelected: (idx) => root.existingPrefixIndex = idx
                                    onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                }
                            }
                        }
                    }

                    // ── Card 3: Launch Options ───────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 14
                        color: appSettings.surfaceContainerLow
                        border.color: appSettings.borderColor
                        border.width: 1
                        implicitHeight: launchCardCol.implicitHeight + 28

                        RowLayout {
                            id: launchCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                RowLayout {
                                    spacing: 5
                                    Label {
                                        text: "Working Directory"
                                        color: appSettings.textSecColor
                                        font.family: "Rubik"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        renderType: Text.QtRendering
                                    }
                                    Item {
                                        width: 16
                                        height: 16
                                        YIcon {
                                            anchors.centerIn: parent
                                            symbol: "info"
                                            size: 14
                                            color: wdInfoHover.hovered ? appSettings.accentColor : appSettings.textTerColor
                                        }
                                        HoverHandler { id: wdInfoHover }
                                        M3ToolTip {
                                            visible: wdInfoHover.hovered
                                            text: "Optional. Defaults to the executable's folder."
                                        }
                                    }
                                }

                                M3TextField {
                                    id: workDirInputField
                                    objectName: "addGameWorkDirField"
                                    twoStageFocus: true
                                    Layout.fillWidth: true
                                    text: root.workDir
                                    placeholderText: "Default (exe folder)"
                                    onTextChanged: root.workDir = text
                                    onCommit: (val) => root.workDir = val
                                    onMoveUp: root.navigateStep(-1, 0)
                                    onMoveDown: root.navigateStep(1, 0)
                                    onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Label {
                                    text: "Launch Arguments"
                                    color: appSettings.textSecColor
                                    font.family: "Rubik"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    renderType: Text.QtRendering
                                }

                                M3TextField {
                                    id: argsInputField
                                    twoStageFocus: true
                                    Layout.fillWidth: true
                                    text: root.launchArgs
                                    placeholderText: "-fullscreen -skipintro"
                                    onTextChanged: root.launchArgs = text
                                    onCommit: (val) => root.launchArgs = val
                                    onMoveUp: root.navigateStep(-1, 0)
                                    onMoveDown: root.navigateStep(1, 0)
                                    onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Compact Footer ───────────────────────────────────────────────────
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
                id: dialogFooterRow
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 10
                Keys.onEscapePressed: (event) => root.handleDialogCancelKey(event)
                Keys.onBackPressed: (event) => root.handleDialogCancelKey(event)
                Keys.onPressed: (event) => root.handleDialogKeyPress(event)

                Item { Layout.fillWidth: true }

                M3Button {
                    id: cancelAddBtn
                    objectName: "addGameCancelBtn"
                    text: "Cancel"
                    buttonType: "tonal"
                    onClicked: root.close()
                }

                M3Button {
                    id: addSubmitBtn
                    objectName: "addGameSubmitBtn"
                    text: "Add Game"
                    iconSymbol: "add"
                    buttonType: "filled"
                    enabled: root.exePath.trim().length > 0
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: {
                        let finalTitle = titleInputField.text.trim().length > 0 ? titleInputField.text.trim() : root.gameTitle.trim()
                        let finalExe = exeInputField.text.trim().length > 0 ? exeInputField.text.trim() : root.exePath.trim()
                        let finalWorkDir = workDirInputField.text.trim().length > 0 ? workDirInputField.text.trim() : root.workDir.trim()
                        let finalArgs = argsInputField.text.trim()

                        if (root.platform === "linux") {
                            uiController.gameManager.addNativeGame(
                                finalTitle,
                                finalExe,
                                finalWorkDir,
                                finalArgs
                            )
                        } else {
                            let runners = uiController.runnerManager.installedRunners
                            let chosenRunnerId = ""
                            if (root.runnerIndex > 0 && root.runnerIndex - 1 < runners.length) {
                                chosenRunnerId = runners[root.runnerIndex - 1].id
                            }
                            let pfxMode = "dedicated"
                            if (!root.useDedicatedPrefix) {
                                let pfxs = uiController.prefixManager.prefixes
                                if (root.existingPrefixIndex >= 0 && root.existingPrefixIndex < pfxs.length) {
                                    pfxMode = pfxs[root.existingPrefixIndex].id
                                } else {
                                    pfxMode = "default-prefix"
                                }
                            }
                            uiController.gameManager.addGame(
                                finalTitle,
                                finalExe,
                                finalWorkDir,
                                finalArgs,
                                chosenRunnerId,
                                pfxMode,
                                root.customPrefixName,
                                root.customPrefixLocation,
                                root.prefixArch
                            )
                        }
                        root.close()
                    }
                }
            }
        }
    }
}
