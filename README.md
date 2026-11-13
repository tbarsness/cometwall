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

## Auto-login

Click the key icon on a tile to save that pane's password. It is stored in your
login Keychain (as "CometWall login (host)") and never written to `panes.json`.
When the page shows a password field, CometWall asks for Touch ID once per
launch, then fills the field and presses the login button. It only fills on the
pane's own host, and it stops after two failed tries in two minutes. If you cancel
Touch ID, use Layout › Unlock Saved Logins to try again.

Sign the app with your own development certificate so the Keychain recognizes
it across rebuilds:

```sh
xcodebuild -scheme CometWall -derivedDataPath build \
  CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=<your team id> CODE_SIGN_STYLE=Manual
```

## Certificates

KVMs and other LAN appliances usually ship self-signed certificates. CometWall
accepts a host's certificate only when its pane sets `trustSelfSigned`, or after
you click **Trust this certificate** on that tile's error screen (remembered
across launches). Every other host gets the normal system check. To make that
possible for named hosts, the app sets `NSAllowsArbitraryLoadsInWebContent`, so
only add hosts you control.

## License

MIT. See [LICENSE](LICENSE).
