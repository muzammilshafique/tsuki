import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Page {
    id: root
    objectName: "gameDetailPage"
    property string gameId: ""
    property var gameData: ({})
    property int activeTab: 0
    property bool isSaving: false

    readonly property bool isNative: root.gameData.isNative === true

    readonly property var tabList: {
        if (root.isNative) {
            return [
                { label: "General & Paths", stackIndex: 0 },
                { label: "Performance & Controller", stackIndex: 2 },
                { label: "Artwork & Media", stackIndex: 3 },
                { label: "Execution Logs", stackIndex: 4 }
            ]
        }
        return [
            { label: "General & Paths", stackIndex: 0 },
            { label: "Wine & DXVK", stackIndex: 1 },
            { label: "Performance & Controller", stackIndex: 2 },
            { label: "Artwork & Media", stackIndex: 3 },
            { label: "Execution Logs", stackIndex: 4 }
        ]
    }

    onGameDataChanged: {
        if (root.isNative && root.activeTab === 1) {
            root.activeTab = 0
        }
    }

    signal backRequested()
    signal winetricksRequested(string prefixId, string gameTitle)

    focus: true

    function isTextInputActive() {
        const fi = root.Window.activeFocusItem
        if (!fi) return false
        const s = fi.toString()
        if (s.indexOf("M3TextField") !== -1) {
            return Boolean(fi.isEditing)
        }
        return s.indexOf("TextInput") !== -1 || s.indexOf("TextField") !== -1 || s.indexOf("TextArea") !== -1 || s.indexOf("TextEdit") !== -1
    }

    function isAnyModalOpen() {
        return isAnyPopupOpen()
    }

    function isAnyPopupOpen() {
        if (actionsPopup.visible || artworkUrlDialog.visible || removeGameDialog.visible) return true
        if (typeof detailRunnerCombo !== "undefined" && detailRunnerCombo.popup.visible) return true
        if (typeof detailPrefixCombo !== "undefined" && detailPrefixCombo.popup.visible) return true
        if (typeof hudCombo !== "undefined" && hudCombo.popup.visible) return true
        return false
    }

    function cycleTab(delta, focusTabContent) {
        if (!tabList || tabList.length === 0) return
        saveAllChanges()
        let curPos = 0
        for (let i = 0; i < tabList.length; i++) {
            if (tabList[i].stackIndex === root.activeTab) {
                curPos = i
                break
            }
        }
        let nextPos = (curPos + delta + tabList.length) % tabList.length
        root.activeTab = tabList[nextPos].stackIndex
        const shouldFocusContent = (focusTabContent !== false)
        if (shouldFocusContent && !primaryActionBtn.activeFocus && !actionsDropdownBtn.activeFocus && !backBtn.activeFocus && !tabsBar.activeFocus) {
            Qt.callLater(() => {
                let grid = getFocusGrid()
                if (grid.length > 3 && grid[3].length > 0 && grid[3][0]) {
                    grid[3][0].forceActiveFocus()
                    scrollToControl(grid[3][0])
                }
            })
        }
    }

    function getFocusGrid() {
        let rows = [
            [backBtn],
            [primaryActionBtn, actionsDropdownBtn],
            [tabsBar]
        ]
        if (root.activeTab === 0) {
            rows.push([titleField, argsField])
            rows.push([exePathField, exeBrowseBtn])
            rows.push([workDirField, workDirBrowseBtn])
            if (!root.isNative) {
                rows.push([detailRunnerCombo, detailPrefixCombo])
            } else {
                rows.push([nativeEnvWrap])
            }
        } else if (root.activeTab === 1 && !root.isNative) {
            rows.push([dxvkToggle])
            rows.push([vkd3dToggle])
            rows.push(hudToggle.checked ? [hudCombo, hudToggle] : [hudToggle])
            rows.push([esyncToggle])
            rows.push([fsyncToggle])
            rows.push(vdesktopCheck.checked ? [vdesktopResField, vdesktopCheck] : [vdesktopCheck])
            rows.push([dllOverridesWrap, envVarsWrap])
        } else if (root.activeTab === 2) {
            rows.push([mangohudToggle])
            rows.push([gamemodeToggle])
            rows.push([affinityField])
            rows.push([priorityField])
            rows.push([detailXboxToggle])
            rows.push([preScriptField, preScriptBrowseBtn])
            rows.push([postScriptField, postScriptBrowseBtn])
        } else if (root.activeTab === 3) {
            rows.push([autoFetchArtBtn])
            rows.push([coverLinkBtn, coverBrowseBtn])
            rows.push([bannerLinkBtn, bannerBrowseBtn])
            rows.push([logoLinkBtn, logoBrowseBtn])
            rows.push([iconLinkBtn, iconBrowseBtn])
        } else if (root.activeTab === 4) {
            rows.push([exportLogBtn, clearLogBtn])
            rows.push([logAreaWrap])
        }
        return rows
    }

    function navigateStep(dr, dc) {
        let rows = getFocusGrid()
        let pos = findFocusCoords(rows)
        if (pos.r < 0) {
            primaryActionBtn.forceActiveFocus()
            scrollToControl(primaryActionBtn)
            return true
        }
        if (dr !== 0) {
            let nr = pos.r + dr
            if (nr >= 0 && nr < rows.length) {
                let nextRow = rows[nr]
                let target = nextRow[Math.min(pos.c, nextRow.length - 1)]
                if (target) {
                    target.forceActiveFocus()
                    scrollToControl(target)
                    return true
                }
            }
            return false
        }
        if (dc !== 0) {
            if (rows[pos.r][pos.c] === tabsBar) {
                root.cycleTab(dc, false)
                return true
            }
            let nc = pos.c + dc
            if (nc >= 0 && nc < rows[pos.r].length) {
                let target = rows[pos.r][nc]
                if (target) {
                    target.forceActiveFocus()
                    scrollToControl(target)
                    return true
                }
            }
        }
        return false
    }

    function findFocusCoords(rows) {
        const fi = root.Window.activeFocusItem
        if (!fi) return { r: -1, c: 0 }
        for (let r = 0; r < rows.length; r++) {
            for (let c = 0; c < rows[r].length; c++) {
                let it = rows[r][c]
                if (it && (it.activeFocus || fi === it)) {
                    return { r: r, c: c }
                }
            }
        }
        return { r: -1, c: 0 }
    }

    function scrollToControl(item) {
        if (!item || !detailScroll || !detailScroll.contentItem) return
        if (item === backBtn || item === primaryActionBtn || item === actionsDropdownBtn) {
            detailScrollAnim.to = 0
            detailScrollAnim.restart()
            return
        }
        let flick = detailScroll.contentItem
        if (!flick || flick.contentY === undefined || !detailCol) return
        let p = item.mapToItem(detailCol, 0, 0)
        let maxY = Math.max(0, flick.contentHeight - detailScroll.height)
        let viewTop = flick.contentY
        let viewBottom = flick.contentY + detailScroll.height - 68
        let desiredY = flick.contentY
        if (p.y - 24 < viewTop) {
            desiredY = Math.max(0, p.y - 24)
        } else if (p.y + item.height + 24 > viewBottom) {
            desiredY = Math.min(maxY, p.y + item.height + 24 - (detailScroll.height - 68))
        }
        if (Math.abs(desiredY - flick.contentY) > 1) {
            detailScrollAnim.to = desiredY
            detailScrollAnim.restart()
        }
    }

    Connections {
        target: uiController ? uiController.controllerManager : null
        function onTabLeftRequested() {
            if (root.StackView.status === StackView.Active && !root.isAnyPopupOpen()) {
                uiController.setKeyboardNavActive(true)
                root.cycleTab(-1)
            }
        }
        function onTabRightRequested() {
            if (root.StackView.status === StackView.Active && !root.isAnyPopupOpen()) {
                uiController.setKeyboardNavActive(true)
                root.cycleTab(1)
            }
        }
    }

    Keys.onEscapePressed: (event) => {
        if (actionsPopup.visible) {
            event.accepted = true
            actionsPopup.close()
            return
        }
        event.accepted = true
        root.saveAllChanges()
        root.backRequested()
    }

    function handleDetailKeyPress(event) {
        if (root.isAnyPopupOpen()) {
            if (actionsPopup.visible && event.key === Qt.Key_Backspace) {
                event.accepted = true
                actionsPopup.close()
            }
            return
        }
        if (root.isTextInputActive()) return

        if (event.key === Qt.Key_Backspace) {
            event.accepted = true
            root.saveAllChanges()
            root.backRequested()
            return
        }
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_BracketLeft) {
            event.accepted = true
            root.cycleTab(-1, true)
            return
        }
        if (event.key === Qt.Key_PageDown || event.key === Qt.Key_BracketRight) {
            event.accepted = true
            root.cycleTab(1, true)
            return
        }

        if (event.key === Qt.Key_Down) {
            event.accepted = true
            root.navigateStep(1, 0)
        } else if (event.key === Qt.Key_Up) {
            event.accepted = true
            root.navigateStep(-1, 0)
        } else if (event.key === Qt.Key_Left) {
            event.accepted = true
            root.navigateStep(0, -1)
        } else if (event.key === Qt.Key_Right) {
            event.accepted = true
            root.navigateStep(0, 1)
        }
    }

    Keys.onPressed: (event) => root.handleDetailKeyPress(event)

    function reloadGame() {
        if (gameId.length > 0) {
            gameData = uiController.gameManager.getGameMap(gameId)
            uiController.diagnosticsManager.selectedLogGameId = gameId
            if (typeof detailXboxToggle !== "undefined" && detailXboxToggle) {
                detailXboxToggle.checked = (root.gameData.xboxEmulationState === 1)
            }
        }
    }

    Component.onCompleted: {
        reloadGame()
        Qt.callLater(() => primaryActionBtn.forceActiveFocus())
    }
    Component.onDestruction: saveAllChanges()

    StackView.onStatusChanged: {
        if (StackView.status === StackView.Active) {
            Qt.callLater(() => primaryActionBtn.forceActiveFocus())
        }
    }

    Connections {
        target: uiController.gameManager
        function onGamesChanged() {
            if (!root.isSaving) {
                root.reloadGame()
            } else if (root.gameId.length > 0) {
                root.gameData = uiController.gameManager.getGameMap(root.gameId)
            }
        }
    }
    Connections {
        target: uiController.launchPipeline
        function onRunningGamesChanged() { root.reloadGame() }
    }

    background: Rectangle { color: appSettings.bgColor }

    function saveAllChanges() {
        if (!root.gameId || root.gameId.length === 0) return

        let envMap = {}
        let activeEnvArea = root.isNative
            ? ((typeof nativeEnvVarsArea !== "undefined" && nativeEnvVarsArea) ? nativeEnvVarsArea : null)
            : ((typeof envVarsArea !== "undefined" && envVarsArea) ? envVarsArea : null)

        if (activeEnvArea) {
            let lines = activeEnvArea.text.split("\n")
            for (let i = 0; i < lines.length; ++i) {
                let l = lines[i].trim()
                let eq = l.indexOf("=")
                if (eq > 0) {
                    envMap[l.substring(0, eq).trim()] = l.substring(eq + 1).trim()
                }
            }
        } else if (root.gameData.environmentVariables) {
            envMap = root.gameData.environmentVariables
        }

        let dllMap = {}
        if (!root.isNative) {
            if (typeof dllOverridesArea !== "undefined" && dllOverridesArea) {
                let dlines = dllOverridesArea.text.split("\n")
                for (let j = 0; j < dlines.length; ++j) {
                    let dl = dlines[j].trim()
                    let deq = dl.indexOf("=")
                    if (deq > 0) {
                        dllMap[dl.substring(0, deq).trim()] = dl.substring(deq + 1).trim()
                    }
                }
            } else if (root.gameData.dllOverrides) {
                dllMap = root.gameData.dllOverrides
            }
        }

        let runnerIdVal = ""
        let runners = uiController.runnerManager.installedRunners
        if (!root.isNative && typeof detailRunnerCombo !== "undefined" && detailRunnerCombo && detailRunnerCombo.selectedIndex > 0 && detailRunnerCombo.selectedIndex - 1 < runners.length) {
            runnerIdVal = runners[detailRunnerCombo.selectedIndex - 1].id
        } else if (!root.isNative && typeof detailRunnerCombo !== "undefined" && detailRunnerCombo && detailRunnerCombo.selectedIndex === 0) {
            runnerIdVal = ""
        } else {
            runnerIdVal = root.isNative ? "" : (root.gameData.runnerId || "")
        }

        let pfxIdVal = root.isNative ? "" : (root.gameData.prefixId || "default-prefix")
        let pfxs = uiController.prefixManager.prefixes
        if (!root.isNative && typeof detailPrefixCombo !== "undefined" && detailPrefixCombo && detailPrefixCombo.selectedIndex >= 0 && detailPrefixCombo.selectedIndex < pfxs.length) {
            pfxIdVal = pfxs[detailPrefixCombo.selectedIndex].id
        }

        let xboxEmuVal = (typeof detailXboxToggle !== "undefined" && detailXboxToggle)
            ? (detailXboxToggle.checked ? 1 : 0)
            : ((root.gameData.xboxEmulationState === 1) ? 1 : 0)

        let dxvkVal = (!root.isNative && typeof dxvkToggle !== "undefined" && dxvkToggle)
            ? (dxvkToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.dxvkState !== undefined ? root.gameData.dxvkState : -1))

        let vkd3dVal = (!root.isNative && typeof vkd3dToggle !== "undefined" && vkd3dToggle)
            ? (vkd3dToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.vkd3dState !== undefined ? root.gameData.vkd3dState : -1))

        let esyncVal = (!root.isNative && typeof esyncToggle !== "undefined" && esyncToggle)
            ? (esyncToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.esyncState !== undefined ? root.gameData.esyncState : -1))

        let fsyncVal = (!root.isNative && typeof fsyncToggle !== "undefined" && fsyncToggle)
            ? (fsyncToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.fsyncState !== undefined ? root.gameData.fsyncState : -1))

        let mangohudVal = (typeof mangohudToggle !== "undefined" && mangohudToggle)
            ? (mangohudToggle.checked ? 1 : 0)
            : (root.gameData.mangohudState !== undefined ? root.gameData.mangohudState : -1)

        let gamemodeVal = (typeof gamemodeToggle !== "undefined" && gamemodeToggle)
            ? (gamemodeToggle.checked ? 1 : 0)
            : (root.gameData.gamemodeState !== undefined ? root.gameData.gamemodeState : -1)

        let hudVal = ""
        if (!root.isNative && typeof hudToggle !== "undefined" && hudToggle && typeof hudCombo !== "undefined" && hudCombo) {
            if (!hudToggle.checked) {
                hudVal = ""
            } else {
                let opts = ["fps", "devinfo,fps,frametimes", "full"]
                let idx = hudCombo.selectedIndex
                if (idx < 0 || idx >= opts.length) idx = 0
                hudVal = opts[idx]
            }
        } else {
            hudVal = root.isNative ? "" : (root.gameData.dxvkHud || "")
        }

        root.isSaving = true
        uiController.gameManager.updateGameDetails(root.gameId, {
            title: (typeof titleField !== "undefined" && titleField && titleField.text.trim().length > 0) ? titleField.text.trim() : (root.gameData.title || ""),
            executablePath: (typeof exePathField !== "undefined" && exePathField && exePathField.text.trim().length > 0) ? exePathField.text.trim() : (root.gameData.executablePath || ""),
            workingDirectory: (typeof workDirField !== "undefined" && workDirField) ? workDirField.text.trim() : (root.gameData.workingDirectory || ""),
            launchArguments: (typeof argsField !== "undefined" && argsField) ? argsField.text.trim() : (root.gameData.launchArguments || ""),
            runnerId: runnerIdVal,
            prefixId: pfxIdVal,
            dxvkState: dxvkVal,
            vkd3dState: vkd3dVal,
            esyncState: esyncVal,
            fsyncState: fsyncVal,
            dxvkHud: hudVal,
            virtualDesktop: (!root.isNative && typeof vdesktopCheck !== "undefined" && vdesktopCheck) ? vdesktopCheck.checked : false,
            virtualDesktopResolution: (!root.isNative && typeof vdesktopResField !== "undefined" && vdesktopResField && vdesktopResField.text.length > 0) ? vdesktopResField.text : (root.gameData.virtualDesktopResolution || "1920x1080"),
            mangohudState: mangohudVal,
            gamemodeState: gamemodeVal,
            cpuAffinity: (typeof affinityField !== "undefined" && affinityField) ? affinityField.text.trim() : (root.gameData.cpuAffinity || ""),
            processPriority: (typeof priorityField !== "undefined" && priorityField) ? (Number(priorityField.text) || 0) : (root.gameData.processPriority || 0),
            xboxEmulationState: xboxEmuVal,
            preLaunchScript: (typeof preScriptField !== "undefined" && preScriptField) ? preScriptField.text.trim() : (root.gameData.preLaunchScript || ""),
            postExitScript: (typeof postScriptField !== "undefined" && postScriptField) ? postScriptField.text.trim() : (root.gameData.postExitScript || ""),
            environmentVariables: envMap,
            dllOverrides: dllMap
        })
        root.isSaving = false
    }

    NumberAnimation {
        id: detailScrollAnim
        target: detailScroll.contentItem
        property: "contentY"
        duration: 180
        easing.type: Easing.OutCubic
    }

    ScrollView {
        id: detailScroll
        anchors.fill: parent
        contentWidth: availableWidth
        contentHeight: detailCol.implicitHeight
        clip: true

        ColumnLayout {
            id: detailCol
            width: parent.width
            spacing: 0
            Keys.onPressed: (event) => root.handleDetailKeyPress(event)

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

                // Game Summary Column (Anchored to bottom-left of hero banner/poster)
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 36
                    anchors.rightMargin: 36
                    anchors.bottomMargin: 20
                    spacing: 12

                    // Transparent Game Logo / Icon (Scales dynamically with window size)
                    Item {
                        id: gameLogoCard
                        readonly property bool hasFullLogo: Boolean(root.gameData.logoPath && root.gameData.logoPath.length > 0)
                        readonly property string logoSource: hasFullLogo
                            ? root.gameData.logoPath
                            : (root.gameData.iconPath || "")
                        readonly property bool hasVisual: Boolean(logoSource && logoSource.length > 0)
                        visible: hasVisual && gameLogoImg.status !== Image.Error

                        // Responsive height scaling directly with window width and hero banner height:
                        // Small window  (width ~900-1100):  ~75-100px
                        // Medium window (width ~1200-1500): ~115-155px
                        // Large/maximized window (width ~1600-1920+): ~170-220px
                        // 2K/4K/Ultrawide (width > 2000): up to ~250px
                        readonly property real targetHeight: {
                            if (!visible) return 0
                            let byWidth = root.width * 0.11
                            let byBanner = heroBannerItem.height * 0.38
                            let responsiveH = Math.min(byWidth, byBanner)
                            return Math.max(70, Math.min(250, responsiveH))
                        }

                        implicitHeight: visible ? targetHeight : 0
                        Layout.preferredHeight: implicitHeight

                        // Responsive width preserving aspect ratio within window bounds
                        readonly property real calculatedWidth: {
                            if (!visible) return 0
                            if (gameLogoImg.status === Image.Ready && gameLogoImg.implicitHeight > 0) {
                                let aspect = gameLogoImg.implicitWidth / gameLogoImg.implicitHeight
                                let w = targetHeight * aspect
                                let maxAllowed = Math.min(Math.max(220, root.width * 0.48), 620)
                                return Math.min(maxAllowed, Math.max(60, w))
                            }
                            return Math.min(Math.round(root.width * 0.35), Math.round(targetHeight * 1.8))
                        }

                        implicitWidth: calculatedWidth
                        Layout.preferredWidth: calculatedWidth
                        Layout.alignment: Qt.AlignLeft

                        Image {
                            id: gameLogoImg
                            anchors.fill: parent
                            source: gameLogoCard.logoSource
                            fillMode: Image.PreserveAspectFit
                            horizontalAlignment: Image.AlignLeft
                            verticalAlignment: Image.AlignBottom
                            asynchronous: true
                            smooth: true
                            mipmap: true
                        }
                    }

                    // Title
                    Label {
                        id: gameTitleLbl
                        text: root.gameData.title || "Game Title"
                        color: appSettings.textColor
                        font.pixelSize: Math.max(26, Math.min(36, Math.round(root.width * 0.024)))
                        font.weight: Font.Bold
                        font.letterSpacing: -0.6
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: appSettings.showGameName || !gameLogoCard.hasFullLogo
                    }

                    // Bottom Row: Action (Play Now) + Metadata (Proton Tag, Playtime, Last Played)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        // ── Material 3 / Split Button Row ──────────────
                        Item {
                            id: splitButtonContainer
                            readonly property var heroActionItems: {
                                let items = []
                                if (!root.isNative) {
                                    items.push({
                                        name: "Winetricks",
                                        icon: "qrc:/tsuki_app/icons/actions/wrench.svg",
                                        destructive: false,
                                        action: function() {
                                            root.winetricksRequested(root.gameData.prefixId || "default-prefix", root.gameData.title || "")
                                        }
                                    })
                                }
                                items.push({
                                    name: "Shortcut",
                                    icon: "qrc:/tsuki_app/icons/actions/shortcut.svg",
                                    destructive: false,
                                    action: function() {
                                        uiController.gameManager.createDesktopShortcut(root.gameId, true)
                                    }
                                })
                                items.push({
                                    name: "Game Folder",
                                    icon: "qrc:/tsuki_app/icons/actions/folder.svg",
                                    destructive: false,
                                    action: function() {
                                        uiController.gameManager.openGameDirectory(root.gameId)
                                    }
                                })
                                if (!root.isNative && Boolean(root.gameData.prefixId && root.gameData.prefixId.length > 0)) {
                                    items.push({
                                        name: "Prefix Folder",
                                        icon: "qrc:/tsuki_app/icons/actions/folder.svg",
                                        destructive: false,
                                        action: function() {
                                            if (root.gameData.prefixId) {
                                                uiController.prefixManager.openPrefixInFileManager(root.gameData.prefixId)
                                            }
                                        }
                                    })
                                }
                                items.push({
                                    name: "Remove",
                                    icon: "qrc:/tsuki_app/icons/actions/trash.svg",
                                    destructive: true,
                                    action: function() {
                                        removeGameDialog.openDialog(root.gameId, root.gameData.title, root.gameData.prefixId)
                                    }
                                })
                                return items
                            }

                            implicitWidth: splitButtonRow.implicitWidth
                            implicitHeight: 44
                            Layout.preferredWidth: implicitWidth
                            Layout.preferredHeight: 44

                            Row {
                                id: splitButtonRow
                                spacing: 6
                                anchors.left: parent.left
                                anchors.top: parent.top
                                height: 44

                                // 1. Leading Button: M3 Filled Play/Stop Action
                                Button {
                                    id: primaryActionBtn
                                    text: root.gameData.isRunning ? "Stop Game" : "Play Now"
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    implicitHeight: 44
                                    implicitWidth: playContentRow ? Math.max(136, playContentRow.implicitWidth + leftPadding + rightPadding) : 140
                                    width: implicitWidth
                                    padding: 0
                                    leftPadding: 20
                                    rightPadding: 20
                                    focus: true
                                    activeFocusOnTab: false
                                    z: primaryActionBtn.activeFocus ? 2 : 1

                                    Behavior on implicitWidth {
                                        SpringAnimation {
                                            spring: 3.5
                                            damping: 0.28
                                            epsilon: 0.25
                                        }
                                    }

                                    readonly property bool isBtnHovered: (!uiController || !uiController.isKeyboardNavActive) && primaryActionBtn.hovered
                                    readonly property color effectiveColor: root.gameData.isRunning ? "#ef4444" : appSettings.accentColor
                                    readonly property color onEffectiveColor: root.gameData.isRunning ? "#ffffff" : (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")

                                    scale: down ? 0.96 : (isBtnHovered ? 1.01 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                                    // Leading Button Background (Split Pill Left)
                                    background: Item {
                                        implicitHeight: 44
                                        implicitWidth: primaryActionBtn.width

                                        Rectangle {
                                            id: playBg
                                            anchors.fill: parent
                                            topLeftRadius: 22
                                            bottomLeftRadius: 22
                                            topRightRadius: 4
                                            bottomRightRadius: 4
                                            clip: true

                                            color: primaryActionBtn.down
                                                ? Qt.darker(primaryActionBtn.effectiveColor, 1.12)
                                                : (primaryActionBtn.isBtnHovered ? Qt.lighter(primaryActionBtn.effectiveColor, 1.08) : primaryActionBtn.effectiveColor)
                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            // M3 Ripple effect inside clipped playBg
                                            Rectangle {
                                                id: playRipple
                                                property real centerX: 0
                                                property real centerY: 0
                                                width: radius * 2
                                                height: radius * 2
                                                radius: 0
                                                x: centerX - radius
                                                y: centerY - radius
                                                color: primaryActionBtn.onEffectiveColor
                                                opacity: 0

                                                NumberAnimation {
                                                    id: playRippleAnim
                                                    target: playRipple
                                                    property: "radius"
                                                    duration: 480
                                                    easing.type: Easing.OutCubic
                                                }
                                                NumberAnimation {
                                                    id: playRippleFade
                                                    target: playRipple
                                                    property: "opacity"
                                                    to: 0
                                                    duration: 550
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }

                                        // Focus outline ring
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: -3
                                            topLeftRadius: 25
                                            bottomLeftRadius: 25
                                            topRightRadius: 7
                                            bottomRightRadius: 7
                                            color: "transparent"
                                            border.color: primaryActionBtn.effectiveColor
                                            border.width: 2
                                            visible: Boolean(uiController && uiController.isKeyboardNavActive && primaryActionBtn.activeFocus)
                                            opacity: visible ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                        }
                                    }

                                    contentItem: Item {
                                        clip: true

                                        Row {
                                            id: playContentRow
                                            anchors.centerIn: parent
                                            spacing: 8

                                            YIcon {
                                                size: 18
                                                source: root.gameData.isRunning ? "qrc:/tsuki_app/icons/actions/stop.svg" : "qrc:/tsuki_app/icons/actions/play.svg"
                                                color: primaryActionBtn.onEffectiveColor
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Label {
                                                id: playLabel
                                                text: primaryActionBtn.text
                                                color: primaryActionBtn.onEffectiveColor
                                                font: primaryActionBtn.font
                                                renderType: Text.QtRendering
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    Keys.onRightPressed: (event) => {
                                        if (actionsDropdownBtn.visible && actionsDropdownBtn.enabled) {
                                            event.accepted = true
                                            actionsDropdownBtn.forceActiveFocus()
                                        }
                                    }
                                    Keys.onReturnPressed: (event) => {
                                        event.accepted = true
                                        primaryActionBtn.clicked()
                                    }
                                    Keys.onEnterPressed: (event) => {
                                        event.accepted = true
                                        primaryActionBtn.clicked()
                                    }
                                    Keys.onSpacePressed: (event) => {
                                        event.accepted = true
                                        primaryActionBtn.clicked()
                                    }

                                    onClicked: {
                                        if (root.gameData.isRunning) {
                                            uiController.launchPipeline.stopGame(root.gameId)
                                        } else {
                                            root.saveAllChanges()
                                            uiController.launchPipeline.launchGame(root.gameId)
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onPressed: (mouse) => {
                                            playRipple.centerX = mouse.x
                                            playRipple.centerY = mouse.y
                                            playRipple.opacity = 0.22
                                            playRippleAnim.from = 0
                                            playRippleAnim.to = Math.max(primaryActionBtn.width, primaryActionBtn.height) * 1.5
                                            playRippleAnim.restart()
                                            primaryActionBtn.down = true
                                        }
                                        onReleased: {
                                            primaryActionBtn.down = false
                                            playRippleFade.restart()
                                            primaryActionBtn.clicked()
                                        }
                                        onCanceled: {
                                            primaryActionBtn.down = false
                                            playRippleFade.restart()
                                        }
                                    }
                                }

                                // 2. Trailing Button: M3 Morphing Chevron Dropdown Anchor
                                Button {
                                    id: actionsDropdownBtn
                                    flat: true
                                    implicitHeight: 44
                                    implicitWidth: 44
                                    width: 44
                                    height: 44
                                    padding: 0
                                    focus: true
                                    activeFocusOnTab: false
                                    z: actionsDropdownBtn.activeFocus ? 2 : 1

                                    readonly property bool isBtnHovered: (!uiController || !uiController.isKeyboardNavActive) && actionsDropdownBtn.hovered

                                    scale: down ? 0.94 : (isBtnHovered ? 1.04 : 1.0)
                                    Behavior on scale { SpringAnimation { spring: 3.5; damping: 0.25; epsilon: 0.005 } }

                                    background: Item {
                                        implicitHeight: 44
                                        implicitWidth: 44

                                        Rectangle {
                                            id: actionsBg
                                            anchors.fill: parent

                                            property real innerRadius: actionsPopup.visible ? 22 : 4
                                            Behavior on innerRadius {
                                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                            }

                                            topLeftRadius: innerRadius
                                            bottomLeftRadius: innerRadius
                                            topRightRadius: 22
                                            bottomRightRadius: 22

                                            color: actionsDropdownBtn.down
                                                ? Qt.darker(primaryActionBtn.effectiveColor, 1.12)
                                                : (actionsDropdownBtn.isBtnHovered ? Qt.lighter(primaryActionBtn.effectiveColor, 1.08) : primaryActionBtn.effectiveColor)

                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        // Focus outline ring
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: -3
                                            topLeftRadius: actionsBg.topLeftRadius + 3
                                            bottomLeftRadius: actionsBg.bottomLeftRadius + 3
                                            topRightRadius: 25
                                            bottomRightRadius: 25
                                            color: "transparent"
                                            border.color: primaryActionBtn.effectiveColor
                                            border.width: 2
                                            visible: Boolean(uiController && uiController.isKeyboardNavActive && actionsDropdownBtn.activeFocus)
                                            opacity: visible ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                        }
                                    }

                                    contentItem: Item {
                                        anchors.fill: parent

                                        YIcon {
                                            id: chevronIcon
                                            size: 18
                                            source: "qrc:/tsuki_app/icons/actions/chevron_down.svg"
                                            color: primaryActionBtn.onEffectiveColor
                                            anchors.centerIn: parent
                                            rotation: actionsPopup.visible ? 180 : 0
                                            Behavior on rotation {
                                                NumberAnimation {
                                                    duration: 220
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }

                                    onClicked: {
                                        if (actionsPopup.visible) {
                                            actionsPopup.close()
                                        } else {
                                            actionsPopup.focusedActionIndex = 0
                                            actionsPopup.open()
                                        }
                                    }

                                    Keys.onLeftPressed: (event) => {
                                        if (actionsPopup.visible) {
                                            event.accepted = true
                                            actionsPopup.close()
                                        } else {
                                            event.accepted = true
                                            primaryActionBtn.forceActiveFocus()
                                        }
                                    }
                                    Keys.onDownPressed: (event) => {
                                        if (actionsPopup.visible) {
                                            event.accepted = true
                                            actionsPopup.handleDown()
                                        }
                                    }
                                    Keys.onUpPressed: (event) => {
                                        if (actionsPopup.visible) {
                                            event.accepted = true
                                            actionsPopup.handleUp()
                                        }
                                    }
                                    Keys.onReturnPressed: (event) => {
                                        event.accepted = true
                                        if (actionsPopup.visible) {
                                            actionsPopup.handleSelect()
                                        } else {
                                            actionsPopup.focusedActionIndex = 0
                                            actionsPopup.open()
                                        }
                                    }
                                    Keys.onEnterPressed: (event) => {
                                        event.accepted = true
                                        if (actionsPopup.visible) {
                                            actionsPopup.handleSelect()
                                        } else {
                                            actionsPopup.focusedActionIndex = 0
                                            actionsPopup.open()
                                        }
                                    }
                                    Keys.onSpacePressed: (event) => {
                                        event.accepted = true
                                        if (actionsPopup.visible) {
                                            actionsPopup.handleSelect()
                                        } else {
                                            actionsPopup.focusedActionIndex = 0
                                            actionsPopup.open()
                                        }
                                    }
                                    Keys.onEscapePressed: (event) => {
                                        if (actionsPopup.visible) {
                                            event.accepted = true
                                            actionsPopup.close()
                                        }
                                    }

                                    HoverHandler {
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }

                            // ── Material 3 Elevated Actions Menu ───────────────
                            Popup {
                                id: actionsPopup
                                parent: splitButtonContainer
                                readonly property real fullContentHeight: Math.min(260, actionsContentCol.implicitHeight + 12)
                                readonly property bool opensUpward: {
                                    let win = root.Window.window
                                    if (!win) return false
                                    let p = splitButtonContainer.mapToItem(null, 0, splitButtonContainer.height)
                                    return (p.y + fullContentHeight + 16 > win.height) && (p.y > win.height / 2)
                                }
                                y: opensUpward ? (-height - 6) : (splitButtonContainer.height + 6)
                                x: 0
                                width: Math.max(splitButtonContainer.implicitWidth, 210)
                                padding: 6
                                dim: false
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

                                property int focusedActionIndex: 0
                                onAboutToShow: {
                                    focusedActionIndex = 0
                                }

                                function handleDown() {
                                    if (splitButtonContainer.heroActionItems && splitButtonContainer.heroActionItems.length > 0) {
                                        focusedActionIndex = (focusedActionIndex + 1) % splitButtonContainer.heroActionItems.length
                                    }
                                }
                                function handleUp() {
                                    if (splitButtonContainer.heroActionItems && splitButtonContainer.heroActionItems.length > 0) {
                                        focusedActionIndex = (focusedActionIndex - 1 + splitButtonContainer.heroActionItems.length) % splitButtonContainer.heroActionItems.length
                                    }
                                }
                                function handleSelect() {
                                    if (splitButtonContainer.heroActionItems && focusedActionIndex >= 0 && focusedActionIndex < splitButtonContainer.heroActionItems.length) {
                                        let act = splitButtonContainer.heroActionItems[focusedActionIndex]
                                        close()
                                        if (act && act.action) act.action()
                                    }
                                }

                                property real unfoldProgress: 0.0

                                enter: Transition {
                                    ParallelAnimation {
                                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                                        NumberAnimation { property: "unfoldProgress"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                                    }
                                }
                                exit: Transition {
                                    ParallelAnimation {
                                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 140; easing.type: Easing.InCubic }
                                        NumberAnimation { property: "unfoldProgress"; from: 1.0; to: 0.0; duration: 160; easing.type: Easing.InCubic }
                                    }
                                }

                                implicitHeight: fullContentHeight * unfoldProgress
                                height: implicitHeight

                                background: Rectangle {
                                    id: popupCardBg
                                    color: appSettings.surfaceColor
                                    border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
                                    border.width: 1
                                    radius: 14

                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.45 : 0.18)
                                        shadowBlur: 0.60
                                        shadowVerticalOffset: 4
                                    }
                                }

                                contentItem: Item {
                                    clip: true

                                    Flickable {
                                        id: flick
                                        anchors.fill: parent
                                        contentHeight: actionsContentCol.implicitHeight
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        Column {
                                            id: actionsContentCol
                                            width: flick.width
                                            spacing: 2

                                            Repeater {
                                                model: splitButtonContainer.heroActionItems
                                                delegate: Column {
                                                    id: aCol
                                                    width: actionsContentCol.width
                                                    spacing: 2
                                                    required property int index
                                                    required property var modelData

                                                    // Divider before destructive action (Remove)
                                                    Rectangle {
                                                        visible: Boolean(aCol.modelData.destructive)
                                                        width: parent.width - 16
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        height: 1
                                                        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                                                    }

                                                    Item {
                                                        id: aRow
                                                        width: parent.width
                                                        height: 38

                                                        readonly property bool isFocusedAction: actionsPopup.focusedActionIndex === aCol.index
                                                        readonly property bool isHovered: aRowMA.containsMouse || (Boolean(uiController && uiController.isKeyboardNavActive) && isFocusedAction)
                                                        readonly property bool isDestructive: Boolean(aCol.modelData.destructive)

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: 10
                                                            color: {
                                                                if (aRow.isHovered) {
                                                                    if (aRow.isDestructive) {
                                                                        return appSettings.isEffectiveDark ? Qt.rgba(0.93, 0.27, 0.27, 0.18) : Qt.rgba(0.93, 0.27, 0.27, 0.12)
                                                                    }
                                                                    return appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                                                                }
                                                                return "transparent"
                                                            }
                                                            border.color: (Boolean(uiController && uiController.isKeyboardNavActive) && aRow.isFocusedAction)
                                                                ? (aRow.isDestructive ? "#ef4444" : appSettings.accentColor)
                                                                : "transparent"
                                                            border.width: (Boolean(uiController && uiController.isKeyboardNavActive) && aRow.isFocusedAction) ? 1.5 : 0

                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                        }

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 12
                                                            anchors.rightMargin: 12
                                                            spacing: 10

                                                            YIcon {
                                                                size: 16
                                                                source: aCol.modelData.icon || ""
                                                                color: aRow.isDestructive
                                                                    ? "#ef4444"
                                                                    : (aRow.isHovered ? appSettings.accentColor : appSettings.textSecColor)
                                                                Layout.alignment: Qt.AlignVCenter
                                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                            }

                                                            Label {
                                                                Layout.fillWidth: true
                                                                verticalAlignment: Text.AlignVCenter
                                                                text: aCol.modelData.name || ""
                                                                color: aRow.isDestructive ? "#ef4444" : appSettings.textColor
                                                                font.pixelSize: 13
                                                                font.weight: aRow.isHovered ? Font.Medium : Font.Normal
                                                                renderType: Text.QtRendering
                                                                elide: Text.ElideRight
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: aRowMA
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                actionsPopup.close()
                                                                if (aCol.modelData.action) aCol.modelData.action()
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

                        // Metadata Chips Row (Proton Tag, Playtime, Last Played)
                        RowLayout {
                            id: metadataChipsRow
                            spacing: 10
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                id: rTagRect
                                radius: 6
                                height: 24
                                implicitHeight: 24
                                implicitWidth: rTagLbl.implicitWidth + 20
                                Layout.preferredWidth: implicitWidth
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignVCenter
                                readonly property color effectiveTagColor: root.gameData.isRunning
                                    ? "#22c55e"
                                    : (root.isNative ? appSettings.tagColorLinux : appSettings.accentColor)
                                color: Qt.rgba(effectiveTagColor.r, effectiveTagColor.g, effectiveTagColor.b, 0.2)
                                border.color: effectiveTagColor
                                border.width: 1

                                Label {
                                    id: rTagLbl
                                    anchors.centerIn: parent
                                    text: root.gameData.isRunning ? "RUNNING" : (root.gameData.runnerTag || (root.isNative ? "LINUX" : "WINE"))
                                    color: rTagRect.effectiveTagColor
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    renderType: Text.QtRendering
                                }
                            }

                            Label {
                                id: playtimeLbl
                                text: "Playtime: " + (root.gameData.playtimeFormatted || "Never played") + "  •  Last Played: " + (root.gameData.lastPlayedFormatted || "Never")
                                color: appSettings.textSecColor
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // ── Material 3 Primary Tabs Bar ─────────────────────────────────
            Item {
                id: tabsBar
                focus: true
                activeFocusOnTab: false
                readonly property bool isBarFocused: tabsBar.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
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
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    spacing: 8

                    Repeater {
                        id: tabRepeater
                        model: root.tabList

                        Item {
                            id: tabItem
                            required property int index
                            required property var modelData
                            readonly property bool isSelected: root.activeTab === tabItem.modelData.stackIndex
                            height: parent.height
                            width: tabItemLbl.implicitWidth + 32

                            Rectangle {
                                anchors.fill: parent
                                anchors.bottomMargin: 4
                                anchors.topMargin: 2
                                radius: 8
                                color: (tabsBar.isBarFocused && tabItem.isSelected)
                                    ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.14)
                                    : (tabItemMA.containsMouse
                                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
                                        : "transparent")
                                border.color: (tabsBar.isBarFocused && tabItem.isSelected) ? appSettings.accentColor : "transparent"
                                border.width: (tabsBar.isBarFocused && tabItem.isSelected) ? 1.5 : 0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                            }

                            Label {
                                id: tabItemLbl
                                anchors.centerIn: parent
                                text: tabItem.modelData.label
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
                                onClicked: {
                                    root.saveAllChanges()
                                    root.activeTab = tabItem.modelData.stackIndex
                                }
                            }
                        }
                    }
                }

                // Right-aligned keyboard/gamepad tab switch prompts with smooth fade (no horizontal shift of tabs)
                RowLayout {
                    readonly property bool showPrompts: Boolean(uiController && uiController.isKeyboardNavActive)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    opacity: showPrompts ? 0.9 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    GamepadPrompt {
                        iconSource: (uiController && uiController.controllerManager) ? uiController.controllerManager.tabLeftIconSource : ""
                        secondaryIconSource: (uiController && uiController.controllerManager) ? uiController.controllerManager.tabLeftTriggerIconSource : ""
                        keyName: "["
                        iconSize: 18
                        pixelSize: 12
                        iconColor: tabsBar.isBarFocused ? appSettings.accentColor : appSettings.textSecColor
                    }

                    GamepadPrompt {
                        iconSource: (uiController && uiController.controllerManager) ? uiController.controllerManager.tabRightIconSource : ""
                        secondaryIconSource: (uiController && uiController.controllerManager) ? uiController.controllerManager.tabRightTriggerIconSource : ""
                        keyName: "]"
                        suffixText: "Tabs"
                        iconSize: 18
                        pixelSize: 12
                        iconColor: tabsBar.isBarFocused ? appSettings.accentColor : appSettings.textSecColor
                    }
                }

                // Material 3 Active Indicator (3dp height, smooth animation)
                Rectangle {
                    id: tabActiveIndicator
                    height: 3
                    radius: 1.5
                    color: appSettings.accentColor
                    anchors.bottom: parent.bottom

                    property var currentItem: {
                        let _tab = root.activeTab
                        let _nat = root.isNative
                        for (let i = 0; i < tabRepeater.count; i++) {
                            let it = tabRepeater.itemAt(i)
                            if (it && it.modelData && it.modelData.stackIndex === _tab) {
                                return it
                            }
                        }
                        return tabRepeater.count > 0 ? tabRepeater.itemAt(0) : null
                    }
                    x: currentItem ? currentItem.x + 12 : 0
                    width: currentItem ? currentItem.width - 24 : 0

                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            // ── Tab Content Area ─────────────────────────────────────────────
            Item {
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

                implicitHeight: activeTabHeight + 24

                StackLayout {
                    id: tabStack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: tabContentCard.activeTabHeight
                    currentIndex: root.activeTab

                    // TAB 0: General & Paths
                    ColumnLayout {
                        id: tab0General
                        Layout.fillWidth: true
                        width: tabStack.width
                        spacing: 16

                        // Card 1: Executable & Launch Configuration
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: generalCol1.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: generalCol1
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                Label {
                                    text: "EXECUTABLE & LAUNCH CONFIGURATION"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.8
                                }

                                // Row 1: 2 Columns for Title & Custom Launch Arguments
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20

                                    // Left Column: Game Title
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 4

                                        Label { text: "Game Title"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Display name in library and system desktop shortcuts"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                        Item { Layout.preferredHeight: 2 }
                                        M3TextField {
                                            id: titleField
                                            twoStageFocus: true
                                            Layout.fillWidth: true
                                            text: root.gameData.title || ""
                                            showClearButton: true
                                            onCommit: root.saveAllChanges()
                                            onMoveUp: root.navigateStep(-1, 0)
                                            onMoveDown: root.navigateStep(1, 0)
                                        }
                                    }

                                    // Right Column: Custom Launch Arguments
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 4

                                        Label { text: "Custom Launch Arguments"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "CLI parameters passed to the executable upon start"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                        Item { Layout.preferredHeight: 2 }
                                        M3TextField {
                                            id: argsField
                                            twoStageFocus: true
                                            Layout.fillWidth: true
                                            text: root.gameData.launchArguments || ""
                                            placeholderText: "-window -novid %command%"
                                            onCommit: root.saveAllChanges()
                                            onMoveUp: root.navigateStep(-1, 0)
                                            onMoveDown: root.navigateStep(1, 0)
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 2: Executable Path (Full width with Browse button)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label {
                                        text: root.isNative ? "Executable / Script" : "Executable Path (.exe)"
                                        color: appSettings.textColor
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }
                                    Label {
                                        text: root.isNative
                                            ? "Target Linux binary or script to execute directly"
                                            : "Target Windows binary to launch through Wine or Proton"
                                        color: appSettings.textSecColor
                                        font.pixelSize: 12
                                    }
                                    Item { Layout.preferredHeight: 2 }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        M3TextField {
                                            id: exePathField
                                            twoStageFocus: true
                                            Layout.fillWidth: true
                                            text: root.gameData.executablePath || ""
                                            onCommit: root.saveAllChanges()
                                            onMoveUp: root.navigateStep(-1, 0)
                                            onMoveDown: root.navigateStep(1, 0)
                                        }
                                        M3Button {
                                            id: exeBrowseBtn
                                            text: "Browse…"
                                            iconSource: "qrc:/tsuki_app/icons/actions/folder.svg"
                                            buttonType: "tonal"
                                            onClicked: {
                                                let prompt = root.isNative ? "Select Linux Game Executable" : "Select Game Executable"
                                                let filter = root.isNative
                                                    ? "All Files (*);;Executables & Scripts (*.sh *.AppImage *.x86_64 *.x86 *.bin)"
                                                    : "Executable Files (*.exe *.bat *.sh *.bin *.AppImage);;All Files (*)"
                                                let p = uiController.selectFile(prompt, filter, exePathField.text)
                                                if (p && p.length > 0) {
                                                    exePathField.text = p
                                                    root.saveAllChanges()
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 3: Working Directory (Full width with Browse button)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label { text: "Working Directory"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                    Label { text: "Directory where the game process starts and locates game assets"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    Item { Layout.preferredHeight: 2 }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        M3TextField {
                                            id: workDirField
                                            twoStageFocus: true
                                            Layout.fillWidth: true
                                            text: root.gameData.workingDirectory || ""
                                            onCommit: root.saveAllChanges()
                                            onMoveUp: root.navigateStep(-1, 0)
                                            onMoveDown: root.navigateStep(1, 0)
                                        }
                                        M3Button {
                                            id: workDirBrowseBtn
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
                            }
                        }

                        // Card 2 (Windows): Runner & Prefix Environment
                        Rectangle {
                            visible: !root.isNative
                            Layout.fillWidth: true
                            implicitHeight: generalCol2.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: generalCol2
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                Label {
                                    text: "RUNNER & PREFIX ENVIRONMENT"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.8
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20

                                    // Left Column: Runner
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 4

                                        Label { text: "Wine / Proton Runner Override"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Select a custom Wine or Proton build, or inherit global default runner"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                        Item { Layout.preferredHeight: 2 }
                                        StyledCombo {
                                            id: detailRunnerCombo
                                            Layout.fillWidth: true
                                            openUpward: true
                                            upDownNavigatesFocus: true
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
                                            onSelected: root.saveAllChanges()
                                        }
                                    }

                                    // Right Column: Prefix
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 4

                                        Label { text: "Wine Prefix Environment"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Virtual Windows filesystem (C: drive) and registry container"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                        Item { Layout.preferredHeight: 2 }
                                        StyledCombo {
                                            id: detailPrefixCombo
                                            Layout.fillWidth: true
                                            openUpward: true
                                            upDownNavigatesFocus: true
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
                                            onSelected: root.saveAllChanges()
                                        }
                                    }
                                }
                            }
                        }

                        // Card 2 (Native Linux): Environment Variables
                        Rectangle {
                            visible: root.isNative
                            Layout.fillWidth: true
                            implicitHeight: generalNativeEnvCol.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: generalNativeEnvCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 10

                                Label {
                                    text: "ENVIRONMENT VARIABLES"
                                    color: appSettings.tagColorLinux
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.8
                                }

                                Label {
                                    text: "Custom Environment Variables (KEY=VALUE, one per line)"
                                    color: appSettings.textSecColor
                                    font.pixelSize: 12
                                }

                                Rectangle {
                                    id: nativeEnvWrap
                                    focus: true
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 120
                                    radius: 12
                                    color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                                    border.color: ((nativeEnvWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) || nativeEnvVarsArea.activeFocus)
                                        ? appSettings.accentColor
                                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                                    border.width: ((nativeEnvWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) || nativeEnvVarsArea.activeFocus) ? 2 : 1
                                    Keys.onReturnPressed: (event) => { if (!nativeEnvVarsArea.activeFocus) { event.accepted = true; nativeEnvVarsArea.forceActiveFocus() } }
                                    Keys.onEnterPressed: (event) => { if (!nativeEnvVarsArea.activeFocus) { event.accepted = true; nativeEnvVarsArea.forceActiveFocus() } }
                                    Keys.onSpacePressed: (event) => { if (!nativeEnvVarsArea.activeFocus) { event.accepted = true; nativeEnvVarsArea.forceActiveFocus() } }

                                    ScrollView {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        TextArea {
                                            id: nativeEnvVarsArea
                                            color: appSettings.textColor
                                            font.family: "monospace"
                                            font.pixelSize: 12
                                            placeholderText: "SDL_VIDEODRIVER=wayland\n__GL_THREADED_OPTIMIZATIONS=1\nENABLE_VKBASALT=1"
                                            placeholderTextColor: appSettings.textTerColor
                                            text: {
                                                let m = root.gameData.environmentVariables || {}
                                                let out = []
                                                for (let k in m) out.push(k + "=" + m[k])
                                                return out.join("\n")
                                            }
                                            background: null
                                            onActiveFocusChanged: if (!activeFocus) root.saveAllChanges()
                                            Keys.onEscapePressed: (event) => {
                                                event.accepted = true
                                                root.saveAllChanges()
                                                nativeEnvWrap.forceActiveFocus()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // TAB 1: Wine & DXVK
                    ColumnLayout {
                        id: tab1Wine
                        Layout.fillWidth: true
                        width: tabStack.width
                        visible: !root.isNative
                        spacing: 16

                        // Card 1: Direct3D Translators
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: d3dCol.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: d3dCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                Label {
                                    text: "DIRECT3D TRANSLATORS"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.8
                                }

                                // Row 1: DXVK (Toggle)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "DXVK (D3D9/10/11 → Vulkan)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Hardware-accelerated Vulkan translation for DirectX 9, 10, and 11 games"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: dxvkToggle
                                        checked: (root.gameData.dxvkState === 1) ? true : ((root.gameData.dxvkState === 0) ? false : appSettings.dxvkDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 2: VKD3D-Proton (Toggle)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "VKD3D-Proton (D3D12 → Vulkan)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "DirectX 12 translation layer for modern Vulkan-capable drivers"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: vkd3dToggle
                                        checked: (root.gameData.vkd3dState === 1) ? true : ((root.gameData.vkd3dState === 0) ? false : appSettings.vkd3dDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 3: DXVK HUD Statistics
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "DXVK HUD Statistics"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "On-screen real-time statistics overlay (framerate, GPU load, frame times)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    RowLayout {
                                        spacing: 12
                                        StyledCombo {
                                            id: hudCombo
                                            Layout.preferredWidth: 220
                                            openUpward: false
                                            forceDownward: true
                                            upDownNavigatesFocus: true
                                            enabled: hudToggle.checked
                                            opacity: hudToggle.checked ? 1.0 : 0.4
                                            comboModel: ["fps", "devinfo,fps,frametimes", "full"]
                                            selectedIndex: {
                                                let h = root.gameData.dxvkHud || ""
                                                let idx = ["fps", "devinfo,fps,frametimes", "full"].indexOf(h)
                                                return idx >= 0 ? idx : 0
                                            }
                                            onSelected: root.saveAllChanges()
                                        }
                                        Toggle {
                                            id: hudToggle
                                            checked: Boolean(root.gameData.dxvkHud && root.gameData.dxvkHud !== "" && root.gameData.dxvkHud !== "none")
                                            onToggled: root.saveAllChanges()
                                        }
                                    }
                                }
                            }
                        }

                        // Card 2: Kernel Synchronization & Display
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: syncCol.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: syncCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                Label {
                                    text: "KERNEL SYNCHRONIZATION & DISPLAY"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.8
                                }

                                // Row 1: Esync (Toggle)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "Esync (Eventfd Synchronization)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Eliminates wineserver lock contention using Linux eventfd primitives"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: esyncToggle
                                        checked: (root.gameData.esyncState === 1) ? true : ((root.gameData.esyncState === 0) ? false : appSettings.esyncDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 2: Fsync (Toggle)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "Fsync (Futex Synchronization)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Direct kernel futex2 synchronization for Linux 5.16+ kernels"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: fsyncToggle
                                        checked: (root.gameData.fsyncState === 1) ? true : ((root.gameData.fsyncState === 0) ? false : appSettings.fsyncDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 3: Virtual Desktop
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "Virtual Desktop Mode"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Launch game within an emulated X11 desktop window"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    RowLayout {
                                        spacing: 12
                                        M3TextField {
                                            id: vdesktopResField
                                            twoStageFocus: true
                                            implicitWidth: 140
                                            text: root.gameData.virtualDesktopResolution || "1920x1080"
                                            placeholderText: "1920x1080"
                                            enabled: vdesktopCheck.checked
                                            opacity: vdesktopCheck.checked ? 1.0 : 0.4
                                            onCommit: root.saveAllChanges()
                                            onMoveUp: root.navigateStep(-1, 0)
                                            onMoveDown: root.navigateStep(1, 0)
                                        }
                                        Toggle {
                                            id: vdesktopCheck
                                            checked: Boolean(root.gameData.virtualDesktop)
                                            onToggled: root.saveAllChanges()
                                        }
                                    }
                                }
                            }
                        }

                        // Card 3: Overrides & Environment Variables (2 Columns)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: overridesCol.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: overridesCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                Label {
                                    text: "OVERRIDES & ENVIRONMENT VARIABLES"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.8
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20

                                    // Left Column: DLL Overrides
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 6
                                        Label { text: "DLL Overrides (one per line, e.g. dinput8=n,b)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                        Rectangle {
                                            id: dllOverridesWrap
                                            focus: true
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 110
                                            radius: 12
                                            color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                                            border.color: ((dllOverridesWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) || dllOverridesArea.activeFocus)
                                                ? appSettings.accentColor
                                                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                                            border.width: ((dllOverridesWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) || dllOverridesArea.activeFocus) ? 2 : 1
                                            Keys.onReturnPressed: (event) => { if (!dllOverridesArea.activeFocus) { event.accepted = true; dllOverridesArea.forceActiveFocus() } }
                                            Keys.onEnterPressed: (event) => { if (!dllOverridesArea.activeFocus) { event.accepted = true; dllOverridesArea.forceActiveFocus() } }
                                            Keys.onSpacePressed: (event) => { if (!dllOverridesArea.activeFocus) { event.accepted = true; dllOverridesArea.forceActiveFocus() } }

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
                                                    onActiveFocusChanged: if (!activeFocus) root.saveAllChanges()
                                                    Keys.onEscapePressed: (event) => {
                                                        event.accepted = true
                                                        root.saveAllChanges()
                                                        dllOverridesWrap.forceActiveFocus()
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Right Column: Environment Variables
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 6
                                        Label { text: "Environment Variables (KEY=VALUE)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                        Rectangle {
                                            id: envVarsWrap
                                            focus: true
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 110
                                            radius: 12
                                            color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                                            border.color: ((envVarsWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) || envVarsArea.activeFocus)
                                                ? appSettings.accentColor
                                                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                                            border.width: ((envVarsWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) || envVarsArea.activeFocus) ? 2 : 1
                                            Keys.onReturnPressed: (event) => { if (!envVarsArea.activeFocus) { event.accepted = true; envVarsArea.forceActiveFocus() } }
                                            Keys.onEnterPressed: (event) => { if (!envVarsArea.activeFocus) { event.accepted = true; envVarsArea.forceActiveFocus() } }
                                            Keys.onSpacePressed: (event) => { if (!envVarsArea.activeFocus) { event.accepted = true; envVarsArea.forceActiveFocus() } }

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
                                                    onActiveFocusChanged: if (!activeFocus) root.saveAllChanges()
                                                    Keys.onEscapePressed: (event) => {
                                                        event.accepted = true
                                                        root.saveAllChanges()
                                                        envVarsWrap.forceActiveFocus()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // TAB 2: Performance & Controller
                    ColumnLayout {
                        id: tab2Perf
                        Layout.fillWidth: true
                        width: tabStack.width
                        spacing: 16

                        // Card 1: Performance Enhancements
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: perfCol1.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: perfCol1
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                Label {
                                    text: "PERFORMANCE ENHANCEMENTS"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.8
                                }

                                // Row 1: MangoHud (Toggle)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "MangoHud Overlay"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Real-time in-game overlay displaying FPS, frametimes, temperature, and CPU/GPU usage"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: mangohudToggle
                                        checked: (root.gameData.mangohudState === 1) ? true : ((root.gameData.mangohudState === 0) ? false : appSettings.mangohudDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 2: Feral GameMode (Toggle)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "Feral GameMode"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Applies performance governor, real-time scheduler priorities, and inhibits screensaver"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: gamemodeToggle
                                        checked: (root.gameData.gamemodeState === 1) ? true : ((root.gameData.gamemodeState === 0) ? false : appSettings.gamemodeDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 3: CPU Core Affinity
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "CPU Core Affinity (taskset)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Pin the game process and threads to specific CPU cores (e.g. 0-7, or 0,2,4,6)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    M3TextField {
                                        id: affinityField
                                        twoStageFocus: true
                                        Layout.preferredWidth: 260
                                        text: root.gameData.cpuAffinity || ""
                                        placeholderText: "e.g. 0-7"
                                        onCommit: root.saveAllChanges()
                                        onMoveUp: root.navigateStep(-1, 0)
                                        onMoveDown: root.navigateStep(1, 0)
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 4: Process Priority
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "Process Priority (nice)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Linux scheduler niceness from -20 (highest priority) to 19 (lowest priority)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    M3TextField {
                                        id: priorityField
                                        twoStageFocus: true
                                        Layout.preferredWidth: 120
                                        text: String(root.gameData.processPriority || 0)
                                        placeholderText: "0"
                                        onCommit: root.saveAllChanges()
                                        onMoveUp: root.navigateStep(-1, 0)
                                        onMoveDown: root.navigateStep(1, 0)
                                    }
                                }
                            }
                        }

                        // Card 2: Controller & Gamepad
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: ctrlCol.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: ctrlCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                Label {
                                    text: "CONTROLLER & GAMEPAD"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.8
                                }

                                // Xbox Controller Emulation ON/OFF Toggle
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label {
                                            text: "Xbox Controller Emulation"
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }
                                        Label {
                                            text: "Emulates an authentic XInput gamepad via Linux /dev/uinput daemon"
                                            color: appSettings.textSecColor
                                            font.pixelSize: 12
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: detailXboxToggle
                                        checked: (root.gameData.xboxEmulationState === 1)
                                        onToggled: (c) => {
                                            root.saveAllChanges()
                                        }
                                    }
                                }
                            }
                        }

                        // Card 3: Automation Scripts
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: autoCol.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: autoCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                Label {
                                    text: "AUTOMATION SCRIPTS"
                                    color: appSettings.accentColor
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.8
                                }

                                // Pre-launch Script
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Label { text: "Pre-Launch Script"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                    Label { text: "Shell script executed right before the game process is spawned"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    Item { Layout.preferredHeight: 2 }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        M3TextField {
                                            id: preScriptField
                                            twoStageFocus: true
                                            Layout.fillWidth: true
                                            text: root.gameData.preLaunchScript || ""
                                            placeholderText: "/path/to/pre.sh"
                                            onCommit: root.saveAllChanges()
                                            onMoveUp: root.navigateStep(-1, 0)
                                            onMoveDown: root.navigateStep(1, 0)
                                        }
                                        M3Button {
                                            id: preScriptBrowseBtn
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

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Post-exit Script
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Label { text: "Post-Exit Script"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                    Label { text: "Shell script executed after the game process exits and cleans up"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    Item { Layout.preferredHeight: 2 }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        M3TextField {
                                            id: postScriptField
                                            twoStageFocus: true
                                            Layout.fillWidth: true
                                            text: root.gameData.postExitScript || ""
                                            placeholderText: "/path/to/post.sh"
                                            onCommit: root.saveAllChanges()
                                            onMoveUp: root.navigateStep(-1, 0)
                                            onMoveDown: root.navigateStep(1, 0)
                                        }
                                        M3Button {
                                            id: postScriptBrowseBtn
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
                        }
                    }

                    // TAB 3: Artwork & Media
                    ColumnLayout {
                        id: tab3Art
                        Layout.fillWidth: true
                        width: tabStack.width
                        spacing: 16

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: artCol.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: artCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

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
                                        id: autoFetchArtBtn
                                        text: "Auto-Fetch Artwork"
                                        iconSource: "qrc:/tsuki_app/icons/actions/refresh.svg"
                                        buttonType: "tonal"
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
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 64
                                        radius: 8
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
                                            id: coverLinkBtn
                                            text: "Link…"
                                            iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                                            buttonType: "tonal"
                                            onClicked: artworkUrlDialog.openFor(root.gameId, "cover", "Cover Poster")
                                        }
                                        M3Button {
                                            id: coverBrowseBtn
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

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 2: Hero Banner (1920×620)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    spacing: 16

                                    Rectangle {
                                        Layout.preferredWidth: 84
                                        Layout.preferredHeight: 38
                                        radius: 8
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
                                            id: bannerLinkBtn
                                            text: "Link…"
                                            iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                                            buttonType: "tonal"
                                            onClicked: artworkUrlDialog.openFor(root.gameId, "banner", "Hero Banner")
                                        }
                                        M3Button {
                                            id: bannerBrowseBtn
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

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 3: Transparent Logo
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    spacing: 16

                                    Rectangle {
                                        Layout.preferredWidth: 70
                                        Layout.preferredHeight: 38
                                        radius: 8
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
                                            id: logoLinkBtn
                                            text: "Link…"
                                            iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                                            buttonType: "tonal"
                                            onClicked: artworkUrlDialog.openFor(root.gameId, "logo", "Transparent Logo")
                                        }
                                        M3Button {
                                            id: logoBrowseBtn
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

                                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04) }

                                // Row 4: Shortcut Icon
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    spacing: 16

                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 44
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
                                            id: iconLinkBtn
                                            text: "Link…"
                                            iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                                            buttonType: "tonal"
                                            onClicked: artworkUrlDialog.openFor(root.gameId, "icon", "Shortcut Icon")
                                        }
                                        M3Button {
                                            id: iconBrowseBtn
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
                        }
                    }

                    // TAB 4: Execution Logs
                    ColumnLayout {
                        id: tab4Logs
                        Layout.fillWidth: true
                        width: tabStack.width
                        spacing: 16

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: logCol.implicitHeight + 40
                            radius: 16
                            color: appSettings.surfaceColor
                            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                            ColumnLayout {
                                id: logCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: "EXECUTION CONSOLE LOG (" + (root.gameData.title || "").toUpperCase() + ")"
                                        color: appSettings.accentColor
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.8
                                        Layout.fillWidth: true
                                    }
                                    M3Button {
                                        id: exportLogBtn
                                        text: "Export Log"
                                        iconSource: "qrc:/tsuki_app/icons/actions/shortcut.svg"
                                        buttonType: "tonal"
                                        onClicked: uiController.diagnosticsManager.exportGameLog(root.gameId, "")
                                    }
                                    M3Button {
                                        id: clearLogBtn
                                        text: "Clear"
                                        iconSource: "qrc:/tsuki_app/icons/actions/trash.svg"
                                        buttonType: "destructive"
                                        onClicked: uiController.diagnosticsManager.clearGameLog(root.gameId)
                                    }
                                }

                                Rectangle {
                                    id: logAreaWrap
                                    focus: true
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 320
                                    radius: 12
                                    color: "#08080b"
                                    readonly property bool kbFocused: logAreaWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                                    border.color: logAreaWrap.kbFocused ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08))
                                    border.width: logAreaWrap.kbFocused ? 2 : 1
                                    Keys.onUpPressed: (event) => {
                                        let lf = logScroll.contentItem
                                        if (lf && lf.contentY > 2) {
                                            event.accepted = true
                                            lf.contentY = Math.max(0, lf.contentY - 60)
                                        }
                                    }
                                    Keys.onDownPressed: (event) => {
                                        let lf = logScroll.contentItem
                                        if (lf && lf.contentY < Math.max(0, lf.contentHeight - logScroll.height - 2)) {
                                            event.accepted = true
                                            lf.contentY = Math.min(Math.max(0, lf.contentHeight - logScroll.height), lf.contentY + 60)
                                        }
                                    }

                                    ScrollView {
                                        id: logScroll
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        clip: true
                                        TextArea {
                                            readOnly: true
                                            activeFocusOnTab: false
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

            // Bottom spacer for scroll clearance
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 68
            }
        }
    }

    // ── Fixed Floating Back Button (Top-Left) ────────────────────────────────
    Button {
        id: backBtn
        font.pixelSize: 13
        font.weight: Font.DemiBold
        padding: 0
        activeFocusOnTab: false
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 28
        anchors.topMargin: 24
        z: 100

        readonly property bool kbFocused: backBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
        readonly property bool isBtnActive: backBtn.hovered || backBtn.kbFocused
        property real expandedWidth: 10 + 18 + 8 + backLabel.implicitWidth + 14
        implicitWidth: isBtnActive ? expandedWidth : 40
        implicitHeight: 40

        Behavior on implicitWidth {
            SpringAnimation { spring: 4; damping: 0.25; epsilon: 0.25 }
        }

        background: Rectangle {
            property color accent: appSettings.accentColor
            radius: 20
            color: backBtn.isBtnActive ? accent : (appSettings.isEffectiveDark ? Qt.rgba(0.08, 0.08, 0.10, 0.70) : Qt.rgba(1, 1, 1, 0.75))
            border.color: backBtn.isBtnActive ? "transparent" : accent
            border.width: backBtn.isBtnActive ? 0 : 1.5
            scale: backBtn.pressed ? 0.96 : (backBtn.kbFocused ? 1.02 : 1.0)
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 100 } }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.50 : 0.20)
                shadowBlur: 0.5
                shadowVerticalOffset: 2
            }
        }

        contentItem: Item {
            clip: true
            implicitWidth: backBtn.implicitWidth
            implicitHeight: 40

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 8

                Item {
                    width: 18
                    height: parent.height
                    YIcon {
                        anchors.centerIn: parent
                        size: 18
                        source: "qrc:/tsuki_app/icons/actions/back.svg"
                        color: backBtn.isBtnActive ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : appSettings.accentColor
                    }
                }

                Label {
                    id: backLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Back"
                    color: backBtn.isBtnActive ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : appSettings.accentColor
                    font: backBtn.font
                    renderType: Text.QtRendering
                    opacity: backBtn.isBtnActive ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }
        }

        onClicked: {
            root.saveAllChanges()
            root.backRequested()
        }
        Keys.onDownPressed: (event) => { event.accepted = true; root.navigateStep(1, 0) }
        Keys.onRightPressed: (event) => { event.accepted = true; root.navigateStep(1, 0) }
        Keys.onReturnPressed: (event) => { event.accepted = true; backBtn.clicked() }
        Keys.onEnterPressed: (event) => { event.accepted = true; backBtn.clicked() }
        Keys.onSpacePressed: (event) => { event.accepted = true; backBtn.clicked() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    ArtworkUrlDialog {
        id: artworkUrlDialog
    }

    RemoveGameDialog {
        id: removeGameDialog
        onGameRemoved: stack.pop()
    }
}
