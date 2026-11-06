import QtQuick
import QtQuick.Controls

Item {
    id: toggle
    property bool checked: false
    signal toggled(bool c)

    implicitWidth: 52
    implicitHeight: 32
    focus: true

    function toggleIt() {
        toggle.checked = !toggle.checked
        toggle.toggled(toggle.checked)
    }

    Keys.onReturnPressed: (event) => { event.accepted = true; toggleIt() }
    Keys.onEnterPressed: (event) => { event.accepted = true; toggleIt() }
    Keys.onSpacePressed: (event) => { event.accepted = true; toggleIt() }
    Keys.onLeftPressed: (event) => {
        if (toggle.checked) {
            event.accepted = true
            toggleIt()
        }
    }
    Keys.onRightPressed: (event) => {
        if (!toggle.checked) {
            event.accepted = true
            toggleIt()
        }
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: 16

        color: toggle.checked
            ? appSettings.accentColor
            : (toggle.activeFocus
                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)))

        border.color: {
            if (toggle.activeFocus) {
                return toggle.checked
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.2))
                    : appSettings.accentColor
            }
            return toggle.checked
                ? appSettings.accentColor
                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.24))
        }
        border.width: toggle.activeFocus ? 2.5 : (toggle.checked ? 0 : 2)
        scale: toggle.activeFocus ? 1.05 : 1.0

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
                    return appSettings.isEffectiveDark ? "#111114" : "#ffffff"
                }
                if (toggle.activeFocus) return appSettings.accentColor
                return appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.70) : Qt.rgba(0, 0, 0, 0.60)
            }

            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 150 } }

            // Checkmark icon inside selected thumb
            Image {
                anchors.centerIn: parent
                width: 14
                height: 14
                source: "qrc:/tsuki_app/icons/actions/check.svg"
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
