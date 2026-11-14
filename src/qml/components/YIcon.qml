import QtQuick
import QtQuick.Effects

Item {
    id: root
    property string source: ""
    property string symbol: ""
    property bool filled: false
    property color color: "#ffffff"
    property real size: 20

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Text {
        id: symbolIcon
        anchors.centerIn: parent
        visible: root.symbol !== ""
        text: root.symbol
        font.family: "Material Symbols Rounded"
        font.pixelSize: Math.max(1, root.size)
        font.variableAxes: ({
            "opsz": Math.max(20, Math.min(48, Math.round(root.size))),
            "FILL": root.filled ? 1 : 0
        })
        // Native FreeType rasterization uses non-zero contour fill and avoids GPU SDF holes
        // where variable FILL=1 glyphs collapse opposite-winding inner contours.
        renderType: Text.NativeRendering
        color: root.color
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Image {
        id: rawIcon
        anchors.fill: parent
        source: (root.symbol === "" && root.source !== "") ? root.source : ""
        sourceSize: Qt.size(Math.max(16, root.size * 2), Math.max(16, root.size * 2))
        fillMode: Image.PreserveAspectFit
        visible: false
        asynchronous: false
        smooth: true
    }

    MultiEffect {
        anchors.fill: rawIcon
        source: rawIcon
        visible: root.symbol === "" && root.source !== ""
        colorization: 1.0
        colorizationColor: root.color
        Behavior on colorizationColor { ColorAnimation { duration: 120 } }
    }
}
