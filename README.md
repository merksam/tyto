# Tyto

![Tyto: press the shortcut, drag a region, mark it up, paste it](.github/media/demo.gif)

Fast region screenshots with markup, for macOS. Press ⌘⇧9 and the screen freezes right away –
so a menu, a tooltip, an animation stays exactly where it was while you pick what to keep.
Drag a region, or click a window to grab just that one. Mark it up, press Return, paste it
wherever you need.

Named after the barn owl, *Tyto alba*. It also sounds like "отуто", Ukrainian for "right
here", which is roughly what you mean when you drag a box around something.

## No network, at all

Tyto contains no networking code. Nothing is uploaded, no analytics, no account, no server.
That claim is checkable rather than a promise – `grep -r URLSession Sources/` comes back
empty, and the app is sandboxed with only four entitlements: the sandbox itself, read/write
to Pictures, user-selected files for the save panel, and app-scoped bookmarks so a chosen
save folder survives a restart.

## Building

Requires macOS 26 or later. Build with Xcode 27.

```bash
swift test              # TytoCore: geometry, the selection state machine, the renderer
scripts/dev.sh          # build Tyto.app, sign it, relaunch, wait for the debug socket
scripts/e2e-phase2.sh   # drive the real app on a second display; PNGs land in out/
scripts/gen-project.sh  # generate Tyto.xcodeproj from project.yml (for archiving)
```

`scripts/build-app.sh` signs with a Developer ID certificate if one is in the keychain, and
ad-hoc otherwise. macOS ties the Screen Recording grant to the signature, so an ad-hoc build
has to be re-approved on every rebuild.

## Layout

- `Sources/TytoCore` – pure model: geometry, the selection state machine, the annotation
  document, undo history, and the renderer. No AppKit, and this is what the tests cover.
- `Sources/Tyto` – the app: capture, the overlay windows, the toolbar, settings.
- `Sources/tytoctl` – a debug CLI that drives a running debug build over a unix socket, so
  the AppKit layer can be exercised end to end rather than mocked. Compiled out of Release.

One renderer draws both the live overlay and the exported image, so what you see on screen is
what lands on the clipboard, by construction rather than by vigilance.

## A published app, not a project looking for contributors

Tyto is a finished thing I use every day, released free on the Mac App Store. The source is
here so the claim above is checkable, not because the repo needs maintainers. Bug reports are
welcome in [Issues](https://github.com/merksam/tyto/issues); pull requests may sit for a
while, so please open an issue before writing one.

If it saves you time, there is a Sponsor button at the top of this page, and
[Ko-fi](https://ko-fi.com/merksam) if you prefer. Entirely optional – nothing in the app asks.

## Licence

MIT. See [LICENSE](LICENSE).
