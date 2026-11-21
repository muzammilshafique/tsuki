import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Page {
    id: root
    objectName: "gameDetailPage"
    property string gameId: ""
    property string epicAppName: ""
    property var gameData: ({})
    property var epicData: ({})
    property int activeTab: 0
    property bool isSaving: false
    property int gamescopeStateDraft: -1
    property var gamescopeDraft: ({})
    property bool externalModalOpen: false
    property var cloudStatus: ({})
    property var cloudSnapshots: []
    property var gameDlcs: []

    readonly property bool isEpicEntry: root.epicAppName.length > 0 || Boolean(root.gameData.isEpic)
    readonly property bool isUninstalledEpic: root.isEpicEntry && root.gameId.length === 0
    readonly property bool isEpicDownloading: Boolean(root.epicData && root.epicData.isDownloading)
    readonly property bool isEpicPaused: Boolean(root.epicData && root.epicData.isPaused)
    readonly property bool isEpicVerifying: Boolean(root.epicData && root.epicData.isVerifying)
    readonly property var displayData: root.isUninstalledEpic ? root.epicData : root.gameData

    function formatGamescopeSummary() {
        let cfg = root.gamescopeDraft || ({})
        if (cfg.inheritGlobal !== false) {
            cfg = (appSettings && appSettings.defaultGamescopeConfig) ? appSettings.defaultGamescopeConfig : ({})
        }
        let parts = []
        if (cfg.windowMode === "borderless") parts.push("Borderless")
        else if (cfg.windowMode === "windowed") parts.push("Windowed")
        else parts.push("Fullscreen")

        let hasInt = Number(cfg.internalWidth) > 0 && Number(cfg.internalHeight) > 0
        let hasOut = Number(cfg.outputWidth) > 0 && Number(cfg.outputHeight) > 0
        if (hasInt && hasOut) {
            parts.push(cfg.internalWidth + "×" + cfg.internalHeight + " → " + cfg.outputWidth + "×" + cfg.outputHeight)
        } else if (hasOut) {
            parts.push(cfg.outputWidth + "×" + cfg.outputHeight)
        } else if (hasInt) {
            parts.push(cfg.internalWidth + "×" + cfg.internalHeight + " render")
        }

        if (cfg.filter && cfg.filter !== "auto") {
            parts.push(String(cfg.filter).toUpperCase())
        }
        if (Number(cfg.fpsLimit) > 0) {
            parts.push(cfg.fpsLimit + " FPS")
        }
        if (cfg.hdrEnabled) {
            parts.push("HDR")
        }
        if (cfg.adaptiveSync) {
            parts.push("VRR")
        }
        let text = parts.join(" • ")
        if (!root.gamescopeDraft || root.gamescopeDraft.inheritGlobal !== false) {
            return "Global Default (" + text + ")"
        }
        return text
    }

    readonly property bool isNative: root.gameData.isNative === true

    readonly property var tabList: {
        let tabs = [
            { label: "General & Paths", stackIndex: 0 }
        ]
        if (!root.isNative) {
            tabs.push({ label: "Wine & DXVK", stackIndex: 1 })
        }
        if (root.isEpicEntry) {
            tabs.push({ label: "Epic & Online", stackIndex: 5 })
        }
        tabs.push({ label: "Performance & Controller", stackIndex: 2 })
        tabs.push({ label: "Artwork & Media", stackIndex: 3 })
        tabs.push({ label: "Execution Logs", stackIndex: 4 })
        return tabs
    }

    onGameDataChanged: {
        if ((root.isNative && root.activeTab === 1) || (!root.isEpicEntry && root.activeTab === 5)) {
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
        if (root.externalModalOpen || actionsPopup.visible || artworkUrlDialog.visible || removeGameDialog.visible || gamescopeDialog.visible || epicDownloadDialog.visible || epicImportDialog.visible) return true
        if (typeof detailRunnerCombo !== "undefined" && detailRunnerCombo.popup.visible) return true
        if (typeof detailPrefixCombo !== "undefined" && detailPrefixCombo.popup.visible) return true
        if (typeof hudCombo !== "undefined" && hudCombo.popup.visible) return true
        if (typeof gpuCombo !== "undefined" && gpuCombo.popup.visible) return true
        if (typeof fsrStrengthCombo !== "undefined" && fsrStrengthCombo.popup.visible) return true
        if (typeof cloudSnapshotsCombo !== "undefined" && cloudSnapshotsCombo.popup.visible) return true
        return false
    }

    function cycleTab(delta, focusTabContent) {
        if (root.isUninstalledEpic || !tabList || tabList.length === 0) return
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
            focusTabContentTimer.restart()
        }
    }

    function getFocusGrid() {
        if (root.isUninstalledEpic) {
            let uRows = [[backBtn]]
            if (actionsDropdownBtn.visible) {
                uRows.push([primaryActionBtn, actionsDropdownBtn])
            } else {
                uRows.push([primaryActionBtn])
            }
            return uRows
        }
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
                rows.push([umuToggle])
                if (umuToggle.checked) {
                    rows.push([umuGameIdField, disableProtonfixesToggle])
                }
            } else {
                rows.push([nativeEnvWrap])
            }
        } else if (root.activeTab === 1 && !root.isNative) {
            rows.push([dxvkToggle])
            rows.push([vkd3dToggle])
            rows.push(hudToggle.checked ? [hudCombo, hudToggle] : [hudToggle])
            rows.push([esyncToggle])
            rows.push([fsyncToggle])
            rows.push([ntsyncToggle])
            rows.push([waylandToggle])
            rows.push([hdrToggle])
            rows.push([nvapiToggle])
            rows.push(fsrToggle.checked ? [fsrStrengthCombo, fsrToggle] : [fsrToggle])
            rows.push([gpuCombo])
            rows.push(vdesktopCheck.checked ? [vdesktopResField, vdesktopCheck] : [vdesktopCheck])
            rows.push([disableMonoGeckoToggle])
            rows.push([dllOverridesWrap, envVarsWrap])
        } else if (root.activeTab === 2) {
            rows.push([mangohudToggle])
            rows.push([gamemodeToggle])
            rows.push(gamescopeToggle.checked ? [gamescopeCustomizeBtn, gamescopeToggle] : [gamescopeToggle])
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
        } else if (root.activeTab === 5) {
            if (root.isEpicEntry && !root.isUninstalledEpic) {
                rows.push([epicOnlineAuthToggle])
            }
            if (root.isEpicEntry && !root.isUninstalledEpic && !root.isNative) {
                rows.push([eosOverlayToggle])
                rows.push([eacRuntimeToggle])
                rows.push([battleyeRuntimeToggle])
            }
            if (root.isEpicEntry && !root.isUninstalledEpic) {
                rows.push([cloudEnabledToggle])
                if (cloudEnabledToggle.checked) {
                    rows.push([cloudAutoSyncToggle])
                }
                rows.push([cloudFolderOverrideField])
            }
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
            if (gameData && gameData.epicAppName && root.epicAppName.length === 0) {
                root.epicAppName = gameData.epicAppName
            }
            gamescopeStateDraft = (gameData.gamescopeState !== undefined) ? gameData.gamescopeState : -1
            gamescopeDraft = gameData.gamescope || ({})
            uiController.diagnosticsManager.selectedLogGameId = gameId
            if (typeof detailXboxToggle !== "undefined" && detailXboxToggle) {
                detailXboxToggle.checked = (root.gameData.xboxEmulationState === 1)
            }
            if (typeof epicOnlineAuthToggle !== "undefined" && epicOnlineAuthToggle) {
                epicOnlineAuthToggle.checked = !Boolean(root.gameData.epicOfflineMode)
            }
            if (typeof eosOverlayToggle !== "undefined" && eosOverlayToggle) {
                eosOverlayToggle.checked = Boolean(root.gameData.enableEosOverlay)
            }
            if (typeof eacRuntimeToggle !== "undefined" && eacRuntimeToggle) {
                eacRuntimeToggle.checked = Boolean(root.isEpicEntry && root.gameData.enableEacRuntime)
            }
            if (typeof battleyeRuntimeToggle !== "undefined" && battleyeRuntimeToggle) {
                battleyeRuntimeToggle.checked = Boolean(root.isEpicEntry && root.gameData.enableBattlEyeRuntime)
            }
            if (typeof cloudEnabledToggle !== "undefined" && cloudEnabledToggle) {
                cloudEnabledToggle.checked = Boolean(root.gameData.epicCloudSavesEnabled)
            }
            if (typeof cloudAutoSyncToggle !== "undefined" && cloudAutoSyncToggle) {
                cloudAutoSyncToggle.checked = Boolean(root.gameData.epicAutoSyncCloudSaves)
            }
            if (uiController && uiController.cloudSaveService) {
                root.cloudStatus = uiController.cloudSaveService.getCloudSaveStatus(gameId)
                root.cloudSnapshots = uiController.cloudSaveService.listLocalSnapshots(gameId)
            }
        }
        if (root.epicAppName.length > 0 && uiController && uiController.epicService) {
            root.epicData = uiController.epicService.getEpicGameMap(root.epicAppName)
            root.gameDlcs = uiController.epicService.getDlcsForGame(root.epicAppName)
            if (root.gameId.length === 0 && root.epicData && root.epicData.installedGameId && root.epicData.installedGameId.length > 0) {
                root.gameId = root.epicData.installedGameId
                root.gameData = uiController.gameManager.getGameMap(root.gameId)
                gamescopeStateDraft = (gameData.gamescopeState !== undefined) ? gameData.gamescopeState : -1
                gamescopeDraft = gameData.gamescope || ({})
                uiController.diagnosticsManager.selectedLogGameId = root.gameId
                if (uiController && uiController.cloudSaveService) {
                    root.cloudStatus = uiController.cloudSaveService.getCloudSaveStatus(root.gameId)
                    root.cloudSnapshots = uiController.cloudSaveService.listLocalSnapshots(root.gameId)
                }
            }
        }
    }

    Timer {
        id: focusPrimaryBtnTimer
        interval: 0
        repeat: false
        onTriggered: primaryActionBtn.forceActiveFocus()
    }

    Timer {
        id: focusTabContentTimer
        interval: 0
        repeat: false
        onTriggered: {
            let grid = root.getFocusGrid()
            if (grid.length > 3 && grid[3].length > 0 && grid[3][0]) {
                grid[3][0].forceActiveFocus()
                root.scrollToControl(grid[3][0])
            }
        }
    }

    Component.onCompleted: {
        reloadGame()
        if (root.isUninstalledEpic && uiController && uiController.epicService) {
            uiController.epicService.fetchInstallInfo(root.epicAppName)
        }
        if (root.isEpicEntry && root.epicAppName.length > 0 && uiController && uiController.epicService) {
            uiController.epicService.requestDetailArtwork(root.epicAppName)
        }
        focusPrimaryBtnTimer.restart()
    }
    Component.onDestruction: saveAllChanges()

    StackView.onStatusChanged: {
        if (StackView.status === StackView.Active) {
            focusPrimaryBtnTimer.restart()
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
    Connections {
        target: (uiController && uiController.epicService) ? uiController.epicService : null
        function onDownloadStateChanged(appName) {
            if (appName === root.epicAppName) {
                root.epicData = uiController.epicService.getEpicGameMap(root.epicAppName)
            }
        }
        function onArtworkUpdated(appName) {
            if (appName === root.epicAppName) {
                root.epicData = uiController.epicService.getEpicGameMap(root.epicAppName)
            }
        }
        function onInstallInfoReady(appName, dlSize, instSize) {
            if (appName === root.epicAppName) {
                root.epicData = uiController.epicService.getEpicGameMap(root.epicAppName)
            }
        }
        function onDownloadFinished(appName, newGameId) {
            if (appName === root.epicAppName && newGameId.length > 0) {
                root.gameId = newGameId
                root.reloadGame()
            }
        }
        function onUpdatesChanged() {
            root.reloadGame()
        }
    }
    Connections {
        target: (uiController && uiController.cloudSaveService) ? uiController.cloudSaveService : null
        function onCloudSaveStatusChanged(gid) {
            if (gid === root.gameId && root.gameId.length > 0) {
                root.cloudStatus = uiController.cloudSaveService.getCloudSaveStatus(root.gameId)
                root.cloudSnapshots = uiController.cloudSaveService.listLocalSnapshots(root.gameId)
            }
        }
    }

    background: Rectangle { color: appSettings.surfaceContainerLowest }

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

        let ntsyncVal = (!root.isNative && typeof ntsyncToggle !== "undefined" && ntsyncToggle)
            ? (ntsyncToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.ntsyncState !== undefined ? root.gameData.ntsyncState : -1))

        let umuVal = (!root.isNative && typeof umuToggle !== "undefined" && umuToggle)
            ? (umuToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.umuState !== undefined ? root.gameData.umuState : -1))

        let waylandVal = (!root.isNative && typeof waylandToggle !== "undefined" && waylandToggle)
            ? (waylandToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.waylandDriverState !== undefined ? root.gameData.waylandDriverState : -1))

        let hdrVal = (!root.isNative && typeof hdrToggle !== "undefined" && hdrToggle)
            ? (hdrToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.hdrState !== undefined ? root.gameData.hdrState : -1))

        let nvapiVal = (!root.isNative && typeof nvapiToggle !== "undefined" && nvapiToggle)
            ? (nvapiToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.nvapiState !== undefined ? root.gameData.nvapiState : -1))

        let fsrVal = (!root.isNative && typeof fsrToggle !== "undefined" && fsrToggle)
            ? (fsrToggle.checked ? 1 : 0)
            : (root.isNative ? -1 : (root.gameData.fsrState !== undefined ? root.gameData.fsrState : -1))

        let fsrStrengthVal = (!root.isNative && typeof fsrStrengthCombo !== "undefined" && fsrStrengthCombo && fsrStrengthCombo.selectedIndex >= 0)
            ? fsrStrengthCombo.selectedIndex
            : (root.gameData.fsrStrength !== undefined ? root.gameData.fsrStrength : -1)

        let gpuSelVal = root.gameData.gpuSelection || ""
        if (!root.isNative && typeof gpuCombo !== "undefined" && gpuCombo) {
            const gpus = (uiController && uiController.diagnosticsManager) ? uiController.diagnosticsManager.detectedGpus : []
            if (gpuCombo.selectedIndex === 0) {
                gpuSelVal = ""
            } else if (gpuCombo.selectedIndex - 1 >= 0 && gpuCombo.selectedIndex - 1 < gpus.length) {
                gpuSelVal = gpus[gpuCombo.selectedIndex - 1].id
            }
        }

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
            ntsyncState: ntsyncVal,
            umuState: umuVal,
            umuGameId: (!root.isNative && typeof umuGameIdField !== "undefined" && umuGameIdField) ? umuGameIdField.text.trim() : (root.gameData.umuGameId || ""),
            disableProtonfixes: (!root.isNative && typeof disableProtonfixesToggle !== "undefined" && disableProtonfixesToggle) ? disableProtonfixesToggle.checked : Boolean(root.gameData.disableProtonfixes),
            disableMonoGecko: (!root.isNative && typeof disableMonoGeckoToggle !== "undefined" && disableMonoGeckoToggle) ? disableMonoGeckoToggle.checked : Boolean(root.gameData.disableMonoGecko),
            waylandDriverState: waylandVal,
            hdrState: hdrVal,
            nvapiState: nvapiVal,
            fsrState: fsrVal,
            fsrStrength: fsrStrengthVal,
            gpuSelection: gpuSelVal,
            epicCloudSavesEnabled: (typeof cloudEnabledToggle !== "undefined" && cloudEnabledToggle) ? cloudEnabledToggle.checked : Boolean(root.gameData.epicCloudSavesEnabled),
            epicAutoSyncCloudSaves: (typeof cloudAutoSyncToggle !== "undefined" && cloudAutoSyncToggle) ? cloudAutoSyncToggle.checked : Boolean(root.gameData.epicAutoSyncCloudSaves),
            epicCloudSaveFolder: (typeof cloudFolderOverrideField !== "undefined" && cloudFolderOverrideField) ? cloudFolderOverrideField.text.trim() : (root.gameData.epicCloudSaveFolder || ""),
            dxvkHud: hudVal,
            virtualDesktop: (!root.isNative && typeof vdesktopCheck !== "undefined" && vdesktopCheck) ? vdesktopCheck.checked : false,
            virtualDesktopResolution: (!root.isNative && typeof vdesktopResField !== "undefined" && vdesktopResField && vdesktopResField.text.length > 0) ? vdesktopResField.text : (root.gameData.virtualDesktopResolution || "1920x1080"),
            mangohudState: mangohudVal,
            gamemodeState: gamemodeVal,
            gamescopeState: root.gamescopeStateDraft,
            gamescope: root.gamescopeDraft || ({}),
            cpuAffinity: (typeof affinityField !== "undefined" && affinityField) ? affinityField.text.trim() : (root.gameData.cpuAffinity || ""),
            processPriority: (typeof priorityField !== "undefined" && priorityField) ? (Number(priorityField.text) || 0) : (root.gameData.processPriority || 0),
            xboxEmulationState: xboxEmuVal,
            epicOfflineMode: (root.isEpicEntry && typeof epicOnlineAuthToggle !== "undefined" && epicOnlineAuthToggle) ? !epicOnlineAuthToggle.checked : Boolean(root.gameData.epicOfflineMode),
            enableEosOverlay: (root.isEpicEntry && typeof eosOverlayToggle !== "undefined" && eosOverlayToggle) ? eosOverlayToggle.checked : false,
            enableEacRuntime: (root.isEpicEntry && typeof eacRuntimeToggle !== "undefined" && eacRuntimeToggle) ? eacRuntimeToggle.checked : false,
            enableBattlEyeRuntime: (root.isEpicEntry && typeof battleyeRuntimeToggle !== "undefined" && battleyeRuntimeToggle) ? battleyeRuntimeToggle.checked : false,
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
                    source: root.displayData.bannerPath || ""
                    sourceSize.width: 1920
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(13/255, 13/255, 17/255, 0.40) }
                        GradientStop { position: 0.35; color: "transparent" }
                        GradientStop { position: 0.65; color: Qt.rgba(appSettings.surfaceContainerLowest.r, appSettings.surfaceContainerLowest.g, appSettings.surfaceContainerLowest.b, 0.55) }
                        GradientStop { position: 1.0; color: appSettings.surfaceContainerLowest }
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
                        readonly property bool hasFullLogo: Boolean(root.displayData.logoPath && root.displayData.logoPath.length > 0)
                        readonly property string logoSource: hasFullLogo
                            ? root.displayData.logoPath
                            : (root.displayData.iconPath || "")
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
                            sourceSize.width: 640
                            sourceSize.height: 260
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
                        text: root.displayData.title || "Game Title"
                        color: appSettings.textColor
                        font.pixelSize: Math.max(26, Math.min(36, Math.round(root.width * 0.024)))
                        font.weight: Font.Bold
                        font.letterSpacing: -0.6
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: appSettings.showGameName || !gameLogoCard.hasFullLogo
                    }

                    // Bottom Row: Action (Play Now / Download) + Metadata
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        // ── Material 3 / Split Button Row ──────────────
                        Item {
                            id: splitButtonContainer
                            readonly property var heroActionItems: {
                                let items = []
                                if (root.isUninstalledEpic) {
                                    if (root.isEpicDownloading) {
                                        items.push({
                                            name: Boolean(root.epicData.isImporting) ? "Cancel Import" : "Cancel Download",
                                            symbol: "close",
                                            destructive: true,
                                            action: function() {
                                                if (uiController && uiController.epicService) {
                                                    uiController.epicService.cancelDownload(root.epicAppName, true)
                                                }
                                            }
                                        })
                                    } else {
                                        items.push({
                                            name: "Import Game",
                                            symbol: "folder_open",
                                            destructive: false,
                                            action: function() {
                                                epicImportDialog.openForApp(root.epicAppName)
                                            }
                                        })
                                    }
                                    return items
                                }
                                if (root.isEpicEntry && uiController && uiController.epicService) {
                                    if (Boolean(root.gameData.hasUpdate)) {
                                        items.push({
                                            name: "Update Game",
                                            symbol: "download",
                                            destructive: false,
                                            action: function() {
                                                uiController.epicService.updateGame(root.gameId)
                                            }
                                        })
                                    }
                                    items.push({
                                        name: "Verify Files",
                                        symbol: "refresh",
                                        destructive: false,
                                        action: function() {
                                            uiController.epicService.verifyGame(root.gameId)
                                        }
                                    })
                                    if (root.gameData.epicPrereqPath && String(root.gameData.epicPrereqPath).length > 0) {
                                        items.push({
                                            name: "Run Prerequisites",
                                            symbol: "build",
                                            destructive: false,
                                            action: function() {
                                                uiController.epicService.runGamePrerequisites(root.gameId, true)
                                            }
                                        })
                                    }
                                }
                                if (!root.isNative) {
                                    items.push({
                                        name: "Winetricks",
                                        symbol: "build",
                                        destructive: false,
                                        action: function() {
                                            root.winetricksRequested(root.gameData.prefixId || "default-prefix", root.gameData.title || "")
                                        }
                                    })
                                }
                                items.push({
                                    name: "Move Game Folder…",
                                    symbol: "folder_open",
                                    destructive: false,
                                    action: function() {
                                        const dest = uiController.selectFolder("Select Destination Folder to Move Game Into", "")
                                        if (dest && dest.length > 0) {
                                            uiController.gameManager.relocateGame(root.gameId, dest)
                                        }
                                    }
                                })
                                items.push({
                                    name: Boolean(root.gameData.isHidden) ? "Unhide Game" : "Hide Game",
                                    symbol: "tune",
                                    destructive: false,
                                    action: function() {
                                        uiController.gameManager.toggleHidden(root.gameId)
                                    }
                                })
                                items.push({
                                    name: "Shortcut",
                                    symbol: "shortcut",
                                    destructive: false,
                                    action: function() {
                                        uiController.gameManager.createDesktopShortcut(root.gameId, true)
                                    }
                                })
                                items.push({
                                    name: "Game Folder",
                                    symbol: "folder_open",
                                    destructive: false,
                                    action: function() {
                                        uiController.gameManager.openGameDirectory(root.gameId)
                                    }
                                })
                                if (!root.isNative && Boolean(root.gameData.prefixId && root.gameData.prefixId.length > 0)) {
                                    items.push({
                                        name: "Prefix Folder",
                                        symbol: "folder_open",
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
                                    symbol: "delete",
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

                                // 1. Leading Button: M3 Filled Play/Stop/Download Action
                                Button {
                                    id: primaryActionBtn
                                    objectName: "detailPrimaryActionBtn"
                                    text: {
                                        if (root.isUninstalledEpic) {
                                            if (root.isEpicDownloading) return root.isEpicPaused ? "Resume" : "Pause"
                                            return "Download"
                                        }
                                        return root.gameData.isRunning ? "Stop Game" : "Play Now"
                                    }
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
                                    // Avoid "on<Property>" prefix next to effectiveColor so QML does not parse it as a signal handler.
                                    readonly property color foregroundColor: root.gameData.isRunning ? "#ffffff" : appSettings.onPrimary

                                    scale: down ? 0.96 : (isBtnHovered ? 1.01 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                                    // Leading Button Background (Split Pill Left or Full Pill when no dropdown)
                                    background: Item {
                                        implicitHeight: 44
                                        implicitWidth: primaryActionBtn.width

                                        Rectangle {
                                            id: playBg
                                            anchors.fill: parent
                                            topLeftRadius: 22
                                            bottomLeftRadius: 22
                                            topRightRadius: actionsDropdownBtn.visible ? 4 : 22
                                            bottomRightRadius: actionsDropdownBtn.visible ? 4 : 22

                                            color: primaryActionBtn.down
                                                ? Qt.darker(primaryActionBtn.effectiveColor, 1.12)
                                                : (primaryActionBtn.isBtnHovered ? Qt.lighter(primaryActionBtn.effectiveColor, 1.08) : primaryActionBtn.effectiveColor)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        // Offscreen alpha mask matching split/full pill corners so click ripple never shows sharp corners
                                        Rectangle {
                                            id: playBgMask
                                            anchors.fill: parent
                                            topLeftRadius: playBg.topLeftRadius
                                            bottomLeftRadius: playBg.bottomLeftRadius
                                            topRightRadius: playBg.topRightRadius
                                            bottomRightRadius: playBg.bottomRightRadius
                                            color: "white"
                                            antialiasing: true
                                            visible: false
                                            layer.enabled: playRippleLayer.hasRipple
                                            layer.smooth: true
                                        }

                                        Item {
                                            id: playRippleLayer
                                            anchors.fill: parent
                                            clip: true
                                            readonly property bool hasRipple: playRipple.opacity > 0.001
                                            layer.enabled: hasRipple
                                            layer.smooth: true
                                            layer.effect: MultiEffect {
                                                autoPaddingEnabled: false
                                                maskEnabled: true
                                                maskSource: playBgMask
                                                maskThresholdMin: 0.5
                                                maskSpreadAtMin: 1.0
                                            }

                                            Rectangle {
                                                id: playRipple
                                                property real centerX: 0
                                                property real centerY: 0
                                                width: radius * 2
                                                height: radius * 2
                                                radius: 0
                                                x: centerX - radius
                                                y: centerY - radius
                                                color: primaryActionBtn.foregroundColor
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
                                            topRightRadius: actionsDropdownBtn.visible ? 7 : 25
                                            bottomRightRadius: actionsDropdownBtn.visible ? 7 : 25
                                            color: Qt.rgba(0, 0, 0, 0)
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
                                                size: 20
                                                symbol: {
                                                    if (root.isUninstalledEpic) {
                                                        if (root.isEpicDownloading) return root.isEpicPaused ? "play_arrow" : "stop"
                                                        return "download"
                                                    }
                                                    return root.gameData.isRunning ? "stop" : "play_arrow"
                                                }
                                                filled: !root.isUninstalledEpic || root.isEpicPaused
                                                color: primaryActionBtn.foregroundColor
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Label {
                                                id: playLabel
                                                text: primaryActionBtn.text
                                                color: primaryActionBtn.foregroundColor
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
                                        if (root.isUninstalledEpic) {
                                            if (!uiController || !uiController.epicService) return
                                            if (root.isEpicDownloading) {
                                                if (root.isEpicPaused) uiController.epicService.resumeDownload(root.epicAppName)
                                                else uiController.epicService.pauseDownload(root.epicAppName)
                                            } else {
                                                epicDownloadDialog.openForApp(root.epicAppName)
                                            }
                                            return
                                        }
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
                                        onReleased: (mouse) => {
                                            primaryActionBtn.down = false
                                            playRippleFade.restart()
                                            if (mouse.x >= 0 && mouse.x <= width && mouse.y >= 0 && mouse.y <= height) {
                                                primaryActionBtn.clicked()
                                            }
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
                                    objectName: "detailActionsDropdownBtn"
                                    visible: splitButtonContainer.heroActionItems.length > 0
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
                                            size: 20
                                            symbol: "keyboard_arrow_down"
                                            color: primaryActionBtn.foregroundColor
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
                                property real _spaceBelow: 460
                                property real _spaceAbove: 460
                                function refreshAvailableSpace() {
                                    let win = root.Window.window
                                    if (!win) {
                                        _spaceBelow = Math.max(460, naturalContentHeight)
                                        _spaceAbove = Math.max(460, naturalContentHeight)
                                        return
                                    }
                                    let pBottom = splitButtonContainer.mapToItem(null, 0, splitButtonContainer.height)
                                    let pTop = splitButtonContainer.mapToItem(null, 0, 0)
                                    _spaceBelow = Math.max(180, win.height - pBottom.y - 16)
                                    _spaceAbove = Math.max(180, pTop.y - 16)
                                }
                                readonly property real naturalContentHeight: actionsContentCol.implicitHeight + 12
                                readonly property bool opensUpward: (naturalContentHeight > _spaceBelow) && (_spaceAbove > _spaceBelow)
                                readonly property real fullContentHeight: Math.min(opensUpward ? _spaceAbove : _spaceBelow, naturalContentHeight)
                                y: opensUpward ? (-height - 6) : (splitButtonContainer.height + 6)
                                x: 0
                                width: Math.max(splitButtonContainer.implicitWidth, 210)
                                padding: 6
                                dim: false
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

                                property int focusedActionIndex: 0
                                onAboutToShow: {
                                    focusedActionIndex = 0
                                    refreshAvailableSpace()
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
                                    color: appSettings.surfaceContainer
                                    border.width: 0
                                    radius: 16

                                    layer.enabled: actionsPopup.visible
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

                                                        // Hover container highlight (opacity-only eliminates dark #00000000 transition flash)
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: 19
                                                            color: aRow.isDestructive
                                                                ? (appSettings.isEffectiveDark ? Qt.rgba(0.93, 0.27, 0.27, 0.18) : Qt.rgba(0.93, 0.27, 0.27, 0.12))
                                                                : appSettings.secondaryContainer
                                                            opacity: aRow.isHovered ? 1.0 : 0.0
                                                            Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                                        }

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: 19
                                                            color: Qt.rgba(0, 0, 0, 0)
                                                            border.color: aRow.isDestructive ? "#ef4444" : appSettings.accentColor
                                                            border.width: 1.5
                                                            opacity: (Boolean(uiController && uiController.isKeyboardNavActive) && aRow.isFocusedAction) ? 1.0 : 0.0
                                                            Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                                        }

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 12
                                                            anchors.rightMargin: 12
                                                            spacing: 10

                                                            YIcon {
                                                                size: 18
                                                                symbol: aCol.modelData.symbol || ""
                                                                color: aRow.isDestructive
                                                                    ? "#ef4444"
                                                                    : (aRow.isHovered ? appSettings.onSecondaryContainer : appSettings.textSecColor)
                                                                Layout.alignment: Qt.AlignVCenter
                                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                            }

                                                            Label {
                                                                Layout.fillWidth: true
                                                                verticalAlignment: Text.AlignVCenter
                                                                text: aCol.modelData.name || ""
                                                                color: aRow.isDestructive
                                                                    ? "#ef4444"
                                                                    : (aRow.isHovered ? appSettings.onSecondaryContainer : appSettings.textColor)
                                                                font.family: "Rubik"
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
                                radius: 12
                                height: 24
                                implicitHeight: 24
                                implicitWidth: rTagLbl.implicitWidth + 20
                                Layout.preferredWidth: implicitWidth
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignVCenter
                                readonly property color effectiveTagColor: root.gameData.isRunning
                                    ? "#22c55e"
                                    : (root.isNative ? appSettings.tagColorLinux : appSettings.accentColor)
                                color: (root.gameData.isRunning || root.isNative)
                                    ? Qt.rgba(effectiveTagColor.r, effectiveTagColor.g, effectiveTagColor.b, 0.16)
                                    : appSettings.secondaryContainer
                                border.width: 0

                                Label {
                                    id: rTagLbl
                                    anchors.centerIn: parent
                                    text: {
                                        if (root.isUninstalledEpic) return "EPIC GAMES"
                                        return root.gameData.isRunning ? "RUNNING" : (root.gameData.runnerTag || (root.isNative ? "LINUX" : "WINE"))
                                    }
                                    color: (root.gameData.isRunning || root.isNative)
                                        ? rTagRect.effectiveTagColor
                                        : appSettings.onSecondaryContainer
                                    font.family: "Rubik"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    renderType: Text.QtRendering
                                }
                            }

                            Label {
                                id: playtimeLbl
                                text: {
                                    if (root.isUninstalledEpic) {
                                        let parts = []
                                        if (root.epicData.developer && root.epicData.developer.length > 0) parts.push(root.epicData.developer)
                                        if (root.epicData.downloadSizeFormatted && root.epicData.downloadSizeFormatted.length > 0) parts.push("Download: " + root.epicData.downloadSizeFormatted)
                                        if (root.epicData.installSizeFormatted && root.epicData.installSizeFormatted.length > 0) parts.push("Install Size: " + root.epicData.installSizeFormatted)
                                        return parts.length > 0 ? parts.join("  •  ") : "Not Installed"
                                    }
                                    return "Playtime: " + (root.gameData.playtimeFormatted || "Never played") + "  •  Last Played: " + (root.gameData.lastPlayedFormatted || "Never")
                                }
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

            // ── Active Epic Download / Verify Progress Card ──────────────────
            Rectangle {
                id: epicProgressCard
                visible: root.isEpicDownloading
                Layout.fillWidth: true
                Layout.maximumWidth: 1020
                Layout.alignment: Qt.AlignHCenter
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 12
                implicitHeight: epicProgCol.implicitHeight + 36
                radius: 20
                color: appSettings.surfaceContainerLow
                border.color: appSettings.accentColor
                border.width: 1

                ColumnLayout {
                    id: epicProgCol
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Label {
                            text: (root.epicData.stage || "Downloading…") + " (" + Math.round(Number(root.epicData.progress || 0)) + "%)"
                            color: appSettings.textColor
                            font.family: "Rubik"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        Label {
                            text: (root.epicData.downloadedSizeStr || "0 B") +
                                  (root.epicData.totalSizeStr ? (" / " + root.epicData.totalSizeStr) : "") +
                                  (root.epicData.eta ? ("  •  " + root.epicData.eta) : "")
                            color: appSettings.textSecColor
                            font.pixelSize: 13
                        }

                        M3Button {
                            visible: !root.isEpicVerifying && !Boolean(root.epicData.isImporting)
                            text: root.isEpicPaused ? "Resume" : "Pause"
                            iconSymbol: root.isEpicPaused ? "play_arrow" : "stop"
                            buttonType: "tonal"
                            onClicked: {
                                if (!uiController || !uiController.epicService) return
                                if (root.isEpicPaused) uiController.epicService.resumeDownload(root.epicAppName)
                                else uiController.epicService.pauseDownload(root.epicAppName)
                            }
                        }

                        M3Button {
                            text: "Cancel"
                            iconSymbol: "close"
                            buttonType: "destructive"
                            onClicked: {
                                if (uiController && uiController.epicService) {
                                    uiController.epicService.cancelDownload(root.epicAppName, true)
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: appSettings.surfaceContainerHighest

                        Rectangle {
                            height: parent.height
                            width: parent.width * Math.max(0.0, Math.min(1.0, Number(root.epicData.progress || 0) / 100.0))
                            radius: 3
                            color: root.isEpicPaused ? "#f59e0b" : appSettings.accentColor
                            Behavior on width { NumberAnimation { duration: 150 } }
                        }
                    }
                }
            }

            // ── Uninstalled Epic Game Overview Card ──────────────────────────
            Rectangle {
                id: epicOverviewCard
                objectName: "epicOverviewCard"
                visible: root.isUninstalledEpic
                Layout.fillWidth: true
                Layout.maximumWidth: 1020
                Layout.alignment: Qt.AlignHCenter
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 12
                Layout.bottomMargin: 24
                implicitHeight: epicOverviewCol.implicitHeight + 48
                radius: 24
                color: appSettings.surfaceContainerLow

                ColumnLayout {
                    id: epicOverviewCol
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 14

                    Label {
                        text: "Epic Games Overview"
                        color: appSettings.accentColor
                        font.family: "Rubik"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Label {
                        visible: Boolean(root.epicData.description && root.epicData.description.length > 0)
                        text: root.epicData.description || ""
                        color: appSettings.textColor
                        font.pixelSize: 14
                        lineHeight: 1.4
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        visible: !root.epicData.description || root.epicData.description.length === 0
                        text: "Ready to download from your Epic Games account. Click Download above to choose the install folder, Wine prefix, and Proton runner."
                        color: appSettings.textSecColor
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 24

                        ColumnLayout {
                            spacing: 2
                            Label { text: "App Name"; color: appSettings.textTerColor; font.pixelSize: 11 }
                            Label { text: root.epicAppName; color: appSettings.textColor; font.family: "JetBrains Mono NF"; font.pixelSize: 13 }
                        }

                        ColumnLayout {
                            visible: Boolean(root.epicData.buildVersion && root.epicData.buildVersion.length > 0)
                            spacing: 2
                            Label { text: "Build Version"; color: appSettings.textTerColor; font.pixelSize: 11 }
                            Label { text: root.epicData.buildVersion || ""; color: appSettings.textColor; font.family: "JetBrains Mono NF"; font.pixelSize: 13 }
                        }

                        ColumnLayout {
                            spacing: 2
                            Label { text: "Compatibility"; color: appSettings.textTerColor; font.pixelSize: 11 }
                            Label { text: "Windows · Wine / Proton"; color: appSettings.textColor; font.pixelSize: 13 }
                        }
                    }
                }
            }

            // ── Material 3 Expressive Sliding Pill Tabs Bar ─────────────────
            Item {
                id: tabsBar
                visible: !root.isUninstalledEpic
                focus: true
                activeFocusOnTab: false
                readonly property bool isBarFocused: tabsBar.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                property real activePillX: 0
                property real activePillW: 0
                property bool pillInitialized: false

                function syncActiveTabPill(animate) {
                    let target = null
                    for (let i = 0; i < tabRepeater.count; ++i) {
                        const item = tabRepeater.itemAt(i)
                        if (item && item.modelData && item.modelData.stackIndex === root.activeTab) {
                            target = item
                            break
                        }
                    }
                    if (!target || target.width <= 0) return
                    const shouldAnimate = Boolean(animate && pillInitialized)
                    pillXBehavior.enabled = shouldAnimate
                    pillWBehavior.enabled = shouldAnimate
                    activePillX = tabsRow.x + target.x
                    activePillW = target.width
                    if (!pillInitialized) {
                        pillInitialized = true
                    }
                }

                Timer {
                    id: syncPillTimer
                    interval: 0
                    repeat: false
                    onTriggered: tabsBar.syncActiveTabPill(false)
                }

                Connections {
                    target: root
                    function onActiveTabChanged() {
                        tabsBar.syncActiveTabPill(true)
                    }
                    function onTabListChanged() {
                        tabsBar.pillInitialized = false
                        syncPillTimer.restart()
                    }
                }

                Layout.fillWidth: true
                Layout.maximumWidth: 1020
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 46
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 4

                // Sliding active indicator behind tabsRow
                Rectangle {
                    id: activeTabPill
                    visible: tabsBar.activePillW > 0
                    x: tabsBar.activePillX
                    y: tabsRow.y
                    width: tabsBar.activePillW
                    height: 38
                    radius: 19
                    color: appSettings.secondaryContainer

                    Behavior on x {
                        id: pillXBehavior
                        enabled: false
                        NumberAnimation {
                            duration: 240
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on width {
                        id: pillWBehavior
                        enabled: false
                        NumberAnimation {
                            duration: 240
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    // Keyboard focus outline ring
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Qt.rgba(0, 0, 0, 0)
                        border.color: appSettings.accentColor
                        border.width: 1.5
                        opacity: tabsBar.isBarFocused ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                }

                Row {
                    id: tabsRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Repeater {
                        id: tabRepeater
                        model: root.tabList

                        Item {
                            id: tabItem
                            required property int index
                            required property var modelData
                            readonly property bool isSelected: root.activeTab === tabItem.modelData.stackIndex
                            height: 38
                            width: tabItemLbl.implicitWidth + 32
                            scale: tabItemMA.pressed ? 0.96 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            onXChanged: if (isSelected) tabsBar.syncActiveTabPill(tabsBar.pillInitialized)
                            onWidthChanged: if (isSelected) tabsBar.syncActiveTabPill(tabsBar.pillInitialized)
                            Component.onCompleted: if (isSelected) syncPillTimer.restart()

                            // Opacity-only hover highlight prevents #00000000 dark hover flash
                            Rectangle {
                                anchors.fill: parent
                                radius: 19
                                color: appSettings.surfaceContainerHigh
                                opacity: (!tabItem.isSelected && tabItemMA.containsMouse) ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }

                            Label {
                                id: tabItemLbl
                                anchors.centerIn: parent
                                text: tabItem.modelData.label
                                color: tabItem.isSelected
                                    ? appSettings.onSecondaryContainer
                                    : (tabItemMA.containsMouse ? appSettings.textColor : appSettings.textSecColor)
                                font.family: "Rubik"
                                font.pixelSize: 14
                                font.weight: tabItem.isSelected ? Font.DemiBold : Font.Medium
                                renderType: Text.QtRendering
                                Behavior on color { ColorAnimation { duration: 150 } }
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
            }

            // ── Tab Content Area ─────────────────────────────────────────────
            Item {
                id: tabContentCard
                visible: !root.isUninstalledEpic
                Layout.fillWidth: true
                Layout.maximumWidth: 1020
                Layout.alignment: Qt.AlignHCenter
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 12
                Layout.bottomMargin: 24

                property int prevTab: 0
                property int slideDir: 1
                property real tabOffsetX: 0
                property real tabOpacity: 1.0

                Connections {
                    target: root
                    function onActiveTabChanged() {
                        tabContentCard.slideDir = (root.activeTab >= tabContentCard.prevTab) ? 1 : -1
                        tabContentCard.prevTab = root.activeTab
                        tabSwitchAnim.restart()
                    }
                }

                ParallelAnimation {
                    id: tabSwitchAnim
                    NumberAnimation {
                        target: tabContentCard
                        property: "tabOffsetX"
                        from: 18 * tabContentCard.slideDir
                        to: 0
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: tabContentCard
                        property: "tabOpacity"
                        from: 0.0
                        to: 1.0
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                readonly property real activeTabHeight: {
                    switch (root.activeTab) {
                        case 0: return tab0General ? tab0General.implicitHeight : 380
                        case 1: return tab1Wine ? tab1Wine.implicitHeight : 480
                        case 2: return tab2Perf ? tab2Perf.implicitHeight : 650
                        case 3: return tab3Art ? tab3Art.implicitHeight : 300
                        case 4: return tab4Logs ? tab4Logs.implicitHeight : 360
                        case 5: return tab5Online ? tab5Online.implicitHeight : 420
                        default: return 400
                    }
                }

                implicitHeight: activeTabHeight + 24
                Behavior on implicitHeight {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                StackLayout {
                    id: tabStack
                    objectName: "detailTabStack"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: tabContentCard.activeTabHeight
                    currentIndex: root.activeTab
                    opacity: tabContentCard.tabOpacity
                    transform: Translate { x: tabContentCard.tabOffsetX }

                    // TAB 0: General & Paths
                    ColumnLayout {
                        id: tab0General
                        Layout.fillWidth: true
                        width: tabStack.width
                        spacing: 16

                        // Card 1: Executable & Launch Configuration
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: generalCol1.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: generalCol1
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: "Executable & Launch Configuration"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
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
                                            iconSymbol: "folder_open"
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
                                            iconSymbol: "folder_open"
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
                            implicitHeight: generalCol2.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: generalCol2
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: "Runner & Prefix Environment"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
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

                                // UMU Launcher Toggle
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            text: "UMU Launcher (Protonfixes & Steam Runtime)"
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }
                                        Label {
                                            text: (uiController && uiController.runnerManager && uiController.runnerManager.umuAvailable)
                                                ? "Run Proton through umu-run for automatic per-game Protonfixes & container runtime"
                                                : "umu-launcher not installed — falls back to standalone Proton until installed in Runners"
                                            color: appSettings.textSecColor
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Toggle {
                                        id: umuToggle
                                        objectName: "detailUmuToggle"
                                        checked: (root.gameData.umuState === 1) ? true : ((root.gameData.umuState === 0) ? false : appSettings.umuDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                // UMU Game ID & Disable Protonfixes Row (50/50 Two-Column Split)
                                RowLayout {
                                    visible: umuToggle.checked
                                    Layout.fillWidth: true
                                    spacing: 20

                                    // Left Half: UMU Game ID
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 4
                                        Label {
                                            text: "UMU Game ID (GAMEID)"
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: "Auto-resolved from UMU database, or override manually (e.g. umu-123456)"
                                            color: appSettings.textSecColor
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                        Item { Layout.preferredHeight: 2 }
                                        M3TextField {
                                            id: umuGameIdField
                                            twoStageFocus: true
                                            Layout.fillWidth: true
                                            text: root.gameData.umuGameId || ""
                                            placeholderText: "Auto-resolved (or override e.g. umu-123456)"
                                            onCommit: root.saveAllChanges()
                                            onMoveUp: root.navigateStep(-1, 0)
                                            onMoveDown: root.navigateStep(1, 0)
                                        }
                                    }

                                    // Right Half: Disable Protonfixes Toggle + Explanation
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 14

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Label {
                                                text: "Disable Protonfixes"
                                                color: appSettings.textColor
                                                font.pixelSize: 14
                                                font.weight: Font.Medium
                                                Layout.fillWidth: true
                                            }
                                            Label {
                                                text: "Skip automatic per-game UMU fixes (tweaks, DLL overrides, and launch workarounds)"
                                                color: appSettings.textSecColor
                                                font.pixelSize: 12
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }

                                        Toggle {
                                            id: disableProtonfixesToggle
                                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                            checked: Boolean(root.gameData.disableProtonfixes)
                                            onToggled: root.saveAllChanges()
                                        }
                                    }
                                }
                            }
                        }

                        // Card 2.5: Collections & Tags
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: collectionsCardCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: collectionsCardCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 14

                                Label {
                                    text: "Collections"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: (uiController && uiController.gameManager) ? uiController.gameManager.categories : []
                                        delegate: Rectangle {
                                            required property string modelData
                                            readonly property bool isAssigned: Boolean(root.gameData.categories && root.gameData.categories.indexOf(modelData) !== -1)
                                            height: 32
                                            width: colChipRow.implicitWidth + 20
                                            radius: 16
                                            color: isAssigned ? appSettings.secondaryContainer : appSettings.surfaceContainerHigh
                                            border.color: isAssigned ? appSettings.accentColor : appSettings.borderColor
                                            border.width: 1

                                            Row {
                                                id: colChipRow
                                                anchors.centerIn: parent
                                                spacing: 6
                                                YIcon {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    size: 14
                                                    symbol: isAssigned ? "check" : "add"
                                                    color: isAssigned ? appSettings.onSecondaryContainer : appSettings.textSecColor
                                                }
                                                Label {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData
                                                    color: isAssigned ? appSettings.onSecondaryContainer : appSettings.textColor
                                                    font.pixelSize: 12
                                                    font.weight: isAssigned ? Font.DemiBold : Font.Medium
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (!uiController || !uiController.gameManager) return
                                                    if (isAssigned) uiController.gameManager.removeGameFromCollection(root.gameId, modelData)
                                                    else uiController.gameManager.addGameToCollection(root.gameId, modelData)
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    M3TextField {
                                        id: detailNewColField
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: 320
                                        placeholderText: "Create & assign collection…"
                                        onCommit: (val) => {
                                            const nm = val.trim()
                                            if (nm.length > 0 && uiController && uiController.gameManager) {
                                                uiController.gameManager.addGameToCollection(root.gameId, nm)
                                                detailNewColField.text = ""
                                            }
                                        }
                                    }
                                    M3Button {
                                        text: "Add"
                                        buttonType: "tonal"
                                        onClicked: {
                                            const nm = detailNewColField.text.trim()
                                            if (nm.length > 0 && uiController && uiController.gameManager) {
                                                uiController.gameManager.addGameToCollection(root.gameId, nm)
                                                detailNewColField.text = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Card 2 (Native Linux): Environment Variables
                        Rectangle {
                            visible: root.isNative
                            Layout.fillWidth: true
                            implicitHeight: generalNativeEnvCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: generalNativeEnvCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: "Environment Variables"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
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
                                    radius: 14
                                    color: appSettings.surfaceContainerHigh
                                    border.color: appSettings.accentColor
                                    border.width: ((nativeEnvWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) || nativeEnvVarsArea.activeFocus) ? 2 : 0
                                    Keys.onReturnPressed: (event) => { if (!nativeEnvVarsArea.activeFocus) { event.accepted = true; nativeEnvVarsArea.forceActiveFocus() } }
                                    Keys.onEnterPressed: (event) => { if (!nativeEnvVarsArea.activeFocus) { event.accepted = true; nativeEnvVarsArea.forceActiveFocus() } }
                                    Keys.onSpacePressed: (event) => { if (!nativeEnvVarsArea.activeFocus) { event.accepted = true; nativeEnvVarsArea.forceActiveFocus() } }

                                    ScrollView {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        TextArea {
                                            id: nativeEnvVarsArea
                                            color: appSettings.textColor
                                            font.family: "JetBrains Mono NF"
                                            font.pixelSize: 13
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
                        spacing: 16

                        // Card 1: Direct3D Translators
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: d3dCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: d3dCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: "Direct3D Translators"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
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
                            implicitHeight: syncCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: syncCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: "Kernel Synchronization & Display"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
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

                                // Row 2.1: NTSync (Toggle)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        RowLayout {
                                            spacing: 8
                                            Label { text: "NTSync (Linux 6.14+ /dev/ntsync)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                            Rectangle {
                                                height: 18
                                                implicitWidth: ntsyncBadgeLbl.implicitWidth + 10
                                                radius: 9
                                                color: (uiController && uiController.diagnosticsManager && uiController.diagnosticsManager.ntsyncAvailable)
                                                    ? Qt.rgba(34/255, 197/255, 94/255, 0.16)
                                                    : Qt.rgba(0.58, 0.64, 0.72, 0.16)
                                                Label {
                                                    id: ntsyncBadgeLbl
                                                    anchors.centerIn: parent
                                                    text: (uiController && uiController.diagnosticsManager && uiController.diagnosticsManager.ntsyncAvailable) ? "Available" : "No /dev/ntsync"
                                                    color: (uiController && uiController.diagnosticsManager && uiController.diagnosticsManager.ntsyncAvailable) ? "#22c55e" : appSettings.textSecColor
                                                    font.pixelSize: 10
                                                    font.weight: Font.Medium
                                                }
                                            }
                                        }
                                        Label { text: "Native kernel NT synchronization primitives for lowest CPU overhead"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: ntsyncToggle
                                        objectName: "detailNtsyncToggle"
                                        checked: (root.gameData.ntsyncState === 1) ? true : ((root.gameData.ntsyncState === 0) ? false : appSettings.ntsyncDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                // Row 2.2: Native Wine Wayland Driver
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "Native Wine Wayland Driver"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Bypass XWayland via PROTON_ENABLE_WAYLAND=1 (Proton 10+ / GE-Proton 10+)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: waylandToggle
                                        checked: (root.gameData.waylandDriverState === 1) ? true : ((root.gameData.waylandDriverState === 0) ? false : appSettings.waylandDriverDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                // Row 2.3: HDR Output
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "HDR Output"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Enable PROTON_ENABLE_HDR=1 and DXVK_HDR=1 for Wayland / Gamescope HDR"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: hdrToggle
                                        checked: (root.gameData.hdrState === 1) ? true : ((root.gameData.hdrState === 0) ? false : appSettings.hdrDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                // Row 2.4: NVIDIA NVAPI / DLSS
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "NVIDIA NVAPI / DLSS / Reflex"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Expose PROTON_ENABLE_NVAPI=1 and DXVK_ENABLE_NVAPI=1 for DLSS & Reflex"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        id: nvapiToggle
                                        checked: (root.gameData.nvapiState === 1) ? true : ((root.gameData.nvapiState === 0) ? false : appSettings.nvapiDefault)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                // Row 2.5: Wine Fullscreen FSR + Sharpness
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "Wine Fullscreen FSR"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Upscale lower fullscreen resolutions with AMD FSR (suppressed when Gamescope is active)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    RowLayout {
                                        spacing: 10
                                        StyledCombo {
                                            id: fsrStrengthCombo
                                            Layout.preferredWidth: 140
                                            upDownNavigatesFocus: true
                                            enabled: fsrToggle.checked
                                            opacity: fsrToggle.checked ? 1.0 : 0.4
                                            comboModel: ["0 (Sharpest)", "1", "2 (Balanced)", "3", "4", "5 (Softest)"]
                                            selectedIndex: {
                                                const s = (root.gameData.fsrStrength !== undefined && root.gameData.fsrStrength >= 0)
                                                    ? root.gameData.fsrStrength : appSettings.defaultFsrStrength
                                                return Math.max(0, Math.min(5, s))
                                            }
                                            onSelected: root.saveAllChanges()
                                        }
                                        Toggle {
                                            id: fsrToggle
                                            checked: (root.gameData.fsrState === 1) ? true : ((root.gameData.fsrState === 0) ? false : appSettings.fsrDefault)
                                            onToggled: root.saveAllChanges()
                                        }
                                    }
                                }

                                // Row 2.6: GPU / PRIME Selection
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        spacing: 2
                                        Label { text: "GPU / Hybrid PRIME Selector"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Pin DirectX/Vulkan rendering and PRIME offload to a specific GPU"; color: appSettings.textSecColor; font.pixelSize: 12 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    StyledCombo {
                                        id: gpuCombo
                                        objectName: "detailGpuCombo"
                                        Layout.preferredWidth: 260
                                        upDownNavigatesFocus: true
                                        readonly property var gpuList: (uiController && uiController.diagnosticsManager)
                                            ? uiController.diagnosticsManager.detectedGpus : []
                                        comboModel: {
                                            let list = ["Auto (Global / Default)"]
                                            for (let i = 0; i < gpuList.length; ++i) {
                                                list.push(gpuList[i].name)
                                            }
                                            return list
                                        }
                                        selectedIndex: {
                                            const cur = root.gameData.gpuSelection || ""
                                            if (!cur || cur.length === 0) return 0
                                            for (let i = 0; i < gpuList.length; ++i) {
                                                if (gpuList[i].id === cur || gpuList[i].name === cur) return i + 1
                                            }
                                            return 0
                                        }
                                        onSelected: root.saveAllChanges()
                                    }
                                }


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
                            implicitHeight: overridesCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: overridesCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: "Overrides & Environment Variables"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
                                }

                                // Opt-in Disable Mono / Gecko DLL Override
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 16
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label { text: "Disable Wine Mono & Gecko (mscoree,mshtml=)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label { text: "Leave OFF for Unity/.NET and embedded-browser launchers; turn ON only to suppress Wine installer dialogs"; color: appSettings.textSecColor; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }
                                    Toggle {
                                        id: disableMonoGeckoToggle
                                        checked: Boolean(root.gameData.disableMonoGecko)
                                        onToggled: root.saveAllChanges()
                                    }
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
                                            radius: 14
                                            color: appSettings.surfaceContainerHigh
                                            border.color: appSettings.accentColor
                                            border.width: ((dllOverridesWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) || dllOverridesArea.activeFocus) ? 2 : 0
                                            Keys.onReturnPressed: (event) => { if (!dllOverridesArea.activeFocus) { event.accepted = true; dllOverridesArea.forceActiveFocus() } }
                                            Keys.onEnterPressed: (event) => { if (!dllOverridesArea.activeFocus) { event.accepted = true; dllOverridesArea.forceActiveFocus() } }
                                            Keys.onSpacePressed: (event) => { if (!dllOverridesArea.activeFocus) { event.accepted = true; dllOverridesArea.forceActiveFocus() } }

                                            ScrollView {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                TextArea {
                                                    id: dllOverridesArea
                                                    color: appSettings.textColor
                                                    font.family: "JetBrains Mono NF"
                                                    font.pixelSize: 13
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
                                            radius: 14
                                            color: appSettings.surfaceContainerHigh
                                            border.color: appSettings.accentColor
                                            border.width: ((envVarsWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) || envVarsArea.activeFocus) ? 2 : 0
                                            Keys.onReturnPressed: (event) => { if (!envVarsArea.activeFocus) { event.accepted = true; envVarsArea.forceActiveFocus() } }
                                            Keys.onEnterPressed: (event) => { if (!envVarsArea.activeFocus) { event.accepted = true; envVarsArea.forceActiveFocus() } }
                                            Keys.onSpacePressed: (event) => { if (!envVarsArea.activeFocus) { event.accepted = true; envVarsArea.forceActiveFocus() } }

                                            ScrollView {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                TextArea {
                                                    id: envVarsArea
                                                    color: appSettings.textColor
                                                    font.family: "JetBrains Mono NF"
                                                    font.pixelSize: 13
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
                            implicitHeight: perfCol1.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: perfCol1
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: "Performance Enhancements"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
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


                                // Row 3: Gamescope Micro-Compositor (Customize Button + Toggle)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: 46
                                    spacing: 16
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        RowLayout {
                                            spacing: 8
                                            Label { text: "Gamescope Micro-Compositor"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                            Rectangle {
                                                visible: gamescopeToggle.checked && Boolean(uiController && uiController.diagnosticsManager && !uiController.diagnosticsManager.gamescopeAvailable)
                                                implicitWidth: gsWarnLbl.implicitWidth + 12
                                                implicitHeight: 20
                                                radius: 10
                                                color: Qt.rgba(0.96, 0.62, 0.04, 0.16)
                                                border.color: Qt.rgba(0.96, 0.62, 0.04, 0.45)
                                                Label {
                                                    id: gsWarnLbl
                                                    anchors.centerIn: parent
                                                    text: "Not installed"
                                                    color: appSettings.isEffectiveDark ? "#fcd34d" : "#92400e"
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: gamescopeToggle.checked
                                                ? ("Active: " + root.formatGamescopeSummary())
                                                : "Isolates display resolution, FSR/NIS upscaling, FPS cap, VRR, HDR & cursor grab"
                                            color: gamescopeToggle.checked ? appSettings.accentColor : appSettings.textSecColor
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                    RowLayout {
                                        spacing: 12
                                        M3Button {
                                            id: gamescopeCustomizeBtn
                                            objectName: "gamescopeCustomizeBtn"
                                            visible: gamescopeToggle.checked
                                            text: "Customize…"
                                            iconSymbol: "tune"
                                            buttonType: "tonal"
                                            onClicked: {
                                                gamescopeDialog.openWithConfig(root.gamescopeDraft, {
                                                    isGlobal: false,
                                                    title: root.gameData.title || "",
                                                    useMangohud: mangohudToggle.checked,
                                                    targetCommand: root.gameData.title || "<game>"
                                                })
                                            }
                                        }
                                        Toggle {
                                            id: gamescopeToggle
                                            objectName: "gamescopeToggle"
                                            checked: (root.gamescopeStateDraft === 1) ? true : ((root.gamescopeStateDraft === 0) ? false : appSettings.gamescopeDefault)
                                            onToggled: (c) => {
                                                root.gamescopeStateDraft = c ? 1 : 0
                                                root.saveAllChanges()
                                            }
                                        }
                                    }
                                }


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
                            implicitHeight: ctrlCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: ctrlCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: "Controller & Gamepad"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
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
                            implicitHeight: autoCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: autoCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: "Automation Scripts"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
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
                                            iconSymbol: "folder_open"
                                            buttonType: "tonal"
                                            onClicked: {
                                                let p = uiController.selectFile("Select Pre-Launch Script", "Shell Scripts (*.sh *.bash);;All Files (*)", preScriptField.text)
                                                if (p && p.length > 0) { preScriptField.text = p; root.saveAllChanges() }
                                            }
                                        }
                                    }
                                }


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
                                            iconSymbol: "folder_open"
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
                            implicitHeight: artCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: artCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: 2

                                    Label {
                                        text: "SteamGridDB Automatic Artwork & Manual Overrides"
                                        color: appSettings.accentColor
                                        font.family: "Rubik"
                                        font.pixelSize: 17
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }

                                    M3Button {
                                        id: autoFetchArtBtn
                                        text: "Auto-Fetch Artwork"
                                        iconSymbol: "refresh"
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
                                        color: appSettings.surfaceContainerHigh
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: root.gameData.coverPath || ""
                                            sourceSize.width: 96
                                            sourceSize.height: 144
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
                                            iconSymbol: "download"
                                            buttonType: "tonal"
                                            onClicked: artworkUrlDialog.openFor(root.gameId, "cover", "Cover Poster")
                                        }
                                        M3Button {
                                            id: coverBrowseBtn
                                            text: "Browse…"
                                            iconSymbol: "folder_open"
                                            buttonType: "tonal"
                                            onClicked: {
                                                let p = uiController.selectFile("Select Poster Image", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                                if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, p, "", "", "")
                                            }
                                        }
                                    }
                                }


                                // Row 2: Hero Banner (1920×620)
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    spacing: 16

                                    Rectangle {
                                        Layout.preferredWidth: 84
                                        Layout.preferredHeight: 38
                                        radius: 8
                                        color: appSettings.surfaceContainerHigh
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: root.gameData.bannerPath || ""
                                            sourceSize.width: 192
                                            sourceSize.height: 96
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
                                            iconSymbol: "download"
                                            buttonType: "tonal"
                                            onClicked: artworkUrlDialog.openFor(root.gameId, "banner", "Hero Banner")
                                        }
                                        M3Button {
                                            id: bannerBrowseBtn
                                            text: "Browse…"
                                            iconSymbol: "folder_open"
                                            buttonType: "tonal"
                                            onClicked: {
                                                let p = uiController.selectFile("Select Hero Banner", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                                if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, "", p, "", "")
                                            }
                                        }
                                    }
                                }


                                // Row 3: Transparent Logo
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    spacing: 16

                                    Rectangle {
                                        Layout.preferredWidth: 70
                                        Layout.preferredHeight: 38
                                        radius: 8
                                        color: appSettings.surfaceContainerHigh
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: root.gameData.logoPath || ""
                                            sourceSize.width: 160
                                            sourceSize.height: 96
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
                                            iconSymbol: "download"
                                            buttonType: "tonal"
                                            onClicked: artworkUrlDialog.openFor(root.gameId, "logo", "Transparent Logo")
                                        }
                                        M3Button {
                                            id: logoBrowseBtn
                                            text: "Browse…"
                                            iconSymbol: "folder_open"
                                            buttonType: "tonal"
                                            onClicked: {
                                                let p = uiController.selectFile("Select Logo Image", "Images (*.png *.jpg *.jpeg *.webp *.svg *.ico);;All Files (*)")
                                                if (p && p.length > 0) uiController.gameManager.setGameArtwork(root.gameId, "", "", p, "")
                                            }
                                        }
                                    }
                                }


                                // Row 4: Shortcut Icon
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    spacing: 16

                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 44
                                        radius: 8
                                        color: appSettings.surfaceContainerHigh
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: root.gameData.iconPath || ""
                                            sourceSize.width: 96
                                            sourceSize.height: 96
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
                                            iconSymbol: "download"
                                            buttonType: "tonal"
                                            onClicked: artworkUrlDialog.openFor(root.gameId, "icon", "Shortcut Icon")
                                        }
                                        M3Button {
                                            id: iconBrowseBtn
                                            text: "Browse…"
                                            iconSymbol: "folder_open"
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
                            implicitHeight: logCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: logCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: "Execution Console Log" + ((root.gameData.title && root.gameData.title.length > 0) ? (" — " + root.gameData.title) : "")
                                        color: appSettings.accentColor
                                        font.family: "Rubik"
                                        font.pixelSize: 17
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }
                                    M3Button {
                                        id: exportLogBtn
                                        text: "Export Log"
                                        iconSymbol: "shortcut"
                                        buttonType: "tonal"
                                        onClicked: uiController.diagnosticsManager.exportGameLog(root.gameId, "")
                                    }
                                    M3Button {
                                        id: clearLogBtn
                                        text: "Clear"
                                        iconSymbol: "delete"
                                        buttonType: "destructive"
                                        onClicked: uiController.diagnosticsManager.clearGameLog(root.gameId)
                                    }
                                }

                                Rectangle {
                                    id: logAreaWrap
                                    focus: true
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 320
                                    radius: 14
                                    color: "#08080b"
                                    readonly property bool kbFocused: logAreaWrap.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                                    border.color: appSettings.accentColor
                                    border.width: logAreaWrap.kbFocused ? 2 : 0
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
                                            font.family: "JetBrains Mono NF"
                                            font.pixelSize: 12
                                            wrapMode: TextEdit.Wrap
                                            background: null
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // TAB 5: Epic & Online / Anti-Cheat
                    ColumnLayout {
                        id: tab5Online
                        objectName: "detailOnlineTab"
                        Layout.fillWidth: true
                        width: tabStack.width
                        spacing: 16

                        // Card 1: Online Authentication, EOS Overlay & Anti-Cheat Runtimes
                        Rectangle {
                            visible: root.isEpicEntry
                            Layout.fillWidth: true
                            implicitHeight: onlineCardCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: onlineCardCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 18

                                Label {
                                    text: root.isEpicEntry ? "Epic Online Services & Anti-Cheat" : "Online & Anti-Cheat Runtimes"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
                                }

                                // Epic Online Auth Toggle (for installed Epic Games)
                                RowLayout {
                                    visible: root.isEpicEntry && !root.isUninstalledEpic
                                    Layout.fillWidth: true
                                    spacing: 16

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            text: "Epic Online Authentication"
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }
                                        Label {
                                            text: "Pass an Epic Games single-use auth exchange token when launching online"
                                            color: appSettings.textSecColor
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Toggle {
                                        id: epicOnlineAuthToggle
                                        checked: !Boolean(root.gameData.epicOfflineMode)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                // EOS Social Overlay Toggle
                                RowLayout {
                                    visible: root.isEpicEntry && !root.isUninstalledEpic && !root.isNative
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            text: "EOS Social Overlay"
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }
                                        Label {
                                            text: (uiController && uiController.epicService && uiController.epicService.isInstallingEosOverlay)
                                                ? ("Installing EOS Overlay… (" + Math.round(Number(uiController.epicService.eosOverlayProgress || 0)) + "%)")
                                                : ((uiController && uiController.epicService && uiController.epicService.eosOverlayInstalled)
                                                    ? "Enable Epic Online Services social overlay (friends & invites) — press Shift+F3 in-game to open"
                                                    : "EOS Overlay is not installed yet — install once to enable Epic social overlay (Shift+F3 in-game)")
                                            color: appSettings.textSecColor
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    M3Button {
                                        visible: Boolean(uiController && uiController.epicService && !uiController.epicService.eosOverlayInstalled)
                                        enabled: Boolean(uiController && uiController.epicService && !uiController.epicService.isInstallingEosOverlay)
                                        text: (uiController && uiController.epicService && uiController.epicService.isInstallingEosOverlay) ? "Installing…" : "Install"
                                        buttonType: "tonal"
                                        onClicked: if (uiController && uiController.epicService) uiController.epicService.installEosOverlay()
                                    }

                                    Toggle {
                                        id: eosOverlayToggle
                                        objectName: "eosOverlayToggle"
                                        checked: Boolean(root.gameData.enableEosOverlay)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                // Proton EasyAntiCheat Runtime Toggle
                                RowLayout {
                                    visible: root.isEpicEntry && !root.isUninstalledEpic && !root.isNative
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            text: "EasyAntiCheat Runtime (EAC)"
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }
                                        Label {
                                            text: (uiController && uiController.runnerManager && uiController.runnerManager.isInstallingEac)
                                                ? "Downloading Proton EasyAntiCheat Runtime…"
                                                : ((uiController && uiController.runnerManager && uiController.runnerManager.eacRuntimeAvailable)
                                                    ? "Set PROTON_EAC_RUNTIME for online EasyAntiCheat multiplayer titles"
                                                    : "EAC runtime not found (uses Steam or 1-click install below)")
                                            color: appSettings.textSecColor
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    M3Button {
                                        visible: Boolean(uiController && uiController.runnerManager && !uiController.runnerManager.eacRuntimeAvailable)
                                        enabled: Boolean(uiController && uiController.runnerManager && !uiController.runnerManager.isInstallingEac)
                                        text: (uiController && uiController.runnerManager && uiController.runnerManager.isInstallingEac) ? "Installing…" : "Install"
                                        buttonType: "tonal"
                                        onClicked: if (uiController && uiController.runnerManager) uiController.runnerManager.installAntiCheatRuntime("eac_runtime")
                                    }

                                    Toggle {
                                        id: eacRuntimeToggle
                                        objectName: "eacRuntimeToggle"
                                        enabled: root.isEpicEntry && !root.isUninstalledEpic && !root.isNative
                                        checked: Boolean(root.isEpicEntry && root.gameData.enableEacRuntime)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                // Proton BattlEye Runtime Toggle
                                RowLayout {
                                    visible: root.isEpicEntry && !root.isUninstalledEpic && !root.isNative
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            text: "BattlEye Runtime"
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }
                                        Label {
                                            text: (uiController && uiController.runnerManager && uiController.runnerManager.isInstallingBattleye)
                                                ? "Downloading Proton BattlEye Runtime…"
                                                : ((uiController && uiController.runnerManager && uiController.runnerManager.battleyeRuntimeAvailable)
                                                    ? "Set PROTON_BATTLEYE_RUNTIME for online BattlEye multiplayer titles"
                                                    : "BattlEye runtime not found (uses Steam or 1-click install below)")
                                            color: appSettings.textSecColor
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    M3Button {
                                        visible: Boolean(uiController && uiController.runnerManager && !uiController.runnerManager.battleyeRuntimeAvailable)
                                        enabled: Boolean(uiController && uiController.runnerManager && !uiController.runnerManager.isInstallingBattleye)
                                        text: (uiController && uiController.runnerManager && uiController.runnerManager.isInstallingBattleye) ? "Installing…" : "Install"
                                        buttonType: "tonal"
                                        onClicked: if (uiController && uiController.runnerManager) uiController.runnerManager.installAntiCheatRuntime("battleye_runtime")
                                    }

                                    Toggle {
                                        id: battleyeRuntimeToggle
                                        objectName: "battleyeRuntimeToggle"
                                        enabled: root.isEpicEntry && !root.isUninstalledEpic && !root.isNative
                                        checked: Boolean(root.isEpicEntry && root.gameData.enableBattlEyeRuntime)
                                        onToggled: root.saveAllChanges()
                                    }
                                }
                            }
                        }

                        // Card 2: Epic Cloud Saves (Installed Epic Games)
                        Rectangle {
                            visible: root.isEpicEntry && !root.isUninstalledEpic
                            Layout.fillWidth: true
                            implicitHeight: epicCloudCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: epicCloudCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 16

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: "Epic Cloud Saves"
                                        color: appSettings.accentColor
                                        font.family: "Rubik"
                                        font.pixelSize: 17
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }
                                    M3Button {
                                        visible: Boolean(root.gameData.hasUpdate)
                                        text: "Update Available"
                                        iconSymbol: "download"
                                        buttonType: "filled"
                                        onClicked: if (uiController && uiController.epicService) uiController.epicService.updateGame(root.gameId)
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 16
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label { text: "Enable Epic Cloud Saves"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                                        Label {
                                            text: root.cloudStatus.localSaveDir
                                                ? ("Save folder: " + root.cloudStatus.localSaveDir + " (" + (root.cloudStatus.localFileCount || 0) + " files)")
                                                : "Configure or override the save path below to sync saves with Epic Cloud Storage"
                                            color: appSettings.textSecColor
                                            font.pixelSize: 12
                                            elide: Text.ElideMiddle
                                            Layout.fillWidth: true
                                        }
                                    }
                                    M3Button {
                                        visible: Boolean(root.cloudStatus.localSaveDir && String(root.cloudStatus.localSaveDir).length > 0)
                                        text: "Open Folder"
                                        iconSymbol: "folder_open"
                                        buttonType: "tonal"
                                        onClicked: if (uiController && uiController.cloudSaveService) uiController.cloudSaveService.openSaveFolder(root.gameId)
                                    }
                                    Toggle {
                                        id: cloudEnabledToggle
                                        objectName: "detailCloudEnabledToggle"
                                        checked: Boolean(root.gameData.epicCloudSavesEnabled)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                RowLayout {
                                    visible: cloudEnabledToggle.checked
                                    Layout.fillWidth: true
                                    spacing: 16
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            text: "Auto-Sync Before Launch & After Exit"
                                            color: appSettings.textColor
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: "Always pauses on conflict and backs up local saves before overwriting"
                                            color: appSettings.textSecColor
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                    Toggle {
                                        id: cloudAutoSyncToggle
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        checked: Boolean(root.gameData.epicAutoSyncCloudSaves)
                                        onToggled: root.saveAllChanges()
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Label { text: "Custom Save Folder Override (optional)"; color: appSettings.textColor; font.pixelSize: 13; font.weight: Font.Medium }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        M3TextField {
                                            id: cloudFolderOverrideField
                                            Layout.fillWidth: true
                                            text: root.gameData.epicCloudSaveFolder || ""
                                            placeholderText: "{AppData}/GameName/Saved"
                                            onCommit: root.saveAllChanges()
                                        }
                                        M3Button {
                                            text: "Browse…"
                                            iconSymbol: "folder_open"
                                            buttonType: "tonal"
                                            onClicked: {
                                                const d = uiController.selectFolder("Select Custom Save Folder", cloudFolderOverrideField.text)
                                                if (d && d.length > 0) {
                                                    cloudFolderOverrideField.text = d
                                                    root.saveAllChanges()
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    visible: cloudEnabledToggle.checked
                                    Layout.fillWidth: true
                                    spacing: 8
                                    M3Button {
                                        text: "Sync Now"
                                        iconSymbol: "refresh"
                                        buttonType: "filled"
                                        onClicked: {
                                            root.saveAllChanges()
                                            if (uiController && uiController.cloudSaveService) uiController.cloudSaveService.syncGameSaves(root.gameId, "auto")
                                        }
                                    }
                                    M3Button {
                                        text: "Force Download"
                                        iconSymbol: "download"
                                        buttonType: "tonal"
                                        onClicked: {
                                            root.saveAllChanges()
                                            if (uiController && uiController.cloudSaveService) uiController.cloudSaveService.syncGameSaves(root.gameId, "download")
                                        }
                                    }
                                    M3Button {
                                        text: "Force Upload"
                                        buttonType: "tonal"
                                        onClicked: {
                                            root.saveAllChanges()
                                            if (uiController && uiController.cloudSaveService) uiController.cloudSaveService.syncGameSaves(root.gameId, "upload")
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                // Safety Snapshots Restore Row
                                RowLayout {
                                    visible: root.cloudSnapshots && root.cloudSnapshots.length > 0
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Label {
                                        text: "Safety Snapshots:"
                                        color: appSettings.textSecColor
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    StyledCombo {
                                        id: cloudSnapshotsCombo
                                        Layout.fillWidth: true
                                        comboModel: {
                                            let out = []
                                            for (let i = 0; i < root.cloudSnapshots.length; ++i) {
                                                out.push(root.cloudSnapshots[i].fileName + " (" + root.cloudSnapshots[i].sizeFormatted + ")")
                                            }
                                            return out
                                        }
                                        selectedIndex: 0
                                    }
                                    M3Button {
                                        text: "Restore"
                                        buttonType: "tonal"
                                        onClicked: {
                                            if (uiController && uiController.cloudSaveService && cloudSnapshotsCombo.selectedIndex >= 0 && cloudSnapshotsCombo.selectedIndex < root.cloudSnapshots.length) {
                                                uiController.cloudSaveService.restoreLocalSnapshot(root.gameId, root.cloudSnapshots[cloudSnapshotsCombo.selectedIndex].path)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Card 3: Owned DLCs (Installed Epic Games)
                        Rectangle {
                            visible: root.isEpicEntry && !root.isUninstalledEpic && root.gameDlcs && root.gameDlcs.length > 0
                            Layout.fillWidth: true
                            implicitHeight: epicDlcsCardCol.implicitHeight + 48
                            radius: 24
                            color: appSettings.surfaceContainerLow

                            ColumnLayout {
                                id: epicDlcsCardCol
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 12

                                Label {
                                    text: "Owned DLCs (" + (root.gameDlcs ? root.gameDlcs.length : 0) + ")"
                                    color: appSettings.accentColor
                                    font.family: "Rubik"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
                                }

                                Repeater {
                                    model: root.gameDlcs || []
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Label {
                                            Layout.fillWidth: true
                                            text: String(modelData.title || modelData.dlcAppName || "")
                                            color: appSettings.textColor
                                            font.pixelSize: 13
                                            elide: Text.ElideRight
                                        }
                                        M3Button {
                                            text: modelData.isInstalled ? "Installed ✓" : "Install DLC"
                                            buttonType: modelData.isInstalled ? "tonal" : "filled"
                                            enabled: !modelData.isInstalled
                                            implicitHeight: 30
                                            onClicked: if (uiController && uiController.epicService) uiController.epicService.installDlc(root.gameId, String(modelData.dlcAppName))
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
            color: backBtn.isBtnActive ? accent : appSettings.surfaceContainerHigh
            border.width: 0
            scale: backBtn.pressed ? 0.96 : (backBtn.kbFocused ? 1.02 : 1.0)
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 100 } }

            layer.enabled: backBtn.visible
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
                        size: 20
                        symbol: "arrow_back"
                        color: backBtn.isBtnActive ? appSettings.onPrimary : appSettings.accentColor
                    }
                }

                Label {
                    id: backLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Back"
                    color: backBtn.isBtnActive ? appSettings.onPrimary : appSettings.accentColor
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
        onGameRemoved: root.backRequested()
    }

    EpicDownloadDialog {
        id: epicDownloadDialog
        onDownloadStarted: {
            if (uiController && uiController.epicService && root.epicAppName.length > 0) {
                root.epicData = uiController.epicService.getEpicGameMap(root.epicAppName)
            }
        }
    }

    EpicImportDialog {
        id: epicImportDialog
        onImportStarted: {
            if (uiController && uiController.epicService && root.epicAppName.length > 0) {
                root.epicData = uiController.epicService.getEpicGameMap(root.epicAppName)
            }
        }
    }

    GamescopeDialog {
        id: gamescopeDialog
        objectName: "gamescopeDialog"
        onSaveRequested: (cfgMap) => {
            root.gamescopeStateDraft = 1
            root.gamescopeDraft = cfgMap
            root.saveAllChanges()
        }
        onResetToGlobalRequested: {
            let defMap = Object.assign({}, (appSettings && appSettings.defaultGamescopeConfig) ? appSettings.defaultGamescopeConfig : ({}))
            defMap.inheritGlobal = true
            root.gamescopeDraft = defMap
            root.saveAllChanges()
        }
        Timer {
            id: restoreGamescopeFocusTimer
            interval: 0
            repeat: false
            onTriggered: {
                if (typeof gamescopeCustomizeBtn !== "undefined" && gamescopeCustomizeBtn && gamescopeCustomizeBtn.visible) {
                    gamescopeCustomizeBtn.forceActiveFocus()
                } else if (typeof gamescopeToggle !== "undefined" && gamescopeToggle) {
                    gamescopeToggle.forceActiveFocus()
                }
            }
        }
        onClosed: restoreGamescopeFocusTimer.restart()
    }
}
