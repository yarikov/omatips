# OmaTips

Master Omarchy keyboard shortcuts with native notifications and Anki-style
spaced repetition.

OmaTips is an Omarchy 4 shell plugin with 229 concise tips based on
the official [Omarchy hotkeys manual](https://omarchy.org/manual/hotkeys/).
The course covers desktop navigation, window management, applications,
capture tools, Tmux, Ghostty, the file manager, Neovim, quick emojis, and
XCompose completions.

Rather than presenting a long cheat sheet, OmaTips introduces shortcuts one at
a time and brings them back for review until they become muscle memory.

![OmaTips study panel](assets/screenshot.png)

## Install

Install and enable OmaTips from GitHub:

```sh
omarchy plugin add https://github.com/yarikov/omatips --enable
```

Plugins run as unsandboxed code inside `omarchy-shell`; review third-party
plugin code before enabling it.

## Use

- Click the lightbulb in the bar to open the current card.
- Grade it with `1` Again, `2` Hard, `3` Good, or `4` Easy.
- Press Escape to close the panel.
- Click the notification itself (or its **Study now** action) to open the same panel.

Due reviews always come before unseen cards. When no review is due, the next
new shortcut is available immediately—there is no calendar-day study gate.
The bar count includes only studied cards whose review time has arrived; an
available new card is shown as a lightbulb without a number.

OmaTips sends at most one study notification per local calendar day. When the
queue is not empty, it appears at the first active, unlocked moment between
08:00 and 16:00; notifications wait while the system is locked or idle. You can
still introduce any number of new cards manually through the lightbulb. The
notification is a short study reminder and does not reveal the next card.

## Scheduling

Each rating button previews the actual interval that will be assigned to the
current card. New cards begin with:

| Rating | Initial interval | Later behavior |
| --- | ---: | --- |
| **Again** | `1m` | Resets the successful-review streak and lowers ease |
| **Hard** | `10m` | Multiplies the current interval by `1.2` and lowers ease |
| **Good** | `1d` | Multiplies the current interval by the card's ease factor |
| **Easy** | `4d` | Multiplies by ease and an additional `1.3` bonus |

Ease starts at `2.5`. Successful reviews make intervals grow from the card's
current interval, while difficult or forgotten cards grow more slowly or
return to the initial steps.

Choosing **Easy** three reviews in a row completes the card permanently, so it
no longer appears in the study queue. Any other rating resets this streak.

Button labels stay compact as intervals grow: `m` is minutes, `h` is hours,
`d` is days, `mo` is 30-day months, and `y` is 365-day years. A trailing `+`
means the exact interval contains a smaller remainder—for example, `27d+`
may represent 27 days and several additional hours.

When every introduced card is scheduled for later, OmaTips stays out of sight
until the next review becomes due.

## Privacy and safety

The hotkey course is instructional data: studying a card does not execute its
shortcut or modify your bindings. OmaTips does not use the network, request
privileges, collect telemetry, or edit system configuration.

Course state is stored at:

```text
${XDG_STATE_HOME:-~/.local/state}/omarchy/omatips/state.json
```

The previous valid state is kept alongside it as `state.json.bak`. Before a new
state is committed, the current primary becomes the backup and the new file is
atomically moved into place. If the primary file cannot be read or is invalid
during startup, OmaTips restores the backup and preserves the bad primary as a
timestamped `state.json.corrupt.*` file. If neither copy is valid, storage is
disabled instead of overwriting evidence that may still be recoverable.

State files larger than 1 MiB are rejected without creating or overwriting
either state file. OmaTips disables study-state updates and reports the error
in the shell log so the oversized file can be inspected safely.

## Develop and verify

From the repository root:

```sh
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell Service.qml BarWidget.qml Panel.qml
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= /usr/lib/qt6/bin/qmltestrunner -input tests
bash tests/validate_content.sh
bash tests/test_state_io.sh
```

Changes under `~/.config/omarchy/plugins/` hot-reload. If needed, request a
manual rescan with `omarchy-shell shell rescanPlugins`.

## Remove

```sh
omarchy plugin remove yarikov.omatips --yes
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/omatips/state.json"
```

The first command removes the plugin. The second deletes all saved study
progress; omit it if you want a future reinstall to resume the schedule.

## License

MIT
