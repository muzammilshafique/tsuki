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
    property bool showStops: false
    property alias slider: slider

    function adjustLeft() {
        slider.value = Math.max(slider.from, slider.value - (slider.stepSize || 1))
    }

    function adjustRight() {
        slider.value = Math.min(slider.to, slider.value + (slider.stepSize || 1))
    }

    Row {
        anchors.fill: parent
        spacing: 14

        Slider {
            id: slider
            width: parent.width - valueBadge.width - 14
            anchors.verticalCenter: parent.verticalCenter
            focus: true

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
            }
            Keys.onDownPressed: (event) => {
                event.accepted = true
                if (typeof settingsPage !== "undefined") settingsPage.focusNextSettingRow()
            }

            // Material 3 Track (16dp height, fully rounded radius 8dp, signature handle gap)
            background: Item {
                id: trackContainer
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: 16

                readonly property real handleCenter: slider.visualPosition * (slider.availableWidth - sliderHandle.width) + sliderHandle.width / 2
                readonly property real gapSize: 6

                // Inactive track segment (right of handle)
                Rectangle {
                    x: Math.min(parent.width, trackContainer.handleCenter + trackContainer.gapSize)
                    y: 0
                    width: Math.max(0, parent.width - x)
                    height: parent.height
                    radius: 4
                    color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                // Active track segment (left of handle) - Bar side with reduced radius
                Rectangle {
                    x: 0
                    y: 0
                    width: Math.max(0, Math.min(parent.width, trackContainer.handleCenter - trackContainer.gapSize))
                    height: parent.height
                    radius: 3
                    color: appSettings.accentColor
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            // Material 3 Vertical Pill Handle (44dp height, 4dp/6dp width, radius 2dp/3dp)
            handle: Rectangle {
                id: sliderHandle
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                implicitWidth: (slider.pressed || slider.activeFocus || sliderHover.hovered) ? 6 : 4
                implicitHeight: 44
                radius: (slider.pressed || slider.activeFocus || sliderHover.hovered) ? 3 : 2
                color: appSettings.accentColor

                Behavior on implicitWidth { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on radius { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }

                HoverHandler {
                    id: sliderHover
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }

        // Material 3 Value Badge (Pill container with DemiBold readout)
        Rectangle {
            id: valueBadge
            width: Math.max(56, valLabel.implicitWidth + 20)
            height: 30
            radius: 15
            anchors.verticalCenter: parent.verticalCenter
            color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
            border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
            border.width: 1

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            Label {
                id: valLabel
                anchors.centerIn: parent
                text: Math.round(slider.value) + root.suffix
                color: appSettings.textColor
                font.pixelSize: 12
                font.weight: Font.DemiBold
                renderType: Text.QtRendering
            }
        }
    }
}
