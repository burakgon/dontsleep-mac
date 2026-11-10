# Changelog

## 1.0.1

- DontSleep starts afresh after the welcome, and no longer opens its menu by itself. The welcome
  window took about 20 MB that the app then kept for as long as it ran; now it is back at about
  13 MB a moment after you have chosen an icon.
- An update that arrives while the welcome is on screen waits until it is closed.

## 1.0.0

The first release.

- Keeps your Mac awake from the menu bar: until you turn it off, or for 15 minutes to 8 hours.
- Allow Display Sleep lets the screen turn off while the Mac itself stays awake.
- A right-click on the icon switches DontSleep on or off without opening the menu.
- Six icons for the menu bar to choose from. Each is one shape that lights up while your Mac is
  kept awake, so it never moves when the state changes.
- `dontsleep`, a command line tool for scripts and AI agents: `on`, `off`, `toggle`, `status`
  and `display-sleep`, with `--for 2h` and `--json`. It starts the app when it has to.
- Updates itself in the background. Every release is signed with Developer ID, notarized by
  Apple and signed again with an update key.
- Idle, it uses about 13 MB of memory and no CPU: it holds one power assertion and waits.
