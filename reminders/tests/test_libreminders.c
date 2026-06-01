/* Tests for libreminders. Plain C; compile and run with:
 *   cc -std=c11 -Wall -Wextra -Werror -I../lib \
 *      ../lib/libreminders.c test_libreminders.c -o test_libreminders && ./test_libreminders
 */
#include "libreminders.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_passed = 0;
static int g_failed = 0;

#define RUN(test)                                                  \
    do {                                                           \
        printf("RUN  %s\n", #test);                                \
        int before_failed = g_failed;                              \
        test();                                                    \
        if (g_failed == before_failed) {                           \
            g_passed++;                                            \
            printf("PASS %s\n", #test);                            \
        } else {                                                   \
            printf("FAIL %s\n", #test);                            \
        }                                                          \
    } while (0)

#define CHECK(cond)                                                \
    do {                                                           \
        if (!(cond)) {                                             \
            g_failed++;                                            \
            fprintf(stderr, "  check failed: %s (%s:%d)\n",        \
                    #cond, __FILE__, __LINE__);                    \
        }                                                          \
    } while (0)

/* ---------- Cycle 2a: CRUD ---------- */

static void test_version_nonnull(void) {
    const char* v = reminders_version();
    CHECK(v != NULL);
    CHECK(strlen(v) > 0);
}

static void test_create_empty(void) {
    ReminderList* list = reminders_create();
    CHECK(list != NULL);
    CHECK(reminders_count(list) == 0);
    reminders_destroy(list);
}

static void test_add_increments_count(void) {
    ReminderList* list = reminders_create();
    reminder_id_t id = reminders_add(list, "buy milk", 1000);
    CHECK(id >= 1);
    CHECK(reminders_count(list) == 1);
    reminders_destroy(list);
}

static void test_add_returns_distinct_ids(void) {
    ReminderList* list = reminders_create();
    reminder_id_t a = reminders_add(list, "one", 10);
    reminder_id_t b = reminders_add(list, "two", 20);
    CHECK(a != b);
    CHECK(reminders_count(list) == 2);
    reminders_destroy(list);
}

static void test_add_null_text_fails(void) {
    ReminderList* list = reminders_create();
    reminder_id_t id = reminders_add(list, NULL, 100);
    CHECK(id == 0);
    CHECK(reminders_count(list) == 0);
    reminders_destroy(list);
}

static void test_remove_existing(void) {
    ReminderList* list = reminders_create();
    reminder_id_t id = reminders_add(list, "x", 100);
    int ok = reminders_remove(list, id);
    CHECK(ok == 1);
    CHECK(reminders_count(list) == 0);
    reminders_destroy(list);
}

static void test_remove_missing(void) {
    ReminderList* list = reminders_create();
    int ok = reminders_remove(list, 9999);
    CHECK(ok == 0);
    reminders_destroy(list);
}

static void test_remove_then_remove_again(void) {
    ReminderList* list = reminders_create();
    reminder_id_t id = reminders_add(list, "x", 100);
    CHECK(reminders_remove(list, id) == 1);
    CHECK(reminders_remove(list, id) == 0);
    reminders_destroy(list);
}

/* ---------- Cycle 2b: Time logic ---------- */

static void test_peek_no_reminders(void) {
    ReminderList* list = reminders_create();
    reminder_id_t out_id = 0;
    const char* out_text = NULL;
    int found = reminders_peek_due(list, 1000, &out_id, &out_text);
    CHECK(found == 0);
    reminders_destroy(list);
}

static void test_peek_before_due(void) {
    ReminderList* list = reminders_create();
    reminders_add(list, "future", 1000);
    reminder_id_t out_id = 0;
    const char* out_text = NULL;
    int found = reminders_peek_due(list, 500, &out_id, &out_text);
    CHECK(found == 0);
    reminders_destroy(list);
}

static void test_peek_at_due(void) {
    ReminderList* list = reminders_create();
    reminder_id_t id = reminders_add(list, "now", 1000);
    reminder_id_t out_id = 0;
    const char* out_text = NULL;
    int found = reminders_peek_due(list, 1000, &out_id, &out_text);
    CHECK(found == 1);
    CHECK(out_id == id);
    CHECK(out_text != NULL && strcmp(out_text, "now") == 0);
    reminders_destroy(list);
}

static void test_peek_does_not_mutate(void) {
    ReminderList* list = reminders_create();
    reminders_add(list, "x", 100);
    reminder_id_t out_id = 0;
    const char* out_text = NULL;
    reminders_peek_due(list, 200, &out_id, &out_text);
    reminders_peek_due(list, 200, &out_id, &out_text);
    CHECK(reminders_count(list) == 1);
    reminders_destroy(list);
}

static void test_peek_earliest_due_first(void) {
    ReminderList* list = reminders_create();
    reminders_add(list, "later", 200);   /* due_at = 200 */
    reminder_id_t earlier = reminders_add(list, "earlier", 100);
    reminder_id_t out_id = 0;
    const char* out_text = NULL;
    int found = reminders_peek_due(list, 1000, &out_id, &out_text);
    CHECK(found == 1);
    CHECK(out_id == earlier);
    CHECK(strcmp(out_text, "earlier") == 0);
    reminders_destroy(list);
}

static void test_pop_due_removes(void) {
    ReminderList* list = reminders_create();
    reminder_id_t id = reminders_add(list, "ping", 100);
    reminder_id_t out_id = 0;
    char* out_text = NULL;
    int ok = reminders_pop_due(list, 200, &out_id, &out_text);
    CHECK(ok == 1);
    CHECK(out_id == id);
    CHECK(out_text != NULL && strcmp(out_text, "ping") == 0);
    CHECK(reminders_count(list) == 0);
    free(out_text);
    reminders_destroy(list);
}

static void test_pop_due_none_when_empty(void) {
    ReminderList* list = reminders_create();
    reminder_id_t out_id = 0;
    char* out_text = NULL;
    int ok = reminders_pop_due(list, 1000, &out_id, &out_text);
    CHECK(ok == 0);
    CHECK(out_text == NULL);
    reminders_destroy(list);
}

/* ---------- Cycle 2c: Indexed accessor ---------- */

static void test_get_out_of_range(void) {
    ReminderList* list = reminders_create();
    reminder_id_t id = 0;
    const char* text = NULL;
    int64_t due = 0;
    CHECK(reminders_get(list, 0, &id, &text, &due) == 0);
    reminders_add(list, "x", 100);
    CHECK(reminders_get(list, 1, &id, &text, &due) == 0);
    reminders_destroy(list);
}

static void test_get_returns_fields(void) {
    ReminderList* list = reminders_create();
    reminder_id_t added = reminders_add(list, "hello", 1234);
    reminder_id_t id = 0;
    const char* text = NULL;
    int64_t due = 0;
    int ok = reminders_get(list, 0, &id, &text, &due);
    CHECK(ok == 1);
    CHECK(id == added);
    CHECK(text != NULL && strcmp(text, "hello") == 0);
    CHECK(due == 1234);
    reminders_destroy(list);
}

static void test_get_null_outs_ok(void) {
    ReminderList* list = reminders_create();
    reminders_add(list, "x", 1);
    /* All outs NULL should still return 1 if index is in range. */
    CHECK(reminders_get(list, 0, NULL, NULL, NULL) == 1);
    reminders_destroy(list);
}

static void test_get_iterates_all(void) {
    ReminderList* list = reminders_create();
    reminders_add(list, "a", 10);
    reminders_add(list, "b", 20);
    reminders_add(list, "c", 30);
    int seen_a = 0, seen_b = 0, seen_c = 0;
    for (size_t i = 0; i < reminders_count(list); i++) {
        const char* text = NULL;
        CHECK(reminders_get(list, i, NULL, &text, NULL) == 1);
        if (strcmp(text, "a") == 0) seen_a++;
        if (strcmp(text, "b") == 0) seen_b++;
        if (strcmp(text, "c") == 0) seen_c++;
    }
    CHECK(seen_a == 1 && seen_b == 1 && seen_c == 1);
    reminders_destroy(list);
}

static void test_capacity_reached(void) {
    ReminderList* list = reminders_create();
    for (int i = 0; i < LIBREMINDERS_CAPACITY; i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "r%d", i);
        reminder_id_t id = reminders_add(list, buf, 1000 + i);
        CHECK(id >= 1);
    }
    CHECK(reminders_count(list) == LIBREMINDERS_CAPACITY);
    /* One more should fail */
    reminder_id_t overflow = reminders_add(list, "overflow", 9999);
    CHECK(overflow == 0);
    CHECK(reminders_count(list) == LIBREMINDERS_CAPACITY);
    reminders_destroy(list);
}

int main(void) {
    /* Cycle 2a */
    RUN(test_version_nonnull);
    RUN(test_create_empty);
    RUN(test_add_increments_count);
    RUN(test_add_returns_distinct_ids);
    RUN(test_add_null_text_fails);
    RUN(test_remove_existing);
    RUN(test_remove_missing);
    RUN(test_remove_then_remove_again);
    /* Cycle 2b */
    RUN(test_peek_no_reminders);
    RUN(test_peek_before_due);
    RUN(test_peek_at_due);
    RUN(test_peek_does_not_mutate);
    RUN(test_peek_earliest_due_first);
    RUN(test_pop_due_removes);
    RUN(test_pop_due_none_when_empty);
    /* Cycle 2c */
    RUN(test_get_out_of_range);
    RUN(test_get_returns_fields);
    RUN(test_get_null_outs_ok);
    RUN(test_get_iterates_all);
    RUN(test_capacity_reached);

    printf("\n=== %d passed, %d failed ===\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
