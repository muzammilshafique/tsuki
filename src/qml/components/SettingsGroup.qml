import QtQuick
import QtQuick.Controls

Rectangle {
    id: group
    property string iconPath: ""
    property string sectionTitle: ""
    default property alias rows: rowsCol.data
    property alias rowsContainer: rowsCol
    property bool isHighlighted: false

    function highlight() {
        isHighlighted = true
        groupHighlightTimer.restart()
    }

    Timer {
        id: groupHighlightTimer
        interval: 1800
        onTriggered: group.isHighlighted = false
    }

    width: parent ? parent.width : 0
    color: appSettings.surfaceColor
    radius: 24
    border.color: group.isHighlighted
        ? appSettings.accentColor
        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
    border.width: group.isHighlighted ? 2 : 1
    implicitHeight: outerCol.implicitHeight + 36

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 200 } }
    Behavior on border.width { NumberAnimation { duration: 200 } }

    Column {
        id: outerCol
        width: parent.width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 16
        spacing: 4

        // Material 3 Category Header Row
        Row {
            spacing: 10
            width: parent.width - 40
            height: 32
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                source: group.iconPath !== ""
                    ? ("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' height='24' viewBox='0 -960 960 960' width='24'><path fill='" + encodeURIComponent(appSettings.accentColor) + "' d='" + group.iconPath + "'/></svg>")
                    : ""
                width: 22
                height: 22
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
                visible: group.iconPath !== ""
            }

            Label {
                text: group.sectionTitle
                color: appSettings.accentColor
                font.pixelSize: 16
                font.weight: Font.DemiBold
                renderType: Text.QtRendering
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Inset Hairline Divider below header
        Rectangle {
            width: parent.width - 40
            height: 1
            anchors.horizontalCenter: parent.horizontalCenter
            color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
            visible: rowsCol.children && rowsCol.children.length > 0
        }

        // Settings items container
        Column {
            id: rowsCol
            width: parent.width
            spacing: 0
        }

        // Bottom spacer inside card
        Item {
            width: parent.width
            height: 4
        }
    }
}
