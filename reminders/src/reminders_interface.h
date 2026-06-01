#ifndef REMINDERS_INTERFACE_H
#define REMINDERS_INTERFACE_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include "interface.h"

/**
 * Plugin-facing interface for the reminders core module.
 *
 * V1 surface — local sticky reminders only. Delivery / peer-broadcast
 * methods are intentionally deferred to V2 (see logos-reminder-idea.md).
 */
class RemindersInterface : public PluginInterface
{
public:
    virtual ~RemindersInterface() = default;

    /* Add a reminder. Returns its id (>= 1) on success, 0 on failure
     * (list full, empty text, or allocation error). NOTE: dueAtEpochSec is
     * `int` (not qint64) so the Logos IPC bridge can marshal JS numbers
     * directly without type-promotion failures. Epoch seconds fit in int32
     * until 2038, which is well past this demo's lifetime. */
    Q_INVOKABLE virtual int addReminder(const QString& text,
                                        int dueAtEpochSec) = 0;

    /* Remove a reminder by id. Returns true if removed, false if not found. */
    Q_INVOKABLE virtual bool removeReminder(int id) = 0;

    /* Return all pending reminders as a native list of maps. The bridge
     * marshals this into a JS array of objects with shape:
     *   { id: <int>, text: <string>, dueAt: <int epoch sec> }
     * IMPORTANT: do NOT return a JSON-encoded QString — the bridge will
     * JSON-encode it again, double-stringifying the payload and breaking
     * the QML consumer. */
    Q_INVOKABLE virtual QVariantList listReminders() = 0;

    /* Current count of pending reminders. */
    Q_INVOKABLE virtual int count() = 0;

    /* libreminders version string (debug aid). */
    Q_INVOKABLE virtual QString libVersion() = 0;
};

#define RemindersInterface_iid "org.logos.RemindersInterface"
Q_DECLARE_INTERFACE(RemindersInterface, RemindersInterface_iid)

#endif /* REMINDERS_INTERFACE_H */
