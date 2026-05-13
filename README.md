# langedaemon

`langedaemon` is a small macOS background tool for deterministic language switching.

It listens for dedicated function-key presses from your keyboard firmware and
selects exact macOS input sources by ID.

## What it does

- Captures `F20` and `F19` key-down events.
- Switches directly to exact input source IDs using `TISSelectInputSource`.
- Does not cycle through sources.
- Suppresses handled key events by default so they do not leak into apps.

## How it works

- Your keyboard (ZMK) sends `F20` and `F19`.
- `langedaemon` captures those events with a macOS event tap.
- It calls `TISSelectInputSource` with fixed IDs:
  - `F20` -> `org.sil.ukelele.keyboardlayout.jinnyswe.jinnyswe`
  - `F19` -> `org.sil.ukelele.keyboardlayout.unsavedukeleledocument.jinnyrus`
- Result: deterministic switching to target layout, no “next/previous source”
  cycling.

## Build

```bash
cd /Users/evgenyn/orodruin/zmk/langedaemon
swift build -c release
```

Binary path:

```bash
.build/release/langedaemon
```

## List available source IDs

```bash
.build/release/langedaemon --list-sources
```

Use IDs from this output for exact deterministic mapping.

## Run

```bash
.build/release/langedaemon \
  --left-source org.sil.ukelele.keyboardlayout.jinnyswe.jinnyswe \
  --right-source org.sil.ukelele.keyboardlayout.unsavedukeleledocument.jinnyrus
```

Optional:

- `--pass-through` to not suppress `F20/F19` events.

## Permissions

Grant the daemon app/terminal:

- Accessibility
- Input Monitoring

Without these permissions event-tap creation or event capture may fail.

## Daily use (automatic start)

Do not run the daemon manually in a terminal for daily work. Run it as a
`launchd` user agent.

1. Install the LaunchAgent plist:
```bash
mkdir -p ~/Library/LaunchAgents
cp /Users/evgenyn/orodruin/zmk/langedaemon/launchd/com.evgenyn.langedaemon.plist \
  ~/Library/LaunchAgents/
```

2. Load and start the agent:
```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.evgenyn.langedaemon.plist
launchctl enable gui/$(id -u)/com.evgenyn.langedaemon
launchctl kickstart -k gui/$(id -u)/com.evgenyn.langedaemon
```

3. Verify status:
```bash
launchctl print gui/$(id -u)/com.evgenyn.langedaemon | rg "state|pid|last exit"
```

4. Check logs:
```bash
tail -f /tmp/langedaemon.out.log /tmp/langedaemon.err.log
```

## Updating after changes

After rebuilding `langedaemon` or changing plist arguments, reload:

```bash
launchctl bootout gui/$(id -u)/com.evgenyn.langedaemon
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.evgenyn.langedaemon.plist
launchctl kickstart -k gui/$(id -u)/com.evgenyn.langedaemon
```

## Stopping the daemon

```bash
launchctl bootout gui/$(id -u)/com.evgenyn.langedaemon
```
