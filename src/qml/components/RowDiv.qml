import QtQuick

Rectangle {
    width: parent ? parent.width : 0
    height: 1
    color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
    Behavior on color { ColorAnimation { duration: 150 } }
}
