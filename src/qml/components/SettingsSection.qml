import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: section
    property string sectionTitle: ""
    property string infoTip: ""
    property bool showDivider: false
    default property alias content: innerCol.data
    property alias contentContainer: innerCol

    Layout.fillWidth: true
    spacing: 12

    // Subtle hairline separator between sections inside the content surface
    Rectangle {
        visible: section.showDivider
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.bottomMargin: 2
        height: 1
        color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.07)
    }

    // Crisp 1-line Section Heading
    RowLayout {
        visible: section.sectionTitle !== ""
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: section.sectionTitle
            color: appSettings.textColor
            font.family: "Rubik"
            font.pixelSize: 17
            font.weight: Font.DemiBold
            renderType: Text.QtRendering
        }

        Item {
            visible: section.infoTip !== ""
            width: 20
            height: 20
            Layout.alignment: Qt.AlignVCenter

            YIcon {
                anchors.centerIn: parent
                symbol: "info"
                size: 15
                color: secInfoHover.hovered ? appSettings.accentColor : appSettings.textTerColor
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            HoverHandler {
                id: secInfoHover
                cursorShape: Qt.WhatsThisCursor
            }
            M3ToolTip {
                visible: secInfoHover.hovered
                text: section.infoTip
            }
        }

        Item { Layout.fillWidth: true }
    }

    ColumnLayout {
        id: innerCol
        Layout.fillWidth: true
        spacing: 10
    }
}

