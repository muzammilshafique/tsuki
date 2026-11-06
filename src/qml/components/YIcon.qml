import QtQuick
import QtQuick.Effects

Item {
    id: root
    property string source: ""
    property color color: "#ffffff"
    property real size: 20

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        id: rawIcon
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(Math.max(16, root.size * 2), Math.max(16, root.size * 2))
        fillMode: Image.PreserveAspectFit
        visible: false
        asynchronous: false
        smooth: true
    }

    MultiEffect {
        anchors.fill: rawIcon
        source: rawIcon
        colorization: 1.0
        colorizationColor: root.color
        Behavior on colorizationColor { ColorAnimation { duration: 120 } }
    }
}
