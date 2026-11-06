import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: root
    spacing: 6

    property string prefixText: ""
    property url iconSource: ""
    property string keyName: ""
    property string suffixText: ""
    property color textColor: appSettings.textSecColor
    property color iconColor: appSettings.accentColor
    property int pixelSize: 13
    property int iconSize: 16
    property bool isBold: false

    Label {
        visible: root.prefixText.length > 0
        text: root.prefixText
        color: root.textColor
        font.pixelSize: root.pixelSize
        font.weight: root.isBold ? Font.DemiBold : Font.Normal
        renderType: Text.QtRendering
    }

    YIcon {
        visible: root.iconSource.toString().length > 0
        source: root.iconSource
        color: root.iconColor
        size: root.iconSize
    }

    Rectangle {
        visible: root.keyName.length > 0 && root.iconSource.toString().length === 0
        implicitWidth: keyLbl.implicitWidth + 10
        implicitHeight: root.iconSize + 4
        radius: 4
        color: Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 0.16)
        border.color: root.iconColor
        border.width: 1

        Label {
            id: keyLbl
            anchors.centerIn: parent
            text: root.keyName
            color: root.iconColor
            font.pixelSize: root.pixelSize - 2
            font.weight: Font.DemiBold
            renderType: Text.QtRendering
        }
    }

    Label {
        visible: root.suffixText.length > 0
        text: root.suffixText
        color: root.textColor
        font.pixelSize: root.pixelSize
        font.weight: root.isBold ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
        Layout.fillWidth: true
        renderType: Text.QtRendering
    }
}

