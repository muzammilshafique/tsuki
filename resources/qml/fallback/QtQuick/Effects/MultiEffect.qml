import QtQuick

Item {
    id: root
    property var source
    property bool autoPaddingEnabled: true
    property rect paddingRect: Qt.rect(0, 0, 0, 0)
    property rect itemRect: Qt.rect(0, 0, width, height)
    property bool hasProxySerial: false

    property bool blurEnabled: false
    property real blur: 0.0
    property real blurMax: 32.0
    property real blurMultiplier: 1.0

    property bool shadowEnabled: false
    property color shadowColor: "#000000"
    property real shadowBlur: 1.0
    property real shadowScale: 1.0
    property real shadowHorizontalOffset: 0.0
    property real shadowVerticalOffset: 0.0
    property real shadowOpacity: 1.0

    property bool maskEnabled: false
    property var maskSource
    property real maskThresholdMin: 0.0
    property real maskSpreadAtMin: 0.0
    property real maskThresholdMax: 1.0
    property real maskSpreadAtMax: 0.0
    property bool maskInverted: false

    property real colorization: 0.0
    property color colorizationColor: "#ffffff"
    property real brightness: 0.0
    property real contrast: 0.0
    property real saturation: 0.0

    Component.onCompleted: {
        if (root.source && typeof root.source === "object" && "visible" in root.source && !root.source.visible) {
            root.source.visible = true
        }
    }

    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: (root.source && typeof root.source === "object") ? root.source : null
        visible: root.source !== null && root.source !== undefined
    }
}
