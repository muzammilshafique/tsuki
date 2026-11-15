import QtQuick
import QtQuick.Controls
import QtQuick.Effects

ToolTip {
    id: tip
    delay: 260
    timeout: 5000
    horizontalPadding: 12
    verticalPadding: 7
    margins: 8
    closePolicy: Popup.CloseOnEscape

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.94; to: 1.0; duration: 120; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 90; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.96; duration: 90; easing.type: Easing.InCubic }
        }
    }

    TextMetrics {
        id: tipMetrics
        font.family: "Rubik"
        font.pixelSize: 12
        font.weight: Font.Medium
        text: tip.text
    }

    contentWidth: Math.min(260, Math.ceil(tipMetrics.advanceWidth) + 2)

    contentItem: Label {
        text: tip.text
        color: appSettings.textColor
        font.family: "Rubik"
        font.pixelSize: 12
        font.weight: Font.Medium
        lineHeight: 1.25
        wrapMode: Text.WordWrap
        renderType: Text.QtRendering
    }

    background: Rectangle {
        radius: 10
        color: appSettings.surfaceContainerHighest
        border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.14) : appSettings.borderColor
        border.width: 1

        layer.enabled: tip.visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.45 : 0.18)
            shadowBlur: 0.5
            shadowVerticalOffset: 3
        }
    }
}

