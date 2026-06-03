# logos-reminder-module

A local sticky reminder mini-app for Logos basecamp. V1 single-device:
type reminder text, pick a date and time from a calendar/tumbler picker,
Save, and a **native OS notification** fires when the time arrives
(plus an in-app popup if basecamp is in foreground).

Two modules:

- **`reminders`** (core) — wraps a small C library (`libreminders`) that
  owns the reminder list. A `QTimer` polls every second; when a reminder
  is due, the plugin emits a `reminderDue` event.
- **`reminders_ui_qml`** (QML UI) — text input, `MonthGrid`-based calendar
  date picker, dual-`Tumbler` time picker (24-hour), pending-list with
  live relative countdowns, in-app modal popup on `reminderDue`, and
  native OS notifications via `Qt.labs.platform.SystemTrayIcon` so
  reminders surface on top of whichever app you're using, not just
  inside basecamp.

Same `core` + `ui_qml` split as the tic-tac-toe example. Delivery / peer
broadcast is intentionally **not** in V1.

## Compatibility

Built and verified against:

- **basecamp v0.1.2** (the GA release on the
  [releases page](https://github.com/logos-co/logos-basecamp/releases))
- **`logos-module-builder` tag `tutorial-v2`** for both modules

Earlier `logos-module-builder` tags (`tutorial-v1`, `0.1.2-RC1`) crash on
load against basecamp v0.1.2 because of SDK ABI mismatches in the
`PluginInterface` vtable layout. Use `tutorial-v2`.

## Gotchas hit while building this (in order)

In rough order of how painful they were to debug. None are documented
in the official tutorial as of writing; capturing them here for the
next person.

1. **`nix flake update` after every `flake.nix` change.** Editing the
   `logos-module-builder.url` ref in `flake.nix` does *nothing* on its
   own — the pinned commit lives in `flake.lock`. Without an explicit
   `nix flake update`, you can swap tags and rebuild all day and you'll
   still get the old SDK. This is the single thing that cost me the
   most time.
2. **Nix flakes only stage *git-tracked* files into the build sandbox.**
   Untracked files (e.g. a freshly-dropped `.wav` or a new `.qml`
   component) silently vanish from the `.lgx` with no warning. Always
   `git add` new resources before `nix build`.
3. **`view: "Main.qml"` collapses the bundle to a single file.** The
   `mkLogosQmlModule` builder only copies the *view directory*
   recursively when `view` points at a subdirectory (e.g.
   `qml/Main.qml`). With `view: "Main.qml"`, viewDir is `"."` and the
   builder falls through to a single-file copy — every other resource
   in your project root is silently dropped. Layout your project as
   `qml/Main.qml` + `qml/extras…` and everything Just Works.
4. **`Q_INVOKABLE` numeric params must be `int`, not `qint64`.** The
   Logos IPC bridge marshals JS numbers as `QVariant(int, ...)` and
   Qt's meta system does not auto-promote `int → qlonglong`. A slot
   declared with `qint64` fails to dispatch with `QMetaObject::invokeMethod:
   No such method...` Switching to `int` is the fix. Epoch seconds fit
   in int32 until 2038, which is fine for a demo.
5. **`Q_INVOKABLE` returning `QVariantList` arrives as a JSON-encoded
   string in QML.** Signal payloads emitted via `eventResponse(QString,
   QVariantList)` come through as native JS arrays. The asymmetry is
   surprising — your QML consumer needs `JSON.parse` for method
   returns but not for signal payloads.
6. **`QtMultimedia` is not shipped in basecamp v0.1.2.** There is no
   way to play audio in pure QML on this build (`SoundEffect`,
   `MediaPlayer`, and friends all live in `QtMultimedia`). This repo
   keeps a `ChimePlayer.qml` + `pop.wav` scaffold loaded via a `Loader`
   so it'll start working the day basecamp ships `QtMultimedia`. In
   the meantime, use `Qt.labs.platform.SystemTrayIcon.showMessage()`
   for OS-level notifications — much better UX than sound anyway.
7. **macOS `Dialog` body renders white.** Default white text on white
   background is invisible. Use dark text colors in the dialog
   `contentItem`.
8. **Overriding `Dialog`'s `contentItem` breaks `standardButtons`
   auto-close.** Clicking OK fires `accepted` but doesn't call
   `close()`. Wire `onAccepted: close()` and `onRejected: close()`
   explicitly.

Popup visibility (the originally-flagged "risky assumption") is
**verified working** — the in-app `Dialog` does pop modal-style on top
of the reminders tab, and the OS notification fires regardless of which
app has focus.

## Project layout

```
logos-reminder-module/
├── reminders/                 # core module (C++ plugin + C library)
│   ├── lib/
│   │   ├── libreminders.h     # public C API
│   │   └── libreminders.c     # storage + time logic
│   ├── src/
│   │   ├── reminders_interface.h
│   │   ├── reminders_plugin.h
│   │   └── reminders_plugin.cpp
│   ├── tests/
│   │   └── test_libreminders.c
│   ├── CMakeLists.txt
│   ├── metadata.json
│   └── flake.nix
└── reminders-ui-qml/          # QML UI plugin
    ├── icons/
    │   └── reminders.png      # 64×64 menu-bar / module-list icon
    ├── qml/                   # view directory (must be a subdir, not ".")
    │   ├── Main.qml           # date+time pickers, pending list, OS notifs
    │   ├── ChimePlayer.qml    # forward-compat audio (no-op on v0.1.2)
    │   └── sounds/
    │       └── pop.wav        # bundled but unplayable until QtMultimedia ships
    ├── metadata.json          # view: "qml/Main.qml"  ← critical
    └── flake.nix
```

## Run the C library tests

The C library is independently testable without nix or Qt — useful for
quick iteration on storage logic.

```bash
cd reminders
cc -std=c11 -Wall -Wextra -Werror -Ilib \
   lib/libreminders.c tests/test_libreminders.c \
   -o tests/test_libreminders
./tests/test_libreminders
```

Expected: `=== 20 passed, 0 failed ===`, exit 0.

## Build the modules (nix)

Requires [Nix](https://nixos.org/download.html) with flakes enabled.

```bash
# Core module — builds the .lgx archive
cd reminders
nix flake update          # important after any flake.nix change
nix build .#lgx-portable
# → result/logos-reminders-module-lib.lgx

# UI module — depends on the sibling reminders flake
cd ../reminders-ui-qml
nix flake update
nix build .#lgx-portable
# → result/logos-reminders_ui_qml-module.lgx
```

## Install into basecamp (manual)

The `.lgx` files produced above are gzipped tar archives. basecamp
expects each module as an **extracted directory** under its user-data
folder (per-user installs *shadow* the bundled ones), with the
`variants/<platform>/` subdir flattened to the module root plus a
`variant` marker file.

On macOS the user-data path is:

```
~/Library/Application Support/Logos/LogosBasecamp/{modules,plugins}/
```

The bash sequence to install one `.lgx`:

```bash
LGX=path/to/result/logos-reminders-module-lib.lgx
NAME=reminders                    # for the UI use reminders_ui_qml
KIND=modules                      # core → modules, ui_qml → plugins
DEST="$HOME/Library/Application Support/Logos/LogosBasecamp/$KIND/$NAME"

TMP=$(mktemp -d)
tar -xzf "$LGX" -C "$TMP"
mkdir -p "$DEST"
cp "$TMP/manifest.json" "$DEST/"
cp -R "$TMP/variants/darwin-arm64/"* "$DEST/"
printf "darwin-arm64" > "$DEST/variant"
rm -rf "$TMP"
```

Then quit and relaunch basecamp; the new modules appear in the
in-app Package Manager and can be loaded from there.

`logos-scaffold` (`lgs basecamp install`) also works, but only from
inside a scaffolded project root — this repo isn't one.

## API (core module)

| Method | Args | Returns | Notes |
|---|---|---|---|
| `addReminder` | `text: string, dueAtEpochSec: int` | `int id` | `int` (not `qint64`) — the Logos IPC bridge doesn't auto-promote JS numbers to `qlonglong`. Epoch seconds fit in `int32` until 2038. |
| `removeReminder` | `id: int` | `bool` | true if found + removed |
| `listReminders` | — | `QVariantList` | The bridge JSON-encodes this for transport; the UI parses with `JSON.parse`. Each entry: `{id, text, dueAt}`. |
| `count` | — | `int` | pending reminders |
| `libVersion` | — | string | libreminders version |

Events emitted:

| Event | Payload | When |
|---|---|---|
| `reminderDue` | `[id: int, text: string]` | A reminder's `dueAt <= now`; the plugin pops + emits in `onTick`. Signal payloads come through as native JS arrays (no parsing needed). |

## V2 sketch (not built)

- **Delivery broadcast** of new reminders on a content topic
  (`/reminders/1/events/proto`) using the same logos-delivery-module
  pattern as tictactoe multiplayer. Receiving peers schedule locally.
- **JSON-file persistence** in the module data dir — survive basecamp
  restart.
- **Sound chime** — once basecamp ships `QtMultimedia`, the existing
  `ChimePlayer.qml` scaffold will start working without code changes.
  Until then, OS notifications are the audible signal (they ride
  whatever notification sound macOS is configured for).
- **Snooze / recurrence** — not yet.
- **Click-to-focus** on the OS notification: wire `SystemTrayIcon.
  onMessageClicked` to bring basecamp's window forward.

## License

Same dual MIT / Apache-2.0 as the surrounding Logos ecosystem.
