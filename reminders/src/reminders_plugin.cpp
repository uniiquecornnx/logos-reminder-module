#include "reminders_plugin.h"
#include "logos_api.h"

#include <QDateTime>
#include <QDebug>
#include <QVariantList>
#include <QVariantMap>

#include <cstdlib>

RemindersPlugin::RemindersPlugin(QObject* parent)
    : QObject(parent)
    , m_list(reminders_create())
    , m_tick(new QTimer(this))
{
    /* 1Hz polling cadence. Fine for V1 demo; the C-side scan is O(n)
     * over at most LIBREMINDERS_CAPACITY (64) entries — trivial. */
    m_tick->setInterval(1000);
    m_tick->setSingleShot(false);
    connect(m_tick, &QTimer::timeout, this, &RemindersPlugin::onTick);
    m_tick->start();
    qDebug() << "RemindersPlugin: created (libreminders" << reminders_version() << ")";
}

RemindersPlugin::~RemindersPlugin()
{
    if (m_tick) m_tick->stop();   /* Qt parent deletes m_tick. */
    reminders_destroy(m_list);
    qDebug() << "RemindersPlugin: destroyed";
}

void RemindersPlugin::initLogos(LogosAPI* api)
{
    /* IMPORTANT: assign the global `logosAPI` from liblogos, mirroring
     * calc_module's pattern. Lifetime is owned by the host. */
    logosAPI = api;
    qDebug() << "RemindersPlugin: LogosAPI initialized";
}

int RemindersPlugin::addReminder(const QString& text, int dueAtEpochSec)
{
    if (!m_list) return 0;
    const QByteArray utf8 = text.toUtf8();
    if (utf8.isEmpty()) return 0;

    /* int → int64_t for the C library; safe widening conversion. The
     * Q_INVOKABLE param is `int` so the Logos bridge can marshal JS
     * numbers (which arrive as QVariant(int, ...)) without the type
     * promotion failure we hit with qlonglong. */
    reminder_id_t id = reminders_add(m_list,
                                     utf8.constData(),
                                     static_cast<int64_t>(dueAtEpochSec));
    qDebug() << "RemindersPlugin::addReminder text=" << text
             << "dueAt=" << dueAtEpochSec << "id=" << static_cast<qulonglong>(id);
    /* Truncate to int for the Q_INVOKABLE signature. uint64 ids are
     * monotonic from 1; INT_MAX is far beyond V1's per-session usage. */
    return static_cast<int>(id);
}

bool RemindersPlugin::removeReminder(int id)
{
    if (!m_list || id <= 0) return false;
    int ok = reminders_remove(m_list, static_cast<reminder_id_t>(id));
    qDebug() << "RemindersPlugin::removeReminder id=" << id << "ok=" << ok;
    return ok == 1;
}

QVariantList RemindersPlugin::listReminders()
{
    /* Return a native QVariantList of QVariantMaps. The Logos bridge
     * marshals this into a real JS array of objects (no JSON encoding
     * dance). Returning a JSON-encoded QString here gets double-encoded
     * by the bridge and breaks the consumer. */
    QVariantList result;
    const size_t n = reminders_count(m_list);
    for (size_t i = 0; i < n; i++) {
        reminder_id_t id = 0;
        const char* text = nullptr;
        int64_t due = 0;
        if (!reminders_get(m_list, i, &id, &text, &due)) continue;

        QVariantMap obj;
        obj.insert(QStringLiteral("id"),    static_cast<int>(id));
        obj.insert(QStringLiteral("text"),  QString::fromUtf8(text));
        obj.insert(QStringLiteral("dueAt"), static_cast<int>(due));
        result.append(obj);
    }
    return result;
}

int RemindersPlugin::count()
{
    return static_cast<int>(reminders_count(m_list));
}

QString RemindersPlugin::libVersion()
{
    return QString::fromUtf8(reminders_version());
}

void RemindersPlugin::onTick()
{
    if (!m_list) return;
    const qint64 now = QDateTime::currentSecsSinceEpoch();

    /* Drain *all* currently-due reminders in one tick. If two fire
     * within the same second, the user sees both events. */
    for (;;) {
        reminder_id_t id = 0;
        char* text = nullptr;
        int popped = reminders_pop_due(m_list,
                                       static_cast<int64_t>(now),
                                       &id, &text);
        if (!popped) break;

        const QString textStr = text ? QString::fromUtf8(text) : QString();
        std::free(text);

        qDebug() << "RemindersPlugin::onTick due id=" << static_cast<qulonglong>(id)
                 << "text=" << textStr;
        emit eventResponse("reminderDue",
                           QVariantList() << static_cast<int>(id) << textStr);
    }
}
