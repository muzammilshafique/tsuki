import QtQuick

Item {
    id: root

    property url source: ""
    property int sourceWidth: 256
    property int sourceHeight: 384
    property real topRadius: 11
    property real bottomRadius: 0
    property color placeholderColor: "#1a1a22"
    property real topVignetteAlpha: 0.0
    property real topVignetteHeight: 48
    property real bottomVignetteAlpha: 0.0
    property real bottomVignetteHeight: 36
    property real darkenAlpha: 0.0

    readonly property int status: coverImg.status
    readonly property bool isReady: coverImg.status === Image.Ready
    readonly property bool useShader: GraphicsInfo.api !== GraphicsInfo.Software
                                      && GraphicsInfo.api !== GraphicsInfo.Unknown

    // Rounded placeholder fill (works on all Qt 6 versions without FBOs)
    Rectangle {
        anchors.fill: parent
        radius: Math.max(0, root.topRadius)
        color: root.placeholderColor
        antialiasing: true
    }

    // Flatten bottom corners of placeholder when metadata sits below the cover
    Rectangle {
        visible: root.bottomRadius < root.topRadius && root.topRadius > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.min(parent.height / 2, Math.max(0, root.topRadius))
        radius: Math.max(0, root.bottomRadius)
        color: root.placeholderColor
        antialiasing: true
    }

    // Texture source (hidden on GPU backends where ShaderEffect renders it directly with 0 FBOs)
    Image {
        id: coverImg
        anchors.fill: parent
        source: root.source
        sourceSize.width: root.sourceWidth
        sourceSize.height: root.sourceHeight
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: false
        visible: !root.useShader && status === Image.Ready
    }

    // 0-FBO GPU rounded-corner + PreserveAspectCrop + vignette/darken pass
    ShaderEffect {
        id: coverShader
        anchors.fill: parent
        visible: root.useShader && coverImg.status === Image.Ready
        property variant source: coverImg
        property size itemSize: Qt.size(Math.max(1, width), Math.max(1, height))
        property size texSize: Qt.size(Math.max(1, coverImg.implicitWidth), Math.max(1, coverImg.implicitHeight))
        property real topRadius: Math.max(0, root.topRadius)
        property real bottomRadius: Math.max(0, root.bottomRadius)
        property real topVignetteAlpha: root.topVignetteAlpha
        property real topVignetteHeight: root.topVignetteHeight
        property real bottomVignetteAlpha: root.bottomVignetteAlpha
        property real bottomVignetteHeight: root.bottomVignetteHeight
        property real darkenAlpha: root.darkenAlpha
        fragmentShader: "qrc:/tsuki_app/shaders/rounded_cover.frag.qsb"
    }

    // Darken overlay fallback when no cover image is ready (or on software backend)
    Rectangle {
        visible: (!root.useShader || !root.isReady) && root.darkenAlpha > 0.001
        anchors.fill: parent
        radius: Math.max(0, root.topRadius)
        color: Qt.rgba(0, 0, 0, root.darkenAlpha)
        antialiasing: true
    }
}

