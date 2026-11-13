import QtQuick
import QtQuick.Controls
import QtQuick.Layouts


Item {
    id: root
    property var presets: []
    property string currentColor: ""
    property bool allowCustom: true
    property bool showCustomInput: false
    signal colorSelected(string hex)

    implicitWidth: mainCol.implicitWidth
    implicitHeight: mainCol.implicitHeight
    focus: true
    activeFocusOnTab: false

    readonly property int totalCount: (presets ? presets.length : 0) + (allowCustom ? 1 : 0)

    readonly property int selectedPresetIndex: {
        if (!presets || presets.length === 0) return -1
        let cur = (currentColor || "").toLowerCase()
        for (let i = 0; i < presets.length; i++) {
            let pColor = (presets[i].color || "").toLowerCase()
            if (pColor === cur) return i
        }
        return -1
    }

    readonly property bool isCustomSelected: allowCustom && (selectedPresetIndex === -1) && (currentColor !== "")

    readonly property int activeIndex: {
        if (selectedPresetIndex >= 0) return selectedPresetIndex
        if (isCustomSelected && presets) return presets.length
        return 0
    }

    property int focusedIndex: -1

    onCurrentColorChanged: {
        if (focusedIndex === -1) {
            focusedIndex = activeIndex
        }
    }

    Component.onCompleted: {
        focusedIndex = activeIndex
    }

    readonly property bool isParentRowFocused: {
        let p = root.parent
        while (p) {
            if (p.isTvFocused !== undefined) return Boolean(p.isTvFocused)
            p = p.parent
        }
        return false
    }

    readonly property bool isNavActive: Boolean(uiController && uiController.isKeyboardNavActive)
                                        && (root.activeFocus || isParentRowFocused)

    function adjustLeft() {
        if (totalCount <= 0) return
        if (focusedIndex < 0 || focusedIndex >= totalCount) focusedIndex = activeIndex
        focusedIndex = (focusedIndex - 1 + totalCount) % totalCount
        commitFocused()
    }

    function adjustRight() {
        if (totalCount <= 0) return
        if (focusedIndex < 0 || focusedIndex >= totalCount) focusedIndex = activeIndex
        focusedIndex = (focusedIndex + 1) % totalCount
        commitFocused()
    }

    function commitFocused() {
        if (focusedIndex < presets.length) {
            showCustomInput = false
            let chosen = presets[focusedIndex].color
            root.colorSelected(chosen)
        } else {
            showCustomInput = true
        }
    }

    function activate() {
        if (focusedIndex === presets.length || isCustomSelected || showCustomInput) {
            showCustomInput = true
            hexField.forceActiveFocus()
            hexField.selectAll()
        } else {
            adjustRight()
        }
    }

    Keys.onLeftPressed: (event) => {
        event.accepted = true
        adjustLeft()
    }
    Keys.onRightPressed: (event) => {
        event.accepted = true
        adjustRight()
    }
    Keys.onReturnPressed: (event) => {
        event.accepted = true
        activate()
    }
    Keys.onEnterPressed: (event) => {
        event.accepted = true
        activate()
    }
    Keys.onSpacePressed: (event) => {
        event.accepted = true
        activate()
    }

    Column {
        id: mainCol
        spacing: 10
        anchors.verticalCenter: parent.verticalCenter

        // Swatches Row
        Row {
            id: swatchesRow
            spacing: 8

            Repeater {
                model: root.presets
                delegate: Item {
                    id: swatchItem
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: root.selectedPresetIndex === index
                    readonly property bool isKeyboardFocused: (root.focusedIndex === index) && root.isNavActive

                    width: 34
                    height: 34

                    // Outer M3 focus and selection ring
                    Rectangle {
                        anchors.fill: parent
                        radius: 17
                        color: "transparent"
                        border.color: swatchItem.isKeyboardFocused
                            ? "#ffffff"
                            : (swatchItem.isSelected ? appSettings.accentColor : "transparent")
                        border.width: swatchItem.isKeyboardFocused ? 2.5 : 2
                        scale: swatchItem.isKeyboardFocused ? 1.12 : (swatchItem.isSelected ? 1.0 : 0.8)
                        opacity: (swatchItem.isKeyboardFocused || swatchItem.isSelected) ? 1.0 : 0.0

                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                    }

                    // Inner Color Swatch Circle
                    Rectangle {
                        anchors.centerIn: parent
                        width: swatchItem.isSelected ? 26 : 28
                        height: swatchItem.isSelected ? 26 : 28
                        radius: width / 2
                        color: (modelData.color === "" || !modelData.color)
                            ? (appSettings.isEffectiveDark ? "#18181b" : "#f4f4f5")
                            : modelData.color
                        border.color: (modelData.color === "" || !modelData.color || modelData.color.toLowerCase() === "#ffffff")
                            ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.15))
                            : "transparent"
                        border.width: 1

                        Behavior on width { NumberAnimation { duration: 120 } }
                        Behavior on height { NumberAnimation { duration: 120 } }

                        // Checkmark inside selected swatch
                        Image {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            source: "qrc:/tsuki_app/icons/actions/check.svg"
                            visible: swatchItem.isSelected
                            scale: swatchItem.isSelected ? 1.0 : 0.5
                            opacity: swatchItem.isSelected ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        HoverHandler {
                            id: swatchHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        ToolTip.visible: swatchHover.hovered
                        ToolTip.text: modelData.name || modelData.color || "Auto"
                        ToolTip.delay: 300

                        TapHandler {
                            onTapped: {
                                root.focusedIndex = swatchItem.index
                                root.colorSelected(modelData.color)
                                root.showCustomInput = false
                            }
                        }
                    }
                }
            }

            // Custom Color Swatch (+)
            Item {
                id: customItem
                width: 34
                height: 34
                visible: root.allowCustom

                readonly property int customIdx: root.presets ? root.presets.length : 0
                readonly property bool isCustomFocused: (root.focusedIndex === customIdx) && root.isNavActive
                readonly property bool isSelected: root.isCustomSelected

                // Outer ring
                Rectangle {
                    anchors.fill: parent
                    radius: 17
                    color: "transparent"
                    border.color: customItem.isCustomFocused
                        ? "#ffffff"
                        : (customItem.isSelected ? appSettings.accentColor : "transparent")
                    border.width: customItem.isCustomFocused ? 2.5 : 2
                    scale: customItem.isCustomFocused ? 1.12 : (customItem.isSelected ? 1.0 : 0.8)
                    opacity: (customItem.isCustomFocused || customItem.isSelected) ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: customItem.isSelected ? 26 : 28
                    height: customItem.isSelected ? 26 : 28
                    radius: width / 2
                    color: customItem.isSelected ? root.currentColor : "transparent"
                    border.color: customItem.isSelected
                        ? appSettings.accentColor
                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.2))
                    border.width: 1.5

                    YIcon {
                        size: 14
                        anchors.centerIn: parent
                        source: customItem.isSelected ? "qrc:/tsuki_app/icons/actions/check.svg" : "qrc:/tsuki_app/icons/actions/add.svg"
                        color: customItem.isSelected ? "#ffffff" : appSettings.textSecColor
                    }

                    HoverHandler {
                        id: customHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    ToolTip.visible: customHover.hovered
                    ToolTip.text: "Custom Color"
                    ToolTip.delay: 300

                    TapHandler {
                        onTapped: {
                            root.focusedIndex = customItem.customIdx
                            root.showCustomInput = !root.showCustomInput
                        }
                    }
                }
            }
        }

        // Custom Hex Input Row
        Row {
            id: hexInputRow
            spacing: 8
            visible: root.allowCustom && (root.isCustomSelected || root.showCustomInput)

            Rectangle {
                width: 22
                height: 22
                radius: 11
                anchors.verticalCenter: parent.verticalCenter
                color: root.currentColor !== "" ? root.currentColor : appSettings.accentColor
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.15)
                border.width: 1
            }

            Rectangle {
                width: 110
                height: 34
                radius: 12
                color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                border.color: hexField.activeFocus ? appSettings.accentColor : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10))
                border.width: hexField.activeFocus ? 2 : 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 4

                    Label {
                        text: "#"
                        color: appSettings.textSecColor
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextField {
                        id: hexField
                        activeFocusOnTab: false
                        width: parent.width - 20
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter
                        color: appSettings.textColor
                        font.pixelSize: 13
                        font.capitalization: Font.AllUppercase
                        placeholderText: (root.currentColor || "").replace("#", "")
                        placeholderTextColor: appSettings.textTerColor
                        selectByMouse: true
                        background: null
                        padding: 0

                        function commitHex() {
                            let hex = text.replace("#", "").trim()
                            if (/^[0-9a-fA-F]{3}$/.test(hex)) {
                                hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2]
                            }
                            if (/^[0-9a-fA-F]{6}$/.test(hex)) {
                                root.colorSelected("#" + hex.toLowerCase())
                                text = ""
                            }
                            root.showCustomInput = false
                            root.forceActiveFocus()
                        }

                        onEditingFinished: commitHex()

                        Keys.onReturnPressed: (event) => {
                            event.accepted = true
                            commitHex()
                        }
                        Keys.onEnterPressed: (event) => {
                            event.accepted = true
                            commitHex()
                        }

                        Keys.onEscapePressed: (event) => {
                            event.accepted = true
                            root.showCustomInput = false
                            root.forceActiveFocus()
                        }
                    }
                }
            }
        }
    }
}
