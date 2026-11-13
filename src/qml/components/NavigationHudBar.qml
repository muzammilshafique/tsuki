import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts

Item {
    id: root

    property string pageContext: "home" // "home", "settings", "gameDetail", "modal"
    property bool isLibraryActive: true

    readonly property var ctrlMgr: uiController ? uiController.controllerManager : null
    readonly property bool isGamepad: uiController ? uiController.isGamepadActive : false
    readonly property bool showBar: Boolean(uiController && uiController.isKeyboardNavActive)
                                    && (!appSettings || appSettings.showNavigationHud)

    width: Math.min(parent ? parent.width - 40 : 960, hudRow.implicitWidth + 44)
    height: 40

    opacity: showBar ? 1.0 : 0.0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: appSettings.isEffectiveDark
            ? Qt.rgba(0.04, 0.04, 0.06, 0.88)
            : Qt.rgba(0.09, 0.11, 0.15, 0.90)
        border.color: appSettings.isEffectiveDark
            ? Qt.rgba(1, 1, 1, 0.10)
            : Qt.rgba(1, 1, 1, 0.18)
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.65 : 0.38)
            shadowBlur: 0.85
            shadowVerticalOffset: 4
        }
    }

    RowLayout {
        id: hudRow
        anchors.centerIn: parent
        spacing: 18

        // Navigate (D-Pad / Left Stick or Arrow keys)
        GamepadPrompt {
            iconSource: root.ctrlMgr ? root.ctrlMgr.dpadUpIconSource : ""
            secondaryIconSource: root.ctrlMgr ? root.ctrlMgr.leftAnalogIconSource : ""
            keyName: "↑↓←→"
            suffixText: "Navigate"
            pixelSize: 13
            iconSize: 18
            isBold: true
            textColor: "#f8fafc"
            iconColor: "#ffffff"
        }

        // Select (gamepad-down or Enter / Space)
        GamepadPrompt {
            iconSource: root.ctrlMgr ? root.ctrlMgr.confirmIconSource : ""
            keyName: "Enter / Space"
            suffixText: "Select"
            pixelSize: 13
            iconSize: 18
            isBold: true
            textColor: "#f8fafc"
            iconColor: "#ffffff"
        }

        // Options on MediaGrid (gamepad-left or Hold Enter / Space)
        GamepadPrompt {
            visible: root.pageContext === "home" && root.isLibraryActive
            iconSource: root.ctrlMgr ? root.ctrlMgr.optionsIconSource : ""
            keyName: "Hold Enter / Space"
            suffixText: "Options"
            pixelSize: 13
            iconSize: 18
            isBold: true
            textColor: "#f8fafc"
            iconColor: "#ffffff"
        }

        // Search (gamepad-up or /)
        GamepadPrompt {
            visible: root.pageContext === "home" || root.pageContext === "settings"
            iconSource: root.ctrlMgr ? root.ctrlMgr.searchIconSource : ""
            keyName: "/"
            suffixText: "Search"
            pixelSize: 13
            iconSize: 18
            isBold: true
            textColor: "#f8fafc"
            iconColor: "#ffffff"
        }

        // Switch Tab Left / Right (L1/L2 + R1/R2 or [ / ])
        RowLayout {
            visible: root.pageContext === "home" || root.pageContext === "gameDetail"
            spacing: 4

            GamepadPrompt {
                iconSource: root.ctrlMgr ? root.ctrlMgr.tabLeftIconSource : ""
                secondaryIconSource: root.ctrlMgr ? root.ctrlMgr.tabLeftTriggerIconSource : ""
                keyName: "["
                pixelSize: 13
                iconSize: 18
                isBold: true
                textColor: "#f8fafc"
                iconColor: "#ffffff"
            }
            GamepadPrompt {
                iconSource: root.ctrlMgr ? root.ctrlMgr.tabRightIconSource : ""
                secondaryIconSource: root.ctrlMgr ? root.ctrlMgr.tabRightTriggerIconSource : ""
                keyName: "]"
                suffixText: "Tabs"
                pixelSize: 13
                iconSize: 18
                isBold: true
                textColor: "#f8fafc"
                iconColor: "#ffffff"
            }
        }

        // Settings (Tab or PS Options / Xbox Menu)
        GamepadPrompt {
            visible: root.pageContext !== "settings"
            iconSource: root.ctrlMgr ? root.ctrlMgr.settingsIconSource : ""
            keyName: "Tab"
            suffixText: "Settings"
            pixelSize: 13
            iconSize: 18
            isBold: true
            textColor: "#f8fafc"
            iconColor: "#ffffff"
        }

        // Back (gamepad-right or Esc / Backspace)
        GamepadPrompt {
            iconSource: root.ctrlMgr ? root.ctrlMgr.cancelIconSource : ""
            keyName: "Esc / Backspace"
            suffixText: "Back"
            pixelSize: 13
            iconSize: 18
            isBold: true
            textColor: "#f8fafc"
            iconColor: "#ffffff"
        }
    }
}

