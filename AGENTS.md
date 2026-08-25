# Repository Guidelines

## Project Structure & Module Organization

OmaTips is an Omarchy 4 shell plugin written in QML and JavaScript. Plugin entry points live at the repository root: `Service.qml` owns scheduling, persistence, and notifications; `BarWidget.qml` renders the bar item; and `Panel.qml` provides the study interface. Pure scheduling logic belongs in `TipModel.js`. Lesson content is stored in `tips.json`, while plugin identity and entry-point metadata live in `manifest.json`.

Tests are under `tests/`: `tst_tipmodel.qml` covers scheduling behavior with Qt Test, and `validate_content.sh` checks lesson schema, uniqueness, and the action allowlist. Keep documentation in `README.md` synchronized with user-visible behavior.

## Build, Test, and Development Commands

This plugin has no compilation step. Run these commands from the repository root:

```sh
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell Service.qml BarWidget.qml Panel.qml
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= \
  /usr/lib/qt6/bin/qmltestrunner -input tests
bash tests/validate_content.sh
```

The first command validates the manifest, `qmllint` checks QML, the Qt runner executes unit tests, and the shell script validates all 234 tips. Installed local plugins hot-reload; use `omarchy-shell shell rescanPlugins` when a manual refresh is needed.

## Coding Style & Naming Conventions

Use two-space indentation in QML and JavaScript. Name QML components in `PascalCase.qml`, JavaScript functions and properties in `camelCase`, and lesson IDs as stable lowercase kebab-case strings. Keep scheduling calculations pure in `TipModel.js`; isolate filesystem, process, notification, and shell integration in `Service.qml`. Prefer explicit property types and guard clauses. Run `qmllint` before submitting changes.

## Testing Guidelines

Add Qt Test functions named `test_<behavior>` for every scheduling or state transition change. Use deterministic timestamps rather than the current clock. Changes to `tips.json` must preserve exactly 234 unique entries and must pass `tests/validate_content.sh`. Test both successful behavior and boundary cases such as empty queues, corrupt state, and delayed reviews.

## Commit & Pull Request Guidelines

The repository has no established commit history yet. Follow Conventional Commits, for example `feat(panel): add keyboard grading` or `fix(notifications): handle default action`. Keep commits focused and avoid mixing unrelated changes.

Pull requests should explain the user-visible result, list verification commands, and note any state-schema or manifest changes. Include a screenshot for panel or bar layout changes. Link relevant issues when available.

## Security & State

Actions in lessons must remain allowlisted; do not introduce arbitrary shell execution. The plugin must not require network access or elevated privileges. Preserve existing study state unless a migration is explicitly required.
