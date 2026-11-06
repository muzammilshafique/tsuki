import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "home"
import "pages"
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
            onGameDetailsRequested: function(gameId) {
                stack.push(detailPageComponent, { gameId: gameId })
            }
            onSettingsRequested: {
                stack.push(settingsPageComponent)
            }
        }
    }

    Component {
        id: settingsPageComponent
        SettingsPage {
            onBackRequested: stack.pop()
        }
    }

    Component {
        id: detailPageComponent
        GameDetailPage {
            onBackRequested: stack.pop()
            onWinetricksRequested: function(prefixId, gameTitle) {
                globalWinetricksModal.openForPrefix(prefixId, gameTitle)
            }
        }
    }

    WinetricksModal {
        id: globalWinetricksModal
    }

    // Non-blocking Toast Notification Banner
    Rectangle {
        id: toastBanner
        property string message: ""
        property bool isError: false

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 28
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

