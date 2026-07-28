# mic-reminder

A macOS menu bar app that warns you when your active microphone isn't the one
you'd prefer, and offers a one-click switch.

Free and open-source (Apache 2.0). Covers a small subset of what
[AudioWrangler](https://audiowrangler.app/) does — automatic mic-priority
switching, with a warning-and-confirm popover instead of fully automatic
switching. Not affiliated with or endorsed by AudioWrangler; if you want a
more complete, polished tool, that's a good place to look.

## How it works

You rank your microphones by preference in a priority list (via Preferences).
The app listens for CoreAudio configuration changes (default input device
changed, devices plugged/unplugged) and, whenever the currently active input
isn't the highest-priority *connected* device from your list, shows a popover
near the menu bar icon with a button to switch to the better one.

Devices not in your priority list are treated as lowest priority — plugging
into some random unranked mic will still prompt you to switch to a ranked
device if one is connected. Devices you haven't ranked yet show up in a
separate "other known mics" list in Preferences; drag them into the priority
list to opt them in, drag priority entries back out to opt them out. Order
and list membership persist across disconnect/reconnect, matched by device
name.

## Build & install

```sh
./build_app.sh            # builds AppBundle/MicReminder.app
./build_app.sh --install  # also copies it to /Applications
```

Requires Swift/Xcode command line tools (macOS 13+).

## Development

```sh
swift build
.build/debug/mic-reminder   # run directly, without installing
```

Preferences are stored in `UserDefaults` under the `com.kubukoz.mic-reminder`
domain (or `mic-reminder` when run directly via `swift run`/`.build/debug`,
since that path has no bundle identifier).
