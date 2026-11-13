import QtQuick
import QtQuick.Controls
import QtQuick.Layouts


Item {
    id: root
    property string text: ""
    property string placeholderText: ""
    property string leadingIcon: ""
    property bool isPassword: false
    property bool showClearButton: true
    property bool twoStageFocus: false
    readonly property bool isEditing: inputField.activeFocus
    readonly property bool kbFocused: root.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
    signal editingFinished()
    signal commit(string value)
    signal cleared()
    signal moveUp()
    signal moveDown()

    implicitWidth: 280
    implicitHeight: 46
    width: implicitWidth
    height: implicitHeight
    focus: twoStageFocus
    activeFocusOnTab: false

    property alias placeholder: root.placeholderText

    onTextChanged: {
        if (inputField.text !== root.text) {
            inputField.text = root.text
        }
    }

    function activate() {
        inputField.forceActiveFocus()
        inputField.selectAll()
    }

    Keys.onReturnPressed: (event) => {
        if (root.twoStageFocus && !inputField.activeFocus) {
            event.accepted = true
            root.activate()
        }
    }
    Keys.onEnterPressed: (event) => {
        if (root.twoStageFocus && !inputField.activeFocus) {
            event.accepted = true
            root.activate()
        }
    }
    Keys.onSpacePressed: (event) => {
        if (root.twoStageFocus && !inputField.activeFocus) {
            event.accepted = true
            root.activate()
        }
    }

    Rectangle {
        id: container
        anchors.fill: parent
        radius: 12
        color: (inputField.activeFocus || root.kbFocused)
            ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
            : (containerHover.hovered 
                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.02)))

        border.color: (inputField.activeFocus || root.kbFocused)
            ? appSettings.accentColor
            : (containerHover.hovered
                ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18))
                : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.09)))
        border.width: (inputField.activeFocus || root.kbFocused) ? 2 : 1

        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 10

            // Optional Leading Icon
            YIcon {
                size: 18
                source: root.leadingIcon
                visible: root.leadingIcon !== ""
                color: inputField.activeFocus ? appSettings.accentColor : appSettings.textSecColor
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            // Text Input Field
            TextField {
                id: inputField
                Layout.fillWidth: true
                Layout.fillHeight: true
                activeFocusOnTab: false
                text: root.text
                placeholderText: root.placeholderText
                placeholderTextColor: appSettings.textTerColor
                color: appSettings.textColor
                font.pixelSize: 14
                font.weight: Font.Normal
                padding: 0
                verticalAlignment: Text.AlignVCenter
                selectByMouse: true
                echoMode: root.isPassword ? TextInput.PasswordEchoOnEdit : TextInput.Normal
                background: Item {}
                renderType: Text.QtRendering

                onTextEdited: {
                    root.text = text
                }

                onEditingFinished: {
                    root.commit(text.trim())
                    root.editingFinished()
                }

                Keys.onReturnPressed: (event) => {
                    event.accepted = true
                    root.commit(text.trim())
                    root.editingFinished()
                    returnFocusToRow()
                }
                Keys.onEnterPressed: (event) => {
                    event.accepted = true
                    root.commit(text.trim())
                    root.editingFinished()
                    returnFocusToRow()
                }
                Keys.onEscapePressed: (event) => {
                    event.accepted = true
                    returnFocusToRow()
                }
                Keys.onUpPressed: (event) => {
                    event.accepted = true
                    returnFocusToRow()
                    if (typeof settingsPage !== "undefined") settingsPage.focusPrevSettingRow()
                    else root.moveUp()
                }
                Keys.onDownPressed: (event) => {
                    event.accepted = true
                    returnFocusToRow()
                    if (typeof settingsPage !== "undefined") settingsPage.focusNextSettingRow()
                    else root.moveDown()
                }

                function returnFocusToRow() {
                    if (root.twoStageFocus) {
                        inputField.focus = false
                        root.forceActiveFocus()
                        return
                    }
                    let p = root.parent
                    while (p) {
                        if (p.forwardFocus && typeof p.forwardFocus === "function") {
                            p.forwardFocus()
                            return
                        }
                        p = p.parent
                    }
                    inputField.focus = false
                }
            }

            // Clear Button
            Item {
                id: clearBtnContainer
                visible: root.showClearButton && inputField.text.length > 0
                implicitWidth: 26
                implicitHeight: 26
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 13
                    color: clearBtnHover.containsMouse ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                YIcon {
                    anchors.centerIn: parent
                    size: 14
                    source: "qrc:/tsuki_app/icons/actions/close.svg"
                    color: clearBtnHover.containsMouse ? appSettings.textColor : appSettings.textSecColor
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: clearBtnHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        inputField.text = ""
                        root.text = ""
                        root.commit("")
                        root.cleared()
                        inputField.forceActiveFocus()
                    }
                }
            }
        }

        HoverHandler {
            id: containerHover
            cursorShape: Qt.IBeamCursor
        }

        TapHandler {
            onTapped: {
                inputField.forceActiveFocus()
            }
        }
    }
}
