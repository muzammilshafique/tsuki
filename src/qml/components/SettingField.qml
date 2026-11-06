import QtQuick
import QtQuick.Controls

TextField {
    id: sf
    signal commit(string text)
    
    implicitWidth: 100
    implicitHeight: 34
    width: implicitWidth
    height: implicitHeight
    
    color: appSettings.textColor
    font.pixelSize: 13
    leftPadding: 12
    rightPadding: 12
    selectByMouse: true
    placeholderTextColor: appSettings.textTerColor
    
    background: Rectangle {
        radius: 10
        color: sf.activeFocus
            ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
            : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
        border.color: sf.activeFocus
            ? appSettings.accentColor
            : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
        border.width: sf.activeFocus ? 2 : 1
        scale: sf.activeFocus ? 1.02 : 1.0

        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 120 } }
    }
    
    property Item returnFocusItem: null

    onEditingFinished: {
        if (text.length > 0) {
            sf.commit(text)
        }
    }

    Keys.onReturnPressed: (event) => {
        event.accepted = true
        if (text.length > 0) sf.commit(text)
        if (returnFocusItem && typeof returnFocusItem.forceActiveFocus === "function") {
            returnFocusItem.forceActiveFocus()
        } else {
            sf.focus = false
        }
    }

    Keys.onEnterPressed: (event) => {
        event.accepted = true
        if (text.length > 0) sf.commit(text)
        if (returnFocusItem && typeof returnFocusItem.forceActiveFocus === "function") {
            returnFocusItem.forceActiveFocus()
        } else {
            sf.focus = false
        }
    }

    Keys.onEscapePressed: (event) => {
        event.accepted = true
        if (returnFocusItem && typeof returnFocusItem.forceActiveFocus === "function") {
            returnFocusItem.forceActiveFocus()
        } else {
            sf.focus = false
        }
    }
}
