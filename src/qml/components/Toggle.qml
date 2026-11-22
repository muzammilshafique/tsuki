import QtQuick
import QtQuick.Controls

Item {
    id: toggle
    property bool checked: false
    readonly property bool kbFocused: toggle.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
    signal toggled(bool c)

    implicitWidth: 52
    implicitHeight: 32
    focus: true
    activeFocusOnTab: false

    function toggleIt() {
        toggle.checked = !toggle.checked
        toggle.toggled(toggle.checked)
    }

    Keys.onReturnPressed: (event) => { event.accepted = true; toggleIt() }
    Keys.onEnterPressed: (event) => { event.accepted = true; toggleIt() }
    Keys.onSpacePressed: (event) => { event.accepted = true; toggleIt() }

    Rectangle {
        id: focusRing
        objectName: "toggleFocusRing"
        anchors.fill: track
        anchors.margins: -5
        radius: track.radius + 5
        color: "transparent"
        border.width: 2
        border.color: appSettings.accentColor
        visible: toggle.kbFocused
    }

    Rectangle {
        id: track
        objectName: "toggleTrack"
        anchors.fill: parent
        radius: 16

        color: toggle.checked ? appSettings.accentColor : appSettings.surfaceContainerHighest
        border.color: toggle.checked ? "transparent" : appSettings.textTerColor
        border.width: toggle.checked ? 0 : 1.5
        scale: toggleMa.pressed ? 0.96 : 1.0

        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on border.width { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 120 } }

        // Hover overlay
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: appSettings.isEffectiveDark ? "#ffffff" : "#000000"
            opacity: toggleMa.containsMouse ? (toggle.checked ? 0.08 : 0.05) : 0.0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        // M3 Dynamic Thumb
        Rectangle {
            id: thumb
            readonly property bool isPressed: toggleMa.pressed
            readonly property real targetSize: isPressed ? 28 : (toggle.checked ? 24 : 16)
            readonly property real targetX: {
                if (toggle.checked) {
                    return isPressed ? (track.width - 28 - 2) : (track.width - 24 - 4)
                } else {
                    return isPressed ? 2 : 8
                }
            }

            width: targetSize
            height: targetSize
            radius: targetSize / 2
            anchors.verticalCenter: parent.verticalCenter
            x: targetX

            color: {
                if (toggle.checked) {
                    return appSettings.onPrimary
                }
                if (toggle.kbFocused) return appSettings.accentColor
                return appSettings.textSecColor
            }

            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 150 } }

            // Checkmark icon inside selected thumb
            YIcon {
                anchors.centerIn: parent
                size: 16
                symbol: "check"
                color: appSettings.accentColor
                visible: opacity > 0.01
                opacity: toggle.checked && !thumb.isPressed ? 1.0 : 0.0
                scale: toggle.checked ? 1.0 : 0.4
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            }
        }

        MouseArea {
            id: toggleMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggleIt()
        }
    }
}
