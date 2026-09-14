# Owl

Fast region screenshot + annotation for macOS 27. See `PLAN.md`.

```bash
swift test                    # OwlCore unit tests
scripts/dev.sh                # build Owl.app, sign, relaunch, ping the debug socket
scripts/e2e-phase2.sh         # drive the real app on the secondary display, PNGs in out/
.build/debug/owlctl --help
```

Default hotkey: ⌘⇧9. Esc cancels, Enter or ⌘C copies the selection to the clipboard.
