# Contributing

## Before testing changes, quit the installed app

The installed copy (`/Applications/MicReminder.app`) may already be running,
often launched at login. If you `swift run` or run `.build/debug/mic-reminder`
without quitting it first, you'll have two instances racing to switch your
default input device and reacting to each other's changes.

Quit it from its menu bar icon (or `killall MicReminder`) before running a
dev build.

## Running during development

```sh
swift build
.build/debug/mic-reminder   # run directly, without installing
```

Preferences are stored in `UserDefaults` under the `com.kubukoz.mic-reminder`
domain (or `mic-reminder` when run directly via `swift run`/`.build/debug`,
since that path has no bundle identifier). This means a dev build and the
installed app also don't share preferences.
