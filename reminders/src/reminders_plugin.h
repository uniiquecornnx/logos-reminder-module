#ifndef REMINDERS_PLUGIN_H
#define REMINDERS_PLUGIN_H

#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantList>

#include "reminders_interface.h"

/* C library — reminder list storage and time logic. */
#include "lib/libreminders.h"

class LogosAPI;

/**
 * RemindersPlugin — V1 local sticky reminders.
 *
 * State lives in `m_list` (libreminders). A 1Hz QTimer polls for due
 * reminders and emits `reminderDue` events containing (id, text). The
 * UI subscribes via `logos.onModuleEvent("reminders", "reminderDue")`.
 *
 * No persistence — reminders are lost on basecamp restart. This is a
 * known V1 limitation (see logos-reminder-idea.md).
 */
class RemindersPlugin : public QObject, public RemindersInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID RemindersInterface_iid FILE "metadata.json")
    Q_INTERFACES(RemindersInterface PluginInterface)

public:
    explicit RemindersPlugin(QObject* parent = nullptr);
    ~RemindersPlugin() override;

    /* PluginInterface */
    QString name()    const override { return "reminders"; }
    QString version() const override { return "0.1.0"; }

    /* Called reflectively by the Logos host. NOT marked override. */
    Q_INVOKABLE void initLogos(LogosAPI* api);

    /* RemindersInterface */
    Q_INVOKABLE int          addReminder(const QString& text, int dueAtEpochSec) override;
    Q_INVOKABLE bool         removeReminder(int id) override;
    Q_INVOKABLE QVariantList listReminders() override;
    Q_INVOKABLE int          count() override;
    Q_INVOKABLE QString      libVersion() override;

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private slots:
    /* QTimer tick — drains due reminders, emits one event per popped. */
    void onTick();

private:
    ReminderList* m_list = nullptr;
    QTimer*       m_tick = nullptr;
};

#endif /* REMINDERS_PLUGIN_H */
