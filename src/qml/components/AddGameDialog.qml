import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 48 : 660, 660)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

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

    function isAnyTextEditing() {
        return exeInputField.isEditing
            || titleInputField.isEditing
            || customPfxNameField.isEditing
            || customPfxLocField.isEditing
            || workDirInputField.isEditing
            || argsInputField.isEditing
    }

    function scrollToItem(ctrl) {
        if (!ctrl || !dialogScroll.contentItem || !dialogFormCol) return
        let pos = ctrl.mapToItem(dialogFormCol, 0, 0)
        let targetY = Math.max(0, Math.min(pos.y - 60, Math.max(0, dialogFormCol.height - dialogScroll.height)))
        dialogScroll.contentItem.contentY = targetY
    }

    function resetAndOpen() {
        exePath = ""
        platform = "windows"
        gameTitle = ""
        workDir = ""
        launchArgs = ""
        runnerIndex = 0
        useDedicatedPrefix = true
        customPrefixName = ""
        customPrefixLocation = appSettings.defaultPrefixLocation
        prefixArch = "win64"
        existingPrefixIndex = 0
        root.open()
        Qt.callLater(() => platformSeg.forceActiveFocus())
    }

    background: Rectangle {
        color: appSettings.surfaceColor
        radius: 24
        border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.65)
            shadowBlur: 0.8
            shadowVerticalOffset: 8
        }
    }

    contentItem: ColumnLayout {
        spacing: 0
        Keys.onBackPressed: (event) => {
            if (root.isAnyTextEditing()) return
            event.accepted = true
            root.close()
        }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Backspace && !root.isAnyTextEditing()) {
                event.accepted = true
                root.close()
            }
        }

        // ── Dialog Header ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 20

                YIcon {
                    size: 24
                    source: "qrc:/tsuki_app/icons/actions/add.svg"
                    color: appSettings.accentColor
                }

                Label {
                    text: "Add Game"
                    color: appSettings.textColor
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.3
                    Layout.fillWidth: true
                }

                ToolButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    background: Rectangle {
                        radius: 18
                        color: parent.hovered ? appSettings.surfaceAltColor : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    contentItem: YIcon {
                        anchors.centerIn: parent
                        source: "qrc:/tsuki_app/icons/actions/close.svg"
                        color: appSettings.textSecColor
                        size: 18
                    }
                    onClicked: root.close()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
            }
        }

        // ── Scrollable Form Body ─────────────────────────────────────────────
        ScrollView {
            id: dialogScroll
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(520, 480)
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: dialogFormCol
                width: parent.width - 48
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Item { Layout.preferredHeight: 4 }

                // 0. Platform Mode Selector
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label { text: "Platform"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                    M3SegmentedButton {
                        id: platformSeg
                        Layout.fillWidth: true
                        model: [
                            { label: "Windows (Wine / Proton)", val: 0 },
                            { label: "Linux (Native)", val: 1 }
                        ]
                        selectedValue: root.platform === "linux" ? 1 : 0
                        onSelectionChanged: (val) => root.platform = (val === 1 ? "linux" : "windows")
                        onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                        Keys.onDownPressed: (event) => { event.accepted = true; exeInputField.forceActiveFocus() }
                    }
                }

                // 1. Executable Picker
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label {
                        text: root.platform === "linux" ? "Executable / Script" : "Executable File (.exe)"
                        color: appSettings.textColor
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        M3TextField {
                            id: exeInputField
                            twoStageFocus: true
                            Layout.fillWidth: true
                            text: root.exePath
                            placeholderText: root.platform === "linux" ? "/path/to/game.x86_64 or run.sh" : "/path/to/game.exe"
                            onTextChanged: root.exePath = text
                            onCommit: (val) => root.exePath = val
                            onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                            Keys.onUpPressed: (event) => { if (!isEditing) { event.accepted = true; platformSeg.forceActiveFocus() } }
                            Keys.onDownPressed: (event) => { if (!isEditing) { event.accepted = true; titleInputField.forceActiveFocus() } }
                            Keys.onRightPressed: (event) => { if (!isEditing) { event.accepted = true; browseExeBtn.forceActiveFocus() } }
                        }
                        M3Button {
                            id: browseExeBtn
                            text: "Browse…"
                            iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                            buttonType: "tonal"
                            onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                            Keys.onLeftPressed: (event) => { event.accepted = true; exeInputField.forceActiveFocus() }
                            Keys.onUpPressed: (event) => { event.accepted = true; platformSeg.forceActiveFocus() }
                            Keys.onDownPressed: (event) => { event.accepted = true; titleInputField.forceActiveFocus() }
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
                                    let detected = uiController.gameManager.detectPlatform(f)
                                    root.platform = detected
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

                // 2. Title Field
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label { text: "Game Title"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                    M3TextField {
                        id: titleInputField
                        twoStageFocus: true
                        Layout.fillWidth: true
                        text: root.gameTitle
                        placeholderText: "e.g. Cyberpunk 2077"
                        onTextChanged: {
                            root.gameTitle = text
                        }
                        onCommit: (val) => {
                            root.gameTitle = val
                            if (root.platform === "windows" && root.customPrefixName.length === 0 && val.length > 0) {
                                root.customPrefixName = uiController.prefixManager.suggestShortPrefixName(val)
                            }
                        }
                        onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                        Keys.onUpPressed: (event) => { if (!isEditing) { event.accepted = true; exeInputField.forceActiveFocus() } }
                        Keys.onDownPressed: (event) => {
                            if (!isEditing) {
                                event.accepted = true
                                if (root.platform === "windows") runnerCombo.forceActiveFocus()
                                else workDirInputField.forceActiveFocus()
                            }
                        }
                    }
                }

                // 3. Runner Selection
                ColumnLayout {
                    visible: root.platform === "windows"
                    Layout.fillWidth: true
                    spacing: 6
                    Label { text: "Wine / Proton Runner"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
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
                        Keys.onUpPressed: (event) => { event.accepted = true; titleInputField.forceActiveFocus() }
                        Keys.onDownPressed: (event) => { event.accepted = true; pfxModeSeg.forceActiveFocus() }
                    }
                }

                // 4. Wine Prefix Mode
                Rectangle {
                    visible: root.platform === "windows"
                    Layout.fillWidth: true
                    radius: 16
                    color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                    implicitHeight: pfxCol.implicitHeight + 28

                    ColumnLayout {
                        id: pfxCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        Label { text: "Wine Prefix Isolation"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.DemiBold }

                        M3SegmentedButton {
                            id: pfxModeSeg
                            Layout.fillWidth: true
                            model: [
                                { label: "Dedicated Isolated Prefix (Recommended)", val: 1 },
                                { label: "Use Existing Prefix", val: 0 }
                            ]
                            selectedValue: root.useDedicatedPrefix ? 1 : 0
                            onSelectionChanged: (val) => root.useDedicatedPrefix = (val === 1)
                            onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                            Keys.onUpPressed: (event) => { event.accepted = true; runnerCombo.forceActiveFocus() }
                            Keys.onDownPressed: (event) => {
                                event.accepted = true
                                if (root.useDedicatedPrefix) customPfxNameField.forceActiveFocus()
                                else existingPfxCombo.forceActiveFocus()
                            }
                        }

                        // Dedicated Prefix Options
                        ColumnLayout {
                            visible: root.useDedicatedPrefix
                            Layout.fillWidth: true
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Label { text: "Prefix Name (Folder)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    M3TextField {
                                        id: customPfxNameField
                                        twoStageFocus: true
                                        Layout.fillWidth: true
                                        text: root.customPrefixName
                                        placeholderText: "e.g. cyberpunk"
                                        onCommit: (val) => root.customPrefixName = val
                                        onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                        Keys.onUpPressed: (event) => { if (!isEditing) { event.accepted = true; pfxModeSeg.forceActiveFocus() } }
                                        Keys.onDownPressed: (event) => { if (!isEditing) { event.accepted = true; customPfxLocField.forceActiveFocus() } }
                                        Keys.onRightPressed: (event) => { if (!isEditing) { event.accepted = true; archModeSeg.forceActiveFocus() } }
                                    }
                                }

                                ColumnLayout {
                                    Layout.preferredWidth: 160
                                    spacing: 4
                                    Label { text: "Architecture"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    M3SegmentedButton {
                                        id: archModeSeg
                                        Layout.fillWidth: true
                                        model: [
                                            { label: "64-bit", val: 0 },
                                            { label: "32-bit", val: 1 }
                                        ]
                                        selectedValue: root.prefixArch === "win64" ? 0 : 1
                                        onSelectionChanged: (val) => root.prefixArch = (val === 0 ? "win64" : "win32")
                                        onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                        Keys.onUpPressed: (event) => { event.accepted = true; pfxModeSeg.forceActiveFocus() }
                                        Keys.onDownPressed: (event) => { event.accepted = true; customPfxLocField.forceActiveFocus() }
                                        Keys.onLeftPressed: (event) => {
                                            if (selectedValue === 0) {
                                                event.accepted = true
                                                customPfxNameField.forceActiveFocus()
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Label { text: "Prefix Storage Directory"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    M3TextField {
                                        id: customPfxLocField
                                        twoStageFocus: true
                                        Layout.fillWidth: true
                                        text: root.customPrefixLocation
                                        onCommit: (val) => root.customPrefixLocation = val
                                        onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                        Keys.onUpPressed: (event) => { if (!isEditing) { event.accepted = true; customPfxNameField.forceActiveFocus() } }
                                        Keys.onDownPressed: (event) => { if (!isEditing) { event.accepted = true; workDirInputField.forceActiveFocus() } }
                                        Keys.onRightPressed: (event) => { if (!isEditing) { event.accepted = true; customPfxBrowseBtn.forceActiveFocus() } }
                                    }
                                    M3Button {
                                        id: customPfxBrowseBtn
                                        text: "Folder…"
                                        buttonType: "tonal"
                                        onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                                        Keys.onLeftPressed: (event) => { event.accepted = true; customPfxLocField.forceActiveFocus() }
                                        Keys.onUpPressed: (event) => { event.accepted = true; archModeSeg.forceActiveFocus() }
                                        Keys.onDownPressed: (event) => { event.accepted = true; workDirInputField.forceActiveFocus() }
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

                        // Existing Prefix Selector
                        ColumnLayout {
                            visible: !root.useDedicatedPrefix
                            Layout.fillWidth: true
                            spacing: 6
                            Label { text: "Select Existing Prefix"; color: appSettings.textSecColor; font.pixelSize: 12 }
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
                                Keys.onUpPressed: (event) => { event.accepted = true; pfxModeSeg.forceActiveFocus() }
                                Keys.onDownPressed: (event) => { event.accepted = true; workDirInputField.forceActiveFocus() }
                            }
                        }
                    }
                }

                // 5. Working Directory & Launch Arguments (Optional)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: "Working Directory (Optional)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                        M3TextField {
                            id: workDirInputField
                            twoStageFocus: true
                            Layout.fillWidth: true
                            text: root.workDir
                            placeholderText: "Default is executable folder"
                            onTextChanged: root.workDir = text
                            onCommit: (val) => root.workDir = val
                            onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                            Keys.onUpPressed: (event) => {
                                if (!isEditing) {
                                    event.accepted = true
                                    if (root.platform === "linux") titleInputField.forceActiveFocus()
                                    else if (root.useDedicatedPrefix) customPfxLocField.forceActiveFocus()
                                    else existingPfxCombo.forceActiveFocus()
                                }
                            }
                            Keys.onDownPressed: (event) => {
                                if (!isEditing) {
                                    event.accepted = true
                                    if (addSubmitBtn.enabled) addSubmitBtn.forceActiveFocus()
                                    else cancelAddBtn.forceActiveFocus()
                                }
                            }
                            Keys.onRightPressed: (event) => { if (!isEditing) { event.accepted = true; argsInputField.forceActiveFocus() } }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: "Launch Arguments (Optional)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                        M3TextField {
                            id: argsInputField
                            twoStageFocus: true
                            Layout.fillWidth: true
                            text: root.launchArgs
                            placeholderText: "-fullscreen -skipintro"
                            onTextChanged: root.launchArgs = text
                            onCommit: (val) => root.launchArgs = val
                            onActiveFocusChanged: if (activeFocus) root.scrollToItem(this)
                            Keys.onLeftPressed: (event) => { if (!isEditing) { event.accepted = true; workDirInputField.forceActiveFocus() } }
                            Keys.onUpPressed: (event) => {
                                if (!isEditing) {
                                    event.accepted = true
                                    if (root.platform === "linux") titleInputField.forceActiveFocus()
                                    else if (root.useDedicatedPrefix) customPfxLocField.forceActiveFocus()
                                    else existingPfxCombo.forceActiveFocus()
                                }
                            }
                            Keys.onDownPressed: (event) => {
                                if (!isEditing) {
                                    event.accepted = true
                                    if (addSubmitBtn.enabled) addSubmitBtn.forceActiveFocus()
                                    else cancelAddBtn.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }
            }
        }

        // ── Dialog Footer Action Buttons ─────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 68

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 12

                Item { Layout.fillWidth: true }

                M3Button {
                    id: cancelAddBtn
                    text: "Cancel"
                    buttonType: "tonal"
                    onClicked: root.close()
                    Keys.onUpPressed: (event) => { event.accepted = true; workDirInputField.forceActiveFocus() }
                    Keys.onRightPressed: (event) => { if (addSubmitBtn.enabled) { event.accepted = true; addSubmitBtn.forceActiveFocus() } }
                }

                M3Button {
                    id: addSubmitBtn
                    text: "Add to Library"
                    iconSource: "qrc:/tsuki_app/icons/actions/add.svg"
                    buttonType: "filled"
                    enabled: root.exePath.trim().length > 0
                    opacity: enabled ? 1.0 : 0.5
                    Keys.onLeftPressed: (event) => { event.accepted = true; cancelAddBtn.forceActiveFocus() }
                    Keys.onUpPressed: (event) => { event.accepted = true; argsInputField.forceActiveFocus() }
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
