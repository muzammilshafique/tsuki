import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
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

    FileDialog {
        id: exeFileDialog
        title: "Select Game Executable (.exe)"
        nameFilters: ["Windows Executables (*.exe *.EXE *.bat *.msi)", "All Files (*)"]
        onAccepted: {
            let p = selectedFile.toString()
            if (p.startsWith("file://")) p = p.substring(7)
            exePathField.text = p
        }
    }

    FileDialog {
        id: artworkPicker
        property string targetSlot: "cover"
        title: "Select Artwork Image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.svg *.ico)", "All Files (*)"]
        onAccepted: {
            let p = selectedFile.toString()
            if (targetSlot === "cover") uiController.gameManager.setGameArtwork(root.gameId, p, "", "", "")
            else if (targetSlot === "banner") uiController.gameManager.setGameArtwork(root.gameId, "", p, "", "")
            else if (targetSlot === "logo") uiController.gameManager.setGameArtwork(root.gameId, "", "", p, "")
            else if (targetSlot === "icon") uiController.gameManager.setGameArtwork(root.gameId, "", "", "", p)
        }
    }

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
        if (detailRunnerCombo.currentIndex > 0 && detailRunnerCombo.currentIndex < detailRunnerCombo.runnerChoices.length) {
            runnerIdVal = detailRunnerCombo.runnerChoices[detailRunnerCombo.currentIndex].id
        }

        let pfxIdVal = root.gameData.prefixId || "default-prefix"
        let pfxs = uiController.prefixManager.prefixes
        if (detailPrefixCombo.currentIndex >= 0 && detailPrefixCombo.currentIndex < pfxs.length) {
            pfxIdVal = pfxs[detailPrefixCombo.currentIndex].id
        }

        let ctrlProfVal = ""
        let cprofs = uiController.controllerManager.profiles
        if (detailCtrlCombo.currentIndex > 0 && (detailCtrlCombo.currentIndex - 1) < cprofs.length) {
            ctrlProfVal = cprofs[detailCtrlCombo.currentIndex - 1].id
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
            dxvkState: dxvkCombo.currentIndex - 1,
            vkd3dState: vkd3dCombo.currentIndex - 1,
            esyncState: esyncCombo.currentIndex - 1,
            fsyncState: fsyncCombo.currentIndex - 1,
            dxvkHud: hudCombo.currentText === "Global Default" ? "" : hudCombo.currentText,
            virtualDesktop: vdesktopCheck.checked,
            virtualDesktopResolution: vdesktopResField.text,
            mangohudState: mangohudCombo.currentIndex - 1,
            gamemodeState: gamemodeCombo.currentIndex - 1,
            cpuAffinity: affinityField.text,
            processPriority: Number(prioritySpin.value),
            xboxEmulationState: xboxEmuCombo.currentIndex - 1,
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

            // ── Hero Banner Header ──
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 300

                Image {
                    anchors.fill: parent
                    source: root.gameData.bannerPath || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(13/255, 13/255, 17/255, 0.35) }
                        GradientStop { position: 1.0; color: appSettings.bgColor }
                    }
                }

                // Back Button
                Button {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 24
                    implicitWidth: 110; implicitHeight: 40
                    onClicked: root.backRequested()
                    background: Rectangle {
                        radius: 20
                        color: Qt.rgba(22/255, 22/255, 29/255, 0.85)
                        border.color: appSettings.borderColor
                    }
                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        YIcon { source: "qrc:/tsuki_app/icons/actions/back.svg"; color: appSettings.textColor; size: 18 }
                        Label { text: "Library"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                    }
                }

                // Game Summary Overlay Row
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 36
                    anchors.rightMargin: 36
                    anchors.bottomMargin: 16
                    spacing: 24

                    // Poster Thumbnail
                    Rectangle {
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 195
                        radius: 12
                        color: appSettings.surfaceColor
                        border.color: appSettings.accentColor
                        border.width: 2
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: root.gameData.coverPath || ""
                            fillMode: Image.PreserveAspectCrop
                        }
                    }

                    // Title, Stats & Action Bar
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        spacing: 10

                        RowLayout {
                            spacing: 10
                            Rectangle {
                                radius: 6
                                color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.2)
                                border.color: appSettings.accentColor
                                implicitWidth: rTagLbl.implicitWidth + 14; implicitHeight: 24
                                Label {
                                    id: rTagLbl
                                    anchors.centerIn: parent
                                    text: root.gameData.runnerTag || "WINE"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }
                            Label {
                                text: "Playtime: " + (root.gameData.playtimeFormatted || "Never played") + "  •  Last Played: " + (root.gameData.lastPlayedFormatted || "Never")
                                color: appSettings.textSecColor
                                font.pixelSize: 13
                            }
                        }

                        Label {
                            text: root.gameData.title || "Game Title"
                            color: appSettings.textColor
                            font.pixelSize: 30
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Primary Action Buttons
                        RowLayout {
                            spacing: 12

                            Button {
                                implicitWidth: 165; implicitHeight: 46
                                onClicked: {
                                    if (root.gameData.isRunning) {
                                        uiController.launchPipeline.stopGame(root.gameId)
                                    } else {
                                        root.saveAllChanges()
                                        uiController.launchPipeline.launchGame(root.gameId)
                                    }
                                }
                                background: Rectangle {
                                    radius: 23
                                    color: root.gameData.isRunning ? "#ef4444" : appSettings.accentColor
                                }
                                contentItem: RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    YIcon {
                                        source: root.gameData.isRunning ? "qrc:/tsuki_app/icons/actions/stop.svg" : "qrc:/tsuki_app/icons/actions/play.svg"
                                        color: root.gameData.isRunning ? "#ffffff" : "#0f0f11"
                                        size: 18
                                    }
                                    Label {
                                        text: root.gameData.isRunning ? "Stop Game" : "Play Now"
                                        color: root.gameData.isRunning ? "#ffffff" : "#0f0f11"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            Button {
                                text: "Winetricks"
                                implicitHeight: 42
                                onClicked: root.winetricksRequested(root.gameData.prefixId || "default-prefix", root.gameData.title || "")
                                background: Rectangle { radius: 21; color: appSettings.surfaceAltColor; border.color: appSettings.borderColor }
                                contentItem: RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    YIcon { source: "qrc:/tsuki_app/icons/actions/wrench.svg"; color: "#38bdf8"; size: 16 }
                                    Label { text: "Winetricks"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium; rightPadding: 6 }
                                }
                            }

                            Button {
                                text: "Desktop Shortcut"
                                implicitHeight: 42
                                onClicked: uiController.gameManager.createDesktopShortcut(root.gameId, true)
                                background: Rectangle { radius: 21; color: appSettings.surfaceAltColor; border.color: appSettings.borderColor }
                                contentItem: RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    YIcon { source: "qrc:/tsuki_app/icons/actions/shortcut.svg"; color: appSettings.textSecColor; size: 16 }
                                    Label { text: "Create Shortcut"; color: appSettings.textColor; font.pixelSize: 13; rightPadding: 6 }
                                }
                            }

                            Button {
                                text: "Game Folder"
                                implicitHeight: 42
                                onClicked: uiController.gameManager.openGameDirectory(root.gameId)
                                background: Rectangle { radius: 21; color: appSettings.surfaceAltColor; border.color: appSettings.borderColor }
                                contentItem: RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    YIcon { source: "qrc:/tsuki_app/icons/actions/folder.svg"; color: appSettings.textSecColor; size: 16 }
                                    Label { text: "Game Folder"; color: appSettings.textColor; font.pixelSize: 13; rightPadding: 6 }
                                }
                            }

                            Button {
                                text: "Save Config"
                                implicitHeight: 42
                                onClicked: root.saveAllChanges()
                                background: Rectangle { radius: 21; color: Qt.rgba(52/255, 211/255, 153/255, 0.18); border.color: "#34d399" }
                                contentItem: Label {
                                    text: "Save Configuration"
                                    color: "#34d399"
                                    font.pixelSize: 13; font.weight: Font.DemiBold
                                    leftPadding: 16; rightPadding: 16
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }

            // ── Configuration Tabs Bar ──
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 12
                spacing: 10

                Repeater {
                    model: [
                        "General & Runner",
                        "Wine, DXVK & Overrides",
                        "Performance, Scripts & Controller",
                        "Artwork & SteamGridDB",
                        "Live Game Logs"
                    ]
                    delegate: Button {
                        required property int index
                        required property string modelData
                        text: modelData
                        onClicked: root.activeTab = index
                        background: Rectangle {
                            radius: 18
                            color: root.activeTab === index ? appSettings.accentColor : appSettings.surfaceColor
                            border.color: root.activeTab === index ? appSettings.accentColor : appSettings.borderColor
                        }
                        contentItem: Label {
                            text: parent.text
                            color: root.activeTab === index ? "#0f0f11" : appSettings.textColor
                            font.pixelSize: 13
                            font.weight: root.activeTab === index ? Font.DemiBold : Font.Normal
                            leftPadding: 14; rightPadding: 14
                        }
                    }
                }
            }

            // ── Tab Content Area ──
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 16
                Layout.bottomMargin: 36
                implicitHeight: tabStack.implicitHeight + 40
                radius: 16
                color: appSettings.surfaceColor
                border.color: appSettings.borderColor

                StackLayout {
                    id: tabStack
                    anchors.fill: parent
                    anchors.margins: 20
                    currentIndex: root.activeTab

                    // TAB 0: General & Runner
                    ColumnLayout {
                        spacing: 14
                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Game Title"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextField {
                                    id: titleField
                                    Layout.fillWidth: true
                                    text: root.gameData.title || ""
                                    color: appSettings.textColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 180; spacing: 4
                                Label { text: "Category"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextField {
                                    id: categoryField
                                    Layout.fillWidth: true
                                    text: root.gameData.category || "Action"
                                    color: appSettings.textColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 120; spacing: 4
                                Label { text: "Release Year"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextField {
                                    id: yearField
                                    Layout.fillWidth: true
                                    text: root.gameData.releaseYear || ""
                                    color: appSettings.textColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 4
                            Label { text: "Executable Path (.exe)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                TextField {
                                    id: exePathField
                                    Layout.fillWidth: true
                                    text: root.gameData.executablePath || ""
                                    color: appSettings.textColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                                Button { text: "Browse…"; onClicked: exeFileDialog.open() }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Working Directory"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextField {
                                    id: workDirField
                                    Layout.fillWidth: true
                                    text: root.gameData.workingDirectory || ""
                                    color: appSettings.textColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Custom Launch Arguments"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextField {
                                    id: argsField
                                    Layout.fillWidth: true
                                    text: root.gameData.launchArguments || ""
                                    placeholderText: "e.g. -dx11 -novid"
                                    color: appSettings.textColor
                                    placeholderTextColor: appSettings.textTerColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Wine / Proton Runner Override"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: detailRunnerCombo
                                    Layout.fillWidth: true
                                    property var runnerChoices: {
                                        let arr = [{ id: "", name: "Use Global Default Runner" }]
                                        let list = uiController.runnerManager.installedRunners
                                        for (let i = 0; i < list.length; ++i) arr.push(list[i])
                                        return arr
                                    }
                                    model: runnerChoices
                                    textRole: "name"
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Label { text: "Wine Prefix"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: detailPrefixCombo
                                    Layout.fillWidth: true
                                    model: uiController.prefixManager.prefixes
                                    textRole: "name"
                                }
                            }
                        }
                    }

                    // TAB 1: Wine, DXVK & Overrides
                    ColumnLayout {
                        spacing: 14
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            columnSpacing: 14
                            rowSpacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "DXVK (D3D9/10/11 → Vulkan)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: dxvkCombo
                                    Layout.fillWidth: true
                                    model: ["Global Default", "Disabled", "Enabled"]
                                    currentIndex: (root.gameData.dxvkState !== undefined ? root.gameData.dxvkState : -1) + 1
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "VKD3D-Proton (D3D12 → Vulkan)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: vkd3dCombo
                                    Layout.fillWidth: true
                                    model: ["Global Default", "Disabled", "Enabled"]
                                    currentIndex: (root.gameData.vkd3dState !== undefined ? root.gameData.vkd3dState : -1) + 1
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Esync (Eventfd Sync)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: esyncCombo
                                    Layout.fillWidth: true
                                    model: ["Global Default", "Disabled", "Enabled"]
                                    currentIndex: (root.gameData.esyncState !== undefined ? root.gameData.esyncState : -1) + 1
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Fsync (Futex2 Sync)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: fsyncCombo
                                    Layout.fillWidth: true
                                    model: ["Global Default", "Disabled", "Enabled"]
                                    currentIndex: (root.gameData.fsyncState !== undefined ? root.gameData.fsyncState : -1) + 1
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 16
                            ColumnLayout {
                                Layout.preferredWidth: 240
                                Label { text: "DXVK HUD Overlay"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: hudCombo
                                    Layout.fillWidth: true
                                    model: ["Global Default", "none", "fps", "devinfo,fps,frametimes", "full"]
                                }
                            }
                            CheckBox {
                                id: vdesktopCheck
                                text: "Run inside Wine Virtual Desktop"
                                checked: root.gameData.virtualDesktop || false
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 160
                                Label { text: "Desktop Resolution"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextField {
                                    id: vdesktopResField
                                    Layout.fillWidth: true
                                    text: root.gameData.virtualDesktopResolution || "1920x1080"
                                    color: appSettings.textColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Per-Game DLL Overrides (one per line, e.g. dinput8=n,b)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextArea {
                                    id: dllOverridesArea
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 90
                                    color: appSettings.textColor
                                    font.family: "monospace"
                                    placeholderText: "dinput8=n,b\nwinmm=n,b"
                                    placeholderTextColor: appSettings.textTerColor
                                    text: {
                                        let m = root.gameData.dllOverrides || {}
                                        let out = []
                                        for (let k in m) out.push(k + "=" + m[k])
                                        return out.join("\n")
                                    }
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Custom Environment Variables (one per line, KEY=VALUE)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextArea {
                                    id: envVarsArea
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 90
                                    color: appSettings.textColor
                                    font.family: "monospace"
                                    placeholderText: "DXVK_ASYNC=1\nPROTON_ENABLE_NVAPI=1"
                                    placeholderTextColor: appSettings.textTerColor
                                    text: {
                                        let m = root.gameData.environmentVariables || {}
                                        let out = []
                                        for (let k in m) out.push(k + "=" + m[k])
                                        return out.join("\n")
                                    }
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                        }
                    }

                    // TAB 2: Performance, Scripts & Controller
                    ColumnLayout {
                        spacing: 14
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            columnSpacing: 14

                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "MangoHud Performance Overlay"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: mangohudCombo
                                    Layout.fillWidth: true
                                    model: ["Global Default", "Disabled", "Enabled"]
                                    currentIndex: (root.gameData.mangohudState !== undefined ? root.gameData.mangohudState : -1) + 1
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Feral GameMode (gamemoderun)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: gamemodeCombo
                                    Layout.fillWidth: true
                                    model: ["Global Default", "Disabled", "Enabled"]
                                    currentIndex: (root.gameData.gamemodeState !== undefined ? root.gameData.gamemodeState : -1) + 1
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "CPU Core Affinity (taskset)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextField {
                                    id: affinityField
                                    Layout.fillWidth: true
                                    text: root.gameData.cpuAffinity || ""
                                    placeholderText: "All cores (or e.g. 0-7)"
                                    color: appSettings.textColor
                                    placeholderTextColor: appSettings.textTerColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Process Priority (nice)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                SpinBox {
                                    id: prioritySpin
                                    from: -20; to: 19
                                    value: root.gameData.processPriority || 0
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Xbox / XInput Controller Emulation"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: xboxEmuCombo
                                    Layout.fillWidth: true
                                    model: ["Global Default", "Disabled", "Enabled"]
                                    currentIndex: (root.gameData.xboxEmulationState !== undefined ? root.gameData.xboxEmulationState : -1) + 1
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Per-Game Controller Profile"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                ComboBox {
                                    id: detailCtrlCombo
                                    Layout.fillWidth: true
                                    model: {
                                        let arr = ["Global Default Profile"]
                                        let p = uiController.controllerManager.profiles
                                        for (let i = 0; i < p.length; ++i) arr.push(p[i].name)
                                        return arr
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Pre-Launch Script / Command"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextField {
                                    id: preScriptField
                                    Layout.fillWidth: true
                                    text: root.gameData.preLaunchScript || ""
                                    placeholderText: "/path/to/pre-launch.sh"
                                    color: appSettings.textColor
                                    placeholderTextColor: appSettings.textTerColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: "Post-Exit Script / Command"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                TextField {
                                    id: postScriptField
                                    Layout.fillWidth: true
                                    text: root.gameData.postExitScript || ""
                                    placeholderText: "/path/to/post-exit.sh"
                                    color: appSettings.textColor
                                    placeholderTextColor: appSettings.textTerColor
                                    background: Rectangle { radius: 8; color: appSettings.inputColor; border.color: appSettings.borderColor }
                                }
                            }
                        }
                    }

                    // TAB 3: Artwork & SteamGridDB
                    ColumnLayout {
                        spacing: 14
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Automatic SteamGridDB / Steam Artwork & Manual Overrides"
                                color: appSettings.textColor
                                font.pixelSize: 15; font.weight: Font.Medium
                                Layout.fillWidth: true
                            }
                            Button {
                                text: "Auto-Fetch Artwork from SteamGridDB"
                                onClicked: uiController.gameManager.refreshArtworkFromSteamGridDb(root.gameId)
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 12

                            Button {
                                Layout.fillWidth: true
                                text: "Choose Custom Poster (600×900)…"
                                onClicked: { artworkPicker.targetSlot = "cover"; artworkPicker.open() }
                            }
                            Button {
                                Layout.fillWidth: true
                                text: "Choose Custom Hero Banner (1920×620)…"
                                onClicked: { artworkPicker.targetSlot = "banner"; artworkPicker.open() }
                            }
                            Button {
                                Layout.fillWidth: true
                                text: "Choose Custom Transparent Logo…"
                                onClicked: { artworkPicker.targetSlot = "logo"; artworkPicker.open() }
                            }
                            Button {
                                Layout.fillWidth: true
                                text: "Choose Custom Shortcut Icon…"
                                onClicked: { artworkPicker.targetSlot = "icon"; artworkPicker.open() }
                            }
                        }
                    }

                    // TAB 4: Live Game Logs
                    ColumnLayout {
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Live Execution Log (" + (root.gameData.title || "") + ")"
                                color: appSettings.textColor
                                font.pixelSize: 14; font.weight: Font.Medium
                                Layout.fillWidth: true
                            }
                            Button {
                                text: "Export Log to Home"
                                onClicked: {
                                    uiController.diagnosticsManager.exportGameLog(root.gameId, "")
                                }
                            }
                            Button {
                                text: "Clear Log"
                                onClicked: uiController.diagnosticsManager.clearGameLog(root.gameId)
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 260
                            radius: 8
                            color: "#08080b"
                            border.color: appSettings.borderColor

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 10
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

