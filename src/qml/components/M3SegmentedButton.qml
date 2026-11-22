import QtQuick
import QtQuick.Controls


Item {
    id: root
    property var model: []
    property int selectedValue: 0
    property int focusedIndex: 0
    readonly property bool isParentTileFocused: {
        let p = root.parent
        while (p) {
            if (p.isTvFocused !== undefined) return Boolean(p.isTvFocused)
            p = p.parent
        }
        return false
    }
    readonly property bool hasLogicalFocus: root.activeFocus || isParentTileFocused
    readonly property bool kbFocused: Boolean(uiController && uiController.isKeyboardNavActive) && hasLogicalFocus
    signal selectionChanged(var val, int index)
    signal edgeLeft()
    signal edgeRight()

    implicitWidth: Math.max(270, (model && model.length) ? model.length * 90 : 270)
    implicitHeight: 40
    focus: true
    activeFocusOnTab: false

    readonly property int selectedIndex: {
        if (!model || model.length === 0) return 0
        for (let i = 0; i < model.length; i++) {
            let itemVal = (typeof model[i] === "object" && model[i] !== null)
                ? (model[i].val !== undefined ? model[i].val : (model[i].value !== undefined ? model[i].value : i))
                : model[i]
            if (itemVal === selectedValue) return i
        }
        return 0
    }

    onSelectedIndexChanged: focusedIndex = selectedIndex
    onHasLogicalFocusChanged: {
        if (hasLogicalFocus) {
            focusedIndex = selectedIndex
        }
    }
    Component.onCompleted: focusedIndex = selectedIndex

    function getItemVal(item, idx) {
        if (typeof item === "object" && item !== null) {
            return item.val !== undefined ? item.val : (item.value !== undefined ? item.value : idx)
        }
        return item
    }

    function moveFocusLeft() {
        if (!model || model.length === 0) return false
        if (focusedIndex > 0) {
            focusedIndex--
            return true
        }
        return false
    }

    function moveFocusRight() {
        if (!model || model.length === 0) return false
        if (focusedIndex < model.length - 1) {
            focusedIndex++
            return true
        }
        return false
    }

    function adjustLeft() {
        return moveFocusLeft()
    }

    function adjustRight() {
        return moveFocusRight()
    }

    function commitFocused() {
        if (!model || model.length === 0) return
        const idx = Math.max(0, Math.min(model.length - 1, focusedIndex))
        const next = model[idx]
        const val = getItemVal(next, idx)
        root.selectedValue = val
        root.selectionChanged(val, idx)
    }

    function activate() {
        commitFocused()
    }

    Keys.onLeftPressed: (event) => {
        if (moveFocusLeft()) {
            event.accepted = true
        } else {
            event.accepted = false
            root.edgeLeft()
        }
    }
    Keys.onRightPressed: (event) => {
        if (moveFocusRight()) {
            event.accepted = true
        } else {
            event.accepted = false
            root.edgeRight()
        }
    }
    Keys.onSpacePressed: (event) => {
        event.accepted = true
        activate()
    }
    Keys.onReturnPressed: (event) => {
        event.accepted = true
        activate()
    }
    Keys.onEnterPressed: (event) => {
        event.accepted = true
        activate()
    }

    Rectangle {
        id: container
        anchors.fill: parent
        radius: 20
        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
        border.color: root.kbFocused ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10))
        border.width: root.kbFocused ? 2 : 1
        scale: root.kbFocused ? 1.02 : 1.0

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 120 } }

        readonly property real segmentWidth: (width - 8) / Math.max(1, (model ? model.length : 1))

        // Sliding Active Indicator Pill
        Rectangle {
            id: activePill
            z: 1
            y: 4
            width: container.segmentWidth
            height: container.height - 8
            radius: 16
            color: appSettings.accentColor
            x: 4 + Math.max(0, Math.min((model ? model.length - 1 : 0), root.selectedIndex)) * container.segmentWidth

            Behavior on x {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }

        // Segments Row
        Row {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 0
            z: 2

            Repeater {
                model: root.model
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool isSelected: root.selectedIndex === index
                    readonly property bool isSegmentFocused: root.kbFocused && root.focusedIndex === index

                    width: container.segmentWidth
                    height: parent.height
                    radius: 16
                    color: Qt.rgba(0, 0, 0, 0)

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: isSegmentFocused && !isSelected
                            ? Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.18)
                            : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                        opacity: (!isSelected && (segHover.hovered || isSegmentFocused)) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    }

                    // Per-segment keyboard/gamepad focus outline before pressing Enter
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: isSelected ? 1 : 0
                        radius: isSelected ? 15 : 16
                        color: "transparent"
                        border.color: isSelected ? appSettings.onPrimary : appSettings.accentColor
                        border.width: 2
                        opacity: isSegmentFocused ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        YIcon {
                            size: 15
                            source: (typeof modelData === "object" && modelData && modelData.iconSource) ? modelData.iconSource : ""
                            visible: (typeof modelData === "object" && modelData && Boolean(modelData.iconSource))
                            color: isSelected
                                ? appSettings.onPrimary
                                : ((segHover.hovered || isSegmentFocused) ? appSettings.textColor : appSettings.textSecColor)
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            text: (typeof modelData === "object" && modelData)
                                ? (modelData.label !== undefined ? modelData.label : (modelData.name !== undefined ? modelData.name : (modelData.text !== undefined ? modelData.text : "")))
                                : String(modelData)
                            font.pixelSize: 13
                            font.weight: (isSelected || isSegmentFocused) ? Font.DemiBold : Font.Normal
                            color: isSelected
                                ? appSettings.onPrimary
                                : ((segHover.hovered || isSegmentFocused) ? appSettings.textColor : appSettings.textSecColor)
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.QtRendering
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    HoverHandler {
                        id: segHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: {
                            if (uiController) uiController.setKeyboardNavActive(false)
                            root.focusedIndex = index
                            let val = root.getItemVal(modelData, index)
                            root.selectedValue = val
                            root.selectionChanged(val, index)
                        }
                    }
                }
            }
        }
    }
}
