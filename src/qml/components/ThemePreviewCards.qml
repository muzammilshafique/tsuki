import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property int selectedMode: 0 // 0: Dark, 1: Light, 2: System, 3: AMOLED
    readonly property bool kbFocused: root.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)

    signal modeSelected(int mode)

    readonly property var modesModel: [
        { val: 0, label: "Dark",   kind: "dark" },
        { val: 1, label: "Light",  kind: "light" },
        { val: 2, label: "System", kind: "system" },
        { val: 3, label: "AMOLED", kind: "amoled" }
    ]

    function adjustLeft() {
        const order = [0, 1, 2, 3]
        const idx = order.indexOf(selectedMode)
        if (idx > 0) {
            selectedMode = order[idx - 1]
            modeSelected(selectedMode)
        }
    }

    function adjustRight() {
        const order = [0, 1, 2, 3]
        const idx = order.indexOf(selectedMode)
        if (idx >= 0 && idx < order.length - 1) {
            selectedMode = order[idx + 1]
            modeSelected(selectedMode)
        }
    }

    function activate() {
        const next = (selectedMode + 1) % 4
        selectedMode = next
        modeSelected(next)
    }

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight
    focus: true
    activeFocusOnTab: false

    Keys.onLeftPressed: (event) => {
        if (selectedMode > 0) {
            event.accepted = true
            adjustLeft()
        }
    }
    Keys.onRightPressed: (event) => {
        if (selectedMode < 3) {
            event.accepted = true
            adjustRight()
        }
    }
    Keys.onReturnPressed: (event) => { event.accepted = true; activate() }
    Keys.onEnterPressed: (event) => { event.accepted = true; activate() }
    Keys.onSpacePressed: (event) => { event.accepted = true; activate() }

    GridLayout {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        columns: root.width > 0 && root.width < 520 ? 2 : 4
        columnSpacing: 12
        rowSpacing: 12

        Repeater {
            model: root.modesModel
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index

                readonly property bool isSelected: root.selectedMode === modelData.val
                readonly property bool isHovered: cardHover.hovered
                readonly property color previewBg: {
                    if (modelData.kind === "light") return "#f8fafc"
                    if (modelData.kind === "amoled") return "#000000"
                    return "#0d0d11"
                }
                readonly property color previewSidebar: {
                    if (modelData.kind === "light") return "#eef2f6"
                    if (modelData.kind === "amoled") return "#070709"
                    return "#13131a"
                }
                readonly property color previewTile: {
                    if (modelData.kind === "light") return "#e2e8f0"
                    if (modelData.kind === "amoled") return "#141418"
                    return "#1c1c25"
                }

                Layout.fillWidth: true
                Layout.preferredHeight: 112
                radius: 16
                color: isSelected
                    ? appSettings.secondaryContainer
                    : (isHovered ? appSettings.surfaceContainerHigh : appSettings.surfaceContainer)
                border.color: isSelected
                    ? appSettings.accentColor
                    : (isHovered
                        ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14))
                        : (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)))
                border.width: isSelected ? (root.kbFocused ? 3 : 2.2) : 1
                scale: cardTap.pressed ? 0.96 : 1.0

                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on border.color { ColorAnimation { duration: 160 } }
                Behavior on border.width { NumberAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    // Schematic UI Preview Window
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            id: previewBgRect
                            anchors.fill: parent
                            radius: 10
                            color: card.previewBg
                        }

                        // Right-half Light split overlay for "System" preview card
                        Rectangle {
                            visible: card.modelData.kind === "system"
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 1
                            anchors.leftMargin: 0
                            width: Math.max(20, (parent.width - 2) * 0.52)
                            topRightRadius: 9
                            bottomRightRadius: 9
                            topLeftRadius: 0
                            bottomLeftRadius: 0
                            color: "#f8fafc"
                            z: 0

                            Item {
                                anchors.fill: parent
                                anchors.topMargin: 7
                                anchors.bottomMargin: 7
                                anchors.rightMargin: 7
                                anchors.leftMargin: 4

                                Rectangle {
                                    id: sysLightHdr
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    width: Math.max(12, parent.width - 20)
                                    height: 7
                                    radius: 3.5
                                    color: "#e2e8f0"
                                }

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    width: 14
                                    height: 7
                                    radius: 3.5
                                    color: appSettings.accentColor
                                }

                                Row {
                                    anchors.top: sysLightHdr.bottom
                                    anchors.topMargin: 6
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    spacing: 4

                                    Rectangle {
                                        width: Math.max(8, (parent.width - 4) * 0.5)
                                        height: parent.height
                                        radius: 4
                                        color: "#e2e8f0"
                                    }
                                    Rectangle {
                                        width: Math.max(8, (parent.width - 4) * 0.5)
                                        height: parent.height
                                        radius: 4
                                        color: "#e2e8f0"
                                    }
                                }
                            }
                        }

                        // Mini Sidebar (rounded only on left edges to match preview frame cleanly)
                        Rectangle {
                            id: miniBar
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 1
                            anchors.rightMargin: 0
                            width: 22
                            topLeftRadius: 9
                            bottomLeftRadius: 9
                            topRightRadius: 0
                            bottomRightRadius: 0
                            color: card.modelData.kind === "system" ? "#13131a" : card.previewSidebar
                            z: 1

                            Column {
                                anchors.top: parent.top
                                anchors.topMargin: 7
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 4
                                Rectangle { width: 12; height: 4; radius: 2; color: appSettings.accentColor }
                                Rectangle { width: 12; height: 3; radius: 1.5; color: card.modelData.kind === "light" ? "#94a3b8" : "#52525b" }
                                Rectangle { width: 12; height: 3; radius: 1.5; color: card.modelData.kind === "light" ? "#94a3b8" : "#52525b" }
                            }
                        }

                        // Left-half Dark content for "System" preview card
                        Item {
                            visible: card.modelData.kind === "system"
                            anchors.left: miniBar.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 7
                            anchors.leftMargin: 6
                            anchors.rightMargin: 3
                            width: Math.max(10, (parent.width - 23) * 0.45)
                            z: 1

                            Rectangle {
                                id: sysDarkHdr
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 7
                                radius: 3.5
                                color: "#1c1c25"
                            }

                            Rectangle {
                                anchors.top: sysDarkHdr.bottom
                                anchors.topMargin: 6
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                radius: 4
                                color: "#1c1c25"
                            }
                        }

                        // Mini Main Window Content (header + poster grid) for Dark/Light/AMOLED
                        Item {
                            anchors.left: miniBar.right
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 7
                            z: 1
                            visible: card.modelData.kind !== "system"

                            // Mini search/action bar
                            Rectangle {
                                id: miniHdr
                                anchors.top: parent.top
                                anchors.left: parent.left
                                width: Math.min(parent.width * 0.65, 58)
                                height: 7
                                radius: 3.5
                                color: card.previewTile
                            }

                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                width: 14
                                height: 7
                                radius: 3.5
                                color: appSettings.accentColor
                            }

                            Row {
                                anchors.top: miniHdr.bottom
                                anchors.topMargin: 6
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                spacing: 5

                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        width: Math.max(8, (parent.width - 10) / 3)
                                        height: parent.height
                                        radius: 4
                                        color: card.previewTile
                                    }
                                }
                            }
                        }

                        // Top-most crisp border ring so inner panels never overlap rounded corners
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: "transparent"
                            border.color: card.modelData.kind === "light"
                                ? Qt.rgba(0, 0, 0, 0.11)
                                : Qt.rgba(1, 1, 1, 0.09)
                            border.width: 1
                            z: 2
                        }

                        // Active Check Badge
                        Rectangle {
                            width: 19
                            height: 19
                            radius: 9.5
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 5
                            z: 3
                            color: appSettings.accentColor
                            scale: card.isSelected ? 1.0 : 0.4
                            opacity: card.isSelected ? 1.0 : 0.0
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            Behavior on opacity { NumberAnimation { duration: 140 } }

                            YIcon {
                                anchors.centerIn: parent
                                symbol: "check"
                                size: 12
                                color: appSettings.onPrimary
                            }
                        }
                    }

                    // Bottom Mode Label
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 2
                        text: card.modelData.label
                        font.family: "Rubik"
                        font.pixelSize: 13
                        font.weight: card.isSelected ? Font.DemiBold : Font.Medium
                        color: card.isSelected ? appSettings.onSecondaryContainer : appSettings.textSecColor
                        renderType: Text.QtRendering
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                HoverHandler {
                    id: cardHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: cardTap
                    onTapped: {
                        root.selectedMode = card.modelData.val
                        root.modeSelected(card.modelData.val)
                    }
                }
            }
        }
    }
}

