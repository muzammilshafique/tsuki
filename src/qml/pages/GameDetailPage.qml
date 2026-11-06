import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Page {
    id: root
    property string gameId: ""
    property var gameData: ({})
    property int activeTab: 0

    signal backRequested()
    signal winetricksRequested(string prefixId, string gameTitle)

    function reloadGame() {
        if (gameId.length > 0) {
            gameData = uiController.gameManager.getGameMap(gameId)
            uiController.diagnosticsManager.selectedLogGameId = gameId
        }
    }

    Component.onCompleted: reloadGame()

    Connections {
        target: uiController.gameManager
        function onGamesChanged() { root.reloadGame() }
    }
    Connections {
        target: uiController.launchPipeline
        function onRunningGamesChanged() { root.reloadGame() }
    }

    background: Rectangle { color: appSettings.bgColor }

    function saveAllChanges() {
        let envMap = {}
        let lines = envVarsArea.text.split("\n")
        for (let i = 0; i < lines.length; ++i) {
            let l = lines[i].trim()
            let eq = l.indexOf("=")
            if (eq > 0) {
                envMap[l.substring(0, eq).trim()] = l.substring(eq + 1).trim()
            }
        }

        let dllMap = {}
        let dlines = dllOverridesArea.text.split("\n")
        for (let j = 0; j < dlines.length; ++j) {
            let dl = dlines[j].trim()
            let deq = dl.indexOf("=")
            if (deq > 0) {
                dllMap[dl.substring(0, deq).trim()] = dl.substring(deq + 1).trim()
            }
        }

        let runnerIdVal = ""
        let runners = uiController.runnerManager.installedRunners
        if (detailRunnerCombo.selectedIndex > 0 && detailRunnerCombo.selectedIndex - 1 < runners.length) {
            runnerIdVal = runners[detailRunnerCombo.selectedIndex - 1].id
        }

        let pfxIdVal = root.gameData.prefixId || "default-prefix"
        let pfxs = uiController.prefixManager.prefixes
        if (detailPrefixCombo.selectedIndex >= 0 && detailPrefixCombo.selectedIndex < pfxs.length) {
            pfxIdVal = pfxs[detailPrefixCombo.selectedIndex].id
        }

        let ctrlProfVal = ""
        let cprofs = uiController.controllerManager.profiles
        if (detailCtrlCombo.selectedIndex > 0 && (detailCtrlCombo.selectedIndex - 1) < cprofs.length) {
            ctrlProfVal = cprofs[detailCtrlCombo.selectedIndex - 1].id
        }

        uiController.gameManager.updateGameDetails(root.gameId, {
            title: titleField.text,
            category: categoryField.text,
            releaseYear: yearField.text,
            executablePath: exePathField.text,
            workingDirectory: workDirField.text,
            launchArguments: argsField.text,
            runnerId: runnerIdVal,
            prefixId: pfxIdVal,
            dxvkState: dxvkCombo.selectedIndex - 1,
            vkd3dState: vkd3dCombo.selectedIndex - 1,
            esyncState: esyncCombo.selectedIndex - 1,
            fsyncState: fsyncCombo.selectedIndex - 1,
            dxvkHud: hudCombo.selectedIndex === 0 ? "" : ["none", "fps", "devinfo,fps,frametimes", "full"][hudCombo.selectedIndex - 1],
            virtualDesktop: vdesktopCheck.checked,
            virtualDesktopResolution: vdesktopResField.text,
            mangohudState: mangohudCombo.selectedIndex - 1,
            gamemodeState: gamemodeCombo.selectedIndex - 1,
            cpuAffinity: affinityField.text,
            processPriority: Number(priorityField.text) || 0,
            xboxEmulationState: xboxEmuCombo.selectedIndex - 1,
            controllerProfileId: ctrlProfVal,
            preLaunchScript: preScriptField.text,
            postExitScript: postScriptField.text,
            environmentVariables: envMap,
            dllOverrides: dllMap
        })
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 0

            // ── Hero Banner Header ───────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 320

                Image {
                    anchors.fill: parent
                    source: root.gameData.bannerPath || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(13/255, 13/255, 17/255, 0.45) }
                        GradientStop { position: 0.8; color: Qt.rgba(13/255, 13/255, 17/255, 0.85) }
                        GradientStop { position: 1.0; color: appSettings.bgColor }
                    }
                }

                // Back Button (Top-Left)
                M3Button {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 24
                    text: "Library"
                    iconSource: "qrc:/tsuki_app/icons/actions/back.svg"
                    buttonType: "tonal"
                    onClicked: root.backRequested()
                }

                // Game Summary Row
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 36
                    anchors.rightMargin: 36
                    anchors.bottomMargin: 20
                    spacing: 24

                    // Poster Card
                    Rectangle {
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 195
                        radius: appSettings.cardRadius
                        color: appSettings.surfaceColor
                        border.color: root.gameData.isRunning ? "#22c55e" : appSettings.accentColor
                        border.width: 2
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: root.gameData.coverPath || ""
                            fillMode: Image.PreserveAspectCrop
                        }
                    }

                    // Title & Actions Column
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        spacing: 12

                        // Metadata Chips Row
                        RowLayout {
                            spacing: 10

                            Rectangle {
                                radius: 6
                                height: 24
                                implicitHeight: 24
                                implicitWidth: rTagLbl.implicitWidth + 20
                                Layout.preferredWidth: implicitWidth
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignVCenter
                                color: root.gameData.isRunning ? Qt.rgba(34/255, 197/255, 94/255, 0.2) : Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.2)
                                border.color: root.gameData.isRunning ? "#22c55e" : appSettings.accentColor
                                border.width: 1

                                Label {
                                    id: rTagLbl
                                    anchors.centerIn: parent
                                    text: root.gameData.isRunning ? "RUNNING" : (root.gameData.runnerTag || "WINE")
                                    color: root.gameData.isRunning ? "#22c55e" : appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    renderType: Text.QtRendering
                                }
                            }

                            Label {
                                text: "Playtime: " + (root.gameData.playtimeFormatted || "Never played") + "  •  Last Played: " + (root.gameData.lastPlayedFormatted || "Never")
                                color: appSettings.textSecColor
                                font.pixelSize: 13
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        // Title
                        Label {
                            text: root.gameData.title || "Game Title"
                            color: appSettings.textColor
                            font.pixelSize: 34
                            font.weight: Font.Bold
                            font.letterSpacing: -0.6
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Primary Action Buttons
                        RowLayout {
                            spacing: 12

                            M3Button {
                                text: root.gameData.isRunning ? "Stop Game" : "Play Now"
                                iconSource: root.gameData.isRunning ? "qrc:/tsuki_app/icons/actions/stop.svg" : "qrc:/tsuki_app/icons/actions/play.svg"
                                buttonType: root.gameData.isRunning ? "destructive" : "filled"
                                implicitHeight: 44
                                onClicked: {
                                    if (root.gameData.isRunning) {
                                        uiController.launchPipeline.stopGame(root.gameId)
                                    } else {
                                        root.saveAllChanges()
                                        uiController.launchPipeline.launchGame(root.gameId)
                                    }
                                }
                            }

                            M3Button {
                                text: "Winetricks"
                                iconSource: "qrc:/tsuki_app/icons/actions/wrench.svg"
                                buttonType: "tonal"
                                implicitHeight: 44
                                onClicked: root.winetricksRequested(root.gameData.prefixId || "default-prefix", root.gameData.title || "")
                            }

                            M3Button {
                                text: "Shortcut"
                                iconSource: "qrc:/tsuki_app/icons/actions/shortcut.svg"
                                buttonType: "tonal"
                                implicitHeight: 44
                                onClicked: uiController.gameManager.createDesktopShortcut(root.gameId, true)
                            }

                            M3Button {
                                text: "Game Folder"
                                iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                buttonType: "tonal"
                                implicitHeight: 44
                                onClicked: uiController.gameManager.openGameDirectory(root.gameId)
                            }

                            M3Button {
                                text: "Prefix Folder"
                                iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                buttonType: "tonal"
                                implicitHeight: 44
                                onClicked: {
                                    if (root.gameData.prefixId) {
                                        uiController.prefixManager.openPrefixInFileManager(root.gameData.prefixId)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Material 3 Primary Tabs Bar ─────────────────────────────────
            Item {
                id: tabsBar
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 4

                // Bottom full-width line
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: appSettings.borderColor
                }

                Row {
                    id: tabsRow
                    anchors.fill: parent
                    spacing: 8

                    Repeater {
                        id: tabRepeater
                        model: [
                            "General & Paths",
                            "Wine & DXVK",
                            "Performance & Controller",
                            "Artwork & Media",
                            "Execution Logs"
                        ]

                        Item {
                            id: tabItem
                            required property int index
                            required property string modelData
                            readonly property bool isSelected: root.activeTab === index
                            height: parent.height
                            width: tabItemLbl.implicitWidth + 32

                            Rectangle {
                                anchors.fill: parent
                                anchors.bottomMargin: 2
                                radius: 8
                                color: tabItemMA.containsMouse 
                                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)) 
                                    : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            Label {
                                id: tabItemLbl
                                anchors.centerIn: parent
                                text: tabItem.modelData
                                color: tabItem.isSelected ? appSettings.accentColor : (tabItemMA.containsMouse ? appSettings.textColor : appSettings.textSecColor)
                                font.pixelSize: 14
                                font.weight: tabItem.isSelected ? Font.DemiBold : Font.Normal
                                renderType: Text.QtRendering
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: tabItemMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeTab = tabItem.index
                            }
                        }
                    }
                }

                // Material 3 Active Indicator (3dp height, smooth animation)
                Rectangle {
                    id: tabActiveIndicator
                    height: 3
                    radius: 1.5
                    color: appSettings.accentColor
                    anchors.bottom: parent.bottom

                    property var currentItem: tabRepeater.itemAt(root.activeTab)
                    x: currentItem ? currentItem.x + 12 : 0
                    width: currentItem ? currentItem.width - 24 : 0

                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            // ── Tab Content Area ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 12
                Layout.bottomMargin: 36
                implicitHeight: tabStack.implicitHeight + 40
                radius: 20
                color: appSettings.surfaceColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                StackLayout {
                    id: tabStack
                    anchors.fill: parent
                    anchors.margins: 24
                    currentIndex: root.activeTab

                    // TAB 0: General & Paths
                    ColumnLayout {
                        spacing: 16
                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Label { text: "Game Title"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                                M3TextField {
                                    id: titleField
                                    Layout.fillWidth: true
                                    text: root.gameData.title || ""
                                }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 200; spacing: 6
                                Label { text: "Category"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                                M3TextField {
                                    id: categoryField
                                    Layout.fillWidth: true
                                    text: root.gameData.category || "Action"
                                }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 140; spacing: 6
                                Label { text: "Release Year"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                                M3TextField {
                                    id: yearField
                                    Layout.fillWidth: true
                                    text: root.gameData.releaseYear || ""
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6
                            Label { text: "Executable Path (.exe)"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                M3TextField {
                                    id: exePathField
                                    Layout.fillWidth: true
                                    text: root.gameData.executablePath || ""
                                    onCommit: root.saveAllChanges()
                                }
                                M3Button {
                                    text: "Browse…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                    buttonType: "tonal"
                                    onClicked: {
                                        let p = uiController.selectFile("Select Game Executable", "Executable Files (*.exe *.bat *.sh *.bin *.AppImage);;All Files (*)", exePathField.text)
                                        if (p && p.length > 0) {
                                            exePathField.text = p
                                            root.saveAllChanges()
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Label { text: "Working Directory"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    M3TextField {
                                        id: workDirField
                                        Layout.fillWidth: true
                                        text: root.gameData.workingDirectory || ""
                                        onCommit: root.saveAllChanges()
                                    }
                                    M3Button {
                                        text: "Browse…"
                                        iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                        buttonType: "tonal"
                                        onClicked: {
                                            let p = uiController.selectFolder("Select Working Directory", workDirField.text)
                                            if (p && p.length > 0) {
                                                workDirField.text = p
                                                root.saveAllChanges()
                                            }
                                        }
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Label { text: "Custom Launch Arguments"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                                M3TextField {
                                    id: argsField
                                    Layout.fillWidth: true
                                    text: root.gameData.launchArguments || ""
                                    placeholderText: "e.g. -dx11 -novid"
                                    onCommit: root.saveAllChanges()
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Label { text: "Wine / Proton Runner Override"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                                StyledCombo {
                                    id: detailRunnerCombo
                                    Layout.fillWidth: true
                                    readonly property var runners: uiController.runnerManager.installedRunners
                                    comboModel: {
                                        let list = ["Use Global Default Runner"]
                                        for (let i = 0; i < runners.length; i++) {
                                            list.push(runners[i].name)
                                        }
                                        return list
                                    }
                                    selectedIndex: {
                                        let curId = root.gameData.runnerId
                                        for (let i = 0; i < runners.length; i++) {
                                            if (runners[i].id === curId) return i + 1
                                        }
                                        return 0
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Label { text: "Wine Prefix Environment"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                                StyledCombo {
                                    id: detailPrefixCombo
                                    Layout.fillWidth: true
                                    readonly property var pfxs: uiController.prefixManager.prefixes
                                    comboModel: {
                                        let list = []
                                        for (let i = 0; i < pfxs.length; i++) {
                                            list.push(pfxs[i].name)
                                        }
                                        return list.length > 0 ? list : ["Default Prefix"]
                                    }
                                    selectedIndex: {
                                        let curId = root.gameData.prefixId
                                        for (let i = 0; i < pfxs.length; i++) {
                                            if (pfxs[i].id === curId) return i
                                        }
                                        return 0
                                    }
                                }
                            }
                        }
                    }

                    // TAB 1: Wine & DXVK
                    ColumnLayout {
                        spacing: 16

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            columnSpacing: 14
                            rowSpacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "DXVK (D3D9/10/11 → Vulkan)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                StyledCombo {
                                    id: dxvkCombo
                                    Layout.fillWidth: true
                                    comboModel: ["Global Default", "Disabled", "Enabled"]
                                    selectedIndex: (root.gameData.dxvkState !== undefined ? root.gameData.dxvkState : -1) + 1
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "VKD3D-Proton (D3D12 → Vulkan)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                StyledCombo {
                                    id: vkd3dCombo
                                    Layout.fillWidth: true
                                    comboModel: ["Global Default", "Disabled", "Enabled"]
                                    selectedIndex: (root.gameData.vkd3dState !== undefined ? root.gameData.vkd3dState : -1) + 1
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Esync (Eventfd Sync)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                StyledCombo {
                                    id: esyncCombo
                                    Layout.fillWidth: true
                                    comboModel: ["Global Default", "Disabled", "Enabled"]
                                    selectedIndex: (root.gameData.esyncState !== undefined ? root.gameData.esyncState : -1) + 1
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Fsync (Futex2 Sync)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                StyledCombo {
                                    id: fsyncCombo
                                    Layout.fillWidth: true
                                    comboModel: ["Global Default", "Disabled", "Enabled"]
                                    selectedIndex: (root.gameData.fsyncState !== undefined ? root.gameData.fsyncState : -1) + 1
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 16
                            ColumnLayout {
                                Layout.preferredWidth: 260; spacing: 4
                                Label { text: "DXVK HUD Statistics"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                StyledCombo {
                                    id: hudCombo
                                    Layout.fillWidth: true
                                    comboModel: ["Global Default", "none", "fps", "devinfo,fps,frametimes", "full"]
                                    selectedIndex: {
                                        let h = root.gameData.dxvkHud || ""
                                        let idx = ["none", "fps", "devinfo,fps,frametimes", "full"].indexOf(h)
                                        return idx >= 0 ? idx + 1 : 0
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 10
                                Label { text: "Virtual Desktop:"; color: appSettings.textColor; font.pixelSize: 13 }
                                Toggle {
                                    id: vdesktopCheck
                                    checked: root.gameData.virtualDesktop || false
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 160; spacing: 4
                                Label { text: "Resolution"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                M3TextField {
                                    id: vdesktopResField
                                    Layout.fillWidth: true
                                    text: root.gameData.virtualDesktopResolution || "1920x1080"
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "DLL Overrides (one per line, e.g. dinput8=n,b)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 90
                                    radius: 12
                                    color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                                    border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                                    ScrollView {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        TextArea {
                                            id: dllOverridesArea
                                            color: appSettings.textColor
                                            font.family: "monospace"
                                            font.pixelSize: 12
                                            placeholderText: "dinput8=n,b\nwinmm=n,b"
                                            placeholderTextColor: appSettings.textTerColor
                                            text: {
                                                let m = root.gameData.dllOverrides || {}
                                                let out = []
                                                for (let k in m) out.push(k + "=" + m[k])
                                                return out.join("\n")
                                            }
                                            background: null
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Environment Variables (KEY=VALUE)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 90
                                    radius: 12
                                    color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                                    border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                                    ScrollView {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        TextArea {
                                            id: envVarsArea
                                            color: appSettings.textColor
                                            font.family: "monospace"
                                            font.pixelSize: 12
                                            placeholderText: "DXVK_ASYNC=1\nPROTON_ENABLE_NVAPI=1"
                                            placeholderTextColor: appSettings.textTerColor
                                            text: {
                                                let m = root.gameData.environmentVariables || {}
                                                let out = []
                                                for (let k in m) out.push(k + "=" + m[k])
                                                return out.join("\n")
                                            }
                                            background: null
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // TAB 2: Performance & Controller
                    ColumnLayout {
                        spacing: 16

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            columnSpacing: 14
                            rowSpacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "MangoHud Overlay"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                StyledCombo {
                                    id: mangohudCombo
                                    Layout.fillWidth: true
                                    comboModel: ["Global Default", "Disabled", "Enabled"]
                                    selectedIndex: (root.gameData.mangohudState !== undefined ? root.gameData.mangohudState : -1) + 1
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Feral GameMode"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                StyledCombo {
                                    id: gamemodeCombo
                                    Layout.fillWidth: true
                                    comboModel: ["Global Default", "Disabled", "Enabled"]
                                    selectedIndex: (root.gameData.gamemodeState !== undefined ? root.gameData.gamemodeState : -1) + 1
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "CPU Core Affinity (taskset)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                M3TextField {
                                    id: affinityField
                                    Layout.fillWidth: true
                                    text: root.gameData.cpuAffinity || ""
                                    placeholderText: "e.g. 0-7"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Process Priority (nice)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                M3TextField {
                                    id: priorityField
                                    Layout.fillWidth: true
                                    text: String(root.gameData.processPriority || 0)
                                    placeholderText: "0"
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Xbox Controller Emulation"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                StyledCombo {
                                    id: xboxEmuCombo
                                    Layout.fillWidth: true
                                    comboModel: ["Global Default", "Disabled", "Enabled"]
                                    selectedIndex: (root.gameData.xboxEmulationState !== undefined ? root.gameData.xboxEmulationState : -1) + 1
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Controller Profile"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                StyledCombo {
                                    id: detailCtrlCombo
                                    Layout.fillWidth: true
                                    readonly property var pList: uiController.controllerManager.profiles
                                    comboModel: {
                                        let arr = ["Global Default Profile"]
                                        for (let i = 0; i < pList.length; ++i) arr.push(pList[i].name)
                                        return arr
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Pre-Launch Script"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                M3TextField {
                                    id: preScriptField
                                    Layout.fillWidth: true
                                    text: root.gameData.preLaunchScript || ""
                                    placeholderText: "/path/to/pre.sh"
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Post-Exit Script"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                M3TextField {
                                    id: postScriptField
                                    Layout.fillWidth: true
                                    text: root.gameData.postExitScript || ""
                                    placeholderText: "/path/to/post.sh"
                                }
                            }
                        }
                    }

                    // TAB 3: Artwork & Media
                    ColumnLayout {
                        spacing: 16

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "SteamGridDB Automatic Artwork & Manual Overrides"
                                color: appSettings.textColor
                                font.pixelSize: 15; font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }
                            M3Button {
                                text: "Auto-Fetch Artwork"
                                iconSource: "qrc:/tsuki_app/icons/actions/refresh.svg"
                                buttonType: "filled"
                                onClicked: uiController.gameManager.refreshArtworkFromSteamGridDb(root.gameId)
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 12

                            M3Button {
                                Layout.fillWidth: true
                                text: "Choose Poster Cover (600×900)…"
                                iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                buttonType: "tonal"
                                onClicked: {
                                    let p = uiController.selectFile("Select Poster Image", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                    if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, p, "", "", "")
                                }
                            }
                            M3Button {
                                Layout.fillWidth: true
                                text: "Choose Hero Banner (1920×620)…"
                                iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                buttonType: "tonal"
                                onClicked: {
                                    let p = uiController.selectFile("Select Hero Banner", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                    if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, "", p, "", "")
                                }
                            }
                            M3Button {
                                Layout.fillWidth: true
                                text: "Choose Transparent Logo…"
                                iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                buttonType: "tonal"
                                onClicked: {
                                    let p = uiController.selectFile("Select Logo Image", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                    if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, "", "", p, "")
                                }
                            }
                            M3Button {
                                Layout.fillWidth: true
                                text: "Choose Shortcut Icon…"
                                iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                buttonType: "tonal"
                                onClicked: {
                                    let p = uiController.selectFile("Select Icon Image", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                    if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, "", "", "", p)
                                }
                            }
                        }
                    }

                    // TAB 4: Execution Logs
                    ColumnLayout {
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Execution Console Log (" + (root.gameData.title || "") + ")"
                                color: appSettings.textColor
                                font.pixelSize: 14; font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }
                            M3Button {
                                text: "Export Log"
                                iconSource: "qrc:/tsuki_app/icons/actions/shortcut.svg"
                                buttonType: "tonal"
                                onClicked: uiController.diagnosticsManager.exportGameLog(root.gameId, "")
                            }
                            M3Button {
                                text: "Clear"
                                iconSource: "qrc:/tsuki_app/icons/actions/trash.svg"
                                buttonType: "destructive"
                                onClicked: uiController.diagnosticsManager.clearGameLog(root.gameId)
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 280
                            radius: 12
                            color: "#08080b"
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 12
                                clip: true
                                TextArea {
                                    readOnly: true
                                    text: uiController.diagnosticsManager.activeGameLog
                                    color: "#e4e4e7"
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    wrapMode: TextEdit.Wrap
                                    background: null
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
