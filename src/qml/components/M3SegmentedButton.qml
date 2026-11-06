import QtQuick
import QtQuick.Controls


Item {
    id: root
    property var model: []
    property int selectedValue: 0
    signal selectionChanged(var val, int index)

    implicitWidth: Math.max(270, (model && model.length) ? model.length * 90 : 270)
    implicitHeight: 40
    focus: true

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

    function getItemVal(item, idx) {
        if (typeof item === "object" && item !== null) {
            return item.val !== undefined ? item.val : (item.value !== undefined ? item.value : idx)
        }
        return item
    }

    function adjustLeft() {
        if (selectedIndex > 0) {
            let next = model[selectedIndex - 1]
            let val = getItemVal(next, selectedIndex - 1)
            root.selectedValue = val
            root.selectionChanged(val, selectedIndex - 1)
        }
    }

    function adjustRight() {
        if (model && selectedIndex < model.length - 1) {
            let next = model[selectedIndex + 1]
            let val = getItemVal(next, selectedIndex + 1)
            root.selectedValue = val
            root.selectionChanged(val, selectedIndex + 1)
        }
    }

    function activate() {
        if (model && model.length > 0) {
            let nextIdx = (selectedIndex + 1) % model.length
            let next = model[nextIdx]
            let val = getItemVal(next, nextIdx)
            root.selectedValue = val
            root.selectionChanged(val, nextIdx)
        }
    }

    Keys.onLeftPressed: (event) => {
        if (selectedIndex > 0) {
            event.accepted = true
            adjustLeft()
        }
    }
    Keys.onRightPressed: (event) => {
        if (model && selectedIndex < model.length - 1) {
            event.accepted = true
            adjustRight()
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
        border.color: root.activeFocus ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10))
        border.width: root.activeFocus ? 2 : 1
        scale: root.activeFocus ? 1.02 : 1.0

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

                    width: container.segmentWidth
                    height: parent.height
                    radius: 16
                    color: (!isSelected && segHover.hovered)
                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                        : "transparent"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        YIcon {
                            size: 15
                            source: (typeof modelData === "object" && modelData && modelData.iconSource) ? modelData.iconSource : ""
                            visible: (typeof modelData === "object" && modelData && Boolean(modelData.iconSource))
                            color: isSelected
                                ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                                : (segHover.hovered ? appSettings.textColor : appSettings.textSecColor)
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            text: (typeof modelData === "object" && modelData)
                                ? (modelData.label !== undefined ? modelData.label : (modelData.name !== undefined ? modelData.name : (modelData.text !== undefined ? modelData.text : "")))
                                : String(modelData)
                            font.pixelSize: 13
                            font.weight: isSelected ? Font.DemiBold : Font.Normal
                            color: isSelected
                                ? (appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff")
                                : (segHover.hovered ? appSettings.textColor : appSettings.textSecColor)
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
