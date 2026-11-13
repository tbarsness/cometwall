# CometWall

A macOS app that shows several web interfaces at once, built for watching a
handful of GL.iNet Comet KVMs side by side.

- **Wall** (⌘1): every pane in a grid sized to the window. Expand a tile with its
  arrow button or by double-clicking its header; Esc returns to the grid.
- **Sidebar** (⌘2): a list on the left, one pane at a time on the right.
- Switching layouts never reloads a page, so live video streams and logins stay up.
- Logins persist across launches. Sign-in popups (OAuth/SSO) open in their own window.
- Optional auto-reload per pane.

## Build

Requires macOS 14+ and Xcode.

```sh
open CometWall.xcodeproj   # then Run
```

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen);
run `xcodegen generate` after changing it.

## Configure panes

Layout › Edit Panes… (⇧⌘,) opens `panes.json`. On first launch it holds two
example entries.

```json
[
  { "name": "Rack KVM", "url": "https://192.168.1.50/", "trustSelfSigned": true },
  { "name": "Status", "url": "https://status.example.com", "refreshSeconds": 60 }
]
```

| Field | Meaning |
|---|---|
| `name` | Tile title; must be unique |
| `url` | Start page |
| `refreshSeconds` | Reload every N seconds (optional) |
| `trustSelfSigned` | Accept any certificate this host presents (optional) |

Layout › Reload Pane List (⇧⌘R) applies changes without restarting.

## Certificates

KVMs and other LAN appliances usually ship self-signed certificates. CometWall
accepts a host's certificate only when its pane sets `trustSelfSigned`, or after
you click **Trust this certificate** on that tile's error screen (remembered
across launches). Every other host gets the normal system check. To make that
possible for named hosts, the app sets `NSAllowsArbitraryLoadsInWebContent`, so
only add hosts you control.
