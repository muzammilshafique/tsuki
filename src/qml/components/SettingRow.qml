import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: sr
    property string label: ""
    property string description: ""
    property Item controlItem: null

    width: parent ? parent.width : 0
    height: visible ? Math.max(68, sr.controlItem ? sr.controlItem.implicitHeight + 24 : 68) : 0
    implicitHeight: height
    focus: true
    activeFocusOnTab: true

    onControlItemChanged: {
        if (controlItem) {
            controlItem.parent = controlContainer
            controlItem.anchors.verticalCenter = controlContainer.verticalCenter
            controlItem.anchors.right = controlContainer.right
        }
    }

    property bool isHighlighted: false
    property bool isTvFocused: uiController.isKeyboardNavActive && (activeFocus || (controlItem && controlItem.activeFocus))
    readonly property bool isControlPopupOpen: !!(controlItem && controlItem.popup && controlItem.popup.visible)

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
        onTriggered: sr.isHighlighted = false
    }

    function handleLeft(event) {
        if (!controlItem) return false
        if (isControlPopupOpen) return true
        if (controlItem.adjustLeft) {
            controlItem.adjustLeft()
            return true
        }
        if (controlItem.toggleIt && controlItem.checked !== undefined) {
            if (controlItem.checked) controlItem.toggleIt()
            return true
        }
        if (controlItem.value !== undefined && controlItem.from !== undefined) {
            controlItem.value = Math.max(controlItem.from, controlItem.value - (controlItem.stepSize || 1))
            return true
        }
        if (controlItem.selectedIndex !== undefined && controlItem.comboModel !== undefined) {
            if (controlItem.selectedIndex > 0) {
                controlItem.selectedIndex--
                if (controlItem.selected) controlItem.selected(controlItem.selectedIndex)
            }
            return true
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
        if (controlItem.value !== undefined && controlItem.to !== undefined) {
            controlItem.value = Math.min(controlItem.to, controlItem.value + (controlItem.stepSize || 1))
            return true
        }
        if (controlItem.selectedIndex !== undefined && controlItem.comboModel !== undefined) {
            if (controlItem.comboModel && controlItem.selectedIndex < controlItem.comboModel.length - 1) {
                controlItem.selectedIndex++
                if (controlItem.selected) controlItem.selected(controlItem.selectedIndex)
            }
            return true
        }
        return false
    }

    function handleActivate(event) {
        if (!controlItem) return false
        if (controlItem.activate) {
            controlItem.activate()
            return true
        }
        if (controlItem.togglePopup) {
            controlItem.togglePopup()
            return true
        }
        if (controlItem.popup) {
            if (controlItem.popup.visible) controlItem.popup.close()
            else controlItem.popup.open()
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
        return false
    }

    Keys.onUpPressed: (event) => {
        if (isControlPopupOpen) {
            event.accepted = true
            if (controlItem.handleUp) controlItem.handleUp()
        } else {
            event.accepted = true
            if (typeof settingsPage !== "undefined") settingsPage.focusPrevSettingRow()
        }
    }
    Keys.onDownPressed: (event) => {
        if (isControlPopupOpen) {
            event.accepted = true
            if (controlItem.handleDown) controlItem.handleDown()
        } else {
            event.accepted = true
            if (typeof settingsPage !== "undefined") settingsPage.focusNextSettingRow()
        }
    }
    Keys.onLeftPressed: (event) => {
        if (handleLeft(event)) {
            event.accepted = true
        }
    }
    Keys.onRightPressed: (event) => {
        if (handleRight(event)) {
            event.accepted = true
        }
    }
    Keys.onReturnPressed: (event) => {
        if (isControlPopupOpen) {
            event.accepted = true
            if (controlItem.handleSelect) controlItem.handleSelect()
            else controlItem.popup.close()
        } else if (handleActivate(event)) {
            event.accepted = true
        }
    }
    Keys.onEnterPressed: (event) => {
        if (isControlPopupOpen) {
            event.accepted = true
            if (controlItem.handleSelect) controlItem.handleSelect()
            else controlItem.popup.close()
        } else if (handleActivate(event)) {
            event.accepted = true
        }
    }
    Keys.onSpacePressed: (event) => {
        if (isControlPopupOpen) {
            event.accepted = true
            if (controlItem.handleSelect) controlItem.handleSelect()
            else controlItem.popup.close()
        } else if (handleActivate(event)) {
            event.accepted = true
        }
    }
    Keys.onEscapePressed: (event) => {
        if (isControlPopupOpen) {
            event.accepted = true
            controlItem.popup.close()
        } else {
            event.accepted = true
            if (typeof backBtn !== "undefined") backBtn.forceActiveFocus()
        }
    }

    // Material 3 State Layer / Focus Glow
    Rectangle {
        id: stateLayer
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        radius: 14
        z: 0

        color: {
            if (sr.isTvFocused || sr.isHighlighted) return appSettings.accentColor
            if (rowHover.hovered) {
                return appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
            }
            return "transparent"
        }
        opacity: (sr.isTvFocused || sr.isHighlighted) ? 0.14 : (rowHover.hovered ? 1.0 : 0.0)
        border.color: (sr.isTvFocused || sr.isHighlighted) ? appSettings.accentColor : "transparent"
        border.width: (sr.isTvFocused || sr.isHighlighted) ? 2 : 0

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    HoverHandler {
        id: rowHover
    }

    RowLayout {
        z: 1
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 16

        Column {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3

            Label {
                text: sr.label
                color: appSettings.textColor
                font.pixelSize: 15
                font.weight: Font.DemiBold
                renderType: Text.QtRendering
            }

            Label {
                text: sr.description
                color: appSettings.textSecColor
                font.pixelSize: 13
                visible: text !== ""
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.25
                renderType: Text.QtRendering
            }
        }

        Item {
            id: controlContainer
            Layout.preferredWidth: sr.controlItem ? sr.controlItem.implicitWidth : 0
            Layout.fillHeight: true
        }
    }
}
