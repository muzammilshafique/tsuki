import QtQuick
import QtQuick.Controls

Item {
    id: root
    implicitWidth: 240
    implicitHeight: 44
    focus: true
    activeFocusOnTab: false

    property alias from: slider.from
    property alias to: slider.to
    property alias value: slider.value
    property alias stepSize: slider.stepSize
    property alias snapMode: slider.snapMode
    property string suffix: " px"
    property int decimals: 0
    property bool showStops: false
    property alias slider: slider
    property bool isAdjusting: false
    readonly property bool isParentTileFocused: {
        let p = root.parent
        while (p) {
            if (p.isTvFocused !== undefined) return Boolean(p.isTvFocused)
            p = p.parent
        }
        return false
    }
    readonly property bool hasLogicalFocus: root.activeFocus || slider.activeFocus || isParentTileFocused
    readonly property bool kbFocused: Boolean(uiController && uiController.isKeyboardNavActive) && hasLogicalFocus
    signal moveUp()
    signal moveDown()

    onHasLogicalFocusChanged: {
        if (!hasLogicalFocus && isAdjusting) {
            isAdjusting = false
        }
    }

    function normalizeValue(v) {
        if (root.decimals <= 0) return v
        const factor = Math.pow(10, root.decimals)
        return Math.round(v * factor) / factor
    }

    function adjustLeft() {
        const next = normalizeValue(Math.max(slider.from, slider.value - (slider.stepSize || 1)))
        if (next !== slider.value) {
            slider.value = next
            slider.moved()
        }
    }

    function adjustRight() {
        const next = normalizeValue(Math.min(slider.to, slider.value + (slider.stepSize || 1)))
        if (next !== slider.value) {
            slider.value = next
            slider.moved()
        }
    }

    function enterAdjustMode() {
        root.isAdjusting = true
    }

    function exitAdjustMode() {
        root.isAdjusting = false
    }

    function activate() {
        root.isAdjusting = !root.isAdjusting
    }

    function handleLeft() {
        if (!root.isAdjusting) return false
        root.adjustLeft()
        return true
    }

    function handleRight() {
        if (!root.isAdjusting) return false
        root.adjustRight()
        return true
    }

    Keys.onLeftPressed: (event) => {
        if (root.isAdjusting) {
            event.accepted = true
            root.adjustLeft()
        } else {
            event.accepted = false
        }
    }
    Keys.onRightPressed: (event) => {
        if (root.isAdjusting) {
            event.accepted = true
            root.adjustRight()
        } else {
            event.accepted = false
        }
    }
    Keys.onReturnPressed: (event) => {
        event.accepted = true
        root.activate()
    }
    Keys.onEnterPressed: (event) => {
        event.accepted = true
        root.activate()
    }
    Keys.onSpacePressed: (event) => {
        event.accepted = true
        root.activate()
    }
    Keys.onEscapePressed: (event) => {
        if (root.isAdjusting) {
            event.accepted = true
            root.exitAdjustMode()
        } else {
            event.accepted = false
        }
    }
    Keys.onBackPressed: (event) => {
        if (root.isAdjusting) {
            event.accepted = true
            root.exitAdjustMode()
        } else {
            event.accepted = false
        }
    }
    Keys.onUpPressed: (event) => {
        root.isAdjusting = false
        event.accepted = true
        if (typeof settingsPage !== "undefined" && settingsPage.focusPrevSettingRow) settingsPage.focusPrevSettingRow()
        else root.moveUp()
    }
    Keys.onDownPressed: (event) => {
        root.isAdjusting = false
        event.accepted = true
        if (typeof settingsPage !== "undefined" && settingsPage.focusNextSettingRow) settingsPage.focusNextSettingRow()
        else root.moveDown()
    }

    Row {
        anchors.fill: parent
        spacing: 14

        Slider {
            id: slider
            width: parent.width - valueBadge.width - 14
            anchors.verticalCenter: parent.verticalCenter
            focus: false
            focusPolicy: Qt.NoFocus
            activeFocusOnTab: false
            readonly property bool kbFocused: root.kbFocused

            // Material 3 Medium Slider Track (16dp height, pill outer ends, 2dp inner handle corners, 6dp gap + end stop dot)
            background: Item {
                id: trackContainer
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: 16

                readonly property real handleCenter: slider.visualPosition * (slider.availableWidth - sliderHandle.width) + sliderHandle.width / 2
                readonly property real gapHalfSpan: sliderHandle.width / 2 + 6

                // Inactive track segment (right of handle)
                Rectangle {
                    id: inactiveTrack
                    x: Math.min(parent.width, trackContainer.handleCenter + trackContainer.gapHalfSpan)
                    y: 0
                    width: Math.max(0, parent.width - x)
                    height: parent.height
                    visible: width > 1
                    topLeftRadius: 2
                    bottomLeftRadius: 2
                    topRightRadius: 8
                    bottomRightRadius: 8
                    color: appSettings.secondaryContainer
                    Behavior on color { ColorAnimation { duration: 150 } }

                    // End-stop indicator dot inside inactive cap
                    Rectangle {
                        width: 4
                        height: 4
                        radius: 2
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: appSettings.onSecondaryContainer
                        opacity: inactiveTrack.width >= 14 ? 0.85 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                // Active track segment (left of handle)
                Rectangle {
                    x: 0
                    y: 0
                    width: Math.max(0, Math.min(parent.width, trackContainer.handleCenter - trackContainer.gapHalfSpan))
                    height: parent.height
                    visible: width > 1
                    topLeftRadius: 8
                    bottomLeftRadius: 8
                    topRightRadius: 2
                    bottomRightRadius: 2
                    color: appSettings.accentColor
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            // Material 3 Medium Vertical Handle (44dp height, 4dp/5dp width, full pill radius)
            handle: Rectangle {
                id: sliderHandle
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                implicitWidth: slider.pressed ? 3 : (root.isAdjusting ? 6 : ((slider.kbFocused || sliderHover.hovered) ? 5 : 4))
                implicitHeight: 44
                radius: implicitWidth / 2
                color: appSettings.accentColor

                Behavior on implicitWidth { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }

                HoverHandler {
                    id: sliderHover
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }

        // Material 3 Value Badge (Tonal Pill container with DemiBold readout + active adjust indicator)
        Rectangle {
            id: valueBadge
            width: Math.max(56, valLabel.implicitWidth + 20)
            height: 30
            radius: 15
            anchors.verticalCenter: parent.verticalCenter
            color: root.isAdjusting ? appSettings.accentColor : appSettings.surfaceContainerHigh
            border.color: appSettings.accentColor
            border.width: (!root.isAdjusting && root.kbFocused) ? 1.5 : 0

            Behavior on color { ColorAnimation { duration: 150 } }

            Label {
                id: valLabel
                anchors.centerIn: parent
                readonly property string formattedValue: (root.decimals > 0 ? Number(slider.value).toFixed(root.decimals) : Math.round(slider.value)) + root.suffix
                text: root.isAdjusting ? ("◀ " + formattedValue + " ▶") : formattedValue
                color: root.isAdjusting ? appSettings.onPrimary : appSettings.textColor
                font.family: "Rubik"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                renderType: Text.QtRendering
            }
        }
    }
}
