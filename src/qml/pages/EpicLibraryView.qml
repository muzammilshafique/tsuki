import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Item {
    id: root
    objectName: "epicLibraryView"
    Layout.fillWidth: true
    Layout.fillHeight: true

    signal gameDetailsRequested(string gameId, string epicAppName)
    signal focusSidebarRequested()

    readonly property var epicSvc: uiController ? uiController.epicService : null
    readonly property bool isSignedIn: epicSvc ? epicSvc.isSignedIn : false
    readonly property bool isSigningIn: epicSvc ? epicSvc.isSigningIn : false
    readonly property bool isSyncing: epicSvc ? epicSvc.isSyncing : false
    readonly property var epicModel: epicSvc ? epicSvc.libraryModel : null
    readonly property bool isDark: appSettings.isEffectiveDark
    readonly property int cardRadius: appSettings.cardRadius
    readonly property bool hasTitleBelow: appSettings.titleVisibility === 0
    readonly property int metaHeight: hasTitleBelow ? (appSettings.tagPosition === 0 || appSettings.tagPosition === 1 ? 52 : 32) : 0
    readonly property int columns: Math.max(1, Math.floor(epicGrid.width / epicGrid.cellWidth))
    readonly property int coverSourceWidth: Math.max(
        192,
        Math.min(512, Math.ceil((Math.max(160, epicGrid.cellWidth - 16) * Math.max(1.0, Screen.devicePixelRatio)) / 64) * 64)
    )
    readonly property int coverSourceHeight: Math.round(coverSourceWidth * 1.5)

    readonly property var sortOptions: [
        { label: "Title (A → Z)",     mode: 0 },
        { label: "Installed First",   mode: 1 },
        { label: "Title (Z → A)",     mode: 2 }
    ]

    function currentSortName() {
        const m = epicModel ? epicModel.sortMode : 0
        let base = "A → Z"
        if (m === 1) base = "Installed"
        else if (m === 2) base = "Z → A"
        if (epicModel && epicModel.showHidden) {
            return base + " · Hidden"
        }
        return base
    }

    function forceFocus() {
        if (!isSignedIn) {
            openBrowserBtn.forceActiveFocus()
        } else if (epicGrid.count > 0) {
            epicGrid.forceActiveFocus()
        } else {
            searchTile.forceActiveFocus()
        }
    }

    function maybeSyncInitialLibrary() {
        if (visible && isSignedIn && epicModel && epicModel.count === 0 && !isSyncing) {
            epicSvc.syncLibrary()
        }
    }

    Component.onCompleted: {
        if (root.epicModel && root.epicModel.searchQuery && epicSearchField.text !== root.epicModel.searchQuery) {
            epicSearchField.text = root.epicModel.searchQuery
        }
        maybeSyncInitialLibrary()
    }

    onVisibleChanged: maybeSyncInitialLibrary()

    // ═══════════════════════════════════════════════════════════════════════════
    // SIGNED-OUT VIEW: Heroic-Style Browser Token Login (No WebEngine)
    // ═══════════════════════════════════════════════════════════════════════════
    Item {
        id: signInContainer
        visible: !root.isSignedIn
        anchors.fill: parent

        Keys.onEscapePressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
        Keys.onBackPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Backspace && !tokenField.isEditing) {
                event.accepted = true
                root.focusSidebarRequested()
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, 520)
            implicitHeight: loginCol.implicitHeight + 48
            radius: 22
            color: appSettings.surfaceColor
            border.color: appSettings.borderColor
            border.width: 1

            ColumnLayout {
                id: loginCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 16

                RowLayout {
                    spacing: 14
                    Rectangle {
                        width: 46
                        height: 46
                        radius: 14
                        color: appSettings.secondaryContainer
                        YIcon {
                            anchors.centerIn: parent
                            source: "qrc:/tsuki_app/icons/nav/epic-filled.svg"
                            color: appSettings.onSecondaryContainer
                            size: 24
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            text: "Epic Games Library"
                            color: appSettings.textColor
                            font.family: "Rubik"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                        }
                        Label {
                            text: "Native sign-in via account authorization token"
                            color: appSettings.textSecColor
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: 14
                    color: appSettings.surfaceContainerLow
                    border.color: appSettings.borderColor
                    border.width: 1
                    implicitHeight: stepsCol.implicitHeight + 24

                    ColumnLayout {
                        id: stepsCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6

                        Label {
                            text: "1. Click Open Login Page to view your Epic Games token in your browser."
                            color: appSettings.textColor
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "2. Copy the authorizationCode (or entire JSON text) shown on the page, paste it below, and click Sign In."
                            color: appSettings.textSecColor
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                M3Button {
                    id: openBrowserBtn
                    objectName: "epicOpenBrowserBtn"
                    Layout.fillWidth: true
                    text: "Open Epic Login in Browser"
                    iconSymbol: "open_in_new"
                    buttonType: "tonal"
                    onClicked: {
                        if (root.epicSvc) root.epicSvc.openLoginInBrowser()
                    }
                    Keys.onLeftPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                    Keys.onDownPressed: (event) => { event.accepted = true; tokenField.forceActiveFocus() }
                }

                M3TextField {
                    id: tokenField
                    objectName: "epicTokenField"
                    twoStageFocus: true
                    Layout.fillWidth: true
                    placeholderText: "Paste authorizationCode or JSON from browser…"
                    onCommit: (val) => {
                        if (val.length > 0 && root.epicSvc && !root.isSigningIn) {
                            root.epicSvc.signInWithAuthCode(val)
                        }
                    }
                    onMoveUp: openBrowserBtn.forceActiveFocus()
                    onMoveDown: signInBtn.forceActiveFocus()
                }

                Rectangle {
                    visible: root.epicSvc && root.epicSvc.authError.length > 0
                    Layout.fillWidth: true
                    radius: 10
                    color: Qt.rgba(239/255, 68/255, 68/255, 0.14)
                    border.color: Qt.rgba(239/255, 68/255, 68/255, 0.45)
                    border.width: 1
                    implicitHeight: authErrLbl.implicitHeight + 16

                    Label {
                        id: authErrLbl
                        anchors.fill: parent
                        anchors.margins: 8
                        text: root.epicSvc ? root.epicSvc.authError : ""
                        color: "#ef4444"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                M3Button {
                    id: signInBtn
                    objectName: "epicSignInBtn"
                    Layout.fillWidth: true
                    text: root.isSigningIn ? "Signing In…" : "Sign In"
                    iconSymbol: "check"
                    buttonType: "filled"
                    enabled: tokenField.text.trim().length > 0 && !root.isSigningIn
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: {
                        if (root.epicSvc) {
                            root.epicSvc.signInWithAuthCode(tokenField.text)
                        }
                    }
                    Keys.onLeftPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                    Keys.onUpPressed: (event) => { event.accepted = true; tokenField.forceActiveFocus() }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIGNED-IN VIEW: Clean Epic Account Games Grid
    // ═══════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        id: signedInContainer
        visible: root.isSignedIn
        anchors.fill: parent
        spacing: 0

        // Minimal Top Utility Strip (Matches TopBar.qml M3 Design)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 84
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 32
                anchors.rightMargin: 32
                spacing: 12

                // Search pill (matches TopBar.qml)
                Rectangle {
                    id: searchTile
                    focus: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 360
                    Layout.preferredHeight: 40
                    Layout.minimumWidth: 180
                    Layout.maximumWidth: 480
                    radius: 20
                    readonly property bool isEditing: epicSearchField.activeFocus
                    readonly property bool isTileFocused: searchTile.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                    readonly property bool isSearchHovered: epicSearchTileHover.hovered || epicSearchField.hovered
                    color: {
                        let base = appSettings.inputColor
                        if (epicSearchField.activeFocus || searchTile.isTileFocused) {
                            return appSettings.isEffectiveDark
                                ? Qt.rgba(Math.min(1.0, base.r + 0.08), Math.min(1.0, base.g + 0.08), Math.min(1.0, base.b + 0.08), 1.0)
                                : Qt.rgba(Math.max(0.0, base.r - 0.04), Math.max(0.0, base.g - 0.04), Math.max(0.0, base.b - 0.04), 1.0)
                        }
                        if (isSearchHovered) {
                            return appSettings.isEffectiveDark
                                ? Qt.rgba(Math.min(1.0, base.r + 0.04), Math.min(1.0, base.g + 0.04), Math.min(1.0, base.b + 0.04), 1.0)
                                : Qt.rgba(Math.max(0.0, base.r - 0.02), Math.max(0.0, base.g - 0.02), Math.max(0.0, base.b - 0.02), 1.0)
                        }
                        return base
                    }
                    border.color: (epicSearchField.activeFocus || isTileFocused)
                        ? appSettings.accentColor
                        : (isSearchHovered
                            ? (appSettings.isEffectiveDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14))
                            : appSettings.borderColor)
                    border.width: (epicSearchField.activeFocus || isTileFocused) ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    HoverHandler { id: epicSearchTileHover; cursorShape: Qt.IBeamCursor }

                    Keys.onLeftPressed: (event) => {
                        if (!searchTile.isEditing) {
                            event.accepted = true
                            root.focusSidebarRequested()
                        }
                    }
                    Keys.onRightPressed: (event) => {
                        if (!searchTile.isEditing) {
                            event.accepted = true
                            sortBtn.forceActiveFocus()
                        }
                    }
                    Keys.onDownPressed: (event) => {
                        event.accepted = true
                        epicGrid.forceActiveFocus()
                    }
                    Keys.onReturnPressed: (event) => {
                        event.accepted = true
                        epicSearchField.forceActiveFocus()
                    }
                    Keys.onEnterPressed: (event) => {
                        event.accepted = true
                        epicSearchField.forceActiveFocus()
                    }

                    YIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        size: 18
                        source: "qrc:/tsuki_app/icons/actions/search.svg"
                        color: (epicSearchField.activeFocus || searchTile.isTileFocused) ? appSettings.accentColor : appSettings.textSecColor
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    TextField {
                        id: epicSearchField
                        anchors.fill: parent
                        leftPadding: 42
                        rightPadding: epicSearchField.text.length > 0 ? 36 : 14
                        color: appSettings.textColor
                        font.pixelSize: 13
                        background: null
                        verticalAlignment: Text.AlignVCenter
                        selectByMouse: true
                        renderType: Text.QtRendering
                        placeholderText: "Search Epic Games library…"
                        placeholderTextColor: appSettings.textTerColor

                        Keys.onEscapePressed: (event) => {
                            event.accepted = true
                            if (epicSearchField.text.length > 0) searchTile.forceActiveFocus()
                            else epicGrid.forceActiveFocus()
                        }
                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            epicGrid.forceActiveFocus()
                        }
                        onTextChanged: {
                            if (root.epicModel) root.epicModel.searchQuery = text
                        }
                    }

                    ToolButton {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        implicitWidth: 28
                        implicitHeight: 28
                        visible: epicSearchField.text.length > 0
                        focusPolicy: Qt.NoFocus
                        background: Rectangle {
                            radius: 14
                            color: appSettings.surfaceAltColor
                            opacity: parent.hovered ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                        contentItem: YIcon {
                            anchors.centerIn: parent
                            size: 14
                            source: "qrc:/tsuki_app/icons/actions/close.svg"
                            color: appSettings.textSecColor
                        }
                        onClicked: {
                            epicSearchField.clear()
                            epicSearchField.forceActiveFocus()
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // M3 Pill Sort & Hidden Toggle Dropdown (Identical to TopBar.qml sortBtn)
                Button {
                    id: sortBtn
                    objectName: "epicSortBtn"
                    padding: 0
                    activeFocusOnTab: false
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 40
                    implicitWidth: Math.max(112, sortInner.implicitWidth + 32)

                    property int focusedPopupIndex: 0
                    readonly property int popupItemCount: root.sortOptions.length + 1
                    readonly property bool showingHidden: Boolean(root.epicModel && root.epicModel.showHidden)
                    function handlePopupDown() {
                        focusedPopupIndex = (focusedPopupIndex + 1) % popupItemCount
                    }
                    function handlePopupUp() {
                        focusedPopupIndex = (focusedPopupIndex - 1 + popupItemCount) % popupItemCount
                    }
                    function handlePopupSelect() {
                        if (focusedPopupIndex === root.sortOptions.length) {
                            if (root.epicModel) root.epicModel.showHidden = !root.epicModel.showHidden
                            return
                        }
                        if (focusedPopupIndex >= 0 && focusedPopupIndex < root.sortOptions.length && root.epicModel) {
                            root.epicModel.sortMode = root.sortOptions[focusedPopupIndex].mode
                        }
                        sortPopup.close()
                    }
                    function syncActiveIndex() {
                        const cur = root.epicModel ? root.epicModel.sortMode : 0
                        for (let i = 0; i < root.sortOptions.length; ++i) {
                            if (root.sortOptions[i].mode === cur) {
                                focusedPopupIndex = i
                                break
                            }
                        }
                    }

                    readonly property bool isBtnHovered: sortHover.hovered
                    readonly property bool isKeyboardFocused: sortBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                    readonly property bool isHighlighted: sortPopup.visible || isBtnHovered || isKeyboardFocused || showingHidden

                    background: Rectangle {
                        radius: height / 2
                        color: sortBtn.showingHidden
                            ? appSettings.secondaryContainer
                            : ((sortBtn.isBtnHovered || sortPopup.visible)
                                ? appSettings.surfaceContainerHighest
                                : appSettings.surfaceContainerHigh)
                        border.color: appSettings.accentColor
                        border.width: (sortPopup.visible || sortBtn.isKeyboardFocused) ? 2 : 0
                        scale: sortBtn.pressed ? 0.96 : (sortBtn.isKeyboardFocused ? 1.02 : 1.0)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 100 } }
                    }

                    contentItem: Item {
                        implicitWidth: sortInner.implicitWidth
                        implicitHeight: 40
                        Row {
                            id: sortInner
                            anchors.centerIn: parent
                            spacing: 8
                            YIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 17
                                symbol: "sort"
                                color: sortBtn.showingHidden
                                    ? appSettings.onSecondaryContainer
                                    : (sortBtn.isHighlighted ? appSettings.accentColor : appSettings.textSecColor)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.currentSortName()
                                color: sortBtn.showingHidden ? appSettings.onSecondaryContainer : appSettings.textColor
                                font.family: "Rubik"
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                renderType: Text.QtRendering
                            }
                            YIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 18
                                symbol: "keyboard_arrow_down"
                                color: sortBtn.showingHidden
                                    ? appSettings.onSecondaryContainer
                                    : (sortBtn.isHighlighted ? appSettings.accentColor : appSettings.textSecColor)
                                rotation: sortPopup.visible ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                        }
                    }

                    HoverHandler { id: sortHover; cursorShape: Qt.PointingHandCursor }
                    onClicked: {
                        if (sortPopup.visible) {
                            sortPopup.close()
                        } else {
                            sortBtn.syncActiveIndex()
                            sortPopup.open()
                        }
                    }

                    Keys.onLeftPressed: (event) => {
                        if (!sortPopup.visible) {
                            event.accepted = true
                            searchTile.forceActiveFocus()
                        }
                    }
                    Keys.onRightPressed: (event) => {
                        if (!sortPopup.visible) {
                            event.accepted = true
                            syncBtn.forceActiveFocus()
                        }
                    }
                    Keys.onUpPressed: (event) => {
                        if (sortPopup.visible) {
                            event.accepted = true
                            sortBtn.handlePopupUp()
                        }
                    }
                    Keys.onDownPressed: (event) => {
                        event.accepted = true
                        if (sortPopup.visible) sortBtn.handlePopupDown()
                        else epicGrid.forceActiveFocus()
                    }
                    Keys.onReturnPressed: (event) => {
                        event.accepted = true
                        if (sortPopup.visible) sortBtn.handlePopupSelect()
                        else { sortBtn.syncActiveIndex(); sortPopup.open() }
                    }
                    Keys.onEnterPressed: (event) => {
                        event.accepted = true
                        if (sortPopup.visible) sortBtn.handlePopupSelect()
                        else { sortBtn.syncActiveIndex(); sortPopup.open() }
                    }
                    Keys.onSpacePressed: (event) => {
                        event.accepted = true
                        if (sortPopup.visible) sortBtn.handlePopupSelect()
                        else { sortBtn.syncActiveIndex(); sortPopup.open() }
                    }
                    Keys.onEscapePressed: (event) => {
                        event.accepted = true
                        if (sortPopup.visible) sortPopup.close()
                        else epicGrid.forceActiveFocus()
                    }

                    Popup {
                        id: sortPopup
                        y: sortBtn.height + 4
                        x: sortBtn.width - width
                        width: Math.max(sortBtn.width, 232)
                        padding: 6
                        dim: false
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

                        onClosed: {
                            if (uiController && uiController.isKeyboardNavActive) {
                                sortBtn.forceActiveFocus()
                            } else {
                                sortBtn.focus = false
                            }
                        }

                        property real unfoldProgress: 0.0

                        enter: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "unfoldProgress"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                            }
                        }
                        exit: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 140; easing.type: Easing.InCubic }
                                NumberAnimation { property: "unfoldProgress"; from: 1.0; to: 0.0; duration: 160; easing.type: Easing.InCubic }
                            }
                        }

                        readonly property real fullContentHeight: Math.min(300, epicSortCol.implicitHeight + 12)
                        implicitHeight: fullContentHeight * unfoldProgress
                        height: implicitHeight

                        background: Rectangle {
                            color: appSettings.surfaceContainer
                            border.width: 0
                            radius: 16
                            layer.enabled: sortPopup.visible
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Qt.rgba(0, 0, 0, appSettings.isEffectiveDark ? 0.45 : 0.18)
                                shadowBlur: 0.6
                                shadowVerticalOffset: 4
                            }
                        }

                        contentItem: Item {
                            clip: true

                            Flickable {
                                id: epicSortFlick
                                anchors.fill: parent
                                contentHeight: epicSortCol.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: epicSortCol
                                    width: epicSortFlick.width
                                    spacing: 2

                                    Repeater {
                                        model: root.sortOptions
                                        delegate: Item {
                                            id: epicSortRow
                                            required property int index
                                            required property var modelData
                                            width: epicSortCol.width
                                            height: 36
                                            readonly property bool isSelected: Boolean(root.epicModel && root.epicModel.sortMode === modelData.mode)
                                            readonly property bool isHovered: sRowMA.containsMouse || (Boolean(uiController && uiController.isKeyboardNavActive) && sortBtn.focusedPopupIndex === index)

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 18
                                                color: appSettings.surfaceContainerHighest
                                                opacity: (!epicSortRow.isSelected && epicSortRow.isHovered) ? 1.0 : 0.0
                                                Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                            }
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 18
                                                color: appSettings.secondaryContainer
                                                opacity: epicSortRow.isSelected ? 1.0 : 0.0
                                                Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                            }
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 18
                                                color: Qt.rgba(0, 0, 0, 0)
                                                border.color: appSettings.accentColor
                                                border.width: 1.5
                                                opacity: (sortBtn.focusedPopupIndex === index && !epicSortRow.isSelected && Boolean(uiController && uiController.isKeyboardNavActive)) ? 1.0 : 0.0
                                                Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 14
                                                anchors.rightMargin: 14
                                                spacing: 8
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: String(epicSortRow.modelData.label)
                                                    color: epicSortRow.isSelected ? appSettings.onSecondaryContainer : appSettings.textColor
                                                    font.family: "Rubik"
                                                    font.pixelSize: 13
                                                    font.weight: epicSortRow.isSelected ? Font.DemiBold : Font.Normal
                                                    renderType: Text.QtRendering
                                                    verticalAlignment: Text.AlignVCenter
                                                    elide: Text.ElideRight
                                                }
                                                YIcon {
                                                    size: 16
                                                    symbol: "check"
                                                    color: appSettings.onSecondaryContainer
                                                    visible: epicSortRow.isSelected
                                                }
                                            }

                                            MouseArea {
                                                id: sRowMA
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.epicModel) root.epicModel.sortMode = modelData.mode
                                                    sortPopup.close()
                                                }
                                            }
                                        }
                                    }

                                    // Divider before Show Hidden toggle
                                    Item {
                                        width: epicSortCol.width
                                        height: 9
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            height: 1
                                            color: appSettings.borderColor
                                        }
                                    }

                                    // Show Hidden Option (Matches TopBar.qml Filter Row Style)
                                    Item {
                                        id: showHiddenRow
                                        objectName: "epicShowHiddenToggleRow"
                                        width: epicSortCol.width
                                        height: 36
                                        readonly property bool isSelected: Boolean(root.epicModel && root.epicModel.showHidden)
                                        readonly property bool isHovered: showHiddenMA.containsMouse || (Boolean(uiController && uiController.isKeyboardNavActive) && sortBtn.focusedPopupIndex === root.sortOptions.length)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: appSettings.surfaceContainerHighest
                                            opacity: (!showHiddenRow.isSelected && showHiddenRow.isHovered) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: appSettings.secondaryContainer
                                            opacity: showHiddenRow.isSelected ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: Qt.rgba(0, 0, 0, 0)
                                            border.color: appSettings.accentColor
                                            border.width: 1.5
                                            opacity: (sortBtn.focusedPopupIndex === root.sortOptions.length && !showHiddenRow.isSelected && Boolean(uiController && uiController.isKeyboardNavActive)) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 14
                                            spacing: 8

                                            Text {
                                                Layout.fillWidth: true
                                                text: (root.epicModel && root.epicModel.hiddenCount > 0)
                                                    ? ("Show Hidden (" + root.epicModel.hiddenCount + ")")
                                                    : "Show Hidden"
                                                color: showHiddenRow.isSelected ? appSettings.onSecondaryContainer : appSettings.textColor
                                                font.family: "Rubik"
                                                font.pixelSize: 13
                                                font.weight: showHiddenRow.isSelected ? Font.DemiBold : Font.Normal
                                                renderType: Text.QtRendering
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }

                                            YIcon {
                                                size: 16
                                                symbol: "check"
                                                color: appSettings.onSecondaryContainer
                                                visible: showHiddenRow.isSelected
                                            }
                                        }

                                        MouseArea {
                                            id: showHiddenMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.epicModel) root.epicModel.showHidden = !root.epicModel.showHidden
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // M3 Circular Refresh Library Button
                Rectangle {
                    id: syncBtn
                    focus: true
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: 20
                    readonly property bool kbFocused: syncBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                    color: (syncHover.hovered || kbFocused)
                        ? appSettings.surfaceContainerHighest : appSettings.surfaceContainerHigh
                    border.color: appSettings.accentColor
                    border.width: kbFocused ? 2 : 0
                    scale: syncMA.pressed ? 0.94 : (kbFocused ? 1.02 : 1.0)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    HoverHandler { id: syncHover; cursorShape: Qt.PointingHandCursor }
                    YIcon {
                        id: syncIcon
                        anchors.centerIn: parent
                        symbol: "refresh"
                        size: 18
                        color: (root.isSyncing || syncHover.hovered) ? appSettings.accentColor : appSettings.textColor
                        Behavior on color { ColorAnimation { duration: 120 } }
                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 900; loops: Animation.Infinite
                            running: root.isSyncing
                        }
                    }
                    M3ToolTip { visible: syncHover.hovered; text: root.isSyncing ? "Syncing library…" : "Refresh Epic Games library" }
                    MouseArea {
                        id: syncMA
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.epicSvc) { root.epicSvc.syncLibrary(); root.epicSvc.checkForUpdates() }
                    }
                    Keys.onLeftPressed: (event) => { event.accepted = true; sortBtn.forceActiveFocus() }
                    Keys.onRightPressed: (event) => { event.accepted = true; signOutBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { event.accepted = true; epicGrid.forceActiveFocus() }
                    Keys.onReturnPressed: (event) => { event.accepted = true; if (root.epicSvc) { root.epicSvc.syncLibrary(); root.epicSvc.checkForUpdates() } }
                    Keys.onSpacePressed: (event) => { event.accepted = true; if (root.epicSvc) { root.epicSvc.syncLibrary(); root.epicSvc.checkForUpdates() } }
                }

                // M3 Account Pill + Sign Out (Properly padded — zero right-border overlap)
                Rectangle {
                    id: accountPill
                    objectName: "epicAccountPill"
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 40
                    implicitWidth: accRow.implicitWidth + 24
                    radius: 20
                    color: appSettings.surfaceContainerHigh
                    border.width: 0

                    RowLayout {
                        id: accRow
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        spacing: 10

                        YIcon {
                            Layout.alignment: Qt.AlignVCenter
                            symbol: "person"
                            size: 16
                            color: appSettings.accentColor
                        }

                        Label {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.maximumWidth: 160
                            text: (root.epicSvc && root.epicSvc.accountDisplayName.length > 0)
                                ? root.epicSvc.accountDisplayName : "Epic Account"
                            color: appSettings.textColor
                            font.family: "Rubik"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            renderType: Text.QtRendering
                        }

                        M3Button {
                            id: signOutBtn
                            objectName: "epicSignOutBtn"
                            Layout.alignment: Qt.AlignVCenter
                            text: "Sign Out"
                            buttonType: "tonal"
                            implicitHeight: 28
                            onClicked: if (root.epicSvc) root.epicSvc.signOut()
                            Keys.onLeftPressed: (event) => { event.accepted = true; syncBtn.forceActiveFocus() }
                            Keys.onDownPressed: (event) => { event.accepted = true; epicGrid.forceActiveFocus() }
                        }
                    }
                }
            }
        }

        // Epic Games Grid
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            GridView {
                id: epicGrid
                anchors.fill: parent
                anchors.leftMargin: 32
                anchors.rightMargin: 32
                anchors.topMargin: 12
                anchors.bottomMargin: 24
                clip: false
                model: root.epicModel
                cellWidth: Math.floor(width / Math.max(1, Math.floor(width / appSettings.thumbScaleTarget)))
                cellHeight: Math.floor(((cellWidth - 16) * 1.5) + root.metaHeight)
                focus: true
                keyNavigationEnabled: false

                Connections {
                    target: root.epicModel
                    function onModelReset() {
                        epicGrid.currentIndex = 0
                        epicGrid.positionViewAtBeginning()
                    }
                }

                function openCurrent() {
                    if (epicGrid.currentIndex >= 0 && epicGrid.currentIndex < epicGrid.count && root.epicModel) {
                        const d = root.epicModel.get(epicGrid.currentIndex)
                        if (d && d.appName) {
                            root.gameDetailsRequested(d.installedGameId || "", d.appName)
                        }
                    }
                }

                onCurrentIndexChanged: epicGrid.positionViewAtIndex(epicGrid.currentIndex, GridView.Contain)

                Keys.onLeftPressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci && ci.isMenuOpen) { ci.isMenuOpen = false; return }
                    if (epicGrid.count === 0 || (epicGrid.currentIndex % root.columns === 0)) {
                        root.focusSidebarRequested()
                    } else if (epicGrid.currentIndex > 0) {
                        epicGrid.currentIndex--
                    }
                }
                Keys.onRightPressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci && ci.isMenuOpen) { ci.isMenuOpen = false; return }
                    if (epicGrid.currentIndex < epicGrid.count - 1) epicGrid.currentIndex++
                }
                Keys.onUpPressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci && ci.isMenuOpen) { ci.navigateMenuUp(); return }
                    if (epicGrid.count === 0 || epicGrid.currentIndex < root.columns) {
                        searchTile.forceActiveFocus()
                    } else {
                        epicGrid.currentIndex = Math.max(0, epicGrid.currentIndex - root.columns)
                    }
                }
                Keys.onDownPressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci && ci.isMenuOpen) { ci.navigateMenuDown(); return }
                    if (epicGrid.currentIndex + root.columns < epicGrid.count) {
                        epicGrid.currentIndex += root.columns
                    } else if (epicGrid.currentIndex < epicGrid.count - 1) {
                        epicGrid.currentIndex = epicGrid.count - 1
                    }
                }
                Keys.onEscapePressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci && ci.isMenuOpen) ci.isMenuOpen = false
                    else root.focusSidebarRequested()
                }
                Keys.onBackPressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci && ci.isMenuOpen) ci.isMenuOpen = false
                    else root.focusSidebarRequested()
                }
                Keys.onReturnPressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci && ci.isMenuOpen) ci.triggerMenuAction()
                    else epicGrid.openCurrent()
                }
                Keys.onEnterPressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci && ci.isMenuOpen) ci.triggerMenuAction()
                    else epicGrid.openCurrent()
                }
                Keys.onSpacePressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci && ci.isMenuOpen) ci.triggerMenuAction()
                    else epicGrid.openCurrent()
                }
                Keys.onMenuPressed: (event) => {
                    event.accepted = true
                    let ci = epicGrid.currentItem
                    if (ci) ci.toggleMenu()
                }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Backspace) {
                        event.accepted = true
                        let ci = epicGrid.currentItem
                        if (ci && ci.isMenuOpen) ci.isMenuOpen = false
                        else root.focusSidebarRequested()
                    } else if (event.key === Qt.Key_M && !event.isAutoRepeat) {
                        event.accepted = true
                        let ci = epicGrid.currentItem
                        if (ci) ci.toggleMenu()
                    }
                }

                delegate: Item {
                    id: eCell
                    required property int index
                    required property string appName
                    required property string title
                    required property string developer
                    required property url coverPath
                    required property string downloadSizeFormatted
                    required property bool isInstalled
                    required property string installedGameId
                    required property bool hasUpdate
                    required property bool isDownloading
                    required property bool isPaused
                    required property bool isQueued
                    required property double downloadProgress
                    required property bool isHidden

                    property bool isMenuOpen: false
                    property int menuFocusedIndex: 0
                    readonly property var menuActions: {
                        let acts = [
                            { id: "details", label: "Details", symbol: "edit" }
                        ]
                        if (eCell.isDownloading) {
                            acts.push({
                                id: "toggle_dl",
                                label: eCell.isPaused ? "Resume" : "Pause",
                                symbol: eCell.isPaused ? "play_arrow" : "pause"
                            })
                        }
                        acts.push({
                            id: "hide",
                            label: eCell.isHidden ? "Unhide" : "Hide",
                            symbol: eCell.isHidden ? "visibility" : "visibility_off"
                        })
                        return acts
                    }

                    onIsMenuOpenChanged: if (!isMenuOpen) menuFocusedIndex = 0
                    function toggleMenu() {
                        if (isMenuOpen) isMenuOpen = false
                        else { menuFocusedIndex = 0; isMenuOpen = true }
                    }
                    function navigateMenuUp() {
                        menuFocusedIndex = (menuFocusedIndex - 1 + menuActions.length) % menuActions.length
                    }
                    function navigateMenuDown() {
                        menuFocusedIndex = (menuFocusedIndex + 1) % menuActions.length
                    }
                    function executeMenuAction(idx) {
                        isMenuOpen = false
                        if (idx < 0 || idx >= menuActions.length) return
                        const aid = menuActions[idx].id
                        if (aid === "details") {
                            root.gameDetailsRequested(eCell.installedGameId || "", eCell.appName)
                        } else if (aid === "toggle_dl" && root.epicSvc) {
                            if (eCell.isPaused) root.epicSvc.resumeDownload(eCell.appName)
                            else root.epicSvc.pauseDownload(eCell.appName)
                        } else if (aid === "hide" && root.epicSvc) {
                            root.epicSvc.toggleHideEpicGame(eCell.appName)
                        }
                    }
                    function triggerMenuAction() { executeMenuAction(menuFocusedIndex) }

                    width: epicGrid.cellWidth
                    height: epicGrid.cellHeight

                    readonly property bool isMouseActive: (!uiController || !uiController.isKeyboardNavActive) && eHoverMouse.containsMouse
                    readonly property bool isTvFocused: Boolean(uiController && uiController.isKeyboardNavActive) && eCell.GridView.isCurrentItem && epicGrid.activeFocus
                    readonly property bool isHoveredOrFocused: isTvFocused || isMouseActive
                    readonly property bool isCardBlurred: eCell.isMenuOpen || (appSettings.titleVisibility === 1 && isHoveredOrFocused)
                    z: isTvFocused ? 50 : ((isMouseActive || isMenuOpen) ? 20 : 1)

                    Item {
                        anchors.fill: parent
                        anchors.margins: 8
                        opacity: eCell.isHidden && !eCell.isMenuOpen ? 0.62 : 1.0
                        scale: isTvFocused ? 1.06 : ((isMouseActive || eCell.isMenuOpen) ? 1.03 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        HoverHandler {
                            enabled: !uiController || !uiController.isKeyboardNavActive
                            onHoveredChanged: {
                                if (!hovered && (!uiController || !uiController.isKeyboardNavActive)) {
                                    eCell.isMenuOpen = false
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: root.cardRadius
                            color: appSettings.surfaceColor
                            antialiasing: true
                        }

                        Rectangle {
                            id: eMask
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Math.max(0, root.cardRadius - 1)
                            color: "white"
                            antialiasing: true
                            visible: false
                            layer.enabled: eCardContent.needsBlurLayer
                            layer.smooth: true
                        }

                        Item {
                            id: eCardContent
                            anchors.fill: parent
                            anchors.margins: 1
                            property real blurAmount: eCell.isCardBlurred ? 1.0 : 0.0
                            property real blurBrightness: eCell.isCardBlurred ? -0.25 : 0.0
                            Behavior on blurAmount { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on blurBrightness { NumberAnimation { duration: 180 } }
                            readonly property bool needsBlurLayer: eCell.isCardBlurred || blurAmount > 0.01

                            layer.enabled: needsBlurLayer
                            layer.smooth: true
                            layer.effect: MultiEffect {
                                autoPaddingEnabled: false
                                maskEnabled: true
                                maskSource: eMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                                blurEnabled: true
                                blur: eCardContent.blurAmount
                                blurMax: 28
                                brightness: eCardContent.blurBrightness
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: Math.max(0, root.cardRadius - 1)
                                color: appSettings.surfaceColor
                                antialiasing: true
                            }

                            // Bottom metadata (when titleVisibility === 0)
                            Item {
                                id: eMetaArea
                                visible: root.metaHeight > 0
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: root.metaHeight

                                Rectangle {
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: 1
                                    color: root.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
                                }

                                ColumnLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 4

                                    RowLayout {
                                        visible: appSettings.tagPosition === 1
                                        Layout.fillWidth: true
                                        Rectangle {
                                            width: eTagTopLbl.implicitWidth + 8; height: 18; radius: 4
                                            property color tc: eCell.isDownloading ? appSettings.accentColor : (eCell.isInstalled ? "#22c55e" : "#94a3b8")
                                            color: Qt.rgba(tc.r, tc.g, tc.b, 0.18)
                                            Label {
                                                id: eTagTopLbl; anchors.centerIn: parent
                                                text: eCell.isDownloading ? (eCell.isPaused ? "PAUSED" : Math.round(eCell.downloadProgress) + "%") : (eCell.isInstalled ? "INSTALLED" : "EPIC")
                                                color: parent.tc
                                                font { pixelSize: 10; weight: Font.Medium; letterSpacing: 0.5 }
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    Label {
                                        text: eCell.title
                                        color: appSettings.textColor
                                        font { pixelSize: 15; weight: Font.Normal; letterSpacing: 0.1 }
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }

                                    RowLayout {
                                        visible: appSettings.tagPosition === 0
                                        Layout.fillWidth: true
                                        Rectangle {
                                            width: eTagBotLbl.implicitWidth + 8; height: 18; radius: 4
                                            property color tc: eCell.isDownloading ? appSettings.accentColor : (eCell.isInstalled ? "#22c55e" : "#94a3b8")
                                            color: Qt.rgba(tc.r, tc.g, tc.b, 0.18)
                                            Label {
                                                id: eTagBotLbl; anchors.centerIn: parent
                                                text: eCell.isDownloading ? (eCell.isPaused ? "PAUSED" : Math.round(eCell.downloadProgress) + "%") : (eCell.isInstalled ? "INSTALLED" : "EPIC")
                                                color: parent.tc
                                                font { pixelSize: 10; weight: Font.Medium; letterSpacing: 0.5 }
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                            }

                            // Cover Area
                            Item {
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                anchors.bottom: eMetaArea.visible ? eMetaArea.top : parent.bottom

                                RoundedCover {
                                    id: eCoverImg
                                    anchors.fill: parent
                                    source: eCell.coverPath
                                    sourceWidth: root.coverSourceWidth
                                    sourceHeight: root.coverSourceHeight
                                    topRadius: Math.max(0, root.cardRadius - 1)
                                    bottomRadius: root.metaHeight > 0 ? 0 : Math.max(0, root.cardRadius - 1)
                                    placeholderColor: appSettings.surfaceAltColor
                                }

                                YIcon {
                                    anchors.centerIn: parent
                                    size: 44
                                    source: "qrc:/tsuki_app/icons/nav/epic.svg"
                                    color: appSettings.textTerColor
                                    opacity: 0.35
                                    visible: eCell.coverPath.toString().length === 0 || eCoverImg.status === Image.Error
                                }

                                // Live download progress strip at bottom of poster
                                Rectangle {
                                    visible: eCell.isDownloading
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                        leftMargin: root.metaHeight === 0 ? Math.min(root.cardRadius * 0.5, 6) : 0
                                        rightMargin: root.metaHeight === 0 ? Math.min(root.cardRadius * 0.5, 6) : 0
                                        bottomMargin: root.metaHeight === 0 ? 2 : 0
                                    }
                                    height: 5
                                    radius: root.metaHeight === 0 ? 2.5 : 0
                                    color: Qt.rgba(0, 0, 0, 0.65)
                                    Rectangle {
                                        height: parent.height
                                        width: parent.width * Math.max(0.0, Math.min(1.0, eCell.downloadProgress / 100.0))
                                        radius: parent.radius
                                        color: eCell.isPaused ? "#f59e0b" : appSettings.accentColor
                                    }
                                }
                            }
                        }

                        // Floating status pill on poster (when tagPosition === 2 or downloading/update/queued/hidden)
                        Rectangle {
                            visible: !eCell.isMenuOpen && (appSettings.tagPosition === 2 || eCell.isDownloading || eCell.isQueued || eCell.hasUpdate || eCell.isHidden)
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 8
                            z: 12
                            height: 22
                            radius: 4
                            width: ePosterLbl.implicitWidth + 10
                            property color tagC: eCell.isHidden
                                ? "#94a3b8"
                                : (eCell.isQueued
                                    ? "#94a3b8"
                                    : (eCell.isDownloading
                                        ? (eCell.isPaused ? "#f59e0b" : appSettings.accentColor)
                                        : (eCell.hasUpdate ? "#f59e0b" : (eCell.isInstalled ? "#22c55e" : "#cbd5e1"))))
                            color: Qt.rgba(0, 0, 0, 0.78)
                            border.color: Qt.rgba(tagC.r, tagC.g, tagC.b, 0.55)
                            border.width: 1

                            Label {
                                id: ePosterLbl
                                anchors.centerIn: parent
                                text: eCell.isHidden
                                    ? "HIDDEN"
                                    : (eCell.isQueued
                                        ? "QUEUED"
                                        : (eCell.isDownloading
                                            ? (eCell.isPaused ? "PAUSED" : ("DL " + Math.round(eCell.downloadProgress) + "%"))
                                            : (eCell.hasUpdate ? "UPDATE" : (eCell.isInstalled ? "INSTALLED" : "EPIC"))))
                                color: parent.tagC
                                font { pixelSize: 10; weight: Font.Bold; letterSpacing: 0.5 }
                            }
                        }

                        // Hover center download/resume/view icon
                        Rectangle {
                            visible: appSettings.titleVisibility !== 1 && eCell.isHoveredOrFocused && !eCell.isMenuOpen
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -root.metaHeight / 2
                            width: 48
                            height: 48
                            radius: 24
                            color: eCell.isInstalled ? "#22c55e" : (eCell.isDownloading && eCell.isPaused ? "#f59e0b" : appSettings.accentColor)
                            z: 13
                            YIcon {
                                anchors.centerIn: parent
                                size: 20
                                symbol: (eCell.isInstalled || (eCell.isDownloading && eCell.isPaused)) ? "play_arrow" : "download"
                                filled: eCell.isInstalled || (eCell.isDownloading && eCell.isPaused)
                                color: "#ffffff"
                            }
                        }

                        // Hover Title Overlay (when titleVisibility === 1)
                        Label {
                            visible: appSettings.titleVisibility === 1 && eCell.isHoveredOrFocused && !eCell.isMenuOpen
                            anchors.centerIn: parent
                            width: parent.width - 24
                            text: eCell.title
                            color: "#ffffff"
                            font { pixelSize: 16; weight: Font.Medium }
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            z: 13
                        }

                        MouseArea {
                            id: eHoverMouse
                            anchors.fill: parent
                            hoverEnabled: !uiController || !uiController.isKeyboardNavActive
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            enabled: !eCell.isMenuOpen
                            onPressed: if (uiController) uiController.setKeyboardNavActive(false)
                            onClicked: (mouse) => {
                                if (uiController) uiController.setKeyboardNavActive(false)
                                epicGrid.currentIndex = eCell.index
                                epicGrid.forceActiveFocus()
                                if (mouse.button === Qt.RightButton) {
                                    eCell.isMenuOpen = true
                                } else {
                                    root.gameDetailsRequested(eCell.installedGameId || "", eCell.appName)
                                }
                            }
                        }

                        // Right-click / M-key Action Overlay (Matches MediaGrid.qml Pill Style)
                        Rectangle {
                            id: epicActionOverlay
                            anchors.fill: eCardContent
                            z: 20
                            radius: Math.max(0, root.cardRadius - 1)
                            color: Qt.rgba(0, 0, 0, 0.45)
                            opacity: eCell.isMenuOpen ? 1.0 : 0.0
                            visible: opacity > 0.01
                            clip: true
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: eCell.isMenuOpen = false
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 24, 150)
                                spacing: 8
                                transform: Translate {
                                    y: 8 * (1.0 - epicActionOverlay.opacity)
                                }

                                Repeater {
                                    model: eCell.menuActions
                                    delegate: Rectangle {
                                        id: eCtxBtn
                                        required property int index
                                        required property var modelData
                                        readonly property bool isBtnFocused: Boolean(uiController && uiController.isKeyboardNavActive) && eCell.isMenuOpen && eCell.menuFocusedIndex === index
                                        readonly property bool isBtnActive: ((!uiController || !uiController.isKeyboardNavActive) && eCtxMA.containsMouse) || isBtnFocused
                                        Layout.fillWidth: true
                                        height: 38
                                        radius: 19
                                        color: isBtnActive ? appSettings.accentColor : Qt.rgba(0.15, 0.15, 0.18, 0.88)
                                        border.color: isBtnFocused ? "#ffffff" : Qt.rgba(1, 1, 1, 0.15)
                                        border.width: isBtnFocused ? 2 : 1
                                        scale: eCtxMA.pressed ? 0.96 : (isBtnActive ? 1.04 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 100 } }
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Behavior on border.color { ColorAnimation { duration: 120 } }

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            YIcon {
                                                size: 18
                                                symbol: eCtxBtn.modelData.symbol || "edit"
                                                color: eCtxBtn.isBtnActive ? (root.isDark ? "#0f0f11" : "#ffffff") : "#ffffff"
                                            }
                                            Label {
                                                text: eCtxBtn.modelData.label
                                                color: eCtxBtn.isBtnActive ? (root.isDark ? "#0f0f11" : "#ffffff") : "#ffffff"
                                                font.pixelSize: 14
                                                font.weight: Font.Normal
                                                renderType: Text.QtRendering
                                            }
                                        }

                                        MouseArea {
                                            id: eCtxMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: eCell.executeMenuAction(eCtxBtn.index)
                                        }
                                    }
                                }
                            }
                        }

                        // Squircle Border
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: root.cardRadius
                            antialiasing: true
                            border.color: eCell.isDownloading
                                ? appSettings.accentColor
                                : (eCell.isInstalled
                                    ? (eCell.isHoveredOrFocused || eCell.isMenuOpen ? appSettings.accentColor : Qt.rgba(34/255, 197/255, 94/255, 0.55))
                                    : (eCell.isHoveredOrFocused || eCell.isMenuOpen ? appSettings.accentColor : appSettings.borderColor))
                            border.width: eCell.isTvFocused ? 3.0 : ((eCell.isMouseActive || eCell.isMenuOpen) ? 2.5 : 1.5)
                            z: 15
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            // Empty / Syncing State
            Column {
                anchors.centerIn: parent
                spacing: 12
                visible: epicGrid.count === 0

                YIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: "qrc:/tsuki_app/icons/nav/epic.svg"
                    color: appSettings.textTerColor
                    size: 48
                    opacity: 0.6
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.isSyncing ? "Syncing Epic Games Library…" : (epicSearchField.text.length > 0 ? "No Matching Games" : "No Games Found in Epic Library")
                    color: appSettings.textColor
                    font.pixelSize: 20
                    font.weight: Font.Medium
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.isSyncing
                        ? "Fetching your owned games and artwork from Epic Games."
                        : (epicSearchField.text.length > 0 ? "Try clearing your search query." : "Click Refresh to sync games from your Epic Games account.")
                    color: appSettings.textSecColor
                    font.pixelSize: 15
                }

                M3Button {
                    visible: !root.isSyncing && epicSearchField.text.length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Refresh Library"
                    iconSymbol: "refresh"
                    buttonType: "filled"
                    onClicked: if (root.epicSvc) root.epicSvc.syncLibrary()
                }
            }
        }
    }
}

