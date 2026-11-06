import QtQuick
import QtQuick.Effects

Item {
    id: root
    property url source: ""
    property color color: "#ffffff"
    property real size: 20

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: false
    }

    MultiEffect {
        source: img
        anchors.fill: img
        colorization: 1.0
        colorizationColor: root.color
    }
}

