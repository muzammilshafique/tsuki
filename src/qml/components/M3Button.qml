import QtQuick
import QtQuick.Controls


Item {
    id: root
    property string text: ""
    property string iconSource: ""
    property string buttonType: "tonal" // "tonal", "outlined", "filled", "destructive"
    property alias buttonStyle: root.buttonType
    property bool isSuccess: false
    property string successText: "Cleared ✓"
    readonly property bool kbFocused: root.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
    signal clicked()

    implicitWidth: Math.max(80, buttonRow.implicitWidth + 32)
    implicitHeight: 38
    focus: true
    activeFocusOnTab: false

    Keys.onSpacePressed: (event) => {
        event.accepted = true
        root.clicked()
    }
    Keys.onReturnPressed: (event) => {
        event.accepted = true
        root.clicked()
    }
    Keys.onEnterPressed: (event) => {
        event.accepted = true
        root.clicked()
    }

    Rectangle {
        id: btnBg
        anchors.fill: parent
        radius: height / 2

        readonly property bool isHovered: btnMa.containsMouse || root.kbFocused
        readonly property bool isPressed: btnMa.pressed

        color: {
            if (root.isSuccess) {
                return Qt.rgba(0.13, 0.77, 0.36, isHovered ? 0.25 : 0.15)
            }
            if (root.buttonType === "destructive") {
                return isHovered ? "#ef4444" : (appSettings.isEffectiveDark ? Qt.rgba(0.93, 0.27, 0.27, 0.12) : Qt.rgba(0.93, 0.27, 0.27, 0.08))
            }
            if (root.buttonType === "filled") {
                return appSettings.accentColor
            }
            if (root.buttonType === "outlined") {
                return isHovered
                    ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                    : "transparent"
            }
            // default tonal
            return isHovered
                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05))
        }

        border.color: {
            if (root.kbFocused) return appSettings.accentColor
            if (root.isSuccess) return "#22c55e"
            if (root.buttonType === "destructive") return isHovered ? "#ef4444" : Qt.rgba(0.93, 0.27, 0.27, 0.3)
            if (root.buttonType === "outlined") return appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.15)
            return "transparent"
        }
        border.width: root.kbFocused ? 2 : (root.buttonType === "outlined" || root.isSuccess ? 1 : 0)
        scale: isPressed ? 0.97 : (root.kbFocused ? 1.02 : 1.0)

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 120 } }

        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 8

            YIcon {
                size: 16
                source: root.isSuccess ? "qrc:/tsuki_app/icons/actions/check.svg" : (root.iconSource || "")
                visible: root.isSuccess || (root.iconSource || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                color: {
                    if (root.isSuccess) return "#22c55e"
                    if (root.buttonType === "destructive") return btnBg.isHovered ? "#ffffff" : "#ef4444"
                    if (root.buttonType === "filled") return appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff"
                    return appSettings.textColor
                }
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Label {
                text: root.isSuccess ? root.successText : root.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
                renderType: Text.QtRendering
                anchors.verticalCenter: parent.verticalCenter
                color: {
                    if (root.isSuccess) return "#22c55e"
                    if (root.buttonType === "destructive") return btnBg.isHovered ? "#ffffff" : "#ef4444"
                    if (root.buttonType === "filled") return appSettings.isEffectiveDark ? "#0f0f11" : "#ffffff"
                    return appSettings.textColor
                }
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}
