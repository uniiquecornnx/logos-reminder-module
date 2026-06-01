#ifndef LIBREMINDERS_H
#define LIBREMINDERS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle to a reminder list. */
typedef struct ReminderList ReminderList;

/* Monotonic reminder identifier. 0 is reserved for "invalid / not found". */
typedef uint64_t reminder_id_t;

/* Maximum reminders held by a list. Fixed for V1 (demo scope). */
#define LIBREMINDERS_CAPACITY 64

/* Library version. */
const char* reminders_version(void);

/* Create an empty reminder list. Returns NULL on allocation failure. */
ReminderList* reminders_create(void);

/* Free a reminder list and all owned reminder text. */
void reminders_destroy(ReminderList* list);

/* Number of pending reminders. */
size_t reminders_count(const ReminderList* list);

/* Add a reminder. Returns the new id (>= 1) on success, 0 on failure
 * (list full, NULL text, or allocation failure). The list copies `text`. */
reminder_id_t reminders_add(ReminderList* list,
                            const char* text,
                            int64_t due_at_epoch_sec);

/* Remove a reminder by id. Returns 1 if removed, 0 if not found. */
int reminders_remove(ReminderList* list, reminder_id_t id);

/* Peek the earliest reminder whose due_at <= now_epoch_sec.
 * Does NOT mutate the list. Out parameters are valid until the next
 * mutating call on this list.
 * Returns 1 if a due reminder was found, 0 otherwise. */
int reminders_peek_due(const ReminderList* list,
                       int64_t now_epoch_sec,
                       reminder_id_t* out_id,
                       const char** out_text);

/* Pop (remove + return) the earliest due reminder.
 * Out_text is heap-allocated; caller must `free()` it.
 * Returns 1 if popped, 0 otherwise. */
int reminders_pop_due(ReminderList* list,
                      int64_t now_epoch_sec,
                      reminder_id_t* out_id,
                      char** out_text);

/* Read the reminder at `index` (0..count-1). Order is unspecified and may
 * change after any mutation. Out parameters may be NULL if unwanted.
 * Out_text is borrowed; valid until the next mutating call.
 * Returns 1 if index was in range, 0 otherwise. */
int reminders_get(const ReminderList* list,
                  size_t index,
                  reminder_id_t* out_id,
                  const char** out_text,
                  int64_t* out_due_at_epoch_sec);

#ifdef __cplusplus
}
#endif

#endif /* LIBREMINDERS_H */
