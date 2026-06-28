import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform

Item {
    id: root

    /* ── Design tokens ──────────────────────────────────────────
     * Centralised so any colour/spacing change happens in one
     * place. Roughly: GitHub-dark canvas + warm amber accent
     * matching the bell icon. */
    readonly property color bgCanvas:     "#0d1117"
    readonly property color bgCard:       "#161b22"
    readonly property color bgCardHover:  "#1c2129"
    readonly property color bgElevated:   "#1f262e"
    readonly property color bgInput:      "#0d1117"
    readonly property color borderSubtle: "#21262d"
    readonly property color borderStrong: "#30363d"
    readonly property color textPrimary:  "#e6edf3"
    readonly property color textSecondary:"#8b949e"
    readonly property color textMuted:    "#6e7681"
    readonly property color accent:       "#f59e0b"  /* amber-500 */
    readonly property color accentHover:  "#fbbf24"
    readonly property color accentPress:  "#d97706"
    readonly property color accentFaint:  "#f59e0b22"
    readonly property color success:      "#56d364"
    readonly property color successBg:    "#1a2d1a"
    readonly property color errorColor:   "#f85149"
    readonly property color errorBg:      "#3d1a1a"

    /* Painted canvas — so any uncovered area picks up the dark bg
     * instead of the default basecamp container colour. */
    Rectangle { anchors.fill: parent; color: root.bgCanvas }

    /* ── State ───────────────────────────────────────────────── */

    property string statusText: ""
    property string errorText: ""
    property var pickedDate: defaultDueDate()
    property int tick: 0   /* 1 Hz tick to refresh relative times */

    /* ── Logos bridge ────────────────────────────────────────── */

    function callModule(method, args) {
        if (typeof logos === "undefined" || !logos.callModule) {
            root.errorText = "Logos bridge not available"
            return undefined
        }
        return logos.callModule("reminders", method, args)
    }

    function refreshList() {
        var result = callModule("listReminders", [])
        if (result === undefined || result === null) return

        /* Bridge JSON-encodes QVariantList; parse defensively. */
        var arr = result
        if (typeof result === "string") {
            try { arr = JSON.parse(result) }
            catch (e) {
                console.warn("refreshList parse:", e, "raw:", result)
                root.errorText = "Failed to parse reminders payload"
                return
            }
        }
        if (!Array.isArray(arr)) {
            arr = (arr && typeof arr === "object" && arr.id !== undefined)
                  ? [arr] : []
        }

        reminderModel.clear()
        for (var i = 0; i < arr.length; i++) {
            var item = arr[i] || {}
            reminderModel.append({
                rid:   item.id    !== undefined ? item.id    : 0,
                text:  item.text  !== undefined ? item.text  : "",
                dueAt: item.dueAt !== undefined ? item.dueAt : 0
            })
        }
    }

    Component.onCompleted: {
        if (typeof logos !== "undefined" && logos.onModuleEvent)
            logos.onModuleEvent("reminders", "reminderDue")
        refreshList()
    }

    Connections {
        target: typeof logos !== "undefined" ? logos : null
        function onModuleEventReceived(moduleName, eventName, data) {
            if (moduleName !== "reminders") return
            if (eventName === "reminderDue") {
                var id   = data && data.length > 0 ? data[0] : 0
                var text = data && data.length > 1 ? data[1] : "(no text)"
                fireSystemNotification(text, id)
                duePopup.dueId = id
                duePopup.dueText = text
                duePopup.open()
                playChime()
                refreshList()
            }
        }
    }

    /* ── OS notifications (works) + sound (no-op on basecamp v0.1.2) ── */

    Platform.SystemTrayIcon {
        id: systemTray
        visible: available
        icon.source: Qt.resolvedUrl("../icons/reminders.png")
        tooltip: "Reminders — fires due reminders here"
        onMessageClicked: console.info("reminders: notification clicked")
    }

    function fireSystemNotification(text, id) {
        if (!systemTray.available)       return
        if (!systemTray.supportsMessages) return
        systemTray.showMessage("Reminder #" + id, text || "(no text)")
    }

    Loader {
        id: chimeLoader
        source: "ChimePlayer.qml"
        active: true
        asynchronous: true
        onStatusChanged: {
            if (status === Loader.Error) {
                console.info("ChimePlayer unavailable (basecamp v0.1.2 "
                             + "ships no QtMultimedia). Popup + OS "
                             + "notification remain the fire signals.")
            }
        }
    }
    function playChime() {
        if (chimeLoader.status === Loader.Ready && chimeLoader.item) {
            try { chimeLoader.item.play() } catch (e) { /* no-op */ }
        }
    }

    /* ── Models ───────────────────────────────────────────────── */

    ListModel { id: reminderModel }

    /* ── Helpers ──────────────────────────────────────────────── */

    function nowEpochSec() { return Math.floor(Date.now() / 1000) }
    function pad2(n)       { return (n < 10 ? "0" : "") + n }

    function defaultDueDate() {
        var d = new Date(Date.now() + 60 * 60 * 1000)
        d.setMinutes(Math.ceil(d.getMinutes() / 15) * 15, 0, 0)
        return d
    }

    function formatPickedDate() {
        return Qt.formatDate(root.pickedDate, "ddd, MMM d, yyyy")
    }
    function formatPickedTime() {
        return pad2(root.pickedDate.getHours()) + ":"
             + pad2(root.pickedDate.getMinutes())
    }
    function dueAtEpoch() {
        return Math.floor(root.pickedDate.getTime() / 1000)
    }
    function formatRelative(dueAt) {
        var diff = dueAt - nowEpochSec()
        if (diff <= 0)     return "due now"
        if (diff < 60)     return "in " + diff + "s"
        if (diff < 3600)   return "in " + Math.floor(diff / 60) + "m"
        if (diff < 86400)  return "in " + Math.floor(diff / 3600) + "h "
                                 + Math.floor((diff % 3600) / 60) + "m"
        return "in " + Math.floor(diff / 86400) + "d "
               + Math.floor((diff % 86400) / 3600) + "h"
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.tick++
    }

    /* ── Layout ───────────────────────────────────────────────── */

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 20

        /* Header */
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "Reminders"
                color: root.textPrimary
                font.pixelSize: 26
                font.weight: Font.Bold
                font.letterSpacing: -0.4
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: "Pick a moment. We'll find you across whatever app you're in."
                color: root.textSecondary
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
        }

        /* Composer card */
        Rectangle {
            Layout.fillWidth: true
            color: root.bgCard
            border.color: root.borderSubtle
            border.width: 1
            radius: 12
            implicitHeight: composerCol.implicitHeight + 24

            ColumnLayout {
                id: composerCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                /* Text input row */
                TextField {
                    id: inputText
                    placeholderText: "What should I remind you about?"
                    Layout.fillWidth: true
                    color: root.textPrimary
                    placeholderTextColor: root.textMuted
                    selectByMouse: true
                    font.pixelSize: 14
                    background: Rectangle {
                        color: root.bgInput
                        border.color: inputText.activeFocus
                                      ? root.accent : root.borderSubtle
                        border.width: 1
                        radius: 8
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                    }
                    padding: 12
                }

                /* Date + Time + Save row */
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    /* Date picker trigger — wide, card-styled */
                    PickerButton {
                        id: dateButton
                        Layout.fillWidth: true
                        iconText: "📅"
                        text: formatPickedDate()
                        onClicked: datePopup.open()
                    }

                    /* Time picker trigger — narrower */
                    PickerButton {
                        id: timeButton
                        Layout.preferredWidth: 110
                        iconText: "⏰"
                        text: formatPickedTime()
                        onClicked: timePopup.open()
                    }

                    /* Save — primary amber button */
                    PrimaryButton {
                        text: "Save"
                        onClicked: handleSave()
                    }
                }
            }
        }

        /* Status / error banner — slides in/out by visibility */
        Rectangle {
            Layout.fillWidth: true
            radius: 10
            visible: root.errorText.length > 0 || root.statusText.length > 0
            color: root.errorText.length > 0 ? root.errorBg : root.successBg
            border.color: root.errorText.length > 0 ? root.errorColor : root.success
            border.width: 1
            implicitHeight: 40

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                Text {
                    text: root.errorText.length > 0 ? "⚠" : "✓"
                    color: root.errorText.length > 0 ? root.errorColor : root.success
                    font.pixelSize: 14
                }
                Text {
                    text: root.errorText.length > 0 ? root.errorText : root.statusText
                    color: root.errorText.length > 0 ? root.errorColor : root.success
                    font.pixelSize: 13
                    Layout.fillWidth: true
                }
            }
        }

        /* Section label: PENDING (N) */
        RowLayout {
            spacing: 8
            Layout.topMargin: 4
            Text {
                text: "PENDING"
                color: root.textMuted
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 1.4
            }
            Rectangle {
                width: countLabel.implicitWidth + 12
                height: 18
                radius: 9
                color: root.accentFaint
                Text {
                    id: countLabel
                    anchors.centerIn: parent
                    text: reminderModel.count
                    color: root.accent
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
            Item { Layout.fillWidth: true }
        }

        /* Reminder list */
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: reminderModel
            clip: true
            spacing: 8

            delegate: ReminderCard {
                width: list.width
                rid:   model.rid
                text:  model.text
                dueAt: model.dueAt
            }

            /* Empty state */
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                visible: reminderModel.count === 0
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "🔕"
                        font.pixelSize: 36
                        opacity: 0.5
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "Nothing pending"
                        color: root.textMuted
                        font.pixelSize: 13
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }

    /* ── Reusable: Primary (amber) button ───────────────────── */

    component PrimaryButton : Button {
        id: pb
        implicitHeight: 36
        leftPadding: 18
        rightPadding: 18
        contentItem: Text {
            text: pb.text
            color: "#1a1500"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: pb.pressed ? root.accentPress
                  : pb.hovered ? root.accentHover : root.accent
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    /* ── Reusable: Secondary outlined button ─────────────────── */

    component GhostButton : Button {
        id: gb
        property color customText: root.textPrimary
        implicitHeight: 32
        leftPadding: 14
        rightPadding: 14
        contentItem: Text {
            text: gb.text
            color: gb.customText
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: gb.pressed ? root.bgCardHover
                  : gb.hovered ? root.bgCard : "transparent"
            border.color: gb.hovered ? root.borderStrong : root.borderSubtle
            border.width: 1
            Behavior on color        { ColorAnimation { duration: 100 } }
            Behavior on border.color { ColorAnimation { duration: 100 } }
        }
    }

    /* ── Reusable: Date/time picker trigger ──────────────────── */

    component PickerButton : Button {
        id: pkb
        /* `icon` is a FINAL group property on Button — must use a
         * different name to avoid "Cannot override FINAL property". */
        property string iconText: ""
        implicitHeight: 38
        leftPadding: 12
        rightPadding: 12
        contentItem: RowLayout {
            spacing: 8
            Text {
                text: pkb.iconText
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: pkb.text
                color: root.textPrimary
                font.pixelSize: 13
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
            }
            Text {
                text: "▾"
                color: root.textMuted
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }
        }
        background: Rectangle {
            radius: 8
            color: pkb.pressed ? root.bgCardHover
                  : pkb.hovered ? root.bgCard : root.bgInput
            border.color: pkb.hovered ? root.accent : root.borderSubtle
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 120 } }
        }
    }

    /* ── Reusable: list-row card delegate ────────────────────── */

    component ReminderCard : Rectangle {
        id: card
        property int    rid:   0
        property string text:  ""
        property int    dueAt: 0
        height: 68
        radius: 10
        color: cardMouse.containsMouse ? root.bgCardHover : root.bgCard
        border.color: root.borderSubtle
        border.width: 1
        Behavior on color { ColorAnimation { duration: 100 } }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            propagateComposedEvents: true
            acceptedButtons: Qt.NoButton  /* let inner buttons receive clicks */
        }

        /* Left accent bar */
        Rectangle {
            width: 4
            radius: 2
            color: root.accent
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
                leftMargin: 0
                topMargin: 10
                bottomMargin: 10
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: card.text
                    color: root.textPrimary
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                RowLayout {
                    spacing: 8
                    Text {
                        text: "⏱"
                        color: root.textMuted
                        font.pixelSize: 11
                    }
                    Text {
                        text: {
                            var _ = root.tick   /* re-bind each tick */
                            return formatRelative(card.dueAt)
                        }
                        color: root.textSecondary
                        font.pixelSize: 11
                    }
                    Rectangle {
                        width: 3; height: 3; radius: 1.5
                        color: root.textMuted
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: "#" + card.rid
                        color: root.textMuted
                        font.pixelSize: 11
                    }
                }
            }

            /* Delete button — text label, red tint on hover */
            Button {
                id: delBtn
                implicitHeight: 32
                leftPadding: 14
                rightPadding: 14
                contentItem: Text {
                    text: "Delete"
                    color: delBtn.hovered ? root.errorColor : root.textSecondary
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                background: Rectangle {
                    radius: 8
                    color: delBtn.hovered ? root.errorBg : "transparent"
                    border.color: delBtn.hovered ? root.errorColor
                                                 : root.borderSubtle
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 100 } }
                }
                onClicked: {
                    var ok = callModule("removeReminder", [card.rid])
                    if (ok) {
                        root.statusText = "Removed #" + card.rid
                        refreshList()
                    }
                }
            }
        }
    }

    /* ── Save handler (shared by button + Enter) ────────────── */

    function handleSave() {
        root.errorText = ""
        if (inputText.text.length === 0) {
            root.errorText = "Tell me what to remind you about."
            return
        }
        var dueAt = dueAtEpoch()
        if (dueAt <= nowEpochSec()) {
            root.errorText = "Pick a moment in the future."
            return
        }
        var newId = callModule("addReminder", [inputText.text, dueAt])
        if (newId === undefined) return
        if (Number(newId) <= 0) {
            root.errorText = "Could not save (list full?)"
            return
        }
        root.statusText = "Saved reminder #" + newId
        inputText.text = ""
        root.pickedDate = defaultDueDate()
        refreshList()
    }

    /* ── Date picker popup ───────────────────────────────────── */

    Popup {
        id: datePopup
        modal: true
        focus: true
        anchors.centerIn: parent
        width: 340
        height: 400
        padding: 0

        property int displayMonth: pickedDate.getMonth()
        property int displayYear:  pickedDate.getFullYear()

        onOpened: {
            displayMonth = pickedDate.getMonth()
            displayYear  = pickedDate.getFullYear()
        }
        function prevMonth() {
            if (displayMonth === 0) { displayMonth = 11; displayYear-- }
            else displayMonth--
        }
        function nextMonth() {
            if (displayMonth === 11) { displayMonth = 0; displayYear++ }
            else displayMonth++
        }

        background: Rectangle {
            color: root.bgElevated
            border.color: root.borderStrong
            border.width: 1
            radius: 14
        }

        contentItem: ColumnLayout {
            spacing: 12
            anchors.margins: 16

            /* Header */
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                GhostButton {
                    text: "‹"
                    implicitWidth: 36
                    implicitHeight: 32
                    onClicked: datePopup.prevMonth()
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: Qt.formatDate(
                        new Date(datePopup.displayYear,
                                 datePopup.displayMonth, 1),
                        "MMMM yyyy")
                    color: root.textPrimary
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                GhostButton {
                    text: "›"
                    implicitWidth: 36
                    implicitHeight: 32
                    onClicked: datePopup.nextMonth()
                }
            }

            DayOfWeekRow {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                locale: Qt.locale()
                delegate: Text {
                    text: model.shortName.toUpperCase()
                    color: root.textMuted
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MonthGrid {
                id: monthGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                month: datePopup.displayMonth
                year:  datePopup.displayYear
                locale: Qt.locale()

                delegate: Item {
                    property bool inMonth: model.month === datePopup.displayMonth
                    property bool isToday: {
                        var t = new Date()
                        return model.year === t.getFullYear()
                            && model.month === t.getMonth()
                            && model.day === t.getDate()
                    }
                    property bool isSelected:
                        model.year  === pickedDate.getFullYear() &&
                        model.month === pickedDate.getMonth() &&
                        model.day   === pickedDate.getDate()

                    opacity: inMonth ? 1.0 : 0.25

                    /* Selected / today / hover ring as a circle */
                    Rectangle {
                        anchors.centerIn: parent
                        width:  Math.min(parent.width, parent.height) - 6
                        height: width
                        radius: width / 2
                        color: isSelected ? root.accent
                              : (dayMouse.containsMouse ? root.accentFaint
                                                        : "transparent")
                        border.color: isToday && !isSelected
                                      ? root.accent : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: model.day
                        color: isSelected ? "#1a1500" : root.textPrimary
                        font.pixelSize: 13
                        font.weight: isSelected || isToday
                                     ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: parent.inMonth
                        onClicked: {
                            var d = new Date(model.year, model.month, model.day,
                                             pickedDate.getHours(),
                                             pickedDate.getMinutes())
                            pickedDate = d
                            datePopup.close()
                        }
                    }
                }
            }

            /* Footer */
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 16
                Item { Layout.fillWidth: true }
                GhostButton {
                    text: "Today"
                    onClicked: {
                        var t = new Date()
                        var d = new Date(t.getFullYear(), t.getMonth(), t.getDate(),
                                         pickedDate.getHours(),
                                         pickedDate.getMinutes())
                        pickedDate = d
                        datePopup.close()
                    }
                }
                GhostButton {
                    text: "Cancel"
                    onClicked: datePopup.close()
                }
            }
        }
    }

    /* ── Time picker popup (24-hour tumblers) ────────────────── */

    Popup {
        id: timePopup
        modal: true
        focus: true
        anchors.centerIn: parent
        width: 280
        height: 360
        padding: 0

        background: Rectangle {
            color: root.bgElevated
            border.color: root.borderStrong
            border.width: 1
            radius: 14
        }

        onOpened: {
            hourTumbler.currentIndex   = pickedDate.getHours()
            minuteTumbler.currentIndex = pickedDate.getMinutes()
        }

        contentItem: ColumnLayout {
            anchors.margins: 16
            spacing: 12

            Text {
                text: "PICK A TIME · 24H"
                color: root.textMuted
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 1.4
                Layout.topMargin: 16
                Layout.alignment: Qt.AlignHCenter
            }

            /* Tumblers with a centered selection band */
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24

                /* Subtle horizontal selection band (top + bottom borders) */
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height / 5  /* matches visibleItemCount */
                    color: root.accentFaint
                    radius: 6
                    border.color: root.accent
                    border.width: 1
                    opacity: 0.7
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 4

                    Tumbler {
                        id: hourTumbler
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: 24
                        visibleItemCount: 5
                        wrap: false
                        delegate: Text {
                            text: (modelData < 10 ? "0" : "") + modelData
                            color: root.textPrimary
                            font.pixelSize: Tumbler.displacement === 0 ? 26 : 18
                            font.weight: Tumbler.displacement === 0
                                         ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: 1.0 - Math.abs(Tumbler.displacement) /
                                           (Tumbler.tumbler.visibleItemCount / 2)
                            Behavior on font.pixelSize {
                                NumberAnimation { duration: 100 }
                            }
                        }
                    }
                    Text {
                        text: ":"
                        color: root.accent
                        font.pixelSize: 26
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Tumbler {
                        id: minuteTumbler
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: 60
                        visibleItemCount: 5
                        wrap: false
                        delegate: Text {
                            text: (modelData < 10 ? "0" : "") + modelData
                            color: root.textPrimary
                            font.pixelSize: Tumbler.displacement === 0 ? 26 : 18
                            font.weight: Tumbler.displacement === 0
                                         ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: 1.0 - Math.abs(Tumbler.displacement) /
                                           (Tumbler.tumbler.visibleItemCount / 2)
                            Behavior on font.pixelSize {
                                NumberAnimation { duration: 100 }
                            }
                        }
                    }
                }
            }

            /* Footer */
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                spacing: 8
                Item { Layout.fillWidth: true }
                GhostButton {
                    text: "Cancel"
                    onClicked: timePopup.close()
                }
                PrimaryButton {
                    text: "Confirm"
                    onClicked: {
                        var d = new Date(pickedDate)
                        d.setHours(hourTumbler.currentIndex,
                                   minuteTumbler.currentIndex, 0, 0)
                        pickedDate = d
                        timePopup.close()
                    }
                }
            }
        }
    }

    /* ── Due popup ────────────────────────────────────────────── */

    Dialog {
        id: duePopup
        property int dueId: 0
        property string dueText: ""
        modal: true
        anchors.centerIn: parent
        title: "Reminder"
        standardButtons: Dialog.Ok
        onAccepted: duePopup.close()
        onRejected: duePopup.close()

        contentItem: ColumnLayout {
            spacing: 12
            Text {
                text: duePopup.dueText
                color: "#1f2328"
                font.pixelSize: 16
                wrapMode: Text.WordWrap
                Layout.preferredWidth: 320
            }
            Text {
                text: "id #" + duePopup.dueId
                color: "#57606a"
                font.pixelSize: 11
            }
        }
    }
}
