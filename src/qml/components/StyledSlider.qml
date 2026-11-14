import QtQuick
import QtQuick.Controls

Item {
    id: root
    implicitWidth: 240
    implicitHeight: 44

    property alias from: slider.from
    property alias to: slider.to
    property alias value: slider.value
    property alias stepSize: slider.stepSize
    property alias snapMode: slider.snapMode
    property string suffix: " px"
    property int decimals: 0
    property bool showStops: false
    property alias slider: slider
    signal moveUp()
    signal moveDown()

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

    Row {
        anchors.fill: parent
        spacing: 14

        Slider {
            id: slider
            width: parent.width - valueBadge.width - 14
            anchors.verticalCenter: parent.verticalCenter
            focus: true
            activeFocusOnTab: false
            readonly property bool kbFocused: slider.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)

            Keys.onLeftPressed: (event) => {
                event.accepted = true
                root.adjustLeft()
            }
            Keys.onRightPressed: (event) => {
                event.accepted = true
                root.adjustRight()
            }
            Keys.onUpPressed: (event) => {
                event.accepted = true
                if (typeof settingsPage !== "undefined") settingsPage.focusPrevSettingRow()
                else root.moveUp()
            }
            Keys.onDownPressed: (event) => {
                event.accepted = true
                if (typeof settingsPage !== "undefined") settingsPage.focusNextSettingRow()
                else root.moveDown()
            }

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
                implicitWidth: slider.pressed ? 3 : ((slider.kbFocused || sliderHover.hovered) ? 5 : 4)
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

        // Material 3 Value Badge (Tonal Pill container with DemiBold readout)
        Rectangle {
            id: valueBadge
            width: Math.max(56, valLabel.implicitWidth + 20)
            height: 30
            radius: 15
            anchors.verticalCenter: parent.verticalCenter
            color: appSettings.surfaceContainerHigh

            Behavior on color { ColorAnimation { duration: 150 } }

            Label {
                id: valLabel
                anchors.centerIn: parent
                text: (root.decimals > 0 ? Number(slider.value).toFixed(root.decimals) : Math.round(slider.value)) + root.suffix
                color: appSettings.textColor
                font.family: "Rubik"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                renderType: Text.QtRendering
            }
        }
    }
}
