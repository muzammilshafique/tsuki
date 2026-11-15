import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var model: []
    property var selectedValue: undefined
    property bool wrap: false
    property real pillHeight: 36
    property int fontSize: 13
    readonly property bool kbFocused: root.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)

    signal selectionChanged(var val, int index)

    function itemValue(item, idx) {
        if (typeof item === "object" && item !== null) {
            if (item.val !== undefined) return item.val
            if (item.value !== undefined) return item.value
            return idx
        }
        return item
    }

    function itemLabel(item) {
        if (typeof item === "object" && item !== null) {
            if (item.label !== undefined) return String(item.label)
            if (item.name !== undefined) return String(item.name)
            if (item.text !== undefined) return String(item.text)
            return ""
        }
        return String(item)
    }

    function valuesMatch(a, b) {
        if (a === b) return true
        if (typeof a === "string" && typeof b === "string") {
            return a.toLowerCase() === b.toLowerCase()
        }
        return false
    }

    readonly property int selectedIndex: {
        if (!model || model.length === 0) return -1
        for (let i = 0; i < model.length; ++i) {
            if (valuesMatch(itemValue(model[i], i), selectedValue)) return i
        }
        return -1
    }

    function selectAt(idx) {
        if (!model || idx < 0 || idx >= model.length) return
        const val = itemValue(model[idx], idx)
        root.selectedValue = val
        root.selectionChanged(val, idx)
    }

    function adjustLeft() {
        if (!model || model.length === 0) return
        const cur = selectedIndex < 0 ? 0 : selectedIndex
        if (cur > 0) selectAt(cur - 1)
    }

    function adjustRight() {
        if (!model || model.length === 0) return
        const cur = selectedIndex < 0 ? -1 : selectedIndex
        if (cur < model.length - 1) selectAt(cur + 1)
    }

    function activate() {
        if (!model || model.length === 0) return
        const cur = selectedIndex < 0 ? -1 : selectedIndex
        selectAt((cur + 1) % model.length)
    }

    implicitWidth: wrap ? (parent ? parent.width : 320) : (layoutLoader.item ? layoutLoader.item.implicitWidth : 0)
    implicitHeight: layoutLoader.item ? Math.max(pillHeight, layoutLoader.item.implicitHeight) : pillHeight
    focus: true
    activeFocusOnTab: false

    Keys.onLeftPressed: (event) => {
        if (!model || model.length === 0) return
        const cur = selectedIndex < 0 ? 0 : selectedIndex
        if (cur > 0) {
            event.accepted = true
            adjustLeft()
        }
    }
    Keys.onRightPressed: (event) => {
        if (!model || model.length === 0) return
        const cur = selectedIndex < 0 ? -1 : selectedIndex
        if (cur < model.length - 1) {
            event.accepted = true
            adjustRight()
        }
    }
    Keys.onSpacePressed: (event) => { event.accepted = true; activate() }
    Keys.onReturnPressed: (event) => { event.accepted = true; activate() }
    Keys.onEnterPressed: (event) => { event.accepted = true; activate() }

    Component {
        id: pillDelegate

        Rectangle {
            id: pill
            required property var modelData
            required property int index

            readonly property int count: root.model ? root.model.length : 0
            readonly property bool isSelected: root.selectedIndex === index
            readonly property bool isObj: typeof modelData === "object" && modelData !== null
            readonly property bool hasDot: isObj && modelData.dotColor !== undefined
            readonly property string dotHex: hasDot ? String(modelData.dotColor) : ""
            readonly property string sym: (isObj && modelData.iconSymbol) ? String(modelData.iconSymbol) : ""
            readonly property string tipText: (isObj && modelData.tooltip) ? String(modelData.tooltip) : ""
            readonly property real capsuleR: root.pillHeight / 2
            readonly property real restR: root.wrap ? 11 : 6
            readonly property real targetLeftR: isSelected ? capsuleR : ((index === 0 && !root.wrap) ? capsuleR : restR)
            readonly property real targetRightR: isSelected ? capsuleR : ((index === count - 1 && !root.wrap) ? capsuleR : restR)
            property real animLeftR: targetLeftR
            property real animRightR: targetRightR

            Behavior on animLeftR { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on animRightR { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            height: root.pillHeight
            width: Math.max(44, contentRow.implicitWidth + 24)

            topLeftRadius: animLeftR
            bottomLeftRadius: animLeftR
            topRightRadius: animRightR
            bottomRightRadius: animRightR

            // Opaque rest vs selected base color only (never cross-fades through varying alpha)
            color: isSelected ? appSettings.accentColor : appSettings.surfaceContainerHigh
            scale: pillTap.pressed ? 0.95 : 1.0

            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

            // Opacity-only M3 state layer so hover/press never flashes through mixed RGB+alpha
            Rectangle {
                anchors.fill: parent
                topLeftRadius: pill.animLeftR
                bottomLeftRadius: pill.animLeftR
                topRightRadius: pill.animRightR
                bottomRightRadius: pill.animRightR
                color: pill.isSelected
                    ? appSettings.onPrimary
                    : (appSettings.isEffectiveDark ? "#ffffff" : "#000000")
                opacity: pillTap.pressed
                    ? 0.14
                    : (pillHover.hovered ? (pill.isSelected ? 0.10 : 0.08) : 0.0)
                Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            }

            // Keyboard/gamepad focus outline
            Rectangle {
                anchors.fill: parent
                topLeftRadius: pill.animLeftR
                bottomLeftRadius: pill.animLeftR
                topRightRadius: pill.animRightR
                bottomRightRadius: pill.animRightR
                color: "transparent"
                border.color: appSettings.onPrimary
                border.width: 2
                opacity: (root.kbFocused && pill.isSelected) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 110 } }
            }

            Row {
                id: contentRow
                anchors.centerIn: parent
                spacing: 7

                Rectangle {
                    visible: pill.hasDot
                    width: 12
                    height: 12
                    radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: pill.dotHex !== "" ? pill.dotHex : (appSettings.isEffectiveDark ? "#18181b" : "#f4f4f5")
                    border.color: pill.isSelected
                        ? appSettings.onPrimary
                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.22))
                    border.width: pill.isSelected ? 1.5 : 1
                }

                YIcon {
                    visible: pill.sym !== ""
                    symbol: pill.sym
                    filled: pill.isSelected
                    size: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: pill.isSelected ? appSettings.onPrimary : appSettings.textSecColor
                    Behavior on color { ColorAnimation { duration: 140 } }
                }

                Label {
                    text: root.itemLabel(pill.modelData)
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: "Rubik"
                    font.pixelSize: root.fontSize
                    font.weight: pill.isSelected ? Font.DemiBold : Font.Medium
                    color: pill.isSelected ? appSettings.onPrimary : appSettings.textColor
                    opacity: pill.isSelected ? 1.0 : (pillHover.hovered ? 1.0 : 0.88)
                    renderType: Text.QtRendering
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                }
            }

            HoverHandler {
                id: pillHover
                cursorShape: Qt.PointingHandCursor
            }

            M3ToolTip {
                visible: pillHover.hovered && pill.tipText !== ""
                text: pill.tipText
                delay: 320
            }

            TapHandler {
                id: pillTap
                onTapped: {
                    if (uiController) uiController.setKeyboardNavActive(false)
                    root.selectAt(pill.index)
                }
            }
        }
    }

    Component {
        id: rowLayoutComp
        Row {
            spacing: 3
            Repeater {
                model: root.model
                delegate: pillDelegate
            }
        }
    }

    Component {
        id: flowLayoutComp
        Flow {
            width: Math.max(120, root.width)
            spacing: 6
            Repeater {
                model: root.model
                delegate: pillDelegate
            }
        }
    }

    Loader {
        id: layoutLoader
        anchors.left: parent.left
        anchors.right: root.wrap ? parent.right : undefined
        sourceComponent: root.wrap ? flowLayoutComp : rowLayoutComp
    }
}

