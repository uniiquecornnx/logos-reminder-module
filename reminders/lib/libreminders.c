#include "libreminders.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define LIBREMINDERS_VERSION_STR "0.1.0"

typedef struct {
    reminder_id_t id;
    char*         text;            /* owned, strdup'd */
    int64_t       due_at_epoch_sec;
} Reminder;

struct ReminderList {
    Reminder       items[LIBREMINDERS_CAPACITY];
    size_t         count;
    reminder_id_t  next_id;        /* monotonic; never reused */
};

const char* reminders_version(void) {
    return LIBREMINDERS_VERSION_STR;
}

ReminderList* reminders_create(void) {
    ReminderList* list = (ReminderList*)calloc(1, sizeof(ReminderList));
    if (!list) return NULL;
    list->next_id = 1;
    return list;
}

void reminders_destroy(ReminderList* list) {
    if (!list) return;
    for (size_t i = 0; i < list->count; i++) {
        free(list->items[i].text);
    }
    free(list);
}

size_t reminders_count(const ReminderList* list) {
    if (!list) return 0;
    return list->count;
}

reminder_id_t reminders_add(ReminderList* list,
                            const char* text,
                            int64_t due_at_epoch_sec) {
    if (!list || !text) return 0;
    if (list->count >= LIBREMINDERS_CAPACITY) return 0;

    char* copy = strdup(text);
    if (!copy) return 0;

    Reminder* slot = &list->items[list->count];
    slot->id = list->next_id++;
    slot->text = copy;
    slot->due_at_epoch_sec = due_at_epoch_sec;
    list->count++;
    return slot->id;
}

/* Internal: find index of reminder with given id, or -1 if absent. */
static int find_index(const ReminderList* list, reminder_id_t id) {
    for (size_t i = 0; i < list->count; i++) {
        if (list->items[i].id == id) return (int)i;
    }
    return -1;
}

/* Internal: remove at index i (frees text, swap-with-last). */
static void remove_at(ReminderList* list, size_t i) {
    free(list->items[i].text);
    size_t last = list->count - 1;
    if (i != last) {
        list->items[i] = list->items[last];
    }
    /* Clear last slot for hygiene. */
    list->items[last].id = 0;
    list->items[last].text = NULL;
    list->items[last].due_at_epoch_sec = 0;
    list->count--;
}

int reminders_remove(ReminderList* list, reminder_id_t id) {
    if (!list || id == 0) return 0;
    int idx = find_index(list, id);
    if (idx < 0) return 0;
    remove_at(list, (size_t)idx);
    return 1;
}

/* Internal: find index of earliest-due reminder with due_at <= now.
 * Returns -1 if none. */
static int find_earliest_due_index(const ReminderList* list, int64_t now) {
    int best = -1;
    int64_t best_due = 0;
    for (size_t i = 0; i < list->count; i++) {
        if (list->items[i].due_at_epoch_sec <= now) {
            if (best < 0 || list->items[i].due_at_epoch_sec < best_due) {
                best = (int)i;
                best_due = list->items[i].due_at_epoch_sec;
            }
        }
    }
    return best;
}

int reminders_peek_due(const ReminderList* list,
                       int64_t now_epoch_sec,
                       reminder_id_t* out_id,
                       const char** out_text) {
    if (!list) return 0;
    int idx = find_earliest_due_index(list, now_epoch_sec);
    if (idx < 0) return 0;
    if (out_id)   *out_id = list->items[idx].id;
    if (out_text) *out_text = list->items[idx].text;
    return 1;
}

int reminders_get(const ReminderList* list,
                  size_t index,
                  reminder_id_t* out_id,
                  const char** out_text,
                  int64_t* out_due_at_epoch_sec) {
    if (!list || index >= list->count) return 0;
    const Reminder* r = &list->items[index];
    if (out_id)                 *out_id = r->id;
    if (out_text)               *out_text = r->text;
    if (out_due_at_epoch_sec)   *out_due_at_epoch_sec = r->due_at_epoch_sec;
    return 1;
}

int reminders_pop_due(ReminderList* list,
                      int64_t now_epoch_sec,
                      reminder_id_t* out_id,
                      char** out_text) {
    if (!list) return 0;
    int idx = find_earliest_due_index(list, now_epoch_sec);
    if (idx < 0) return 0;

    reminder_id_t id = list->items[idx].id;
    /* Transfer ownership of text to caller (don't strdup; the slot's
     * pointer becomes the caller's). Then remove_at must not free it. */
    char* text = list->items[idx].text;
    list->items[idx].text = NULL;  /* prevent double-free in remove_at */

    /* remove_at frees text — we just nulled it, so the free is a no-op. */
    remove_at(list, (size_t)idx);

    if (out_id)   *out_id = id;
    if (out_text) *out_text = text;
    else          free(text);  /* caller didn't want it; don't leak */
    return 1;
}
