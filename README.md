# Titanfall 2 VR mod fix — auto installer

This branch carries the Linux fix for the Titanfall 2 VR mod, and nothing else.

- `titanfall2-linux-fix/install.sh` — self-contained installer: it detects Steam, the game, the Proton prefix and Proton itself from Steam's own files, refuses an unwritable game folder by naming the path and the operating system's reason, copies the launcher and desktop entries, adds the multiplayer compile fix, and applies the binary patches. `--check`, `--no-patch`, `--no-mp-fix` and `--uninstall` are supported.
- `titanfall2-linux-fix/tf2vr-update` — updates the mod itself: reads the published manifest, compares it with `TF2VR/release.json`, downloads the package and checks its sha256, rebuilds the game-derived assets with `asset_patcher.exe` under Proton, and only then copies into `TF2VR`. It stages everything first, so a failure before the copy leaves the installation untouched. `--check`, `--dry-run`, `--beta`, `--force`.
- `titanfall2-linux-fix/launcher/` — the `tf2vr` launcher, the `tf2vr-detect.sh` it needs at runtime (Steam and Proton detection plus the filesystem probes both scripts share), and both binary patchers.
- `titanfall2-linux-fix/desktop/`, `titanfall2-linux-fix/icon/` — the app menu entries and the icon.
- `titanfall2-linux-fix/northstar-mod/` — the multiplayer compile fix companion mod.
- `titanfall2-linux-fix/tests/test-detect.sh` — 86 checks covering detection, the filesystem probes, the installer's paths, the updater's arguments and version comparison, the launcher's exit reporting, and the installed build.

```sh
cd titanfall2-linux-fix && ./install.sh      # install
cd titanfall2-linux-fix && ./tf2vr-update    # update the VR mod when the manifest has something newer
```

Setup, how the patch works and how to report a problem are documented on
[`main`](https://github.com/polar421/Titanfall-2-VR-linux-fix), which also
holds the upstream CircuitLord installer. The community request list is on
[`requested-community-features`](https://github.com/polar421/test/tree/requested-community-features).
