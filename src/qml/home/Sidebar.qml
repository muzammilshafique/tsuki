import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Rectangle {
    id: sidebar
    property bool isCollapsed: appSettings.sidebarCollapsed
    property real targetWidth: isCollapsed ? 68 : 220
    width: targetWidth
    implicitWidth: targetWidth
    Layout.fillHeight: true
    Layout.preferredWidth: targetWidth
    Layout.minimumWidth: targetWidth
    Layout.maximumWidth: targetWidth
    Behavior on targetWidth { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    color: appSettings.sidebarColor
    Behavior on color { ColorAnimation { duration: 150 } }

    property int currentFilter: -1
    property string currentSection: "library"
    signal filterRequested(int type)
    signal sectionRequested(string section)
    signal settingsRequested()
    signal focusContentRequested()

    focus: true
    property int focusedNavIndex: 0

    readonly property var navModel: {
        let items = [
            { name: "Library",     icon: "qrc:/tsuki_app/icons/nav/library.svg",     action: "filter",  val: -1, section: "library" },
            { name: "Favourites",  icon: "qrc:/tsuki_app/icons/nav/favourite.svg",   action: "filter",  val: 3,  section: "library" },
            { name: "Recent",      icon: "qrc:/tsuki_app/icons/nav/recent.svg",      action: "filter",  val: 4,  section: "library" },
            { name: "divider",     icon: "",                                         action: "",        val: 0,  section: "" },
            { name: "Prefixes",    icon: "qrc:/tsuki_app/icons/nav/prefixes.svg",    action: "section", val: 0,  section: "prefixes" },
            { name: "Runners",     icon: "qrc:/tsuki_app/icons/nav/runner.svg",      action: "section", val: 0,  section: "runners" },
            { name: "Diagnostics", icon: "qrc:/tsuki_app/icons/nav/diagnostics.svg", action: "section", val: 0, section: "diagnostics" }
        ]
        return items
    }

    readonly property bool isKeyboardNavActive: uiController.isKeyboardNavActive

    function activateFocusedItem(event) {
        if (event) event.accepted = true
        uiController.setKeyboardNavActive(true)
        if (focusedNavIndex === -1) {
            appSettings.sidebarCollapsed = !appSettings.sidebarCollapsed
        } else if (focusedNavIndex === navModel.length) {
            sidebar.settingsRequested()
        } else if (focusedNavIndex >= 0 && focusedNavIndex < navModel.length) {
            let item = navModel[focusedNavIndex]
            if (!item) return
            if (item.action === "filter") {
                sidebar.currentSection = "library"
                sidebar.filterRequested(item.val)
                sidebar.sectionRequested("library")
            } else if (item.action === "section") {
                sidebar.currentSection = item.section
                sidebar.sectionRequested(item.section)
            }
        }
    }

    Keys.onUpPressed: (event) => {
        event.accepted = true
        uiController.setKeyboardNavActive(true)
        if (focusedNavIndex === navModel.length) focusedNavIndex = navModel.length - 1
        else if (focusedNavIndex === 4) focusedNavIndex = 2
        else if (focusedNavIndex > 0) focusedNavIndex--
        else if (focusedNavIndex === 0) focusedNavIndex = -1
    }
    Keys.onDownPressed: (event) => {
        event.accepted = true
        uiController.setKeyboardNavActive(true)
        if (focusedNavIndex === -1) focusedNavIndex = 0
        else if (focusedNavIndex === 2) focusedNavIndex = 4
        else if (focusedNavIndex === navModel.length - 1) focusedNavIndex = navModel.length
        else if (focusedNavIndex < navModel.length) focusedNavIndex++
    }
    Keys.onLeftPressed: (event) => {
        event.accepted = true
        uiController.setKeyboardNavActive(true)
        appSettings.sidebarCollapsed = !appSettings.sidebarCollapsed
    }
    Keys.onRightPressed: (event) => {
        event.accepted = true
        uiController.setKeyboardNavActive(true)
        if (focusedNavIndex === -1 && sidebar.isCollapsed) {
            appSettings.sidebarCollapsed = false
        } else {
            sidebar.focusContentRequested()
        }
    }
    Keys.onReturnPressed: (event) => { activateFocusedItem(event) }
    Keys.onEnterPressed: (event) => { activateFocusedItem(event) }
    Keys.onSpacePressed: (event) => { activateFocusedItem(event) }
    Keys.onEscapePressed: (event) => {
        event.accepted = true
        sidebar.focusContentRequested()
    }

    Shortcut {
        sequences: ["Ctrl+B", "["]
        onActivated: appSettings.sidebarCollapsed = !appSettings.sidebarCollapsed
    }

    // Right edge divider
    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1; color: appSettings.sidebarDividerColor
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // App Title / Brand
        Item {
            id: brandHeaderItem
            Layout.fillWidth: true
            Layout.preferredHeight: 72

            readonly property bool isTvFocused: sidebar.isKeyboardNavActive && sidebar.activeFocus && sidebar.focusedNavIndex === -1

            Rectangle {
                visible: brandHeaderItem.isTvFocused
                anchors.fill: parent
                anchors.margins: 10
                radius: 12
                color: "transparent"
                border.color: appSettings.accentColor
                border.width: 2.5
                z: 5

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: appSettings.accentColor
                    opacity: 0.2
                }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 10
                opacity: sidebar.isCollapsed ? 0.0 : 1.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                YIcon {
                    source: "qrc:/tsuki_app/icons/brand/tsuki-sidebar.svg"
                    size: 28
                    color: appSettings.accentColor
                }

                Label {
                    text: "Tsuki"
                    color: appSettings.textColor
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                }
            }

            // Compact icon when collapsed
            YIcon {
                source: "qrc:/tsuki_app/icons/brand/tsuki-sidebar.svg"
                size: 28
                color: appSettings.accentColor
                anchors.centerIn: parent
                opacity: sidebar.isCollapsed ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    uiController.setKeyboardNavActive(false)
                    appSettings.sidebarCollapsed = !appSettings.sidebarCollapsed
                }
            }
        }

        Item { Layout.preferredHeight: 8 }

        // Navigation Repeater
        Repeater {
            model: sidebar.navModel
            delegate: Item {
                id: navDelegateItem
                required property int index
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: modelData.name === "divider" ? 12 : 44

                property bool isActive: (modelData.action === "filter" && sidebar.currentSection === "library" && sidebar.currentFilter === modelData.val) ||
                                        (modelData.action === "section" && sidebar.currentSection === modelData.section)
                readonly property bool isTvFocused: sidebar.isKeyboardNavActive && sidebar.activeFocus && sidebar.focusedNavIndex === navDelegateItem.index

                MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    enabled: modelData.name !== "divider"
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: { uiController.setKeyboardNavActive(false) }
                    onPressed: { uiController.setKeyboardNavActive(false) }
                    onClicked: {
                        uiController.setKeyboardNavActive(false)
                        sidebar.focusedNavIndex = navDelegateItem.index
                        if (modelData.action === "filter") {
                            sidebar.currentSection = "library"
                            sidebar.filterRequested(modelData.val)
                            sidebar.sectionRequested("library")
                        } else if (modelData.action === "section") {
                            sidebar.currentSection = modelData.section
                            sidebar.sectionRequested(modelData.section)
                        }
                    }

                    Rectangle {
                        visible: modelData.name === "divider"
                        width: parent.width - 48
                        height: 1
                        color: appSettings.sidebarDividerColor
                        anchors.centerIn: parent
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Rectangle {
                        visible: modelData.name !== "divider"
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        radius: 8
                        color: appSettings.accentColor
                        opacity: navDelegateItem.isActive ? 0.15 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    Rectangle {
                        visible: modelData.name !== "divider" && !navDelegateItem.isActive
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        radius: 8
                        color: appSettings.sidebarHoverColor
                        opacity: (!sidebar.isKeyboardNavActive && navMouse.containsMouse) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    Rectangle {
                        visible: navDelegateItem.isTvFocused && modelData.name !== "divider"
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        radius: 9
                        color: "transparent"
                        border.color: appSettings.accentColor
                        border.width: 2.5
                        z: 5

                        Rectangle {
                            anchors.fill: parent
                            radius: 7
                            color: appSettings.accentColor
                            opacity: 0.2
                        }
                    }

                    Item {
                        visible: modelData.name !== "divider"
                        anchors.fill: parent
                        Item {
                            id: navIconContainer
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 68
                            YIcon {
                                anchors.centerIn: parent
                                source: navDelegateItem.isActive ? modelData.icon.replace(".svg", "-filled.svg") : modelData.icon
                                color: navDelegateItem.isActive ? appSettings.accentColor : appSettings.sidebarTextSecColor
                                size: 22
                                visible: modelData.icon.length > 0
                            }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: navIconContainer.right
                            text: modelData.name
                            color: navDelegateItem.isActive ? appSettings.accentColor : appSettings.sidebarTextSecColor
                            font.pixelSize: 15
                            font.weight: navDelegateItem.isActive ? Font.DemiBold : Font.Medium
                            opacity: sidebar.isCollapsed ? 0.0 : 1.0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Bottom Settings Item
        Item {
            id: bottomSettingsItem
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            readonly property bool isTvFocused: sidebar.isKeyboardNavActive && sidebar.activeFocus && sidebar.focusedNavIndex === sidebar.navModel.length

            MouseArea {
                id: bottomNavMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: { uiController.setKeyboardNavActive(false) }
                onPressed: { uiController.setKeyboardNavActive(false) }
                onClicked: {
                    uiController.setKeyboardNavActive(false)
                    sidebar.settingsRequested()
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    radius: 8
                    color: appSettings.sidebarHoverColor
                    opacity: (!sidebar.isKeyboardNavActive && bottomNavMouse.containsMouse) ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                // Focus Ring for Settings
                Rectangle {
                    visible: bottomSettingsItem.isTvFocused
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    radius: 9
                    color: "transparent"
                    border.color: appSettings.accentColor
                    border.width: 2.5
                    z: 5

                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: appSettings.accentColor
                        opacity: 0.2
                    }
                }

                Item {
                    anchors.fill: parent
                    Item {
                        id: bottomIconContainer
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 68
                        YIcon {
                            anchors.centerIn: parent
                            source: "qrc:/tsuki_app/icons/actions/settings.svg"
                            color: bottomNavMouse.containsMouse ? appSettings.accentColor : appSettings.sidebarTextSecColor
                            size: 22
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: bottomIconContainer.right
                        text: "Settings"
                        color: bottomNavMouse.containsMouse ? appSettings.textColor : appSettings.sidebarTextSecColor
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        opacity: sidebar.isCollapsed ? 0.0 : 1.0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 16 }
    }
}

