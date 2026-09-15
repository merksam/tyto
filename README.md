# Owl

Fast region screenshot + annotation for macOS 27. See `PLAN.md`.

```bash
swift test                    # OwlCore unit tests
scripts/dev.sh                # build Owl.app, sign, relaunch, ping the debug socket
scripts/e2e-phase2.sh         # drive the real app on the secondary display, PNGs in out/
.build/debug/owlctl --help
.build/debug/owlctl container  # sandbox container; the debug socket lives in <container>/tmp
```

Every build is sandboxed (`Resources/Owl.entitlements`); see `docs/mac-app-store.md`.

Default hotkey: ⌘⇧9. Esc cancels, Enter or ⌘C copies the selection to the clipboard.
