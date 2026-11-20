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
        if (m === 1) return "Installed"
        if (m === 2) return "Z → A"
        return "A → Z"
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

        // Minimal Top Utility Strip
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
                    Layout.minimumWidth: 200
                    Layout.maximumWidth: 500
                    radius: 20
                    readonly property bool isEditing: epicSearchField.activeFocus
                    readonly property bool isTileFocused: searchTile.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)
                    color: (epicSearchField.activeFocus || isTileFocused)
                        ? appSettings.surfaceContainerHigh
                        : appSettings.inputColor
                    border.color: (epicSearchField.activeFocus || isTileFocused) ? appSettings.accentColor : appSettings.borderColor
                    border.width: (epicSearchField.activeFocus || isTileFocused) ? 2 : 1

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
                        background: Rectangle { radius: 14; color: appSettings.surfaceAltColor; opacity: parent.hovered ? 1.0 : 0.0 }
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

                // Sort Button
                Button {
                    id: sortBtn
                    padding: 0
                    activeFocusOnTab: false
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 40
                    implicitWidth: Math.max(106, sortInner.implicitWidth + 28)

                    readonly property bool isKeyboardFocused: sortBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)

                    background: Rectangle {
                        radius: height / 2
                        color: (sortHover.hovered || sortPopup.visible) ? appSettings.surfaceContainerHighest : appSettings.surfaceContainerHigh
                        border.color: appSettings.accentColor
                        border.width: (sortPopup.visible || sortBtn.isKeyboardFocused) ? 2 : 0
                    }

                    contentItem: Item {
                        implicitWidth: sortInner.implicitWidth
                        implicitHeight: 40
                        Row {
                            id: sortInner
                            anchors.centerIn: parent
                            spacing: 6
                            YIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 17
                                symbol: "sort"
                                color: (sortHover.hovered || sortPopup.visible) ? appSettings.accentColor : appSettings.textSecColor
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.currentSortName()
                                color: appSettings.textColor
                                font.family: "Rubik"
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            YIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 18
                                symbol: "keyboard_arrow_down"
                                color: appSettings.textSecColor
                                rotation: sortPopup.visible ? 180 : 0
                            }
                        }
                    }

                    HoverHandler { id: sortHover; cursorShape: Qt.PointingHandCursor }
                    onClicked: sortPopup.visible ? sortPopup.close() : sortPopup.open()
                    Keys.onLeftPressed: (event) => { event.accepted = true; searchTile.forceActiveFocus() }
                    Keys.onRightPressed: (event) => { event.accepted = true; syncBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { event.accepted = true; epicGrid.forceActiveFocus() }

                    Popup {
                        id: sortPopup
                        y: sortBtn.height + 4
                        x: sortBtn.width - width
                        width: 190
                        padding: 6
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
                        background: Rectangle {
                            color: appSettings.surfaceContainer
                            radius: 14
                            border.color: appSettings.borderColor
                            border.width: 1
                        }
                        contentItem: Column {
                            spacing: 2
                            Repeater {
                                model: root.sortOptions
                                delegate: Item {
                                    required property var modelData
                                    width: 178
                                    height: 34
                                    readonly property bool isSel: root.epicModel && root.epicModel.sortMode === modelData.mode
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 17
                                        color: isSel ? appSettings.secondaryContainer : (sRowMA.containsMouse ? appSettings.surfaceContainerHighest : "transparent")
                                    }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        text: modelData.label
                                        color: isSel ? appSettings.onSecondaryContainer : appSettings.textColor
                                        font.pixelSize: 13
                                        font.weight: isSel ? Font.DemiBold : Font.Normal
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
                        }
                    }
                }

                // Refresh Library button
                Rectangle {
                    id: syncBtn
                    focus: true
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: 20
                    color: (syncHover.hovered || (syncBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)))
                        ? appSettings.surfaceContainerHighest : appSettings.surfaceContainerHigh
                    border.color: (syncBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive))
                        ? appSettings.accentColor : appSettings.borderColor
                    border.width: (syncBtn.activeFocus && Boolean(uiController && uiController.isKeyboardNavActive)) ? 2 : 1

                    HoverHandler { id: syncHover; cursorShape: Qt.PointingHandCursor }
                    YIcon {
                        id: syncIcon
                        anchors.centerIn: parent
                        symbol: "refresh"
                        size: 18
                        color: root.isSyncing ? appSettings.accentColor : appSettings.textColor
                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 900; loops: Animation.Infinite
                            running: root.isSyncing
                        }
                    }
                    M3ToolTip { visible: syncHover.hovered; text: root.isSyncing ? "Syncing library…" : "Refresh Epic Games library" }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.epicSvc) root.epicSvc.syncLibrary()
                    }
                    Keys.onLeftPressed: (event) => { event.accepted = true; sortBtn.forceActiveFocus() }
                    Keys.onRightPressed: (event) => { event.accepted = true; signOutBtn.forceActiveFocus() }
                    Keys.onDownPressed: (event) => { event.accepted = true; epicGrid.forceActiveFocus() }
                    Keys.onReturnPressed: (event) => { event.accepted = true; if (root.epicSvc) root.epicSvc.syncLibrary() }
                    Keys.onSpacePressed: (event) => { event.accepted = true; if (root.epicSvc) root.epicSvc.syncLibrary() }
                }

                // Account pill + Sign out
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 40
                    implicitWidth: accRow.implicitWidth + 12
                    radius: 20
                    color: appSettings.surfaceContainerHigh
                    border.color: appSettings.borderColor
                    border.width: 1

                    RowLayout {
                        id: accRow
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 6
                        spacing: 8

                        YIcon {
                            symbol: "person"
                            size: 16
                            color: appSettings.accentColor
                        }

                        Label {
                            text: (root.epicSvc && root.epicSvc.accountDisplayName.length > 0)
                                ? root.epicSvc.accountDisplayName : "Epic Account"
                            color: appSettings.textColor
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        M3Button {
                            id: signOutBtn
                            objectName: "epicSignOutBtn"
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
                    if (epicGrid.count === 0 || (epicGrid.currentIndex % root.columns === 0)) {
                        root.focusSidebarRequested()
                    } else if (epicGrid.currentIndex > 0) {
                        epicGrid.currentIndex--
                    }
                }
                Keys.onRightPressed: (event) => {
                    event.accepted = true
                    if (epicGrid.currentIndex < epicGrid.count - 1) epicGrid.currentIndex++
                }
                Keys.onUpPressed: (event) => {
                    event.accepted = true
                    if (epicGrid.count === 0 || epicGrid.currentIndex < root.columns) {
                        searchTile.forceActiveFocus()
                    } else {
                        epicGrid.currentIndex = Math.max(0, epicGrid.currentIndex - root.columns)
                    }
                }
                Keys.onDownPressed: (event) => {
                    event.accepted = true
                    if (epicGrid.currentIndex + root.columns < epicGrid.count) {
                        epicGrid.currentIndex += root.columns
                    } else if (epicGrid.currentIndex < epicGrid.count - 1) {
                        epicGrid.currentIndex = epicGrid.count - 1
                    }
                }
                Keys.onEscapePressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                Keys.onBackPressed: (event) => { event.accepted = true; root.focusSidebarRequested() }
                Keys.onReturnPressed: (event) => { event.accepted = true; epicGrid.openCurrent() }
                Keys.onEnterPressed: (event) => { event.accepted = true; epicGrid.openCurrent() }
                Keys.onSpacePressed: (event) => { event.accepted = true; epicGrid.openCurrent() }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Backspace) {
                        event.accepted = true
                        root.focusSidebarRequested()
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
                    required property bool isDownloading
                    required property bool isPaused
                    required property double downloadProgress

                    width: epicGrid.cellWidth
                    height: epicGrid.cellHeight

                    readonly property bool isMouseActive: (!uiController || !uiController.isKeyboardNavActive) && eHoverMouse.containsMouse
                    readonly property bool isTvFocused: Boolean(uiController && uiController.isKeyboardNavActive) && eCell.GridView.isCurrentItem && epicGrid.activeFocus
                    readonly property bool isHoveredOrFocused: isTvFocused || isMouseActive
                    readonly property bool isCardBlurred: appSettings.titleVisibility === 1 && isHoveredOrFocused
                    z: isTvFocused ? 50 : (isMouseActive ? 20 : 1)

                    Item {
                        anchors.fill: parent
                        anchors.margins: 8
                        scale: isTvFocused ? 1.06 : (isMouseActive ? 1.03 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

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

                        // Floating status pill on poster (when tagPosition === 2)
                        Rectangle {
                            visible: appSettings.tagPosition === 2 || eCell.isDownloading
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 8
                            z: 12
                            height: 22
                            radius: 4
                            width: ePosterLbl.implicitWidth + 10
                            property color tagC: eCell.isDownloading
                                ? (eCell.isPaused ? "#f59e0b" : appSettings.accentColor)
                                : (eCell.isInstalled ? "#22c55e" : "#cbd5e1")
                            color: Qt.rgba(0, 0, 0, 0.78)
                            border.color: Qt.rgba(tagC.r, tagC.g, tagC.b, 0.55)
                            border.width: 1

                            Label {
                                id: ePosterLbl
                                anchors.centerIn: parent
                                text: eCell.isDownloading
                                    ? (eCell.isPaused ? "PAUSED" : ("DL " + Math.round(eCell.downloadProgress) + "%"))
                                    : (eCell.isInstalled ? "INSTALLED" : "EPIC")
                                color: parent.tagC
                                font { pixelSize: 10; weight: Font.Bold; letterSpacing: 0.5 }
                            }
                        }

                        // Hover center download/view icon
                        Rectangle {
                            visible: appSettings.titleVisibility !== 1 && eCell.isHoveredOrFocused
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -root.metaHeight / 2
                            width: 48
                            height: 48
                            radius: 24
                            color: eCell.isInstalled ? "#22c55e" : appSettings.accentColor
                            z: 13
                            YIcon {
                                anchors.centerIn: parent
                                size: 20
                                symbol: eCell.isInstalled ? "play_arrow" : "download"
                                filled: eCell.isInstalled
                                color: "#ffffff"
                            }
                        }

                        // Hover Title Overlay (when titleVisibility === 1)
                        Label {
                            visible: appSettings.titleVisibility === 1 && eCell.isHoveredOrFocused
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
                            cursorShape: Qt.PointingHandCursor
                            onPressed: if (uiController) uiController.setKeyboardNavActive(false)
                            onClicked: {
                                if (uiController) uiController.setKeyboardNavActive(false)
                                epicGrid.currentIndex = eCell.index
                                epicGrid.forceActiveFocus()
                                root.gameDetailsRequested(eCell.installedGameId || "", eCell.appName)
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
                                    ? (eCell.isHoveredOrFocused ? appSettings.accentColor : Qt.rgba(34/255, 197/255, 94/255, 0.55))
                                    : (eCell.isHoveredOrFocused ? appSettings.accentColor : appSettings.borderColor))
                            border.width: eCell.isTvFocused ? 3.0 : (eCell.isMouseActive ? 2.5 : 1.5)
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

