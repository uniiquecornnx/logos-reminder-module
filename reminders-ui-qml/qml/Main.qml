import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform

Item {
    id: root

    /* Native array returned by reminders.listReminders(). Bridge marshals
     * a QVariantList into a JS array of objects directly — no JSON.parse
     * required, and no double-encoding hazard. */
    property string statusText: ""
    property string errorText: ""

    /* The single source of truth for the "when should this reminder fire"
     * value. Both pickers read it; both pickers mutate it. The displayed
     * labels and the Save action derive from it. */
    property var pickedDate: defaultDueDate()

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

        /* The Logos bridge JSON-encodes QVariantList returns into a string
         * (observed empirically — return value arrives as a JSON string,
         * not a native JS array). Parse defensively: if it's already an
         * array (future-proof), use it; if it's a string, JSON.parse it. */
        var arr = result
        if (typeof result === "string") {
            try {
                arr = JSON.parse(result)
            } catch (e) {
                console.warn("reminders refreshList: JSON.parse failed:", e,
                             "raw:", result)
                root.errorText = "Failed to parse reminders payload"
                return
            }
        }
        if (!Array.isArray(arr)) {
            if (arr && typeof arr === "object" && arr.id !== undefined) {
                arr = [arr]
            } else {
                arr = []
            }
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
                /* data = [id, text] from reminders_plugin */
                var id = data && data.length > 0 ? data[0] : 0
                var text = data && data.length > 1 ? data[1] : "(no text)"

                /* Primary signal: native OS notification — appears on top of
                 * whatever the user is doing, regardless of basecamp focus. */
                fireSystemNotification(text, id)

                /* Secondary signal: in-app popup — visible when basecamp
                 * is already in foreground. */
                duePopup.dueId = id
                duePopup.dueText = text
                duePopup.open()

                playChime()
                refreshList()
            }
        }
    }

    /* ── OS notifications via Qt.labs.platform.SystemTrayIcon ─────────
     *
     * On macOS, SystemTrayIcon.showMessage() triggers a native notification
     * (top-right of screen, persists in Notification Center) AND adds a
     * status-bar icon next to the clock. macOS will ask for notification
     * permission the first time. */

    Platform.SystemTrayIcon {
        id: systemTray
        visible: available
        icon.source: Qt.resolvedUrl("../icons/reminders.png")
        tooltip: "Reminders — fires due reminders here"

        onMessageClicked: console.info("reminders: notification clicked")
    }

    function fireSystemNotification(text, id) {
        if (!systemTray.available) {
            console.info("reminders: SystemTrayIcon not available on this platform")
            return
        }
        if (!systemTray.supportsMessages) {
            console.info("reminders: tray icon present but notifications "
                         + "not supported on this platform")
            return
        }
        systemTray.showMessage("Reminder #" + id, text || "(no text)")
    }

    /* ── Sound (currently a no-op on basecamp v0.1.2) ─────────────────
     *
     * basecamp v0.1.2 does not ship QtMultimedia (verified by inspecting
     * /Applications/LogosBasecamp.app — no QtMultimedia framework, no
     * SoundEffect plugin). The Loader below tries to load ChimePlayer.qml
     * (which imports QtMultimedia); the import fails, the Loader enters
     * the Error state, and playChime() silently no-ops.
     *
     * Forward-compat scaffolding: if a future basecamp release ships
     * QtMultimedia, the chime will start working without any code change.
     * The popup is the primary signal in V1. */

    Loader {
        id: chimeLoader
        source: "ChimePlayer.qml"
        active: true
        asynchronous: true
        onStatusChanged: {
            if (status === Loader.Error) {
                console.info("reminders: ChimePlayer unavailable on this "
                             + "basecamp build (QtMultimedia not shipped). "
                             + "Popup remains the primary fire signal.")
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

    function nowEpochSec() {
        return Math.floor(Date.now() / 1000)
    }

    function pad2(n) {
        return (n < 10 ? "0" : "") + n
    }

    /* Default to "1 hour from now, rounded up to the next 15-minute slot". */
    function defaultDueDate() {
        var d = new Date(Date.now() + 60 * 60 * 1000)
        var minutes = d.getMinutes()
        d.setMinutes(Math.ceil(minutes / 15) * 15, 0, 0)
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
        if (diff <= 0)     return "due"
        if (diff < 60)     return diff + "s"
        if (diff < 3600)   return Math.floor(diff / 60) + "m"
        if (diff < 86400)  return Math.floor(diff / 3600) + "h "
                                 + Math.floor((diff % 3600) / 60) + "m"
        return Math.floor(diff / 86400) + "d "
               + Math.floor((diff % 86400) / 3600) + "h"
    }

    /* Tick once per second to keep relative times fresh. */
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.tick++
    }
    property int tick: 0

    /* ── Layout ───────────────────────────────────────────────── */

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        Text {
            text: "Reminders"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            color: "#ffffff"
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Type a reminder, pick a date and time, and Save."
            color: "#8b949e"
            font.pixelSize: 12
        }

        /* Row 1: reminder text + Save */
        RowLayout {
            spacing: 12
            Layout.fillWidth: true

            TextField {
                id: inputText
                placeholderText: "Reminder text"
                Layout.fillWidth: true
            }

            Button {
                text: "Save"
                onClicked: {
                    root.errorText = ""
                    if (inputText.text.length === 0) {
                        root.errorText = "Enter reminder text"
                        return
                    }
                    var dueAt = dueAtEpoch()
                    if (dueAt <= nowEpochSec()) {
                        root.errorText = "Pick a date/time in the future."
                        return
                    }
                    var newId = callModule("addReminder", [inputText.text, dueAt])
                    if (newId === undefined) return
                    if (Number(newId) <= 0) {
                        root.errorText = "Could not save reminder (list full?)"
                        return
                    }
                    root.statusText = "Saved reminder #" + newId
                    inputText.text = ""
                    root.pickedDate = defaultDueDate()
                    refreshList()
                }
            }
        }

        /* Row 2: date picker button + time picker button */
        RowLayout {
            spacing: 12
            Layout.fillWidth: true

            Label { text: "on"; color: "#8b949e" }

            Button {
                id: dateButton
                Layout.fillWidth: true
                text: formatPickedDate()
                onClicked: datePopup.open()
            }

            Label { text: "at"; color: "#8b949e" }

            Button {
                id: timeButton
                Layout.preferredWidth: 100
                text: formatPickedTime()
                onClicked: timePopup.open()
            }
        }

        /* Status / error banner */
        Rectangle {
            Layout.fillWidth: true
            height: 32
            color: root.errorText.length > 0 ? "#3d1a1a"
                  : (root.statusText.length > 0 ? "#1a2d1a" : "transparent")
            radius: 6
            visible: root.errorText.length > 0 || root.statusText.length > 0
            Text {
                anchors.centerIn: parent
                text: root.errorText.length > 0 ? root.errorText : root.statusText
                color: root.errorText.length > 0 ? "#f85149" : "#56d364"
                font.pixelSize: 13
            }
        }

        /* ── Pending list ────────────────────────────────────── */

        Text {
            text: "Pending (" + reminderModel.count + ")"
            color: "#8b949e"
            font.pixelSize: 12
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: reminderModel
            clip: true
            spacing: 6

            delegate: Rectangle {
                width: list.width
                height: 56
                color: "#1c1f24"
                radius: 8

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: model.text
                            color: "#ffffff"
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: {
                                /* Read root.tick so the binding re-evaluates each second. */
                                var _ = root.tick
                                return "fires in " + formatRelative(model.dueAt)
                                       + "  ·  id #" + model.rid
                            }
                            color: "#8b949e"
                            font.pixelSize: 11
                        }
                    }

                    Button {
                        text: "Delete"
                        onClicked: {
                            var ok = callModule("removeReminder", [model.rid])
                            if (ok) {
                                root.statusText = "Removed #" + model.rid
                                refreshList()
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                visible: reminderModel.count === 0
                Text {
                    anchors.centerIn: parent
                    text: "No reminders yet."
                    color: "#666"
                    font.pixelSize: 13
                }
            }
        }
    }

    /* ── Date picker popup ───────────────────────────────────── */

    Popup {
        id: datePopup
        modal: true
        focus: true
        anchors.centerIn: parent
        width: 340
        height: 380
        padding: 12

        /* The displayed month/year, decoupled from pickedDate so the user
         * can navigate months without committing a selection. */
        property int displayMonth: pickedDate.getMonth()
        property int displayYear: pickedDate.getFullYear()

        onOpened: {
            /* Sync display to current selection each time we open. */
            displayMonth = pickedDate.getMonth()
            displayYear  = pickedDate.getFullYear()
        }

        function prevMonth() {
            if (displayMonth === 0) {
                displayMonth = 11
                displayYear--
            } else { displayMonth-- }
        }
        function nextMonth() {
            if (displayMonth === 11) {
                displayMonth = 0
                displayYear++
            } else { displayMonth++ }
        }

        background: Rectangle {
            color: "#1c1f24"
            border.color: "#30363d"
            border.width: 1
            radius: 8
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            /* Header: < Month Year > */
            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: "‹"
                    onClicked: datePopup.prevMonth()
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: Qt.formatDate(
                        new Date(datePopup.displayYear, datePopup.displayMonth, 1),
                        "MMMM yyyy")
                    color: "#ffffff"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: "›"
                    onClicked: datePopup.nextMonth()
                }
            }

            DayOfWeekRow {
                Layout.fillWidth: true
                locale: Qt.locale()
                delegate: Text {
                    text: model.shortName
                    color: "#8b949e"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MonthGrid {
                Layout.fillWidth: true
                Layout.fillHeight: true
                month: datePopup.displayMonth
                year: datePopup.displayYear
                locale: Qt.locale()

                delegate: Rectangle {
                    /* `model.month` is the actual month for this cell; days
                     * leaking from the previous/next month render dimmed
                     * and aren't clickable. */
                    property bool inMonth: model.month === datePopup.displayMonth
                    property bool isSelected:
                        model.year  === pickedDate.getFullYear() &&
                        model.month === pickedDate.getMonth() &&
                        model.day   === pickedDate.getDate()

                    color: isSelected ? "#0969da" : "transparent"
                    radius: 4
                    opacity: inMonth ? 1.0 : 0.35

                    Text {
                        anchors.centerIn: parent
                        text: model.day
                        color: isSelected ? "#ffffff" : "#e6edf3"
                        font.pixelSize: 13
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.inMonth
                        onClicked: {
                            /* Preserve the currently-picked time when changing date. */
                            var d = new Date(model.year, model.month, model.day,
                                             pickedDate.getHours(),
                                             pickedDate.getMinutes())
                            pickedDate = d
                            datePopup.close()
                        }
                    }
                }
            }

            Button {
                text: "Cancel"
                Layout.alignment: Qt.AlignHCenter
                onClicked: datePopup.close()
            }
        }
    }

    /* ── Time picker popup (24-hour Tumblers) ──────────────────── */

    Popup {
        id: timePopup
        modal: true
        focus: true
        anchors.centerIn: parent
        width: 260
        height: 320
        padding: 12

        background: Rectangle {
            color: "#1c1f24"
            border.color: "#30363d"
            border.width: 1
            radius: 8
        }

        onOpened: {
            hourTumbler.currentIndex   = pickedDate.getHours()
            minuteTumbler.currentIndex = pickedDate.getMinutes()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Text {
                text: "Pick a time (24h)"
                color: "#8b949e"
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Tumbler {
                    id: hourTumbler
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: 24
                    visibleItemCount: 5
                    wrap: false
                    delegate: Text {
                        text: (modelData < 10 ? "0" : "") + modelData
                        color: "#ffffff"
                        font.pixelSize: 22
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: 1.0 - Math.abs(Tumbler.displacement) /
                                       (Tumbler.tumbler.visibleItemCount / 2)
                    }
                }

                Text {
                    text: ":"
                    color: "#ffffff"
                    font.pixelSize: 22
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
                        color: "#ffffff"
                        font.pixelSize: 22
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: 1.0 - Math.abs(Tumbler.displacement) /
                                       (Tumbler.tumbler.visibleItemCount / 2)
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12
                Button {
                    text: "Cancel"
                    onClicked: timePopup.close()
                }
                Button {
                    text: "OK"
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

        /* Overriding `contentItem` can break the Dialog's default behaviour
         * of closing on accept — clicking OK fires `accepted` but doesn't
         * call `close()`. Wire both signals explicitly so OK and the close
         * shortcut both dismiss the popup. */
        onAccepted: duePopup.close()
        onRejected: duePopup.close()

        contentItem: ColumnLayout {
            spacing: 12
            /* Dialog background renders WHITE on macOS — use dark text or
             * the body becomes invisible. */
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
