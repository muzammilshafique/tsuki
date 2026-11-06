import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Rectangle {
    id: sidebar
    property bool isCollapsed: appSettings.sidebarCollapsed
    property real targetWidth: isCollapsed ? 68 : 220
    Layout.fillHeight: true
    Layout.preferredWidth: targetWidth
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

    readonly property var navModel: [
        { name: "Library",        icon: "qrc:/tsuki_app/icons/nav/home.svg",       action: "filter",  val: -1, section: "library" },
        { name: "Favourites",     icon: "qrc:/tsuki_app/icons/nav/star.svg",       action: "filter",  val: 3,  section: "library" },
        { name: "Recent",         icon: "qrc:/tsuki_app/icons/nav/download.svg",   action: "filter",  val: 4,  section: "library" },
        { name: "divider",        icon: "",                                        action: "",        val: 0,  section: "" },
        { name: "Runners",        icon: "qrc:/tsuki_app/icons/nav/runner.svg",     action: "section", val: 0,  section: "runners" },
        { name: "Wine Prefixes",  icon: "qrc:/tsuki_app/icons/nav/prefix.svg",     action: "section", val: 0,  section: "prefixes" },
        { name: "Controllers",    icon: "qrc:/tsuki_app/icons/nav/controller.svg", action: "section", val: 0,  section: "controllers" },
        { name: "Diagnostics",    icon: "qrc:/tsuki_app/icons/nav/terminal.svg",   action: "section", val: 0,  section: "diagnostics" }
    ]

    readonly property bool isKeyboardNavActive: uiController.isKeyboardNavActive

    function activateFocusedItem(event) {
        if (event) event.accepted = true
        uiController.setKeyboardNavActive(true)
        if (focusedNavIndex === -1) {
            appSettings.sidebarCollapsed = !appSettings.sidebarCollapsed
        } else if (focusedNavIndex === 8) {
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
        if (focusedNavIndex === 8) focusedNavIndex = 7
        else if (focusedNavIndex === 4) focusedNavIndex = 2
        else if (focusedNavIndex > 0) focusedNavIndex--
        else if (focusedNavIndex === 0) focusedNavIndex = -1
    }
    Keys.onDownPressed: (event) => {
        event.accepted = true
        uiController.setKeyboardNavActive(true)
        if (focusedNavIndex === -1) focusedNavIndex = 0
        else if (focusedNavIndex === 2) focusedNavIndex = 4
        else if (focusedNavIndex === 7) focusedNavIndex = 8
        else if (focusedNavIndex < 8) focusedNavIndex++
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
                spacing: 8
                opacity: sidebar.isCollapsed ? 0.0 : 1.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                YIcon {
                    source: "qrc:/tsuki_app/icons/brand/tsuki-sidebar.svg"
                    color: appSettings.accentColor
                    size: 22
                }

                Label {
                    text: "Tsuki"
                    color: appSettings.textColor
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }
            }

            // Compact icon when collapsed
            Image {
                id: topSidebarIcon
                source: "qrc:/tsuki_app/icons/brand/tsuki-sidebar.svg"
                width: 24
                height: 24
                sourceSize: Qt.size(24, 24)
                anchors.centerIn: parent
                fillMode: Image.PreserveAspectFit
                visible: false
                asynchronous: false
            }

            MultiEffect {
                source: topSidebarIcon
                anchors.fill: topSidebarIcon
                colorization: 1.0
                colorizationColor: appSettings.accentColor
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

        // Active Running Games Indicator Badge in Sidebar
        Rectangle {
            visible: uiController.launchPipeline.runningCount > 0 && !sidebar.isCollapsed
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.preferredHeight: 38
            radius: 8
            color: Qt.rgba(52/255, 211/255, 153/255, 0.14)
            border.color: "#34d399"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Rectangle { width: 8; height: 8; radius: 4; color: "#34d399" }
                Label {
                    text: uiController.launchPipeline.runningCount + " Game(s) Running"
                    color: "#34d399"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                ToolButton {
                    text: "Stop"
                    onClicked: uiController.launchPipeline.stopAllGames()
                    contentItem: Label { text: "Stop"; color: "#ef4444"; font.pixelSize: 11; font.weight: Font.Bold }
                    background: null
                }
            }
        }

        // Bottom Settings Item
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            readonly property bool isTvFocused: sidebar.isKeyboardNavActive && sidebar.activeFocus && sidebar.focusedNavIndex === 8
            readonly property bool isSettingsActive: sidebar.currentSection === "settings"

            MouseArea {
                id: bottomNavMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: { uiController.setKeyboardNavActive(false) }
                onPressed: { uiController.setKeyboardNavActive(false) }
                onClicked: {
                    uiController.setKeyboardNavActive(false)
                    sidebar.focusedNavIndex = 8
                    sidebar.currentSection = "settings"
                    sidebar.settingsRequested()
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    radius: 8
                    color: parent.parent.isSettingsActive ? appSettings.accentColor : appSettings.sidebarHoverColor
                    opacity: parent.parent.isSettingsActive ? 0.15 : ((!sidebar.isKeyboardNavActive && bottomNavMouse.containsMouse) ? 1.0 : 0.0)
                    Behavior on opacity { NumberAnimation { duration: 150 } }
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
                            color: parent.parent.parent.parent.isSettingsActive ? appSettings.accentColor : appSettings.sidebarTextSecColor
                            size: 22
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: bottomIconContainer.right
                        text: "Settings"
                        color: parent.parent.parent.isSettingsActive ? appSettings.accentColor : appSettings.sidebarTextSecColor
                        font.pixelSize: 15
                        font.weight: parent.parent.parent.isSettingsActive ? Font.DemiBold : Font.Medium
                        opacity: sidebar.isCollapsed ? 0.0 : 1.0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 16 }
    }
}

