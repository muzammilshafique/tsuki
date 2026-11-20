import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 48 : 500, 500)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string targetGameId: ""
    property string targetTitle: ""
    property string targetPrefixId: ""
    property string prefixName: ""
    property bool hasDedicatedPrefix: false
    property bool isEpicGame: false
    property bool isInPlaceImported: false
    property string epicInstallDir: ""

    signal gameRemoved(string gameId)

    function openDialog(gameId, title, prefixId) {
        targetGameId = gameId
        targetTitle = title
        targetPrefixId = prefixId || ""
        deletePrefixToggle.checked = false

        let gMap = (uiController && uiController.gameManager) ? uiController.gameManager.getGameMap(gameId) : ({})
        isEpicGame = Boolean(gMap && gMap.isEpic)
        isInPlaceImported = Boolean(gMap && gMap.epicInPlaceImported)
        epicInstallDir = (gMap && gMap.epicInstallDir) ? gMap.epicInstallDir : ""
        deleteEpicFilesToggle.checked = isEpicGame && !isInPlaceImported

        if (targetPrefixId.length > 0 && targetPrefixId !== "default-prefix") {
            let pMap = uiController.prefixManager.getPrefixMap(targetPrefixId)
            prefixName = pMap.name || targetPrefixId
            hasDedicatedPrefix = true
        } else {
            prefixName = ""
            hasDedicatedPrefix = false
        }

        root.open()
        Qt.callLater(() => {
            if (root.isEpicGame) deleteEpicFilesToggle.forceActiveFocus()
            else if (root.hasDedicatedPrefix) deletePrefixToggle.forceActiveFocus()
            else cancelBtn.forceActiveFocus()
        })
    }

    background: Rectangle {
        color: appSettings.surfaceColor
        radius: 20
        border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
        border.width: 1
        layer.enabled: root.visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.6 : 0.25)
            shadowBlur: 0.8
            shadowVerticalOffset: 8
        }
    }

    contentItem: ColumnLayout {
        spacing: 0
        Keys.onBackPressed: (event) => { event.accepted = true; root.close() }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Backspace) {
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
                    width: 38
                    height: 38
                    radius: 19
                    color: Qt.rgba(239/255, 68/255, 68/255, 0.15)
                    YIcon {
                        anchors.centerIn: parent
                        size: 18
                        source: "qrc:/tsuki_app/icons/actions/trash.svg"
                        color: "#ef4444"
                    }
                }

                Label {
                    text: root.isEpicGame ? "Uninstall Epic Game" : "Remove from Library"
                    color: appSettings.textColor
                    font.pixelSize: 18
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
            spacing: 16

            Label {
                text: root.isEpicGame
                    ? ("Are you sure you want to uninstall <b>" + (root.targetTitle ? root.targetTitle : "this game") + "</b> from your library?")
                    : ("Are you sure you want to remove <b>" + (root.targetTitle ? root.targetTitle : "this game") + "</b> from your Tsuki library?")
                color: appSettings.textColor
                font.pixelSize: 14
                textFormat: Text.RichText
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                lineHeight: 1.3
            }

            Label {
                text: (root.isEpicGame && deleteEpicFilesToggle.checked)
                    ? ("Game files on disk will be permanently deleted" + (root.epicInstallDir.length > 0 ? (":\n" + root.epicInstallDir) : "."))
                    : "Your actual game files on disk will not be deleted."
                color: (root.isEpicGame && deleteEpicFilesToggle.checked) ? "#ef4444" : appSettings.textSecColor
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // Epic Game Files Deletion Toggle Card
            Rectangle {
                visible: root.isEpicGame
                Layout.fillWidth: true
                radius: 12
                color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                implicitHeight: epicFilesRow.implicitHeight + 20

                RowLayout {
                    id: epicFilesRow
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: "Delete Game Files from Disk"
                            color: appSettings.textColor
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        Label {
                            text: root.isInPlaceImported
                                ? "In-place imported folder (unchecked by default so external files stay safe)"
                                : "Removes the installed Epic game directory from disk"
                            color: appSettings.textSecColor
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    Toggle {
                        id: deleteEpicFilesToggle
                        objectName: "deleteEpicFilesToggle"
                        checked: false
                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            if (root.hasDedicatedPrefix) deletePrefixToggle.forceActiveFocus()
                            else cancelBtn.forceActiveFocus()
                        }
                    }
                }
            }

            // Prefix Deletion Option Card
            Rectangle {
                visible: root.hasDedicatedPrefix
                Layout.fillWidth: true
                radius: 12
                color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                border.color: appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                implicitHeight: prefixRow.implicitHeight + 20

                RowLayout {
                    id: prefixRow
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: "Delete Wine Prefix (" + root.prefixName + ")"
                            color: appSettings.textColor
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        Label {
                            text: "Permanently deletes the Windows virtual C: drive, registry, and saves for this prefix"
                            color: appSettings.textSecColor
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    Toggle {
                        id: deletePrefixToggle
                        checked: false
                        Keys.onDownPressed: (event) => { event.accepted = true; cancelBtn.forceActiveFocus() }
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
                    id: cancelBtn
                    text: "Cancel"
                    buttonType: "tonal"
                    onClicked: root.close()
                    Keys.onRightPressed: (event) => { event.accepted = true; removeBtn.forceActiveFocus() }
                    Keys.onUpPressed: (event) => { if (root.hasDedicatedPrefix) { event.accepted = true; deletePrefixToggle.forceActiveFocus() } }
                }

                M3Button {
                    id: removeBtn
                    objectName: "removeConfirmBtn"
                    text: root.isEpicGame ? "Uninstall Game" : "Remove Game"
                    iconSource: "qrc:/tsuki_app/icons/actions/trash.svg"
                    buttonType: "destructive"
                    onClicked: {
                        let gId = root.targetGameId
                        let delPrefix = root.hasDedicatedPrefix && deletePrefixToggle.checked
                        let delFiles = root.isEpicGame && deleteEpicFilesToggle.checked
                        uiController.gameManager.removeGame(gId, delPrefix, delFiles)
                        root.close()
                        root.gameRemoved(gId)
                    }
                    Keys.onLeftPressed: (event) => { event.accepted = true; cancelBtn.forceActiveFocus() }
                    Keys.onUpPressed: (event) => { if (root.hasDedicatedPrefix) { event.accepted = true; deletePrefixToggle.forceActiveFocus() } }
                }
            }
        }
    }
}

