import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "home"
import "components"

ApplicationWindow {
    id: window
    width: appSettings.windowWidth()
    height: appSettings.windowHeight()
    minimumWidth: 960
    minimumHeight: 540
    visible: true
    title: "Tsuki"
    color: appSettings.bgColor

    property real prePlayerWidth: 1280
    property real prePlayerHeight: 820
    property real prePlayerX: -1
    property real prePlayerY: -1

    Component.onCompleted: {
        const sx = appSettings.windowX()
        const sy = appSettings.windowY()
        if (sx >= 0 && sy >= 0) {
            window.x = sx
            window.y = sy
        }
        if (appSettings.windowMaximized()) {
            window.showMaximized()
        }
    }

    onWidthChanged: Qt.callLater(saveGeometry)
    onHeightChanged: Qt.callLater(saveGeometry)
    onXChanged: Qt.callLater(saveGeometry)
    onYChanged: Qt.callLater(saveGeometry)
    onVisibilityChanged: Qt.callLater(saveGeometry)

    function saveGeometry() {
        if (window.visibility === Window.FullScreen) return
        if (window.visibility === Window.Windowed) {
            prePlayerWidth = window.width
            prePlayerHeight = window.height
            prePlayerX = window.x
            prePlayerY = window.y
            appSettings.saveWindowGeometry(window.x, window.y, window.width, window.height, false)
        } else if (window.visibility === Window.Maximized) {
            appSettings.saveWindowGeometry(window.x, window.y, appSettings.windowWidth(), appSettings.windowHeight(), true)
        }
    }

    StackView {
        id: stack
        anchors.fill: parent

        pushEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }
        }
        pushExit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 250; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 1.0; to: 1.05; duration: 250; easing.type: Easing.OutCubic }
            }
        }
        popEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 1.05; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            }
        }
        popExit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 250; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 250; easing.type: Easing.OutCubic }
            }
        }

        initialItem: HomePage {
            id: homePage
            externalModalOpen: window.isWinetricksOpen || window.isCloudConflictOpen
            onGameDetailsRequested: function(gameId, epicAppName) {
                window.openGameDetailPage(gameId, epicAppName)
            }
            onSettingsRequested: {
                window.openSettingsPage()
            }
            onWinetricksRequested: function(prefixId, title) {
                window.openWinetricks(prefixId, title)
            }
        }
    }

    property string _pendingWtPrefixId: ""
    property string _pendingWtTitle: ""
    readonly property bool isWinetricksOpen: Boolean(winetricksLoader.item && winetricksLoader.item.visible)
    readonly property bool isCloudConflictOpen: Boolean(cloudConflictDialog.visible)

    function openSettingsPage() {
        if (stack.currentItem && stack.currentItem.objectName === "settingsPage") return
        const item = stack.push(Qt.resolvedUrl("pages/SettingsPage.qml"))
        if (item) {
            item.backRequested.connect(function() { stack.pop() })
        }
    }

    function openGameDetailPage(gameId, epicAppName) {
        const item = stack.push(Qt.resolvedUrl("pages/GameDetailPage.qml"), {
            gameId: gameId || "",
            epicAppName: epicAppName || ""
        })
        if (item) {
            item.externalModalOpen = Qt.binding(function() { return window.isWinetricksOpen || window.isCloudConflictOpen })
            item.backRequested.connect(function() { stack.pop() })
            item.winetricksRequested.connect(function(prefixId, gameTitle) {
                window.openWinetricks(prefixId, gameTitle)
            })
        }
    }

    function openWinetricks(prefixId, title) {
        _pendingWtPrefixId = prefixId || "default-prefix"
        _pendingWtTitle = title || "Default"
        if (winetricksLoader.item) {
            winetricksLoader.item.openForPrefix(_pendingWtPrefixId, _pendingWtTitle)
        } else {
            winetricksLoader.active = true
        }
    }

    Loader {
        id: winetricksLoader
        anchors.fill: parent
        active: false
        source: active ? Qt.resolvedUrl("components/WinetricksModal.qml") : ""
        onLoaded: {
            if (item) {
                item.openForPrefix(window._pendingWtPrefixId, window._pendingWtTitle)
            }
        }
    }

    Connections {
        target: winetricksLoader.item
        function onClosed() {
            Qt.callLater(function() {
                if (!winetricksLoader.item || !winetricksLoader.item.visible) {
                    winetricksLoader.active = false
                }
                if (stack.currentItem
                        && typeof stack.currentItem.focusActiveSectionContent === "function"
                        && !(stack.currentItem.isAnyModalOpen && stack.currentItem.isAnyModalOpen())) {
                    stack.currentItem.focusActiveSectionContent()
                }
            })
        }
    }

    CloudSaveConflictDialog {
        id: cloudConflictDialog
    }

    Connections {
        target: uiController ? uiController.launchPipeline : null
        function onCloudSaveConflict(gameId, details) {
            cloudConflictDialog.openConflict(gameId, details)
        }
    }

    Connections {
        target: uiController ? uiController.cloudSaveService : null
        function onSyncConflictDetected(gameId, details) {
            if (details && details.triggeredByLaunch === false) {
                cloudConflictDialog.openConflict(gameId, details)
            }
        }
    }

    Connections {
        target: uiController ? uiController.controllerManager : null
        function onSettingsActionRequested() {
            if (window.isWinetricksOpen || window.isCloudConflictOpen) return
            window.openSettingsPage()
        }
    }

    Shortcut {
        sequence: "Tab"
        context: Qt.ApplicationShortcut
        enabled: !window.isWinetricksOpen
                 && !window.isCloudConflictOpen
                 && !(stack.currentItem && stack.currentItem.isAnyModalOpen && stack.currentItem.isAnyModalOpen())
                 && !(stack.currentItem && stack.currentItem.isModalOpen)
                 && !(stack.currentItem && stack.currentItem.isTextInputActive && stack.currentItem.isTextInputActive())
                 && (stack.currentItem ? stack.currentItem.objectName !== "settingsPage" : true)
        onActivated: {
            if (uiController) uiController.setKeyboardNavActive(true)
            window.openSettingsPage()
        }
    }

    NavigationHudBar {
        id: navHudBar
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        z: 900
        pageContext: {
            if (!stack.currentItem || stack.depth <= 1) return "home"
            if (stack.currentItem.objectName === "settingsPage") return "settings"
            if (stack.currentItem.objectName === "gameDetailPage") return "gameDetail"
            return "home"
        }
        isLibraryActive: homePage.activeSection === "library" || homePage.activeSection === "epic"
    }

    // Non-blocking Toast Notification Banner
    Rectangle {
        id: toastBanner
        property string message: ""
        property bool isError: false

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: navHudBar.visible ? 56 : 28
        z: 999
        width: Math.min(parent.width - 80, Math.max(280, toastLabel.implicitWidth + 44))
        height: 44
        radius: 22
        color: isError ? "#ef4444" : appSettings.surfaceAltColor
        border.color: isError ? "#ffffff" : appSettings.accentColor
        border.width: 1.5
        opacity: toastTimer.running ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Label {
            id: toastLabel
            anchors.centerIn: parent
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: toastBanner.message
            color: "#ffffff"
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Timer {
            id: toastTimer
            interval: 3800
            repeat: false
        }

        Connections {
            target: uiController
            function onToastRequested(msg, err) {
                toastBanner.message = msg
                toastBanner.isError = err
                toastTimer.restart()
            }
        }
    }
}

