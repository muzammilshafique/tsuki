import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 48 : 520, 520)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string gameId: ""
    property string artType: "cover"
    property string artTypeName: "Poster Cover"
    property string initialUrl: ""

    function openFor(gId, type, typeName) {
        gameId = gId
        artType = type
        artTypeName = typeName
        urlInput.text = ""
        root.open()
        Qt.callLater(() => urlInput.forceActiveFocus())
    }

    background: Rectangle {
        color: appSettings.surfaceColor
        radius: 20
        border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.6 : 0.25)
            shadowBlur: 0.8
            shadowVerticalOffset: 8
        }
    }

    contentItem: ColumnLayout {
        spacing: 0
        Keys.onBackPressed: (event) => {
            if (urlInput.isEditing) { urlInput.returnFocusToRow(); event.accepted = true; return }
            event.accepted = true
            root.close()
        }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Backspace && !urlInput.isEditing) {
                event.accepted = true
                root.close()
            }
        }

        // ── Dialog Header ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 20
                spacing: 12

                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: Qt.rgba(appSettings.accentColor.r, appSettings.accentColor.g, appSettings.accentColor.b, 0.15)
                    YIcon {
                        anchors.centerIn: parent
                        size: 18
                        source: "qrc:/tsuki_app/icons/actions/download.svg"
                        color: appSettings.accentColor
                    }
                }

                Label {
                    text: "Set " + root.artTypeName + " from Link"
                    color: appSettings.textColor
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                ToolButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    background: Rectangle {
                        radius: 16
                        color: parent.hovered ? appSettings.surfaceAltColor : "transparent"
                    }
                    contentItem: YIcon {
                        anchors.centerIn: parent
                        source: "qrc:/tsuki_app/icons/actions/close.svg"
                        color: appSettings.textSecColor
                        size: 16
                    }
                    onClicked: root.close()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
            }
        }

        // ── Dialog Body ──────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 24
            spacing: 14

            Label {
                text: "Paste a direct image web URL (SteamGridDB, Steam CDN, Imgur, or direct .jpg/.png link). Tsuki will download and set it automatically."
                color: appSettings.textSecColor
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                lineHeight: 1.3
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    text: "Image Web Link (URL)"
                    color: appSettings.textColor
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                M3TextField {
                    id: urlInput
                    twoStageFocus: true
                    Layout.fillWidth: true
                    placeholderText: "https://.../image.jpg"
                    onCommit: (val) => {
                        if (val.trim().length > 0) {
                            uiController.gameManager.setGameArtworkFromUrl(root.gameId, root.artType, val.trim())
                            root.close()
                        }
                    }
                    Keys.onDownPressed: (event) => {
                        if (!isEditing) {
                            event.accepted = true
                            if (downloadBtn.enabled) downloadBtn.forceActiveFocus()
                            else cancelUrlBtn.forceActiveFocus()
                        }
                    }
                }
            }
        }

        // ── Dialog Footer ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 12

                Item { Layout.fillWidth: true }

                M3Button {
                    id: cancelUrlBtn
                    text: "Cancel"
                    buttonType: "tonal"
                    onClicked: root.close()
                    Keys.onRightPressed: (event) => { if (downloadBtn.enabled) { event.accepted = true; downloadBtn.forceActiveFocus() } }
                    Keys.onUpPressed: (event) => { event.accepted = true; urlInput.forceActiveFocus() }
                }

                M3Button {
                    id: downloadBtn
                    text: "Download & Set"
                    iconSource: "qrc:/tsuki_app/icons/actions/download.svg"
                    buttonType: "filled"
                    enabled: urlInput.text.trim().length > 0
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: {
                        let link = urlInput.text.trim()
                        if (link.length > 0) {
                            uiController.gameManager.setGameArtworkFromUrl(root.gameId, root.artType, link)
                            root.close()
                        }
                    }
                    Keys.onLeftPressed: (event) => { event.accepted = true; cancelUrlBtn.forceActiveFocus() }
                    Keys.onUpPressed: (event) => { event.accepted = true; urlInput.forceActiveFocus() }
                }
            }
        }
    }
}

