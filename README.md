# RightKeyGesture

RightKeyGesture is a small native macOS utility for Apple Silicon Macs. It lives in the menu bar, listens for right-button mouse gestures, and sends the configured keyboard shortcuts.

## Why This Exists

The original `WGestures.app` works well on older Intel Macs, but it is not reliable on Apple Silicon Macs. I like WGestures a lot and bought a license serial number for it; this project exists because I still want that style of right-button gesture workflow on my Apple Silicon Macs.

This project recreates the parts I use most:

- hold right mouse button and draw a gesture
- hold right mouse button and press another mouse button
- trigger keyboard shortcuts from those gestures
- import existing WGestures gesture settings where possible

## Relationship To WGestures

This is an independent Swift/AppKit implementation.

- It does not include, copy, decompile, or derive from WGestures source code.
- It reads the user's local WGestures JSON settings only for migration.
- It is not affiliated with YingDev or the original WGestures project.
- The author likes WGestures and has purchased a software serial number.
- The goal is compatibility with a personal workflow on Apple Silicon, not a full reimplementation of every WGestures feature.

## Install

Download or build `RightKeyGesture.app`, then move it to `/Applications`.

On first launch, enable both permissions:

- System Settings -> Privacy & Security -> Accessibility -> `RightKeyGesture`
- System Settings -> Privacy & Security -> Input Monitoring -> `RightKeyGesture`
- System Settings -> Privacy & Security -> Automation -> allow `RightKeyGesture` to control `System Events`

Quit and reopen the app after granting permissions. The menu bar item shows:

- `RKG`: listener is running
- `RKG!`: listener failed, usually because permissions are missing or stale

If it shows `RKG!`, open the menu and choose `Restart Listener` after fixing permissions.

The bundled Left/Right/Top/Bottom shortcuts target Magnet. Magnet registers these as global system hotkeys, and it does not reliably respond to direct `CGEvent` keyboard synthesis. RightKeyGesture therefore sends those specific actions through macOS `System Events`, which may trigger an Automation permission prompt the first time you use one.

## Default Gestures

The bundled default config is the current migrated personal config used on the development Mac. Hold the right mouse button, draw the gesture, then release:

| Gesture | Shortcut |
| --- | --- |
| Left | `Control + Option + LeftArrow` |
| Right | `Control + Option + RightArrow` |
| Top | `Control + Option + UpArrow` |
| Bottom | `Control + Option + DownArrow` |
| Left-up diagonal | `Command + M` |
| Left-down diagonal | `Command + Shift + 2` |
| Right-up diagonal | `Command + Control + Shift + 4` |
| Right-down diagonal | `Option + Control + M` |

Mouse-button chords:

| Chord | Shortcut |
| --- | --- |
| Right + Left | `Command + Q` |

## Import WGestures Settings

If the old WGestures config exists at:

```text
~/Library/Application Support/com.yingdev.wgestures/2.3.3/gestures.json
```

run:

```sh
node Scripts/import-wgestures.js
```

The imported config is written to:

```text
~/Library/Application Support/RightKeyGesture/gestures.json
```

Existing configs are backed up automatically before import.

## Customize Gestures

Edit:

```text
~/Library/Application Support/RightKeyGesture/gestures.json
```

Then choose `Reload Config` from the menu bar item.

Example:

```json
{
  "gestures": {
    "L": {
      "name": "Left",
      "keys": [{ "keyCode": 123, "modifiers": ["control", "option"] }]
    }
  },
  "mouseButtons": {
    "R+Left": {
      "name": "Quit App",
      "keys": [{ "keyCode": 12, "modifiers": ["command"] }]
    }
  },
  "templates": []
}
```

`templates` stores migrated WGestures point paths. It lets the app distinguish diagonal or custom drawn gestures that cannot be represented by plain `L/R/U/D` strings.

## Build

Requirements:

- macOS 14 or newer
- Xcode command line tools or Xcode
- Swift 6

Build the app:

```sh
make app
```

Install locally:

```sh
make install
```

Create a zip package for another Mac:

```sh
make package
```

The package is written to:

```text
dist/RightKeyGesture-macOS-arm64.zip
```

## Notes

The app is ad-hoc signed for local use. On another Mac, macOS may require opening it from Finder once and confirming the security prompt. If permissions look enabled but gestures do nothing, remove the app from Accessibility and Input Monitoring, add `/Applications/RightKeyGesture.app` again, then restart the app.
