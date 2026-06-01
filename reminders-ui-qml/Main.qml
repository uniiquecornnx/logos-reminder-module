import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    /* Native array returned by reminders.listReminders(). Bridge marshals
     * a QVariantList into a JS array of objects directly — no JSON.parse
     * required, and no double-encoding hazard. */
    property string statusText: ""
    property string errorText: ""

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
        /* A single-item return sometimes comes back as an object instead of
         * a 1-element array. Normalize. */
        if (!Array.isArray(arr)) {
            if (arr && typeof arr === "object" && arr.id !== undefined) {
                arr = [arr]
            } else {
                console.warn("reminders refreshList: unexpected payload shape:",
                             JSON.stringify(arr))
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
                duePopup.dueId = id
                duePopup.dueText = text
                duePopup.open()
                refreshList()
            }
        }
    }

    /* ── Models ───────────────────────────────────────────────── */

    ListModel { id: reminderModel }

    /* ── Helpers ──────────────────────────────────────────────── */

    function nowEpochSec() {
        return Math.floor(Date.now() / 1000)
    }

    function formatRelative(dueAt) {
        var diff = dueAt - nowEpochSec()
        if (diff <= 0) return "due"
        if (diff < 60) return diff + "s"
        if (diff < 3600) return Math.floor(diff / 60) + "m"
        return Math.floor(diff / 3600) + "h " + Math.floor((diff % 3600) / 60) + "m"
    }

    /* Tick once per second to keep relative times fresh. */
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            /* Rebuild the model's display field. Cheapest: toggle a property
             * the delegate watches. We use root.tick. */
            root.tick++
        }
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
            text: "Type a reminder, pick how many minutes from now, and Save."
            color: "#8b949e"
            font.pixelSize: 12
        }

        RowLayout {
            spacing: 12
            Layout.fillWidth: true

            TextField {
                id: inputText
                placeholderText: "Reminder text"
                Layout.fillWidth: true
            }

            Label {
                text: "in"
                color: "#8b949e"
            }

            SpinBox {
                id: inputMinutes
                from: 0
                to: 24 * 60       /* up to a day */
                value: 1
                editable: true
                Layout.preferredWidth: 100
            }

            Label {
                text: "min"
                color: "#8b949e"
            }

            Button {
                text: "Save"
                onClicked: {
                    root.errorText = ""
                    if (inputText.text.length === 0) {
                        root.errorText = "Enter reminder text"
                        return
                    }
                    var dueAt = nowEpochSec() + inputMinutes.value * 60
                    var newId = callModule("addReminder", [inputText.text, dueAt])
                    if (newId === undefined) return
                    if (Number(newId) <= 0) {
                        root.errorText = "Could not save reminder (list full?)"
                        return
                    }
                    root.statusText = "Saved reminder #" + newId
                    inputText.text = ""
                    inputMinutes.value = 1
                    refreshList()
                }
            }
        }

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
