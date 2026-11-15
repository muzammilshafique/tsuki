import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root

    property real fabSize: 40
    property string buttonLabel: "Add Game"
    property var menuItems: [
        { label: "Windows Game", iconSymbol: "desktop_windows", value: "windows" },
        { label: "Linux Game",   iconSymbol: "terminal",        value: "linux" }
    ]
    property bool expandUpward: false
    property int focusedMenuIndex: 0
    property bool _suppressNextClick: false
    property bool _itemActivated: false

    readonly property bool isMenuOpen: menuPopup.visible
    readonly property bool isKeyboardFocused: triggerBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
    readonly property bool isExpanded: menuPopup.visible || triggerHover.hovered || root.isKeyboardFocused
    readonly property real expandedWidth: 12 + 16 + 8 + fabLabel.implicitWidth + 14

    signal itemSelected(string value)
    signal focusLeftRequested()
    signal focusDownRequested()

    implicitWidth: isExpanded ? expandedWidth : fabSize
    implicitHeight: fabSize
    width: implicitWidth
    height: implicitHeight
    focus: true

    Behavior on implicitWidth {
        SpringAnimation { spring: 4; damping: 0.25; epsilon: 0.25 }
    }

    function forceFocus() {
        triggerBtn.forceActiveFocus()
    }

    function openMenu() {
        if (!menuPopup.visible) {
            _itemActivated = false
            focusedMenuIndex = 0
            menuPopup.focus = true
            menuPopup.open()
        }
    }

    function closeMenu() {
        if (menuPopup.visible) {
            menuPopup.close()
        }
    }

    function toggleMenu() {
        if (menuPopup.visible) closeMenu()
        else openMenu()
    }

    function activateItem(idx) {
        if (!menuItems || idx < 0 || idx >= menuItems.length) return
        const chosen = String(menuItems[idx].value || "")
        _itemActivated = true
        // Prevent QQuickPopup exit restoreFocus() from stealing focus from AddGameDialog
        menuPopup.focus = false
        triggerBtn.focus = false
        closeMenu()
        root.itemSelected(chosen)
    }

    Item {
        id: triggerBtn
        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: (event) => {
            if (!menuPopup.visible) {
                event.accepted = true
                root.focusLeftRequested()
            }
        }
        Keys.onDownPressed: (event) => {
            event.accepted = true
            if (!menuPopup.visible) root.focusDownRequested()
            else menuPopup.forceActiveFocus()
        }
        Keys.onReturnPressed: (event) => {
            event.accepted = true
            if (uiController) uiController.setKeyboardNavActive(true)
            root.toggleMenu()
        }
        Keys.onEnterPressed: (event) => {
            event.accepted = true
            if (uiController) uiController.setKeyboardNavActive(true)
            root.toggleMenu()
        }
        Keys.onSpacePressed: (event) => {
            event.accepted = true
            if (uiController) uiController.setKeyboardNavActive(true)
            root.toggleMenu()
        }
        Keys.onEscapePressed: (event) => {
            event.accepted = true
            if (menuPopup.visible) root.closeMenu()
            else root.focusDownRequested()
        }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Backspace) {
                event.accepted = true
                if (menuPopup.visible) root.closeMenu()
                else root.focusDownRequested()
            }
        }

        // Expanding M3 pill button (collapses to 40x40 circle at rest, springs open on hover/focus/open)
        Rectangle {
            id: fabBg
            anchors.fill: parent
            radius: root.fabSize / 2
            color: menuPopup.visible ? appSettings.secondaryContainer : appSettings.accentColor
            scale: triggerMouse.pressed ? 0.96 : (root.isKeyboardFocused ? 1.02 : 1.0)
            border.width: 0

            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.40 : 0.18)
                shadowBlur: 0.5
                shadowVerticalOffset: 3
            }

            // Hover / press state layer (opacity-only prevents transparent flash)
            Rectangle {
                anchors.fill: parent
                radius: fabBg.radius
                color: menuPopup.visible ? appSettings.onSecondaryContainer : appSettings.onPrimary
                opacity: triggerMouse.pressed ? 0.14 : (triggerHover.hovered ? 0.10 : 0.0)
                Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            }

            Item {
                anchors.fill: parent
                clip: true

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    spacing: 8

                    Item {
                        width: 16
                        height: parent.height
                        YIcon {
                            id: fabIcon
                            anchors.centerIn: parent
                            symbol: "add"
                            size: 18
                            color: menuPopup.visible ? appSettings.onSecondaryContainer : appSettings.onPrimary
                            rotation: menuPopup.visible ? 45 : 0

                            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }
                    }

                    Label {
                        id: fabLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.buttonLabel
                        color: menuPopup.visible ? appSettings.onSecondaryContainer : appSettings.onPrimary
                        font.family: "Rubik"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        renderType: Text.QtRendering
                        opacity: root.isExpanded ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }
                }
            }

            // Non-overlapping keyboard focus border ring above state fill
            Rectangle {
                z: 2
                anchors.fill: parent
                radius: fabBg.radius
                color: "transparent"
                border.color: appSettings.accentColor
                border.width: 2
                visible: root.isKeyboardFocused
            }
        }

        HoverHandler {
            id: triggerHover
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            id: triggerMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: {
                if (uiController) uiController.setKeyboardNavActive(false)
                root._suppressNextClick = menuPopup.visible
            }
            onClicked: {
                if (root._suppressNextClick) {
                    root._suppressNextClick = false
                    root.closeMenu()
                } else {
                    root.toggleMenu()
                }
            }
        }
    }

    Popup {
        id: menuPopup
        objectName: "fabMenuPopup"
        parent: root
        x: root.width - width + 16
        y: root.expandUpward ? (-height + 10) : (root.height - 4)
        width: menuCol.implicitWidth + 32
        height: menuCol.implicitHeight + 28
        padding: 0
        dim: false
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property real menuProgress: 0.0

        onOpened: {
            if (uiController && uiController.isKeyboardNavActive) {
                menuContent.forceActiveFocus()
            }
        }
        onClosed: {
            if (!root._itemActivated && uiController && uiController.isKeyboardNavActive) {
                triggerBtn.forceActiveFocus()
            }
            root._itemActivated = false
            menuPopup.focus = true
        }

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { property: "menuProgress"; from: 0.0; to: 1.0; duration: 230; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 130; easing.type: Easing.InCubic }
                NumberAnimation { property: "menuProgress"; from: 1.0; to: 0.0; duration: 140; easing.type: Easing.InCubic }
            }
        }

        background: Item {}

        contentItem: Item {
            id: menuContent
            implicitWidth: menuCol.implicitWidth + 32
            implicitHeight: menuCol.implicitHeight + 28
            focus: true

            Keys.onUpPressed: (event) => {
                event.accepted = true
                if (uiController) uiController.setKeyboardNavActive(true)
                if (root.focusedMenuIndex > 0) root.focusedMenuIndex--
                else root.closeMenu()
            }
            Keys.onDownPressed: (event) => {
                event.accepted = true
                if (uiController) uiController.setKeyboardNavActive(true)
                if (root.focusedMenuIndex < root.menuItems.length - 1) root.focusedMenuIndex++
            }
            Keys.onReturnPressed: (event) => {
                event.accepted = true
                root.activateItem(root.focusedMenuIndex)
            }
            Keys.onEnterPressed: (event) => {
                event.accepted = true
                root.activateItem(root.focusedMenuIndex)
            }
            Keys.onSpacePressed: (event) => {
                event.accepted = true
                root.activateItem(root.focusedMenuIndex)
            }
            Keys.onEscapePressed: (event) => {
                event.accepted = true
                root.closeMenu()
            }
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Backspace) {
                    event.accepted = true
                    root.closeMenu()
                }
            }

            Column {
                id: menuCol
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.top: parent.top
                anchors.topMargin: 12
                spacing: 8

                Repeater {
                    id: itemsRepeater
                    model: root.menuItems
                    delegate: Item {
                        id: menuItemDelegate
                        required property int index
                        required property var modelData

                        readonly property int count: root.menuItems ? root.menuItems.length : 0
                        readonly property int orderIdx: root.expandUpward ? Math.max(0, count - 1 - index) : index
                        readonly property real startOffset: Math.min(0.45, orderIdx * 0.24)
                        readonly property real localProgress: Math.max(0.0, Math.min(1.0, (menuPopup.menuProgress - startOffset) / Math.max(0.01, 1.0 - startOffset)))
                        readonly property bool isItemHovered: itemMA.containsMouse || (Boolean(uiController && uiController.isKeyboardNavActive) && root.focusedMenuIndex === index)
                        readonly property string itemValue: String(modelData.value || "")

                        objectName: "fabMenuItem_" + itemValue
                        anchors.right: parent ? parent.right : undefined
                        width: pillRect.implicitWidth
                        height: 46

                        opacity: localProgress
                        scale: 0.88 + 0.12 * localProgress
                        transformOrigin: Item.Right
                        transform: Translate {
                            y: (root.expandUpward ? 1 : -1) * 14 * (1.0 - menuItemDelegate.localProgress)
                        }

                        Rectangle {
                            id: pillRect
                            readonly property bool isKbItemFocused: Boolean(uiController && uiController.isKeyboardNavActive) && root.focusedMenuIndex === menuItemDelegate.index
                            implicitWidth: itemContentRow.implicitWidth + 36
                            width: implicitWidth
                            height: 46
                            radius: 23
                            color: appSettings.secondaryContainer
                            border.width: 0
                            scale: itemMA.pressed ? 0.97 : 1.0
                            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.42 : 0.16)
                                shadowBlur: 0.5
                                shadowVerticalOffset: 3
                            }

                            // Opacity-only hover/press state layer (inset inside border ring)
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Math.max(0, pillRect.radius - 1)
                                color: appSettings.onSecondaryContainer
                                opacity: itemMA.pressed ? 0.14 : (itemMA.containsMouse ? 0.08 : 0.0)
                                Behavior on opacity { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            }

                            Row {
                                id: itemContentRow
                                z: 1
                                anchors.centerIn: parent
                                spacing: 10

                                YIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    symbol: String(menuItemDelegate.modelData.iconSymbol || "")
                                    size: 19
                                    color: appSettings.onSecondaryContainer
                                }

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(menuItemDelegate.modelData.label || "")
                                    color: appSettings.onSecondaryContainer
                                    font.family: "Rubik"
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    renderType: Text.QtRendering
                                }
                            }

                            // Non-overlapping outer border / focus ring
                            Rectangle {
                                z: 2
                                anchors.fill: parent
                                radius: pillRect.radius
                                color: "transparent"
                                border.color: pillRect.isKbItemFocused ? appSettings.accentColor : appSettings.borderColor
                                border.width: pillRect.isKbItemFocused ? 2 : 1
                            }

                            MouseArea {
                                id: itemMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.focusedMenuIndex = menuItemDelegate.index
                                onClicked: {
                                    if (uiController) uiController.setKeyboardNavActive(false)
                                    root.activateItem(menuItemDelegate.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
