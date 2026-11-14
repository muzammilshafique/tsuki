import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 48 : 740, 740)
    height: Math.min(parent ? parent.height - 40 : 680, 680)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property bool isGlobalMode: false
    property string gameTitle: ""
    property string targetCommandPreview: ""
    property bool previewUseMangohud: false

    // Working draft state
    property string windowMode: "fullscreen"
    property int outputWidth: 0
    property int outputHeight: 0
    property bool outputCustomSelected: false
    property int internalWidth: 0
    property int internalHeight: 0
    property bool internalCustomSelected: false
    property string filter: "auto"
    property int fsrSharpness: 2
    property string scaler: "auto"
    property int fpsLimit: 0
    property bool fpsCustomSelected: false
    property int unfocusedFpsLimit: 0
    property bool adaptiveSync: false
    property bool hdrEnabled: false
    property bool forceGrabCursor: false
    property real mouseSensitivity: 1.0
    property bool mangoapp: true
    property string backend: "auto"
    property bool exposeWayland: false
    property string extraArgs: ""

    signal saveRequested(var configMap)
    signal resetToGlobalRequested()

    readonly property var outputResOptions: [
        { label: "Auto (Native)", w: 0, h: 0 },
        { label: "1280 × 720 (720p)", w: 1280, h: 720 },
        { label: "1920 × 1080 (1080p)", w: 1920, h: 1080 },
        { label: "2560 × 1080 (UW 1080p)", w: 2560, h: 1080 },
        { label: "2560 × 1440 (1440p)", w: 2560, h: 1440 },
        { label: "3440 × 1440 (UW 1440p)", w: 3440, h: 1440 },
        { label: "3840 × 2160 (4K UHD)", w: 3840, h: 2160 },
        { label: "Custom…", w: -1, h: -1 }
    ]

    readonly property var internalResOptions: [
        { label: "Match Output", w: 0, h: 0 },
        { label: "960 × 540 (qHD)", w: 960, h: 540 },
        { label: "1280 × 720 (720p)", w: 1280, h: 720 },
        { label: "1280 × 800 (16:10)", w: 1280, h: 800 },
        { label: "1600 × 900 (900p)", w: 1600, h: 900 },
        { label: "1920 × 1080 (1080p)", w: 1920, h: 1080 },
        { label: "2560 × 1440 (1440p)", w: 2560, h: 1440 },
        { label: "Custom…", w: -1, h: -1 }
    ]

    readonly property var filterOptions: [
        { label: "Default (Auto)", value: "auto" },
        { label: "AMD FSR 1.0 (fsr)", value: "fsr" },
        { label: "NVIDIA NIS (nis)", value: "nis" },
        { label: "Snapdragon SGSR (sgsr)", value: "sgsr" },
        { label: "Pixel Art (pixel)", value: "pixel" },
        { label: "Nearest Neighbor", value: "nearest" },
        { label: "Linear", value: "linear" }
    ]

    readonly property var scalerOptions: [
        { label: "Auto", value: "auto" },
        { label: "Fit (Letterbox)", value: "fit" },
        { label: "Fill (Crop)", value: "fill" },
        { label: "Stretch", value: "stretch" },
        { label: "Integer (Pixel-Exact)", value: "integer" }
    ]

    readonly property var fpsOptions: [0, 30, 40, 60, 90, 120, 144, 165, -1]
    readonly property var unfocusedFpsOptions: [0, 15, 30, 60]
    readonly property var backendOptions: [
        { label: "Auto", value: "auto" },
        { label: "Wayland", value: "wayland" },
        { label: "SDL", value: "sdl" },
        { label: "DRM", value: "drm" }
    ]

    readonly property bool sharpnessVisible: filter === "fsr" || filter === "nis" || filter === "sgsr"

    function labelsOf(optList) {
        let out = []
        for (let i = 0; i < optList.length; i++) out.push(optList[i].label)
        return out
    }

    function indexOfResPreset(optList, w, h, isCustomSelected) {
        if (isCustomSelected) return optList.length - 1
        for (let i = 0; i < optList.length - 1; i++) {
            if (optList[i].w === w && optList[i].h === h) return i
        }
        return optList.length - 1
    }

    function indexOfOptionValue(optList, val) {
        for (let i = 0; i < optList.length; i++) {
            if (optList[i].value === val) return i
        }
        return 0
    }

    function indexOfFps(val, isCustomSelected) {
        if (isCustomSelected) return fpsOptions.length - 1
        for (let i = 0; i < fpsOptions.length - 1; i++) {
            if (fpsOptions[i] === val) return i
        }
        return fpsOptions.length - 1
    }

    function loadFromMap(cfgMap) {
        let m = cfgMap || {}
        windowMode = (m.windowMode === "borderless" || m.windowMode === "windowed") ? m.windowMode : "fullscreen"
        outputWidth = Number(m.outputWidth) || 0
        outputHeight = Number(m.outputHeight) || 0
        outputCustomSelected = (indexOfResPreset(outputResOptions, outputWidth, outputHeight, false) === outputResOptions.length - 1)

        internalWidth = Number(m.internalWidth) || 0
        internalHeight = Number(m.internalHeight) || 0
        internalCustomSelected = (indexOfResPreset(internalResOptions, internalWidth, internalHeight, false) === internalResOptions.length - 1)

        filter = m.filter || "auto"
        fsrSharpness = (m.fsrSharpness !== undefined) ? Math.max(0, Math.min(20, Number(m.fsrSharpness))) : 2
        scaler = m.scaler || "auto"
        fpsLimit = Number(m.fpsLimit) || 0
        fpsCustomSelected = (indexOfFps(fpsLimit, false) === fpsOptions.length - 1)
        unfocusedFpsLimit = Number(m.unfocusedFpsLimit) || 0
        adaptiveSync = Boolean(m.adaptiveSync)
        hdrEnabled = Boolean(m.hdrEnabled)
        forceGrabCursor = Boolean(m.forceGrabCursor)
        mouseSensitivity = (m.mouseSensitivity !== undefined) ? Number(m.mouseSensitivity) : 1.0
        mangoapp = (m.mangoapp !== undefined) ? Boolean(m.mangoapp) : true
        backend = m.backend || "auto"
        exposeWayland = Boolean(m.exposeWayland)
        extraArgs = m.extraArgs || ""

        outputWField.text = outputWidth > 0 ? String(outputWidth) : ""
        outputHField.text = outputHeight > 0 ? String(outputHeight) : ""
        internalWField.text = internalWidth > 0 ? String(internalWidth) : ""
        internalHField.text = internalHeight > 0 ? String(internalHeight) : ""
        customFpsField.text = fpsLimit > 0 ? String(fpsLimit) : ""
        extraArgsField.text = extraArgs
        sharpnessSlider.value = fsrSharpness
        mouseSensSlider.value = mouseSensitivity
    }

    function applyPreset(presetName) {
        if (presetName === "borderless") {
            loadFromMap({
                windowMode: "borderless",
                outputWidth: 0, outputHeight: 0,
                internalWidth: 0, internalHeight: 0,
                filter: "auto", fsrSharpness: 2, scaler: "auto",
                fpsLimit: 0, unfocusedFpsLimit: 0,
                adaptiveSync: false, hdrEnabled: false, forceGrabCursor: false,
                mouseSensitivity: 1.0, mangoapp: true, backend: "auto",
                exposeWayland: false, extraArgs: ""
            })
        } else if (presetName === "fsr720") {
            loadFromMap({
                windowMode: "fullscreen",
                outputWidth: 1920, outputHeight: 1080,
                internalWidth: 1280, internalHeight: 720,
                filter: "fsr", fsrSharpness: 3, scaler: "auto",
                fpsLimit: fpsLimit, unfocusedFpsLimit: unfocusedFpsLimit,
                adaptiveSync: adaptiveSync, hdrEnabled: hdrEnabled, forceGrabCursor: forceGrabCursor,
                mouseSensitivity: mouseSensitivity, mangoapp: mangoapp, backend: backend,
                exposeWayland: exposeWayland, extraArgs: extraArgs
            })
        } else if (presetName === "fsr1080") {
            loadFromMap({
                windowMode: "fullscreen",
                outputWidth: 2560, outputHeight: 1440,
                internalWidth: 1920, internalHeight: 1080,
                filter: "fsr", fsrSharpness: 3, scaler: "auto",
                fpsLimit: fpsLimit, unfocusedFpsLimit: unfocusedFpsLimit,
                adaptiveSync: adaptiveSync, hdrEnabled: hdrEnabled, forceGrabCursor: forceGrabCursor,
                mouseSensitivity: mouseSensitivity, mangoapp: mangoapp, backend: backend,
                exposeWayland: exposeWayland, extraArgs: extraArgs
            })
        } else if (presetName === "pixel") {
            loadFromMap({
                windowMode: "fullscreen",
                outputWidth: 0, outputHeight: 0,
                internalWidth: 0, internalHeight: 0,
                filter: "pixel", fsrSharpness: 0, scaler: "integer",
                fpsLimit: 0, unfocusedFpsLimit: 0,
                adaptiveSync: false, hdrEnabled: false, forceGrabCursor: false,
                mouseSensitivity: 1.0, mangoapp: mangoapp, backend: "auto",
                exposeWayland: false, extraArgs: ""
            })
        }
    }

    function buildConfigMap() {
        let outW = outputCustomSelected ? (parseInt(outputWField.text, 10) || 0) : outputWidth
        let outH = outputCustomSelected ? (parseInt(outputHField.text, 10) || 0) : outputHeight
        let intW = internalCustomSelected ? (parseInt(internalWField.text, 10) || 0) : internalWidth
        let intH = internalCustomSelected ? (parseInt(internalHField.text, 10) || 0) : internalHeight
        let fps = fpsCustomSelected ? (parseInt(customFpsField.text, 10) || 0) : fpsLimit
        return {
            inheritGlobal: false,
            windowMode: windowMode,
            outputWidth: Math.max(0, outW),
            outputHeight: Math.max(0, outH),
            internalWidth: Math.max(0, intW),
            internalHeight: Math.max(0, intH),
            filter: filter,
            fsrSharpness: Math.max(0, Math.min(20, Math.round(sharpnessSlider.value))),
            scaler: scaler,
            fpsLimit: Math.max(0, fps),
            unfocusedFpsLimit: Math.max(0, unfocusedFpsLimit),
            adaptiveSync: adaptiveSync,
            hdrEnabled: hdrEnabled,
            forceGrabCursor: forceGrabCursor,
            mouseSensitivity: Math.round(mouseSensSlider.value * 10) / 10,
            mangoapp: mangoapp,
            backend: backend,
            exposeWayland: exposeWayland,
            extraArgs: extraArgsField.text.trim()
        }
    }

    function openWithConfig(cfgMap, opts) {
        let o = opts || {}
        isGlobalMode = Boolean(o.isGlobal)
        gameTitle = o.title || ""
        targetCommandPreview = o.targetCommand || ""
        previewUseMangohud = Boolean(o.useMangohud)

        let sourceMap = cfgMap
        if (!isGlobalMode && (!sourceMap || sourceMap.inheritGlobal === true)) {
            sourceMap = appSettings ? appSettings.defaultGamescopeConfig : cfgMap
        }
        loadFromMap(sourceMap)
        if (dialogScroll && dialogScroll.contentItem) {
            dialogScroll.contentItem.contentY = 0
        }
        root.open()
        Qt.callLater(() => presetBorderlessBtn.forceActiveFocus())
    }

    Connections {
        target: uiController ? uiController.controllerManager : null
        enabled: root.opened
        function onSearchActionRequested() {
            if (root.isAnyComboPopupOpen()) return
            saveBtn.clicked()
        }
    }

    function isAnyComboPopupOpen() {
        return outputResCombo.popup.visible
            || internalResCombo.popup.visible
            || filterCombo.popup.visible
            || scalerCombo.popup.visible
            || fpsCombo.popup.visible
            || unfocusedFpsCombo.popup.visible
            || backendCombo.popup.visible
    }

    function closeOpenComboPopup() {
        const combos = [outputResCombo, internalResCombo, filterCombo, scalerCombo, fpsCombo, unfocusedFpsCombo, backendCombo]
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
        return outputWField.isEditing
            || outputHField.isEditing
            || internalWField.isEditing
            || internalHField.isEditing
            || customFpsField.isEditing
            || extraArgsField.isEditing
    }

    function getFocusGrid() {
        let rows = [
            [presetBorderlessBtn, presetFsr720Btn, presetFsr1440Btn, presetPixelBtn],
            [windowModeSeg],
            [outputResCombo]
        ]
        if (outputCustomSelected) {
            rows.push([outputWField, outputHField])
        }
        rows.push([internalResCombo])
        if (internalCustomSelected) {
            rows.push([internalWField, internalHField])
        }
        rows.push([filterCombo])
        if (sharpnessVisible) {
            rows.push([sharpnessSlider])
        }
        rows.push([scalerCombo])
        rows.push([fpsCombo])
        if (fpsCustomSelected) {
            rows.push([customFpsField])
        }
        rows.push([unfocusedFpsCombo])
        rows.push([adaptiveSyncToggle])
        rows.push([hdrToggle])
        rows.push([grabCursorToggle])
        rows.push([mouseSensSlider])
        rows.push([mangoappToggle])
        rows.push([backendCombo])
        rows.push([exposeWaylandToggle])
        rows.push([extraArgsField])
        rows.push([resetBtn, cancelBtn, saveBtn])
        return rows
    }

    function findFocusCoords(rows) {
        const fi = dialogCol.Window ? dialogCol.Window.activeFocusItem : null
        for (let r = 0; r < rows.length; r++) {
            for (let c = 0; c < rows[r].length; c++) {
                let it = rows[r][c]
                if (!it) continue
                if (it.activeFocus || (fi && fi === it) || (it.slider && it.slider.activeFocus)) {
                    return { r: r, c: c }
                }
            }
        }
        return { r: -1, c: 0 }
    }

    function scrollToControl(item) {
        if (!item || !dialogScroll || !dialogScroll.contentItem || !dialogCol) return
        if (item === resetBtn || item === cancelBtn || item === saveBtn) return
        let flick = dialogScroll.contentItem
        if (!flick || flick.contentY === undefined) return
        let p = item.mapToItem(dialogCol, 0, 0)
        let maxY = Math.max(0, flick.contentHeight - dialogScroll.height)
        let viewTop = flick.contentY
        let viewBottom = flick.contentY + dialogScroll.height
        let desiredY = flick.contentY
        if (p.y - 24 < viewTop) {
            desiredY = Math.max(0, p.y - 24)
        } else if (p.y + item.height + 24 > viewBottom) {
            desiredY = Math.min(maxY, p.y + item.height + 24 - dialogScroll.height)
        }
        if (Math.abs(desiredY - flick.contentY) > 1) {
            dialogScrollAnim.to = desiredY
            dialogScrollAnim.restart()
        }
    }

    function navigateStep(dr, dc) {
        if (isAnyComboPopupOpen()) return false
        let rows = getFocusGrid()
        let pos = findFocusCoords(rows)
        if (pos.r < 0) {
            presetBorderlessBtn.forceActiveFocus()
            scrollToControl(presetBorderlessBtn)
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

    function handleDialogKeyPress(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
            if (root.closeOpenComboPopup()) {
                event.accepted = true
                return
            }
            if (root.isAnyTextEditing()) return
            event.accepted = true
            root.close()
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

    NumberAnimation {
        id: dialogScrollAnim
        target: dialogScroll.contentItem
        property: "contentY"
        duration: 160
        easing.type: Easing.OutCubic
    }

    background: Rectangle {
        objectName: "gamescopeDialogBg"
        color: appSettings.surfaceColor
        radius: 12
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

        Keys.onEscapePressed: (event) => root.handleDialogKeyPress(event)
        Keys.onBackPressed: (event) => root.handleDialogKeyPress(event)
        Keys.onPressed: (event) => root.handleDialogKeyPress(event)

        // ── Dialog Header ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 68

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 20
                spacing: 12

                YIcon {
                    size: 22
                    source: "qrc:/tsuki_app/icons/actions/settings.svg"
                    color: appSettings.accentColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: root.isGlobalMode ? "Default Gamescope Parameters" : "Gamescope Settings"
                        color: appSettings.textColor
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.3
                    }
                    Label {
                        text: root.isGlobalMode
                            ? "Global defaults inherited by games unless overridden"
                            : (root.gameTitle.length > 0 ? ("Customize micro-compositor options for " + root.gameTitle) : "Customize micro-compositor options")
                        color: appSettings.textSecColor
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                ToolButton {
                    id: headerCloseBtn
                    focusPolicy: Qt.NoFocus
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

        // ── Missing Binary Notice (if not installed on host) ─────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 12
            implicitHeight: missingLbl.implicitHeight + 16
            radius: 10
            visible: Boolean(uiController && uiController.diagnosticsManager && !uiController.diagnosticsManager.gamescopeAvailable)
            color: Qt.rgba(0.96, 0.62, 0.04, appSettings.isEffectiveDark ? 0.16 : 0.12)
            border.color: Qt.rgba(0.96, 0.62, 0.04, 0.45)

            Label {
                id: missingLbl
                anchors.fill: parent
                anchors.margins: 8
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                text: "Note: 'gamescope' was not detected in PATH. Install gamescope using your Linux package manager before launching with these settings."
                color: appSettings.isEffectiveDark ? "#fcd34d" : "#92400e"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        // ── Scrollable Form Body ─────────────────────────────────────────────
        ScrollView {
            id: dialogScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            contentHeight: dialogCol.implicitHeight
            clip: true

            ColumnLayout {
                id: dialogCol
                width: Math.max(200, dialogScroll.availableWidth - 48)
                x: 24
                spacing: 16
                Keys.onPressed: (event) => root.handleDialogKeyPress(event)

                Item { Layout.preferredHeight: 2 }

                // ── Quick Presets ────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label {
                        text: "QUICK PRESETS"
                        color: appSettings.accentColor
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        M3Button {
                            id: presetBorderlessBtn
                            objectName: "gamescopePresetBorderlessBtn"
                            Layout.fillWidth: true
                            text: "Borderless Fix"
                            buttonType: "tonal"
                            onClicked: root.applyPreset("borderless")
                            onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                        }
                        M3Button {
                            id: presetFsr720Btn
                            Layout.fillWidth: true
                            text: "720p → 1080p FSR"
                            buttonType: "tonal"
                            onClicked: root.applyPreset("fsr720")
                            onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                        }
                        M3Button {
                            id: presetFsr1440Btn
                            Layout.fillWidth: true
                            text: "1080p → 1440p FSR"
                            buttonType: "tonal"
                            onClicked: root.applyPreset("fsr1080")
                            onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                        }
                        M3Button {
                            id: presetPixelBtn
                            Layout.fillWidth: true
                            text: "Pixel Integer"
                            buttonType: "tonal"
                            onClicked: root.applyPreset("pixel")
                            onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                // ── Display & Resolution ─────────────────────────────────────
                Label {
                    text: "DISPLAY & RESOLUTION"
                    color: appSettings.accentColor
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }

                // Window Mode
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label { text: "Window Mode"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                    Label { text: "Fullscreen (-f), Borderless (-b), or Windowed inside a nested desktop container"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    M3SegmentedButton {
                        id: windowModeSeg
                        objectName: "gamescopeWindowModeSeg"
                        Layout.fillWidth: true
                        model: [
                            { label: "Fullscreen", val: 0 },
                            { label: "Borderless", val: 1 },
                            { label: "Windowed", val: 2 }
                        ]
                        selectedValue: root.windowMode === "borderless" ? 1 : (root.windowMode === "windowed" ? 2 : 0)
                        onSelectionChanged: (val) => {
                            root.windowMode = (val === 1 ? "borderless" : (val === 2 ? "windowed" : "fullscreen"))
                        }
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                // Output Resolution
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Output Resolution (-W / -H)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Display resolution presented to your monitor"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    StyledCombo {
                        id: outputResCombo
                        objectName: "gamescopeOutputResCombo"
                        upDownNavigatesFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 230
                        comboModel: root.labelsOf(root.outputResOptions)
                        selectedIndex: root.indexOfResPreset(root.outputResOptions, root.outputWidth, root.outputHeight, root.outputCustomSelected)
                        onSelected: (idx) => {
                            if (idx >= 0 && idx < root.outputResOptions.length) {
                                let opt = root.outputResOptions[idx]
                                if (opt.w < 0) {
                                    const wVal = root.outputWidth > 0 ? root.outputWidth : 1920
                                    const hVal = root.outputHeight > 0 ? root.outputHeight : 1080
                                    root.outputCustomSelected = true
                                    outputWField.text = String(wVal)
                                    outputHField.text = String(hVal)
                                    root.outputWidth = wVal
                                    root.outputHeight = hVal
                                } else {
                                    root.outputCustomSelected = false
                                    root.outputWidth = opt.w
                                    root.outputHeight = opt.h
                                    outputWField.text = opt.w > 0 ? String(opt.w) : ""
                                    outputHField.text = opt.h > 0 ? String(opt.h) : ""
                                }
                            }
                        }
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.outputCustomSelected
                    Label {
                        text: "Custom Output W × H:"
                        color: appSettings.textSecColor
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    M3TextField {
                        id: outputWField
                        objectName: "gamescopeOutputWField"
                        twoStageFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 110
                        placeholderText: "Width"
                        onTextChanged: root.outputWidth = parseInt(text, 10) || 0
                        onCommit: (val) => root.outputWidth = parseInt(val, 10) || 0
                        onMoveUp: root.navigateStep(-1, 0)
                        onMoveDown: root.navigateStep(1, 0)
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                    Label { text: "×"; color: appSettings.textSecColor; font.pixelSize: 14; Layout.alignment: Qt.AlignVCenter }
                    M3TextField {
                        id: outputHField
                        twoStageFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 110
                        placeholderText: "Height"
                        onTextChanged: root.outputHeight = parseInt(text, 10) || 0
                        onCommit: (val) => root.outputHeight = parseInt(val, 10) || 0
                        onMoveUp: root.navigateStep(-1, 0)
                        onMoveDown: root.navigateStep(1, 0)
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                // Internal Render Resolution
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Game Render Resolution (-w / -h)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Lower than Output Resolution enables FSR/NIS upscaling for higher FPS"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    StyledCombo {
                        id: internalResCombo
                        upDownNavigatesFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 230
                        comboModel: root.labelsOf(root.internalResOptions)
                        selectedIndex: root.indexOfResPreset(root.internalResOptions, root.internalWidth, root.internalHeight, root.internalCustomSelected)
                        onSelected: (idx) => {
                            if (idx >= 0 && idx < root.internalResOptions.length) {
                                let opt = root.internalResOptions[idx]
                                if (opt.w < 0) {
                                    const wVal = root.internalWidth > 0 ? root.internalWidth : 1280
                                    const hVal = root.internalHeight > 0 ? root.internalHeight : 720
                                    root.internalCustomSelected = true
                                    internalWField.text = String(wVal)
                                    internalHField.text = String(hVal)
                                    root.internalWidth = wVal
                                    root.internalHeight = hVal
                                } else {
                                    root.internalCustomSelected = false
                                    root.internalWidth = opt.w
                                    root.internalHeight = opt.h
                                    internalWField.text = opt.w > 0 ? String(opt.w) : ""
                                    internalHField.text = opt.h > 0 ? String(opt.h) : ""
                                }
                            }
                        }
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.internalCustomSelected
                    Label {
                        text: "Custom Render W × H:"
                        color: appSettings.textSecColor
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    M3TextField {
                        id: internalWField
                        twoStageFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 110
                        placeholderText: "Width"
                        onTextChanged: root.internalWidth = parseInt(text, 10) || 0
                        onCommit: (val) => root.internalWidth = parseInt(val, 10) || 0
                        onMoveUp: root.navigateStep(-1, 0)
                        onMoveDown: root.navigateStep(1, 0)
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                    Label { text: "×"; color: appSettings.textSecColor; font.pixelSize: 14; Layout.alignment: Qt.AlignVCenter }
                    M3TextField {
                        id: internalHField
                        twoStageFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 110
                        placeholderText: "Height"
                        onTextChanged: root.internalHeight = parseInt(text, 10) || 0
                        onCommit: (val) => root.internalHeight = parseInt(val, 10) || 0
                        onMoveUp: root.navigateStep(-1, 0)
                        onMoveDown: root.navigateStep(1, 0)
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                // ── Upscaling & Scaling Filter ───────────────────────────────
                Label {
                    text: "UPSCALING & FILTER"
                    color: appSettings.accentColor
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Upscale Filter (-F)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "AMD FSR, NVIDIA NIS, or crisp Pixel Art scaling"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    StyledCombo {
                        id: filterCombo
                        upDownNavigatesFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 230
                        comboModel: root.labelsOf(root.filterOptions)
                        selectedIndex: root.indexOfOptionValue(root.filterOptions, root.filter)
                        onSelected: (idx) => {
                            if (idx >= 0 && idx < root.filterOptions.length) {
                                root.filter = root.filterOptions[idx].value
                            }
                        }
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: root.sharpnessVisible
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Upscale Sharpness (--fsr-sharpness)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "0 = maximum sharpness, 20 = softest (Gamescope scale)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    StyledSlider {
                        id: sharpnessSlider
                        objectName: "gamescopeSharpnessSlider"
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 230
                        from: 0
                        to: 20
                        stepSize: 1
                        decimals: 0
                        suffix: ""
                        slider.onMoved: root.fsrSharpness = Math.round(sharpnessSlider.value)
                        onMoveUp: root.navigateStep(-1, 0)
                        onMoveDown: root.navigateStep(1, 0)
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Aspect Scaling (-S)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "How the game image fits your display (Integer is ideal for retro games)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    StyledCombo {
                        id: scalerCombo
                        upDownNavigatesFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 230
                        comboModel: root.labelsOf(root.scalerOptions)
                        selectedIndex: root.indexOfOptionValue(root.scalerOptions, root.scaler)
                        onSelected: (idx) => {
                            if (idx >= 0 && idx < root.scalerOptions.length) {
                                root.scaler = root.scalerOptions[idx].value
                            }
                        }
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                // ── Frame Pacing & Sync ──────────────────────────────────────
                Label {
                    text: "FRAME PACING & VRR"
                    color: appSettings.accentColor
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "FPS / Refresh Cap (-r)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Limits game refresh rate inside Gamescope"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    StyledCombo {
                        id: fpsCombo
                        upDownNavigatesFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 180
                        comboModel: ["Unlimited", "30 FPS", "40 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS", "165 FPS", "Custom…"]
                        selectedIndex: root.indexOfFps(root.fpsLimit, root.fpsCustomSelected)
                        onSelected: (idx) => {
                            if (idx >= 0 && idx < root.fpsOptions.length) {
                                let v = root.fpsOptions[idx]
                                if (v < 0) {
                                    const fVal = root.fpsLimit > 0 ? root.fpsLimit : 60
                                    root.fpsCustomSelected = true
                                    customFpsField.text = String(fVal)
                                    root.fpsLimit = fVal
                                } else {
                                    root.fpsCustomSelected = false
                                    root.fpsLimit = v
                                    customFpsField.text = v > 0 ? String(v) : ""
                                }
                            }
                        }
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.fpsCustomSelected
                    Label {
                        text: "Custom FPS Cap:"
                        color: appSettings.textSecColor
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    M3TextField {
                        id: customFpsField
                        twoStageFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 140
                        placeholderText: "e.g. 75"
                        onTextChanged: root.fpsLimit = parseInt(text, 10) || 0
                        onCommit: (val) => root.fpsLimit = parseInt(val, 10) || 0
                        onMoveUp: root.navigateStep(-1, 0)
                        onMoveDown: root.navigateStep(1, 0)
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Background FPS Limit (-o)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Save GPU power when the game window is unfocused"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    StyledCombo {
                        id: unfocusedFpsCombo
                        upDownNavigatesFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 180
                        comboModel: ["Off", "15 FPS", "30 FPS", "60 FPS"]
                        selectedIndex: {
                            let idx = root.unfocusedFpsOptions.indexOf(root.unfocusedFpsLimit)
                            return idx >= 0 ? idx : 0
                        }
                        onSelected: (idx) => {
                            if (idx >= 0 && idx < root.unfocusedFpsOptions.length) {
                                root.unfocusedFpsLimit = root.unfocusedFpsOptions[idx]
                            }
                        }
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Adaptive Sync / VRR (--adaptive-sync)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Enable FreeSync / G-Sync variable refresh rate when supported"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    Toggle {
                        id: adaptiveSyncToggle
                        objectName: "gamescopeAdaptiveSyncToggle"
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        checked: root.adaptiveSync
                        onToggled: (c) => root.adaptiveSync = c
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                // ── Color, Input & Overlay ───────────────────────────────────
                Label {
                    text: "HDR, INPUT & OVERLAY"
                    color: appSettings.accentColor
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "HDR10 Output (--hdr-enabled)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Enables HDR output & DXVK_HDR=1 for Wine/Proton titles"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    Toggle {
                        id: hdrToggle
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        checked: root.hdrEnabled
                        onToggled: (c) => root.hdrEnabled = c
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Force Grab Cursor (--force-grab-cursor)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Traps mouse cursor inside the game window (fixes dual-monitor escape)"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    Toggle {
                        id: grabCursorToggle
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        checked: root.forceGrabCursor
                        onToggled: (c) => root.forceGrabCursor = c
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Mouse Sensitivity (-s)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Multiplier for relative mouse movement inside Gamescope"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    StyledSlider {
                        id: mouseSensSlider
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 230
                        from: 0.2
                        to: 3.0
                        stepSize: 0.1
                        decimals: 1
                        suffix: "x"
                        slider.onMoved: root.mouseSensitivity = Math.round(mouseSensSlider.value * 10) / 10
                        onMoveUp: root.navigateStep(-1, 0)
                        onMoveDown: root.navigateStep(1, 0)
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Integrate MangoHud via --mangoapp"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "When MangoHud is active, render it natively inside Gamescope's overlay layer"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    Toggle {
                        id: mangoappToggle
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        checked: root.mangoapp
                        onToggled: (c) => root.mangoapp = c
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05) }

                // ── Advanced ─────────────────────────────────────────────────
                Label {
                    text: "ADVANCED"
                    color: appSettings.accentColor
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Display Backend (--backend)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Auto works for most desktops; switch to Wayland/SDL if needed"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    StyledCombo {
                        id: backendCombo
                        upDownNavigatesFocus: true
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitWidth: 180
                        comboModel: root.labelsOf(root.backendOptions)
                        selectedIndex: root.indexOfOptionValue(root.backendOptions, root.backend)
                        onSelected: (idx) => {
                            if (idx >= 0 && idx < root.backendOptions.length) {
                                root.backend = root.backendOptions[idx].value
                            }
                        }
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Expose Wayland Socket (--expose-wayland)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Allow native Wayland apps to run directly over xdg-shell inside Gamescope"; color: appSettings.textSecColor; font.pixelSize: 12 }
                    }
                    Toggle {
                        id: exposeWaylandToggle
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        checked: root.exposeWayland
                        onToggled: (c) => root.exposeWayland = c
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label { text: "Extra Gamescope Arguments (Optional)"; color: appSettings.textColor; font.pixelSize: 14; font.weight: Font.Medium }
                    M3TextField {
                        id: extraArgsField
                        twoStageFocus: true
                        Layout.fillWidth: true
                        placeholderText: "e.g. --rt --hdr-itm-enabled -O DP-1"
                        onTextChanged: root.extraArgs = text
                        onCommit: (val) => root.extraArgs = val
                        onMoveUp: root.navigateStep(-1, 0)
                        onMoveDown: root.navigateStep(1, 0)
                        onActiveFocusChanged: if (activeFocus) root.scrollToControl(this)
                    }
                }

                // ── Command Preview ──────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: previewCol.implicitHeight + 18
                    radius: 8
                    color: appSettings.isEffectiveDark ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(0, 0, 0, 0.04)
                    border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                    ColumnLayout {
                        id: previewCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        Label {
                            text: "GENERATED COMMAND PREVIEW"
                            color: appSettings.textSecColor
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.7
                        }
                        Label {
                            Layout.fillWidth: true
                            text: {
                                if (!uiController || !uiController.launchPipeline) return "gamescope -- <game>"
                                // Reference reactive properties so preview updates live
                                const _tick = root.windowMode + "|" + root.outputWidth + "x" + root.outputHeight + "|" +
                                    root.internalWidth + "x" + root.internalHeight + "|" + root.filter + "|" +
                                    root.fsrSharpness + "|" + root.scaler + "|" + root.fpsLimit + "|" +
                                    root.unfocusedFpsLimit + "|" + root.adaptiveSync + "|" + root.hdrEnabled + "|" +
                                    root.forceGrabCursor + "|" + root.mouseSensitivity + "|" + root.mangoapp + "|" +
                                    root.backend + "|" + root.exposeWayland + "|" + root.extraArgs
                                void(_tick)
                                return uiController.launchPipeline.formatGamescopePreview(
                                    root.buildConfigMap(), root.previewUseMangohud, root.targetCommandPreview)
                            }
                            color: appSettings.textColor
                            font.family: "monospace"
                            font.pixelSize: 12
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }

                Item { Layout.preferredHeight: 6 }
            }
        }

        // ── Dialog Footer ────────────────────────────────────────────────────
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
                id: footerRow
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 12
                readonly property var ctrlMgr: uiController ? uiController.controllerManager : null
                readonly property bool controllerConnected: Boolean(ctrlMgr && ctrlMgr.isConnected)
                Keys.onPressed: (event) => root.handleDialogKeyPress(event)

                M3Button {
                    id: resetBtn
                    text: root.isGlobalMode ? "Reset Defaults" : "Use Global Defaults"
                    buttonType: "outlined"
                    onClicked: {
                        if (root.isGlobalMode) {
                            if (appSettings) appSettings.resetDefaultGamescopeConfig()
                            root.loadFromMap(appSettings ? appSettings.defaultGamescopeConfig : {})
                        } else {
                            root.resetToGlobalRequested()
                            root.close()
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 12
                    visible: Boolean(uiController && uiController.isKeyboardNavActive)
                    GamepadPrompt {
                        iconSource: footerRow.ctrlMgr ? footerRow.ctrlMgr.dpadUpIconSource : ""
                        secondaryIconSource: footerRow.ctrlMgr ? footerRow.ctrlMgr.leftAnalogIconSource : ""
                        keyName: "Arrows"
                        suffixText: "Navigate"
                        pixelSize: 12
                        iconSize: 15
                    }
                    GamepadPrompt {
                        iconSource: footerRow.ctrlMgr ? footerRow.ctrlMgr.confirmIconSource : ""
                        keyName: "Enter"
                        suffixText: "Edit / Toggle"
                        pixelSize: 12
                        iconSize: 15
                    }
                }

                M3Button {
                    id: cancelBtn
                    objectName: "gamescopeCancelBtn"
                    text: "Cancel"
                    iconSource: footerRow.controllerConnected && footerRow.ctrlMgr ? footerRow.ctrlMgr.cancelIconSource : ""
                    buttonType: "tonal"
                    onClicked: root.close()
                }

                M3Button {
                    id: saveBtn
                    objectName: "gamescopeSaveBtn"
                    text: "Save"
                    iconSource: footerRow.controllerConnected && footerRow.ctrlMgr
                        ? footerRow.ctrlMgr.searchIconSource
                        : "qrc:/tsuki_app/icons/actions/check.svg"
                    buttonType: "filled"
                    onClicked: {
                        root.saveRequested(root.buildConfigMap())
                        root.close()
                    }
                }
            }
        }
    }
}
