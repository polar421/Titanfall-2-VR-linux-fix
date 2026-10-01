# Titanfall 2 VR — Linux / Proton Fork

This is my fork of [CircuitLordVRModInstaller](https://github.com/CircuitLord/CircuitLordVRModInstaller), focused on getting Titanfall 2 VR working on Linux through Proton.

I originally started this fork to fix the problems I was running into while setting up Titanfall 2 VR on Linux. After working through the compatibility issues, I was able to get the game running in VR and complete the campaign.

## What this fork is for

The main goal of this fork is to improve the Linux/Proton experience for Titanfall 2 VR, including both single-player and multiplayer.

Current focus:

- Linux / Proton compatibility
- OpenXR and WiVRn support
- Titanfall 2 VR
- Northstar
- Single-player VR
- Multiplayer VR
- Proton/Wine compatibility fixes

## Project status

This setup has been tested through actual gameplay rather than by just launching the game — the full campaign has been played through in VR.

### Done and tested

| What | Verified how |
| --- | --- |
| Campaign / single-player VR | Full Titanfall 2 campaign completed in VR on this setup |
| `tf2vr` launch path | Starts Proton, WiVRn and EA Desktop and drops into the game; 1832x1919 per eye, ~90 fps at the menu |
| `mmdevapi.dll` audio fix | Removes the audio-init `0xC0000409` fastfail and re-applies itself after a Proton update |
| `install.sh` | `--check`, a full install, and an `--uninstall` → reinstall round trip all verified |

### In progress or untested

| What | Status | Still missing |
| --- | --- | --- |
| Northstar multiplayer | **Untested** | `mp_lobby` loaded once in a VR session (2026-09-30 11:50) and then went straight back to the campaign — no match has ever been started |
| Frontier Defense | **Untested** | `_gamemode_fd.nut` ships with the mod and has never been launched |
| Private match / listen server | ***In Testing Phase** | the hosting flow itself has not been exercised |
| Official Respawn servers in VR | **In Testing Phase** | `tf2vr --vanilla` reaches the main menu; no session on an official server has been completed |
| Vanilla clients connecting to our server | **Not started** | needs `ns_auth_allow_insecure 1` on the server plus UDP 37015 forwarded; nobody has connected |
| H.264 memory recorder | **Known issue, unfixed** | a separate `0xC0000409` from `writer->SetInputMediaType` returning `E_NOTIMPL` under Proton — the `mmdevapi` patch does not address it |

**Bottom line:** single-player and the Linux launch path are done and tested. Multiplayer is still in progress — nothing in the second table should be treated as working until it has actually been tested.

I'm continuing to work on making the setup easier to reproduce and on getting multiplayer working reliably. This is an independent fork, so Linux-specific changes land here first.

## Linux setup

My current setup:

- **OS:** CachyOS
- **GPU:** NVIDIA RTX 3060 12GB
- **VR headset:** Meta Quest 3S
- **VR runtime:** WiVRn / OpenXR
- **Compatibility layer:** Proton

## Repository contents

Everything Linux-specific lives in [`titanfall2-linux-fix/`](titanfall2-linux-fix/):

| Path | Purpose |
| --- | --- |
| `install.sh` | Preflight checks, copies everything below into place, applies the mmdevapi fix |
| `launcher/tf2vr` | Launcher: starts Proton, checks WiVRn/Steam/EA, builds the launch arguments, optional `--vanilla` |
| `launcher/tf2vr-patch-mmdevapi` | Re-applies the Wine `mmdevapi.dll` fix after a Proton update replaces it |
| `desktop/tf2vr.desktop` | App menu entry (campaign) |
| `desktop/tf2vr-vanilla.desktop` | App menu entry (`tf2vr --vanilla`) |
| `icon/tf2vr.png` | Icon used by both entries |

Install it with:

```sh
cd titanfall2-linux-fix
./install.sh
```

`install.sh` is idempotent. It verifies Steam, Titanfall 2, Proton, the TF2VR mod and WiVRn before touching anything, then copies the launcher to `~/.local/bin`, fills in `@BIN@`/`@ICON@`/`@GAMEDIR@` in the `.desktop` templates with your own paths, installs the icon, and applies the mmdevapi fix. `--check` runs the preflight only and changes nothing, `--no-patch` skips the Proton edit, `--uninstall` removes exactly what it installed.

WiVRn is registered as the OpenXR runtime through `~/.config/openxr/1/active_runtime.json`, which `install.sh` creates if it is missing and otherwise leaves alone. The launcher deliberately unsets `XR_RUNTIME_JSON` so that file is what OpenXR loads; it is a machine-level setting and is intentionally not tracked in this repo.

**No file in the game directory is modified.** The installed `TF2VR/` tree stays byte-for-byte identical to the upstream mod package — checked with SHA-256 against `Titanfall2VR-1.0.7.zip`, all 84 files matching. `xr_probe.exe` and `Titanfall2VR.dll` are therefore the stock shipped binaries, not rebuilt ones, and are deliberately not committed here.

## Linux compatibility fix

One of the main problems I ran into was a crash caused by the VR mod's audio handling under Wine/Proton.

I found that patching Proton's `mmdevapi.dll` fixes the issue and allows the VR mod to continue running.

The patcher in this fork checks the DLL before modifying it and creates a backup of the original file.

### How the patch works

Under Proton, the mod's `ActivateAudioInterfaceAsync(L"VAD\\Process_Loopback", ...)` comes back with `0x80070002`, and Wine fastfails the process with `0xC0000409` shortly after the main menu. `tf2vr-patch-mmdevapi` retargets a single `je` in `mmdevapi.dll` (`0x369e`, `0f8471ffffff` → `0f843efdffff`) so that failure takes the non-fatal path instead. It is signature-guarded, idempotent, keeps a `.orig-*` backup, and only touches Proton builds whose Wine matches that signature.

`tf2vr` runs it automatically before every launch. Set `TF2VR_NO_PATCH=1` to run against an unmodified Proton instead.

## Multiplayer

Multiplayer is the main thing this fork still has to get right — see [Project status](#project-status) for exactly what has and has not been tested.

The goal is to make it possible to:

- Launch Titanfall 2 VR multiplayer through Proton
- Use Northstar multiplayer
- Connect to multiplayer servers
- Play multiplayer normally in VR

### How multiplayer could be run

*None of the options below has been tested yet — they are the plan, not verified instructions. See [Project status](#project-status).*

Northstar ships inside the mod package, so `Northstar.Client`, `Northstar.Custom` and `Northstar.CustomServers` are all enabled, Frontier Defense (`_gamemode_fd.nut`) is present, and the mod's UI override still registers `PrivateLobbyMenu`.

Upstream `TF2VR/tools/launch.json` points Northstar at a dead master server (`+ns_masterserver_hostname http://127.0.0.1:9` and `+ns_report_server_to_masterserver 0`), so the server browser is empty by design. `tf2vr` reproduces those arguments unless `--vanilla` is passed.

- **Offline private match / Frontier Defense** needs no master server. Use *Play → Private Match* in the lobby, or launch a map directly, e.g. `tf2vr +map mp_forwardbase_kodai +mp_gamemode fd`.
- **Playing with vanilla (unmodded) clients:** your server cannot appear on the master server vanilla players browse — that list is EA's closed Atlas backend. A vanilla client can instead direct-connect to your listen server (`connect <ip>:37015`) if the server sets `ns_auth_allow_insecure 1` and UDP 37015 is forwarded. Their stock `client.dll` is accepted because `host_skip_client_dll_crc` is already `1`.
- **`tf2vr --vanilla`** uses Northstar's Vanilla-Compatibility mode. Northstar stays loaded, so the VR plugin still loads, while the game talks to the official Respawn servers. Mods marked `!` must be disabled in the in-game Mods menu.

## Original project

This project is based on:

[CircuitLordVRModInstaller](https://github.com/CircuitLord/CircuitLordVRModInstaller)

All credit for the original Titanfall 2 VR installer and mod work goes to the original project and its contributors.

## Contributing

Linux users who want to help test different Proton versions, hardware, or multiplayer setups are welcome to share their results.

When reporting an issue, please include your:

- Linux distribution
- Proton version
- GPU / driver version
- VR headset
- OpenXR runtime
- Relevant logs

## Disclaimer

This is an unofficial fork and is not affiliated with Respawn Entertainment or Electronic Arts.

Titanfall 2 and its related trademarks belong to their respective owners.
