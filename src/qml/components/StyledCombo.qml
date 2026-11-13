import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: combo
    property var comboModel: []
    property int selectedIndex: 0
    property bool openUpward: false
    property bool forceDownward: false
    property bool upDownNavigatesFocus: false
    signal selected(int idx)

    property alias popup: popup
    property int focusedPopupIndex: selectedIndex
    readonly property bool kbFocused: combo.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)

    function scrollFocusedIntoView() {
        if (!flick || flick.height <= 0) return
        const stride = 38
        const itemY = focusedPopupIndex * stride
        if (itemY < flick.contentY) {
            flick.contentY = Math.max(0, itemY)
        } else if (itemY + 36 > flick.contentY + flick.height) {
            flick.contentY = Math.max(0, itemY + 36 - flick.height)
        }
    }

    function togglePopup() {
        if (popup.visible) {
            popup.close()
        } else {
            focusedPopupIndex = selectedIndex
            popup.open()
            Qt.callLater(scrollFocusedIntoView)
        }
    }

    function handleDown() {
        if (comboModel && comboModel.length > 0) {
            focusedPopupIndex = (focusedPopupIndex + 1) % comboModel.length
            scrollFocusedIntoView()
        }
    }

    function handleUp() {
        if (comboModel && comboModel.length > 0) {
            focusedPopupIndex = (focusedPopupIndex - 1 + comboModel.length) % comboModel.length
            scrollFocusedIntoView()
        }
    }

    function handleSelect() {
        if (comboModel && focusedPopupIndex >= 0 && focusedPopupIndex < comboModel.length) {
            selectedIndex = focusedPopupIndex
            selected(selectedIndex)
        }
        popup.close()
    }

    function adjustLeft() {
        if (selectedIndex > 0) {
            selectedIndex--
            selected(selectedIndex)
        }
    }

    function adjustRight() {
        if (comboModel && selectedIndex < comboModel.length - 1) {
            selectedIndex++
            selected(selectedIndex)
        }
    }

    function activate() {
        togglePopup()
    }

    implicitWidth: Math.max(160, labelMeasure.implicitWidth + 48)
    implicitHeight: 36
    focus: true
    activeFocusOnTab: false

    Text {
        id: labelMeasure
        text: (comboModel && comboModel[selectedIndex]) ? String(comboModel[selectedIndex]) : ""
        font.pixelSize: 13
        font.weight: Font.DemiBold
        visible: false
    }

    Keys.onReturnPressed: (event) => {
        event.accepted = true
        if (popup.visible) handleSelect()
        else togglePopup()
    }
    Keys.onEnterPressed: (event) => {
        event.accepted = true
        if (popup.visible) handleSelect()
        else togglePopup()
    }
    Keys.onSpacePressed: (event) => {
        event.accepted = true
        if (popup.visible) handleSelect()
        else togglePopup()
    }
    Keys.onUpPressed: (event) => {
        if (popup.visible) {
            event.accepted = true
            handleUp()
        } else if (!combo.upDownNavigatesFocus && combo.selectedIndex > 0) {
            event.accepted = true
            combo.selectedIndex--
            combo.selected(combo.selectedIndex)
        }
    }
    Keys.onDownPressed: (event) => {
        if (popup.visible) {
            event.accepted = true
            handleDown()
        } else if (!combo.upDownNavigatesFocus && combo.comboModel && combo.selectedIndex < combo.comboModel.length - 1) {
            event.accepted = true
            combo.selectedIndex++
            combo.selected(combo.selectedIndex)
        }
    }
    Keys.onEscapePressed: (event) => {
        if (popup.visible) {
            event.accepted = true
            popup.close()
        }
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Backspace && popup.visible) {
            event.accepted = true
            popup.close()
        }
    }

    // Material 3 Dropdown Squircle Button (Matching M3 design system)
    Rectangle {
        id: comboBox
        anchors.fill: parent
        radius: 10
        color: (comboMA.containsMouse || popup.visible || combo.kbFocused)
            ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
            : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))

        border.color: (popup.visible || combo.kbFocused)
            ? appSettings.accentColor
            : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
        border.width: (popup.visible || combo.kbFocused) ? 1.5 : 1
        scale: comboMA.pressed ? 0.96 : (combo.kbFocused ? 1.02 : 1.0)

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 100 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: (combo.comboModel && combo.comboModel[combo.selectedIndex]) ? String(combo.comboModel[combo.selectedIndex]) : ""
                color: appSettings.textColor
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                renderType: Text.QtRendering
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }

            YIcon {
                size: 11
                source: "qrc:/tsuki_app/icons/actions/chevron_down.svg"
                color: (popup.visible || combo.kbFocused || comboMA.containsMouse) ? appSettings.accentColor : appSettings.textSecColor
                rotation: popup.visible ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }

        MouseArea {
            id: comboMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: combo.togglePopup()
        }
    }

    // Floating Popup with M3 Styling and Folding Transition (Matching EpisodeDownloadDialog)
    Popup {
        id: popup
        readonly property real fullContentHeight: Math.min(280, (combo.comboModel ? combo.comboModel.length : 1) * 38 + 12)
        readonly property bool opensUpward: {
            if (combo.forceDownward) return false
            if (combo.openUpward) return true
            let win = combo.Window.window
            if (!win) return false
            let p = combo.mapToItem(null, 0, combo.height)
            return (p.y + fullContentHeight + 16 > win.height) && (p.y > win.height / 2)
        }
        y: opensUpward ? (-height - 4) : (combo.height + 4)
        x: Math.min(0, combo.width - width)
        width: Math.max(combo.width, 240)
        padding: 6
        dim: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

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
            color: appSettings.surfaceColor
            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
            border.width: 1
            radius: 14

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.45 : 0.18)
                shadowBlur: 0.6
                shadowVerticalOffset: 4
            }
        }

        contentItem: Item {
            clip: true

            Flickable {
                id: flick
                anchors.fill: parent
                contentHeight: colLayout.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: colLayout
                    width: flick.width
                    spacing: 2

                    Repeater {
                        model: combo.comboModel

                        Item {
                            id: provRow
                            width: colLayout.width
                            height: 36
                            required property var modelData
                            required property int index
                            readonly property bool isSelectedProv: combo.selectedIndex === index
                            readonly property bool isHoveredProv: pItemMa.containsMouse || combo.focusedPopupIndex === index

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: provRow.isSelectedProv
                                    ? appSettings.accentColor
                                    : (provRow.isHoveredProv ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                                border.color: (combo.focusedPopupIndex === index && !provRow.isSelectedProv && Boolean(uiController && uiController.isKeyboardNavActive))
                                    ? appSettings.accentColor
                                    : "transparent"
                                border.width: 1.5
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: String(provRow.modelData)
                                    color: provRow.isSelectedProv 
                                        ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") 
                                        : appSettings.textColor
                                    font.pixelSize: 13
                                    font.weight: provRow.isSelectedProv ? Font.DemiBold : Font.Normal
                                    renderType: Text.QtRendering
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                YIcon {
                                    size: 13
                                    source: "qrc:/tsuki_app/icons/actions/check.svg"
                                    color: provRow.isSelectedProv ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff") : "transparent"
                                    visible: provRow.isSelectedProv
                                }
                            }

                            MouseArea {
                                id: pItemMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    combo.selectedIndex = provRow.index
                                    combo.selected(provRow.index)
                                    popup.close()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
