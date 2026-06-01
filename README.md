# logos-reminder-module

A local sticky reminder mini-app for Logos basecamp. V1 single-device:
type reminder text, pick a duration ("in N minutes"), Save, and a popup
fires when the time arrives.

Two modules:

- **`reminders`** (core) — wraps a small C library (`libreminders`) that
  owns the reminder list. A `QTimer` polls every second; when a reminder
  is due, the plugin emits a `reminderDue` event.
- **`reminders_ui_qml`** (QML UI) — minimal frontend: text input, minutes
  spinbox, save button, pending-list with relative countdowns, and a
  modal `Dialog` that opens on `reminderDue`.

Same `core` + `ui_qml` split as the tic-tac-toe example. Delivery / peer
broadcast is intentionally **not** in V1.

## Compatibility

Built and verified against:

- **basecamp v0.1.2** (the GA release on the
  [releases page](https://github.com/logos-co/logos-basecamp/releases))
- **`logos-module-builder` tag `tutorial-v2`** for both modules

Earlier `logos-module-builder` tags (`tutorial-v1`, `0.1.2-RC1`) crash on
load against basecamp v0.1.2 because of SDK ABI mismatches in the
`PluginInterface` vtable layout. Use `tutorial-v2` and run
`nix flake update` after any change to `flake.nix` — without the update,
the `flake.lock` keeps the old SDK pin and the new tag does nothing.

## Status

V1 is a Logos demo, not a daily-driver tool. Known V1 limitations,
listed honestly:

- **No persistence.** Reminders live in memory; basecamp restart loses them.
- **Capped at 64 pending reminders** (`LIBREMINDERS_CAPACITY`).
- **Basecamp must be open** for a reminder to fire.
- **No icon** — `metadata.json` points at `reminders-ui-qml/icons/reminders.png`
  but ships empty. Drop in any 64×64 PNG.

Popup visibility (the previously-flagged "risky assumption") is
**verified working** — the `Dialog` does pop modal-style on top of the
reminders tab when a reminder fires, even when another tab is focused.

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
    ├── icons/                 # (drop in reminders.png)
    ├── Main.qml
    ├── metadata.json
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
- **JSON-file persistence** in the module data dir.
- **OS notifications** (depending on smoke-test outcome).
- **Snooze / recurrence** — not yet.

## License

Same dual MIT / Apache-2.0 as the surrounding Logos ecosystem.
