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
    readonly property bool isTvFocused: Boolean(uiController && uiController.isKeyboardNavActive)
                                        && (activeFocus || (controlItem && controlItem.activeFocus))
    readonly property bool isControlPopupOpen: !!(controlItem && controlItem.popup && controlItem.popup.visible)

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

    function forwardFocus() {
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
        if (controlItem.adjustLeft) {
            if (controlItem.selectedIndex !== undefined) {
                if (controlItem.selectedIndex > 0) {
                    controlItem.adjustLeft()
                    return true
                }
                return false
            }
            if (controlItem.selectedMode !== undefined) {
                if (controlItem.selectedMode > 0) {
                    controlItem.adjustLeft()
                    return true
                }
                return false
            }
            if (controlItem.slider !== undefined) {
                if (controlItem.slider.value > controlItem.slider.from) {
                    controlItem.adjustLeft()
                    return true
                }
                return false
            }
            controlItem.adjustLeft()
            return true
        }
        if (controlItem.toggleIt && controlItem.checked !== undefined) {
            if (controlItem.checked) {
                controlItem.toggleIt()
                return true
            }
            return false
        }
        return false
    }

    function handleRight(event) {
        if (!controlItem) return false
        if (isControlPopupOpen) return true
        if (controlItem.adjustRight) {
            controlItem.adjustRight()
            return true
        }
        if (controlItem.toggleIt && controlItem.checked !== undefined) {
            if (!controlItem.checked) controlItem.toggleIt()
            return true
        }
        if (controlItem.children) {
            for (let i = 0; i < controlItem.children.length; i++) {
                let c = controlItem.children[i]
                if (c && c.clicked && c.forceActiveFocus) {
                    c.forceActiveFocus()
                    return true
                }
            }
        }
        return false
    }

    function handleActivate(event) {
        if (!controlItem) return false
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
        if (controlItem.children) {
            for (let i = 0; i < controlItem.children.length; i++) {
                let c = controlItem.children[i]
                if (c && c.activate) {
                    c.activate()
                    return true
                }
                if (c && c.clicked) {
                    c.clicked()
                    return true
                }
                if (c && c.forceActiveFocus && (c.placeholderText !== undefined || c.text !== undefined)) {
                    c.forceActiveFocus()
                    return true
                }
            }
        }
        return false
    }

    Keys.onUpPressed: (event) => {
        if (isControlPopupOpen) {
            event.accepted = true
            if (controlItem.handleUp) controlItem.handleUp()
        } else {
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
            event.accepted = true
            if (typeof settingsPage !== "undefined" && settingsPage.focusNextSettingRow) {
                settingsPage.focusNextSettingRow()
            }
        }
    }
    Keys.onLeftPressed: (event) => {
        if (handleLeft(event)) {
            event.accepted = true
        } else if (typeof settingsPage !== "undefined" && settingsPage.focusRailFromContent) {
            event.accepted = true
            settingsPage.focusRailFromContent()
        }
    }
    Keys.onRightPressed: (event) => {
        if (handleRight(event)) {
            event.accepted = true
        }
    }
    Keys.onReturnPressed: (event) => {
        if (handleActivate(event)) event.accepted = true
    }
    Keys.onEnterPressed: (event) => {
        if (handleActivate(event)) event.accepted = true
    }
    Keys.onSpacePressed: (event) => {
        if (handleActivate(event)) event.accepted = true
    }
    Keys.onEscapePressed: (event) => {
        if (typeof settingsPage !== "undefined" && settingsPage.backRequested) {
            event.accepted = true
            settingsPage.backRequested()
        }
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Backspace && typeof settingsPage !== "undefined" && settingsPage.backRequested) {
            event.accepted = true
            settingsPage.backRequested()
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
