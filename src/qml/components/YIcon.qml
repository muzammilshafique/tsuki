import QtQuick
import QtQuick.Effects

Item {
    id: root
    property string source: ""
    property string symbol: ""
    property bool filled: false
    property color color: "#ffffff"
    property real size: 20

    readonly property var _symbolIcons: ({
        "add":                 "add.svg",
        "arrow_back":          "back.svg",
        "article":             "article.svg",
        "auto_awesome":        "auto_awesome.svg",
        "build":               "wrench.svg",
        "check":               "check.svg",
        "close":               "close.svg",
        "colorize":            "colorize.svg",
        "delete":              "trash.svg",
        "desktop_windows":     "desktop_windows.svg",
        "download":            "download.svg",
        "edit":                "edit.svg",
        "folder_open":         "folder_open.svg",
        "grid_view":           "grid_view.svg",
        "info":                "info.svg",
        "keyboard_arrow_down": "chevron_down.svg",
        "menu":                "menu.svg",
        "menu_open":           "menu_open.svg",
        "open_in_new":         "shortcut.svg",
        "palette":             "palette.svg",
        "pause":               "pause.svg",
        "person":              "person.svg",
        "play_arrow":          "play_arrow.svg",
        "refresh":             "refresh.svg",
        "runner":              "nav/runner.svg",
        "shortcut":            "forward.svg",
        "sort":                "sort.svg",
        "speed":               "speed.svg",
        "stop":                "stop.svg",
        "terminal":            "terminal.svg",
        "tune":                "tune.svg",
        "visibility":          "visibility.svg",
        "visibility_off":      "visibility_off.svg"
    })

    readonly property var _filledSymbolIcons: ({
        "article":      "article-filled.svg",
        "auto_awesome": "auto_awesome-filled.svg",
        "colorize":     "colorize-filled.svg",
        "folder_open":  "folder_open-filled.svg",
        "grid_view":    "grid_view-filled.svg",
        "info":         "info-filled.svg",
        "palette":      "palette-filled.svg",
        "play_arrow":   "play.svg",
        "runner":       "nav/runner-filled.svg",
        "speed":        "speed-filled.svg",
        "stop":         "stop.svg"
    })

    function resolveSymbolSource(sym, isFilled) {
        if (!sym) return ""
        const file = (isFilled && _filledSymbolIcons[sym])
            ? _filledSymbolIcons[sym]
            : _symbolIcons[sym]
        if (!file) return ""
        return file.indexOf("/") !== -1
            ? ("qrc:/tsuki_app/icons/" + file)
            : ("qrc:/tsuki_app/icons/actions/" + file)
    }

    readonly property string resolvedSource: root.symbol !== ""
        ? root.resolveSymbolSource(root.symbol, root.filled)
        : root.source

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        id: rawIcon
        anchors.fill: parent
        source: root.resolvedSource
        sourceSize: Qt.size(Math.max(16, root.size * 2), Math.max(16, root.size * 2))
        fillMode: Image.PreserveAspectFit
        visible: false
        asynchronous: false
        smooth: true
    }

    MultiEffect {
        anchors.fill: rawIcon
        source: rawIcon
        visible: root.resolvedSource !== ""
        colorization: 1.0
        colorizationColor: root.color
        Behavior on colorizationColor { ColorAnimation { duration: 120 } }
    }
}
