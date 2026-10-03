# Titanfall 2 VR mod fix — auto installer

This branch carries the Linux fix for the Titanfall 2 VR mod, and nothing else.

- `titanfall2-linux-fix/install.sh` — self-contained installer: it detects Steam, the game, the Proton prefix and Proton itself from Steam's own files, copies the launcher and desktop entries, adds the multiplayer compile fix, and applies the binary patches. `--check`, `--no-patch`, `--no-mp-fix` and `--uninstall` are supported.
- `titanfall2-linux-fix/launcher/` — the `tf2vr` launcher, the `tf2vr-detect.sh` it needs at runtime, and both binary patchers.
- `titanfall2-linux-fix/desktop/`, `titanfall2-linux-fix/icon/` — the app menu entries and the icon.
- `titanfall2-linux-fix/northstar-mod/` — the multiplayer compile fix companion mod.
- `titanfall2-linux-fix/tests/test-detect.sh` — 59 checks covering detection, the installer's paths, the launcher's exit reporting, and the installed build.

```sh
cd titanfall2-linux-fix && ./install.sh
```

Setup, how the patch works and how to report a problem are documented on
[`main`](https://github.com/polar421/Titanfall-2-VR-linux-fix), which also
holds the upstream CircuitLord installer. The community request list is on
[`requested-community-features`](https://github.com/polar421/Titanfall-2-VR-linux-fix/tree/requested-community-features).
