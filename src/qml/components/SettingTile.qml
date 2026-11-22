import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: st
    property string label: ""
    property string infoTip: ""
    property string searchKeywords: ""
    property string badgeText: ""
    property color badgeColor: "#f59e0b"
    property int tabIndex: 0
    property Item controlItem: null
    property bool inlineControl: true
    property bool fillControlWidth: false
    property bool isHighlighted: false
    readonly property Item winFocusItem: st.Window ? st.Window.activeFocusItem : null
    readonly property bool hasFocusWithin: {
        if (st.activeFocus) return true
        if (controlItem && controlItem.activeFocus) return true
        let f = winFocusItem
        while (f) {
            if (f === st) return true
            f = f.parent
        }
        return false
    }
    readonly property bool isTvFocused: Boolean(uiController && uiController.isKeyboardNavActive) && hasFocusWithin
    readonly property bool isControlPopupOpen: !!(controlItem && controlItem.popup && controlItem.popup.visible)
    readonly property bool isControlAdjusting: !!(controlItem && controlItem.isAdjusting === true)

    // Back-compat with SettingsPage search catalog / focus helpers
    readonly property string description: infoTip || searchKeywords

    Layout.fillWidth: true
    implicitWidth: 260
    implicitHeight: visible ? (outerLayout.implicitHeight + 16) : 0
    height: visible ? implicitHeight : 0
    focus: true
    activeFocusOnTab: false

    function syncControlParent() {
        if (!controlItem) return
        if (inlineControl) {
            controlItem.parent = inlineControlSlot
            controlItem.anchors.left = undefined
            controlItem.anchors.top = undefined
            controlItem.anchors.verticalCenter = inlineControlSlot.verticalCenter
            controlItem.anchors.right = inlineControlSlot.right
        } else {
            controlItem.parent = stackedControlSlot
            controlItem.anchors.verticalCenter = undefined
            controlItem.anchors.right = undefined
            controlItem.anchors.left = stackedControlSlot.left
            controlItem.anchors.top = stackedControlSlot.top
            if (fillControlWidth || (controlItem.wrap === true)) {
                controlItem.width = Qt.binding(() => stackedControlSlot.width)
            }
        }
    }

    onControlItemChanged: syncControlParent()
    onInlineControlChanged: syncControlParent()
    onFillControlWidthChanged: syncControlParent()

    function isCompositeControl() {
        if (!controlItem) return false
        if (controlItem.moveFocusLeft || controlItem.adjustLeft || controlItem.toggleIt || controlItem.clicked || controlItem.activate) {
            return false
        }
        return collectActionableChildren(controlItem).length >= 2
    }

    function collectActionableChildren(node, out) {
        let list = out || []
        if (!node || !node.visible || !node.enabled || !node.children) return list
        for (let i = 0; i < node.children.length; ++i) {
            let c = node.children[i]
            if (!c || !c.visible || !c.enabled) continue
            const isActionable = Boolean(
                (c.clicked && typeof c.clicked === "function")
                || (c.toggleIt && typeof c.toggleIt === "function")
                || (c.activate && typeof c.activate === "function")
                || (c.twoStageFocus !== undefined)
            )
            if (isActionable) {
                list.push(c)
            } else if (c.children && c.children.length > 0) {
                collectActionableChildren(c, list)
            }
        }
        return list
    }

    function findFocusedSubIndex(subs) {
        const fi = st.winFocusItem
        for (let i = 0; i < subs.length; ++i) {
            if (subs[i].activeFocus || (fi && fi === subs[i])) return i
            let p = fi
            while (p && p !== st) {
                if (p === subs[i]) return i
                p = p.parent
            }
        }
        return -1
    }

    function forwardFocus(fromRight) {
        if (isCompositeControl()) {
            const subs = collectActionableChildren(controlItem)
            if (subs.length > 0) {
                const idx = fromRight ? (subs.length - 1) : 0
                subs[idx].forceActiveFocus()
                return
            }
        }
        forceActiveFocus()
    }

    function highlight() {
        isHighlighted = true
        highlightTimer.restart()
    }

    Timer {
        id: highlightTimer
        interval: 1800
        onTriggered: st.isHighlighted = false
    }

    function handleLeft(event) {
        if (!controlItem) return false
        if (isControlPopupOpen) return true
        // Sliders only adjust on Left/Right when Enter has entered adjust mode
        if (controlItem.isAdjusting !== undefined) {
            if (controlItem.isAdjusting && controlItem.adjustLeft) {
                controlItem.adjustLeft()
                return true
            }
            return false
        }
        // Segmented / Pill / Theme / Color selectors move focus highlight without committing
        if (controlItem.moveFocusLeft) {
            return Boolean(controlItem.moveFocusLeft())
        }
        // Multi-control composite tiles (e.g. [Input, Browse], [Reinstall, Remove])
        if (isCompositeControl()) {
            const subs = collectActionableChildren(controlItem)
            const cur = findFocusedSubIndex(subs)
            if (cur > 0) {
                subs[cur - 1].forceActiveFocus()
                return true
            }
            return false
        }
        // Toggles, single buttons, and closed combos NEVER mutate on Left
        return false
    }

    function handleRight(event) {
        if (!controlItem) return false
        if (isControlPopupOpen) return true
        // Sliders only adjust on Left/Right when Enter has entered adjust mode
        if (controlItem.isAdjusting !== undefined) {
            if (controlItem.isAdjusting && controlItem.adjustRight) {
                controlItem.adjustRight()
                return true
            }
            return false
        }
        // Segmented / Pill / Theme / Color selectors move focus highlight without committing
        if (controlItem.moveFocusRight) {
            return Boolean(controlItem.moveFocusRight())
        }
        // Multi-control composite tiles (e.g. [Input, Browse], [Reinstall, Remove])
        if (isCompositeControl()) {
            const subs = collectActionableChildren(controlItem)
            const cur = findFocusedSubIndex(subs)
            if (cur >= 0 && cur < subs.length - 1) {
                subs[cur + 1].forceActiveFocus()
                return true
            }
            if (cur < 0 && subs.length > 0) {
                subs[0].forceActiveFocus()
                return true
            }
            return false
        }
        // Toggles, single buttons, and closed combos NEVER mutate on Right
        return false
    }

    function handleActivate(event) {
        if (!controlItem) return false
        if (isCompositeControl()) {
            const subs = collectActionableChildren(controlItem)
            const cur = findFocusedSubIndex(subs)
            const target = (cur >= 0 && cur < subs.length) ? subs[cur] : (subs.length > 0 ? subs[0] : null)
            if (target) {
                if (target.activate) { target.activate(); return true }
                if (target.toggleIt) { target.toggleIt(); return true }
                if (target.clicked) { target.clicked(); return true }
                if (target.forceActiveFocus) { target.forceActiveFocus(); return true }
            }
            return false
        }
        if (controlItem.activate) {
            controlItem.activate()
            return true
        }
        if (controlItem.toggleIt) {
            controlItem.toggleIt()
            return true
        }
        if (controlItem.clicked) {
            controlItem.clicked()
            return true
        }
        if (controlItem.forceActiveFocus && (controlItem.placeholderText !== undefined || controlItem.text !== undefined)) {
            controlItem.forceActiveFocus()
            return true
        }
        const subs = collectActionableChildren(controlItem)
        if (subs.length > 0) {
            const c = subs[0]
            if (c.activate) { c.activate(); return true }
            if (c.toggleIt) { c.toggleIt(); return true }
            if (c.clicked) { c.clicked(); return true }
            if (c.forceActiveFocus) { c.forceActiveFocus(); return true }
        }
        return false
    }

    function handleCancel(event) {
        if (isControlPopupOpen) {
            event.accepted = true
            controlItem.popup.close()
            return true
        }
        if (isControlAdjusting && controlItem.exitAdjustMode) {
            event.accepted = true
            controlItem.exitAdjustMode()
            return true
        }
        if (typeof settingsPage !== "undefined" && settingsPage.backRequested) {
            event.accepted = true
            settingsPage.backRequested()
            return true
        }
        return false
    }

    Keys.onUpPressed: (event) => {
        if (isControlPopupOpen) {
            event.accepted = true
            if (controlItem.handleUp) controlItem.handleUp()
        } else {
            if (isControlAdjusting && controlItem.exitAdjustMode) controlItem.exitAdjustMode()
            event.accepted = true
            if (typeof settingsPage !== "undefined" && settingsPage.focusPrevSettingRow) {
                settingsPage.focusPrevSettingRow()
            }
        }
    }
    Keys.onDownPressed: (event) => {
        if (isControlPopupOpen) {
            event.accepted = true
            if (controlItem.handleDown) controlItem.handleDown()
        } else {
            if (isControlAdjusting && controlItem.exitAdjustMode) controlItem.exitAdjustMode()
            event.accepted = true
            if (typeof settingsPage !== "undefined" && settingsPage.focusNextSettingRow) {
                settingsPage.focusNextSettingRow()
            }
        }
    }
    Keys.onLeftPressed: (event) => {
        if (handleLeft(event)) {
            event.accepted = true
        } else if (typeof settingsPage !== "undefined" && settingsPage.focusLeftSettingTile) {
            event.accepted = true
            settingsPage.focusLeftSettingTile()
        } else if (typeof settingsPage !== "undefined" && settingsPage.focusRailFromContent) {
            event.accepted = true
            settingsPage.focusRailFromContent()
        } else {
            event.accepted = false
        }
    }
    Keys.onRightPressed: (event) => {
        if (handleRight(event)) {
            event.accepted = true
        } else if (typeof settingsPage !== "undefined" && settingsPage.focusRightSettingTile) {
            event.accepted = true
            settingsPage.focusRightSettingTile()
        } else {
            event.accepted = false
        }
    }
    Keys.onReturnPressed: (event) => {
        event.accepted = handleActivate(event)
    }
    Keys.onEnterPressed: (event) => {
        event.accepted = handleActivate(event)
    }
    Keys.onSpacePressed: (event) => {
        event.accepted = handleActivate(event)
    }
    Keys.onEscapePressed: (event) => {
        event.accepted = handleCancel(event)
    }
    Keys.onBackPressed: (event) => {
        event.accepted = handleCancel(event)
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Backspace) {
            event.accepted = handleCancel(event)
        } else {
            event.accepted = false
        }
    }

    // Subtle M3 hover / focus highlight pill (opacity-only so it never flashes through #00000000)
    Item {
        anchors.fill: parent
        z: 0

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: appSettings.isEffectiveDark ? "#ffffff" : "#000000"
            opacity: (!st.isTvFocused && !st.isHighlighted && tileHover.hovered)
                ? (appSettings.isEffectiveDark ? 0.04 : 0.03)
                : 0.0
            Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.12)
            border.color: appSettings.accentColor
            border.width: 1.5
            opacity: (st.isTvFocused || st.isHighlighted) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
    }

    HoverHandler { id: tileHover }

    TextMetrics {
        id: labelMetrics
        font: titleLbl.font
        text: st.label
    }

    ColumnLayout {
        id: outerLayout
        z: 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        // Top / Inline Header Row
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: st.inlineControl ? 34 : 22
            spacing: 12

            Item {
                id: labelClusterSlot
                Layout.fillWidth: true
                Layout.minimumWidth: 60
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.ceil(Math.max(labelMetrics.advanceWidth, labelMetrics.boundingRect.width)) + 8
                               + (infoIconItem.visible ? (infoIconItem.implicitWidth + 6) : 0)
                               + (badgeItem.visible ? (badgeItem.implicitWidth + 6) : 0)
                implicitHeight: Math.max(titleLbl.implicitHeight, infoIconItem.visible ? 18 : 0, badgeItem.visible ? 20 : 0)

                RowLayout {
                    id: labelCluster
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(labelClusterSlot.implicitWidth, parent.width)
                    spacing: 6

                    Label {
                        id: titleLbl
                        objectName: "settingTileTitleLabel"
                        text: st.label
                        color: appSettings.textColor
                        font.family: "Rubik"
                        font.pixelSize: st.inlineControl ? 14 : 13
                        font.weight: Font.Medium
                        opacity: st.inlineControl ? 1.0 : 0.88
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        renderType: Text.QtRendering
                    }

                    Item {
                        id: infoIconItem
                        visible: st.infoTip !== ""
                        implicitWidth: 18
                        implicitHeight: 18
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignVCenter

                        YIcon {
                            anchors.centerIn: parent
                            symbol: "info"
                            size: 15
                            color: (infoHover.hovered || st.isTvFocused) ? appSettings.accentColor : appSettings.textTerColor
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        HoverHandler {
                            id: infoHover
                            cursorShape: Qt.WhatsThisCursor
                        }
                        M3ToolTip {
                            visible: infoHover.hovered
                            text: st.infoTip
                        }
                    }

                    Rectangle {
                        id: badgeItem
                        visible: st.badgeText !== ""
                        implicitWidth: badgeLbl.implicitWidth + 14
                        implicitHeight: 20
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignVCenter
                        radius: 10
                        color: Qt.rgba(st.badgeColor.r, st.badgeColor.g, st.badgeColor.b, 0.16)
                        border.color: Qt.rgba(st.badgeColor.r, st.badgeColor.g, st.badgeColor.b, 0.45)
                        border.width: 1

                        Label {
                            id: badgeLbl
                            anchors.centerIn: parent
                            text: st.badgeText
                            color: st.badgeColor
                            font.family: "Rubik"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            renderType: Text.QtRendering
                        }
                    }
                }
            }

            Item {
                id: inlineControlSlot
                visible: st.inlineControl
                Layout.preferredWidth: st.controlItem ? st.controlItem.implicitWidth : 0
                Layout.preferredHeight: st.controlItem ? Math.max(32, st.controlItem.implicitHeight) : 0
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
        }

        // Stacked Control Slot (for M3PillGroup, StyledSlider, ThemePreviewCards, directory inputs)
        Item {
            id: stackedControlSlot
            visible: !st.inlineControl
            Layout.fillWidth: true
            Layout.preferredHeight: st.controlItem ? st.controlItem.implicitHeight : 0
        }
    }
}
