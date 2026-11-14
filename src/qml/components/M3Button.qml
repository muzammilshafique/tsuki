import QtQuick
import QtQuick.Controls


Item {
    id: root
    property string text: ""
    property string iconSource: ""
    property string iconSymbol: ""
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
        anchors.fill: btnBg
        anchors.margins: -3
        radius: (btnBg.height / 2) + 3
        color: Qt.rgba(0, 0, 0, 0)
        border.width: 2
        border.color: appSettings.accentColor
        visible: root.kbFocused
    }

    Rectangle {
        id: btnBg
        anchors.fill: parent
        radius: height / 2

        readonly property bool isHovered: btnMa.containsMouse || root.kbFocused
        readonly property bool isPressed: btnMa.pressed

        readonly property color contentColor: {
            if (root.isSuccess) return "#22c55e"
            if (root.buttonType === "destructive") return isHovered ? "#ffffff" : "#ef4444"
            if (root.buttonType === "filled") return appSettings.onPrimary
            if (root.buttonType === "outlined") return appSettings.textColor
            return appSettings.onSecondaryContainer
        }

        color: {
            if (root.isSuccess) {
                return Qt.rgba(0.13, 0.77, 0.36, isHovered ? 0.25 : 0.16)
            }
            if (root.buttonType === "destructive") {
                return isHovered ? "#ef4444" : Qt.rgba(0.93, 0.27, 0.27, appSettings.isEffectiveDark ? 0.14 : 0.10)
            }
            if (root.buttonType === "filled") {
                return appSettings.accentColor
            }
            if (root.buttonType === "outlined") {
                return Qt.rgba(appSettings.surfaceContainerHigh.r, appSettings.surfaceContainerHigh.g, appSettings.surfaceContainerHigh.b, 0.0)
            }
            // default tonal
            return appSettings.secondaryContainer
        }

        border.color: {
            if (root.isSuccess) return "#22c55e"
            if (root.buttonType === "outlined") {
                return isHovered
                    ? appSettings.accentColor
                    : Qt.rgba(appSettings.textColor.r, appSettings.textColor.g, appSettings.textColor.b, appSettings.isEffectiveDark ? 0.22 : 0.18)
            }
            return Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.0)
        }
        border.width: (root.buttonType === "outlined" || root.isSuccess) ? 1 : 0
        scale: isPressed ? 0.97 : (root.kbFocused ? 1.02 : 1.0)

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 120 } }

        // Outlined hover container fill (opacity-only so it never interpolates through #00000000)
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: appSettings.surfaceContainerHigh
            opacity: (!root.isSuccess && root.buttonType === "outlined" && btnBg.isHovered) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }

        // Subtle tonal state layer on hover / press for filled and tonal variants
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: {
                if (root.buttonType === "filled") return appSettings.onPrimary
                if (appSettings.isEffectiveDark) return "#ffffff"
                return appSettings.accentColor
            }
            opacity: (!root.isSuccess && root.buttonType !== "destructive" && root.buttonType !== "outlined")
                ? (btnBg.isPressed ? 0.14 : (btnBg.isHovered ? (root.buttonType === "filled" ? 0.12 : 0.09) : 0.0))
                : 0.0
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }

        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 8

            YIcon {
                size: 18
                symbol: root.isSuccess ? "check" : (root.iconSymbol || "")
                source: (root.isSuccess || (root.iconSymbol || "") !== "") ? "" : (root.iconSource || "")
                visible: root.isSuccess || (root.iconSymbol || "") !== "" || (root.iconSource || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                color: btnBg.contentColor
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Label {
                text: root.isSuccess ? root.successText : root.text
                font.family: "Rubik"
                font.pixelSize: 14
                font.weight: Font.Medium
                renderType: Text.QtRendering
                anchors.verticalCenter: parent.verticalCenter
                color: btnBg.contentColor
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
