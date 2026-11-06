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
                id: heroBannerItem
                Layout.fillWidth: true
                Layout.preferredHeight: {
                    let ratio = (bannerImg.status === Image.Ready && bannerImg.implicitWidth > 0)
                        ? (bannerImg.implicitHeight / bannerImg.implicitWidth)
                        : (620 / 1920)
                    let targetHeight = root.width * ratio
                    return Math.max(300, Math.min(root.height * 0.62, targetHeight))
                }

                Image {
                    id: bannerImg
                    anchors.fill: parent
                    source: root.gameData.bannerPath || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(13/255, 13/255, 17/255, 0.40) }
                        GradientStop { position: 0.35; color: "transparent" }
                        GradientStop { position: 0.65; color: Qt.rgba(13/255, 13/255, 17/255, 0.55) }
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

                    // Poster Card (dynamically scaled, 2:3 aspect ratio)
                    Rectangle {
                        id: posterCard
                        readonly property real targetHeight: Math.min(270, Math.max(185, heroBannerItem.height * 0.48))
                        Layout.preferredHeight: targetHeight
                        Layout.preferredWidth: Math.round(targetHeight * (2.0 / 3.0))
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

                            M3Button {
                                text: "Remove"
                                iconSource: "qrc:/tsuki_app/icons/actions/trash.svg"
                                buttonType: "destructive"
                                implicitHeight: 44
                                onClicked: removeGameDialog.openDialog(root.gameId, root.gameData.title, root.gameData.prefixId)
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
                id: tabContentCard
                Layout.fillWidth: true
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 12
                Layout.bottomMargin: 24

                readonly property real activeTabHeight: {
                    switch (root.activeTab) {
                        case 0: return tab0General ? tab0General.implicitHeight : 380
                        case 1: return tab1Wine ? tab1Wine.implicitHeight : 480
                        case 2: return tab2Perf ? tab2Perf.implicitHeight : 650
                        case 3: return tab3Art ? tab3Art.implicitHeight : 300
                        case 4: return tab4Logs ? tab4Logs.implicitHeight : 360
                        default: return 400
                    }
                }

                implicitHeight: activeTabHeight + 48
                radius: 20
                color: appSettings.surfaceColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                StackLayout {
                    id: tabStack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 24
                    height: tabContentCard.activeTabHeight
                    currentIndex: root.activeTab

                    // TAB 0: General & Paths
                    ColumnLayout {
                        id: tab0General
                        spacing: 10

                        // ── Section 1: Executable & Launch Settings ──
                        Label {
                            text: "EXECUTABLE & LAUNCH CONFIGURATION"
                            color: appSettings.accentColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            Layout.bottomMargin: 2
                        }

                        // Row 1: Game Title
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label { text: "Game Title"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Display name in library and system desktop shortcuts"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }

                            M3TextField {
                                id: titleField
                                Layout.preferredWidth: Math.min(420, root.width * 0.45)
                                text: root.gameData.title || ""
                                onCommit: root.saveAllChanges()
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Row 2: Executable Path
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label { text: "Executable Path (.exe)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Target Windows binary to launch through Wine or Proton"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }

                            RowLayout {
                                Layout.preferredWidth: Math.min(520, root.width * 0.50)
                                spacing: 8
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

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Row 3: Working Directory
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label { text: "Working Directory"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Directory where the game process starts and locates game assets"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }

                            RowLayout {
                                Layout.preferredWidth: Math.min(520, root.width * 0.50)
                                spacing: 8
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

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Row 4: Custom Launch Arguments
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label { text: "Custom Launch Arguments"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "CLI parameters passed to the executable upon start"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }

                            M3TextField {
                                id: argsField
                                Layout.preferredWidth: Math.min(420, root.width * 0.45)
                                text: root.gameData.launchArguments || ""
                                placeholderText: "e.g. -dx11 -novid -windowed"
                                onCommit: root.saveAllChanges()
                            }
                        }

                        Item { Layout.fillWidth: true; Layout.preferredHeight: 8 }

                        // ── Section 2: Runner & Prefix Environment ──
                        Label {
                            text: "RUNNER & PREFIX ENVIRONMENT"
                            color: appSettings.accentColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            Layout.bottomMargin: 2
                        }

                        // Row 5: Wine / Proton Runner Override
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label { text: "Wine / Proton Runner Override"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Select a custom Wine or Proton build, or inherit global default runner"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }

                            StyledCombo {
                                id: detailRunnerCombo
                                Layout.preferredWidth: Math.min(340, root.width * 0.40)
                                readonly property var runners: uiController.runnerManager.installedRunners
                                comboModel: {
                                    let defName = "System Wine"
                                    for (let i = 0; i < runners.length; i++) {
                                        if (runners[i].id === appSettings.defaultRunnerId) {
                                            defName = runners[i].name
                                            break
                                        }
                                    }
                                    if (defName === "System Wine" && runners.length > 0) {
                                        defName = runners[0].name
                                    }
                                    let list = ["Global Default (" + defName + ")"]
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

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Row 6: Wine Prefix Environment
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label { text: "Wine Prefix Environment"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Virtual Windows filesystem (C: drive) and registry container"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }

                            StyledCombo {
                                id: detailPrefixCombo
                                Layout.preferredWidth: Math.min(340, root.width * 0.40)
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

                    // TAB 1: Wine & DXVK
                    ColumnLayout {
                        id: tab1Wine
                        spacing: 10

                        // ── Section 1: Direct3D Translators ──
                        Label {
                            text: "DIRECT3D TRANSLATORS"
                            color: appSettings.accentColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            Layout.bottomMargin: 2
                        }

                        // DXVK
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "DXVK (D3D9/10/11 → Vulkan)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Hardware-accelerated Vulkan translation for DirectX 9, 10, and 11 games"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            StyledCombo {
                                id: dxvkCombo
                                Layout.preferredWidth: 250
                                comboModel: ["Global Default (" + (appSettings.dxvkDefault ? "Enabled" : "Disabled") + ")", "Disabled", "Enabled"]
                                selectedIndex: (root.gameData.dxvkState !== undefined ? root.gameData.dxvkState : -1) + 1
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // VKD3D
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "VKD3D-Proton (D3D12 → Vulkan)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "DirectX 12 translation layer for modern Vulkan-capable drivers"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            StyledCombo {
                                id: vkd3dCombo
                                Layout.preferredWidth: 250
                                comboModel: ["Global Default (" + (appSettings.vkd3dDefault ? "Enabled" : "Disabled") + ")", "Disabled", "Enabled"]
                                selectedIndex: (root.gameData.vkd3dState !== undefined ? root.gameData.vkd3dState : -1) + 1
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // DXVK HUD
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "DXVK HUD Statistics"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "On-screen real-time statistics overlay (framerate, GPU load, frame times)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            StyledCombo {
                                id: hudCombo
                                Layout.preferredWidth: 250
                                comboModel: ["Global Default (" + (appSettings.defaultDxvkHud.length > 0 ? appSettings.defaultDxvkHud : "none") + ")", "none", "fps", "devinfo,fps,frametimes", "full"]
                                selectedIndex: {
                                    let h = root.gameData.dxvkHud || ""
                                    let idx = ["none", "fps", "devinfo,fps,frametimes", "full"].indexOf(h)
                                    return idx >= 0 ? idx + 1 : 0
                                }
                            }
                        }

                        Item { Layout.fillWidth: true; Layout.preferredHeight: 8 }

                        // ── Section 2: Kernel Synchronization & Display ──
                        Label {
                            text: "KERNEL SYNCHRONIZATION & DISPLAY"
                            color: appSettings.accentColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            Layout.bottomMargin: 2
                        }

                        // Esync
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Esync (Eventfd Synchronization)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Eliminates wineserver lock contention using Linux eventfd primitives"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            StyledCombo {
                                id: esyncCombo
                                Layout.preferredWidth: 250
                                comboModel: ["Global Default (" + (appSettings.esyncDefault ? "Enabled" : "Disabled") + ")", "Disabled", "Enabled"]
                                selectedIndex: (root.gameData.esyncState !== undefined ? root.gameData.esyncState : -1) + 1
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Fsync
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Fsync (Futex Synchronization)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Direct kernel futex2 synchronization for Linux 5.16+ kernels"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            StyledCombo {
                                id: fsyncCombo
                                Layout.preferredWidth: 250
                                comboModel: ["Global Default (" + (appSettings.fsyncDefault ? "Enabled" : "Disabled") + ")", "Disabled", "Enabled"]
                                selectedIndex: (root.gameData.fsyncState !== undefined ? root.gameData.fsyncState : -1) + 1
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Virtual Desktop
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Virtual Desktop Mode"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Launch game within an emulated X11 desktop window"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            RowLayout {
                                spacing: 12
                                Toggle {
                                    id: vdesktopCheck
                                    checked: root.gameData.virtualDesktop || false
                                }
                                M3TextField {
                                    id: vdesktopResField
                                    implicitWidth: 140
                                    text: root.gameData.virtualDesktopResolution || "1920x1080"
                                    placeholderText: "1920x1080"
                                    enabled: vdesktopCheck.checked
                                }
                            }
                        }

                        Item { Layout.fillWidth: true; Layout.preferredHeight: 8 }

                        // ── Section 3: Advanced Overrides & Environment ──
                        Label {
                            text: "OVERRIDES & ENVIRONMENT VARIABLES"
                            color: appSettings.accentColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            Layout.bottomMargin: 2
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Label { text: "DLL Overrides (one per line, e.g. dinput8=n,b)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 110
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
                                Layout.fillWidth: true
                                spacing: 6
                                Label { text: "Environment Variables (KEY=VALUE)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 110
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
                        id: tab2Perf
                        spacing: 10

                        // ── Section 1: Linux Performance Enhancements ──
                        Label {
                            text: "PERFORMANCE ENHANCEMENTS"
                            color: appSettings.accentColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            Layout.bottomMargin: 2
                        }

                        // MangoHud
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "MangoHud Overlay"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Real-time in-game overlay displaying FPS, frametimes, temperature, and CPU/GPU usage"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            StyledCombo {
                                id: mangohudCombo
                                Layout.preferredWidth: 250
                                comboModel: ["Global Default (" + (appSettings.mangohudDefault ? "Enabled" : "Disabled") + ")", "Disabled", "Enabled"]
                                selectedIndex: (root.gameData.mangohudState !== undefined ? root.gameData.mangohudState : -1) + 1
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // GameMode
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Feral GameMode"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Applies performance governor, real-time scheduler priorities, and inhibits screensaver"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            StyledCombo {
                                id: gamemodeCombo
                                Layout.preferredWidth: 250
                                comboModel: ["Global Default (" + (appSettings.gamemodeDefault ? "Enabled" : "Disabled") + ")", "Disabled", "Enabled"]
                                selectedIndex: (root.gameData.gamemodeState !== undefined ? root.gameData.gamemodeState : -1) + 1
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // CPU Affinity
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "CPU Core Affinity (taskset)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Pin the game process and threads to specific CPU cores (e.g. 0-7, or 0,2,4,6)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            M3TextField {
                                id: affinityField
                                Layout.preferredWidth: 250
                                text: root.gameData.cpuAffinity || ""
                                placeholderText: "e.g. 0-7"
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Process Priority
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Process Priority (nice)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Linux scheduler niceness from -20 (highest priority) to 19 (lowest priority)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            M3TextField {
                                id: priorityField
                                Layout.preferredWidth: 250
                                text: String(root.gameData.processPriority || 0)
                                placeholderText: "0"
                            }
                        }

                        Item { Layout.fillWidth: true; Layout.preferredHeight: 8 }

                        // ── Section 2: Controller & Gamepad ──
                        Label {
                            text: "CONTROLLER & GAMEPAD"
                            color: appSettings.accentColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            Layout.bottomMargin: 2
                        }

                        // Xbox 360 Emulation
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Xbox 360 Controller Emulation"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Emulates an authentic XInput gamepad via Linux /dev/uinput daemon"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            StyledCombo {
                                id: xboxEmuCombo
                                Layout.preferredWidth: 250
                                comboModel: ["Global Default (" + (appSettings.xboxEmulationDefault ? "Enabled" : "Disabled") + ")", "Disabled", "Enabled"]
                                selectedIndex: (root.gameData.xboxEmulationState !== undefined ? root.gameData.xboxEmulationState : -1) + 1
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Controller Profile
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Controller Profile Mapping"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Custom button remapping and stick sensitivity response curves"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            StyledCombo {
                                id: detailCtrlCombo
                                Layout.preferredWidth: 250
                                readonly property var pList: uiController.controllerManager.profiles
                                comboModel: {
                                    let defProf = "Xbox Standard"
                                    for (let i = 0; i < pList.length; ++i) {
                                        if (pList[i].id === appSettings.defaultControllerProfileId) {
                                            defProf = pList[i].name
                                            break
                                        }
                                    }
                                    let arr = ["Global Default (" + defProf + ")"]
                                    for (let i = 0; i < pList.length; ++i) arr.push(pList[i].name)
                                    return arr
                                }
                                selectedIndex: {
                                    let curProf = root.gameData.controllerProfileId
                                    for (let i = 0; i < pList.length; ++i) {
                                        if (pList[i].id === curProf) return i + 1
                                    }
                                    return 0
                                }
                            }
                        }

                        Item { Layout.fillWidth: true; Layout.preferredHeight: 8 }

                        // ── Section 3: Pre-Launch & Post-Exit Automation ──
                        Label {
                            text: "AUTOMATION SCRIPTS"
                            color: appSettings.accentColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            Layout.bottomMargin: 2
                        }

                        // Pre-launch
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Pre-Launch Script"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Shell script executed right before the game process is spawned"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            RowLayout {
                                Layout.preferredWidth: Math.min(460, root.width * 0.45)
                                spacing: 8
                                M3TextField {
                                    id: preScriptField
                                    Layout.fillWidth: true
                                    text: root.gameData.preLaunchScript || ""
                                    placeholderText: "/path/to/pre.sh"
                                    onCommit: root.saveAllChanges()
                                }
                                M3Button {
                                    text: "Browse…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                    buttonType: "tonal"
                                    onClicked: {
                                        let p = uiController.selectFile("Select Pre-Launch Script", "Shell Scripts (*.sh *.bash);;All Files (*)", preScriptField.text)
                                        if (p && p.length > 0) { preScriptField.text = p; root.saveAllChanges() }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Post-exit
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Post-Exit Script"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { text: "Shell script executed after the game process exits and cleans up"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            }
                            RowLayout {
                                Layout.preferredWidth: Math.min(460, root.width * 0.45)
                                spacing: 8
                                M3TextField {
                                    id: postScriptField
                                    Layout.fillWidth: true
                                    text: root.gameData.postExitScript || ""
                                    placeholderText: "/path/to/post.sh"
                                    onCommit: root.saveAllChanges()
                                }
                                M3Button {
                                    text: "Browse…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                    buttonType: "tonal"
                                    onClicked: {
                                        let p = uiController.selectFile("Select Post-Exit Script", "Shell Scripts (*.sh *.bash);;All Files (*)", postScriptField.text)
                                        if (p && p.length > 0) { postScriptField.text = p; root.saveAllChanges() }
                                    }
                                }
                            }
                        }
                    }

                    // TAB 3: Artwork & Media
                    ColumnLayout {
                        id: tab3Art
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 2

                            Label {
                                text: "STEAMGRIDDB AUTOMATIC ARTWORK & MANUAL OVERRIDES"
                                color: appSettings.accentColor
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.8
                                Layout.fillWidth: true
                            }

                            M3Button {
                                text: "Auto-Fetch Artwork"
                                iconSource: "qrc:/tsuki_app/icons/actions/refresh.svg"
                                buttonType: "filled"
                                implicitHeight: 36
                                onClicked: uiController.gameManager.refreshArtworkFromSteamGridDb(root.gameId)
                            }
                        }

                        // Row 1: Poster Cover (600×900)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            spacing: 16

                            Rectangle {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 52
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: root.gameData.coverPath || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Cover Poster (600×900)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { 
                                    text: root.gameData.coverPath ? root.gameData.coverPath : "Default fallback cover generated"
                                    color: appSettings.textSecColor
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }

                            RowLayout {
                                spacing: 8
                                M3Button {
                                    text: "Link…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                                    buttonType: "tonal"
                                    onClicked: artworkUrlDialog.openFor(root.gameId, "cover", "Cover Poster")
                                }
                                M3Button {
                                    text: "Browse…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                    buttonType: "tonal"
                                    onClicked: {
                                        let p = uiController.selectFile("Select Poster Image", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                        if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, p, "", "", "")
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Row 2: Hero Banner (1920×620)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            spacing: 16

                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 36
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: root.gameData.bannerPath || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Hero Banner (1920×620)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { 
                                    text: root.gameData.bannerPath ? root.gameData.bannerPath : "Default fallback hero banner"
                                    color: appSettings.textSecColor
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }

                            RowLayout {
                                spacing: 8
                                M3Button {
                                    text: "Link…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                                    buttonType: "tonal"
                                    onClicked: artworkUrlDialog.openFor(root.gameId, "banner", "Hero Banner")
                                }
                                M3Button {
                                    text: "Browse…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                    buttonType: "tonal"
                                    onClicked: {
                                        let p = uiController.selectFile("Select Hero Banner", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                        if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, "", p, "", "")
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Row 3: Transparent Logo
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            spacing: 16

                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 36
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: root.gameData.logoPath || ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Transparent Logo (PNG/WebP)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { 
                                    text: root.gameData.logoPath ? root.gameData.logoPath : "No custom transparent logo loaded"
                                    color: appSettings.textSecColor
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }

                            RowLayout {
                                spacing: 8
                                M3Button {
                                    text: "Link…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                                    buttonType: "tonal"
                                    onClicked: artworkUrlDialog.openFor(root.gameId, "logo", "Transparent Logo")
                                }
                                M3Button {
                                    text: "Browse…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                    buttonType: "tonal"
                                    onClicked: {
                                        let p = uiController.selectFile("Select Logo Image", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                        if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, "", "", p, "")
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                        // Row 4: Shortcut Icon
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            spacing: 16

                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: root.gameData.iconPath || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: "Desktop & Shortcut Icon"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                Label { 
                                    text: root.gameData.iconPath ? root.gameData.iconPath : "No custom icon assigned"
                                    color: appSettings.textSecColor
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }

                            RowLayout {
                                spacing: 8
                                M3Button {
                                    text: "Link…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                                    buttonType: "tonal"
                                    onClicked: artworkUrlDialog.openFor(root.gameId, "icon", "Shortcut Icon")
                                }
                                M3Button {
                                    text: "Browse…"
                                    iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                    buttonType: "tonal"
                                    onClicked: {
                                        let p = uiController.selectFile("Select Icon Image", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                        if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, "", "", "", p)
                                    }
                                }
                            }
                        }
                    }

                    // TAB 4: Execution Logs
                    ColumnLayout {
                        id: tab4Logs
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

            // Bottom spacer for scroll clearance
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
            }
        }
    }

    ArtworkUrlDialog {
        id: artworkUrlDialog
    }

    RemoveGameDialog {
        id: removeGameDialog
        onGameRemoved: stack.pop()
    }
}
