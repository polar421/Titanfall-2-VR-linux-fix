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

## Linux setup

My current setup:

- **OS:** CachyOS
- **GPU:** NVIDIA RTX 3060 12GB
- **VR headset:** Meta Quest 3S
- **VR runtime:** WiVRn / OpenXR
- **Compatibility layer:** Proton

## Repository contents

Everything Linux-specific lives in [`linux/`](linux/) and mirrors its installed path: `linux/.local/...` is relative to `$HOME`, `linux/config/...` is relative to `$HOME/.config`.

| File (relative to `$HOME`) | Purpose |
| --- | --- |
| `.local/bin/tf2vr` | Launcher: starts Proton, checks WiVRn/Steam/EA, builds the launch arguments, optional `--vanilla` |
| `.local/bin/tf2vr-patch-mmdevapi` | Re-applies the Wine `mmdevapi.dll` fix after a Proton update replaces it |
| `.local/share/applications/tf2vr.desktop` | App menu entry (campaign) |
| `.local/share/applications/tf2vr-vanilla.desktop` | App menu entry (`tf2vr --vanilla`) |
| `.local/share/icons/hicolor/256x256/apps/tf2vr.png` | Icon used by both entries |
| `.config/openxr/1/active_runtime.json` | Registers WiVRn as the OpenXR runtime; the launcher deliberately unsets `XR_RUNTIME_JSON` so this file is what OpenXR loads |

The two `.desktop` files hard-code `/home/polar/...` in `Exec=`, `TryExec=`, `Icon=` and `Path=`; edit those for a different user or machine.

**No file in the game directory is modified.** The installed `TF2VR/` tree stays byte-for-byte identical to the upstream mod package — checked with SHA-256 against `Titanfall2VR-1.0.7.zip`, all 84 files matching. `xr_probe.exe` and `Titanfall2VR.dll` are therefore the stock shipped binaries, not rebuilt ones, and are deliberately not committed here.

## Linux compatibility fix

One of the main problems I ran into was a crash caused by the VR mod's audio handling under Wine/Proton.

I found that patching Proton's `mmdevapi.dll` fixes the issue and allows the VR mod to continue running.

The patcher in this fork checks the DLL before modifying it and creates a backup of the original file.

### How the patch works

Under Proton, the mod's `ActivateAudioInterfaceAsync(L"VAD\\Process_Loopback", ...)` comes back with `0x80070002`, and Wine fastfails the process with `0xC0000409` shortly after the main menu. `tf2vr-patch-mmdevapi` retargets a single `je` in `mmdevapi.dll` (`0x369e`, `0f8471ffffff` → `0f843efdffff`) so that failure takes the non-fatal path instead. It is signature-guarded, idempotent, keeps a `.orig-*` backup, and only touches Proton builds whose Wine matches that signature.

`tf2vr` runs it automatically before every launch. Set `TF2VR_NO_PATCH=1` to run against an unmodified Proton instead.

## Multiplayer

Another major goal of this fork is getting **Titanfall 2 VR multiplayer working on Linux**.

The campaign is already working on my setup, and I'm currently working on the remaining multiplayer compatibility issues.

The goal is to make it possible to:

- Launch Titanfall 2 VR multiplayer through Proton
- Use Northstar multiplayer
- Connect to multiplayer servers
- Play multiplayer normally in VR

Multiplayer support is still being worked on, so this part of the project may require additional fixes and testing.

### What works today, and what doesn't

Northstar ships inside the mod package, so `Northstar.Client`, `Northstar.Custom` and `Northstar.CustomServers` are all enabled, Frontier Defense (`_gamemode_fd.nut`) is present, and the mod's UI override still registers `PrivateLobbyMenu`.

Upstream `TF2VR/tools/launch.json` points Northstar at a dead master server (`+ns_masterserver_hostname http://127.0.0.1:9` and `+ns_report_server_to_masterserver 0`), so the server browser is empty by design. `tf2vr` reproduces those arguments unless `--vanilla` is passed.

- **Offline private match / Frontier Defense** needs no master server. Use *Play → Private Match* in the lobby, or launch a map directly, e.g. `tf2vr +map mp_forwardbase_kodai +mp_gamemode fd`.
- **Playing with vanilla (unmodded) clients:** your server cannot appear on the master server vanilla players browse — that list is EA's closed Atlas backend. A vanilla client can instead direct-connect to your listen server (`connect <ip>:37015`) if the server sets `ns_auth_allow_insecure 1` and UDP 37015 is forwarded. Their stock `client.dll` is accepted because `host_skip_client_dll_crc` is already `1`.
- **`tf2vr --vanilla`** uses Northstar's Vanilla-Compatibility mode. Northstar stays loaded, so the VR plugin still loads, while the game talks to the official Respawn servers. Mods marked `!` must be disabled in the in-game Mods menu.

## Testing

This setup has been tested through actual gameplay rather than just launching the game.

I've completed the Titanfall 2 campaign in VR using this Linux/Proton setup.

### Precise test status

Tested:

- Campaign VR under Proton + WiVRn (1832x1919 per eye, ~90 fps at the menu).
- The `mmdevapi.dll` fix, which removes the audio-init `0xC0000409` fastfail.
- `tf2vr --vanilla` launching and loading.

Observed once in a VR session log (2026-09-30 11:50): `mp_lobby` loaded successfully, after which the session returned to the campaign.

**Not tested:** starting or finishing a private match or Frontier Defense round, joining an official Respawn server in VR, and vanilla clients connecting to a hosted server. Multiplayer is a work in progress — do not treat it as working yet. A separate `0xC0000409` originating from the campaign memory recorder's H.264 sink writer (`writer->SetInputMediaType` returning `E_NOTIMPL` under Proton) has been seen as well and is not fixed by the `mmdevapi.dll` patch.

## Project status

**Single-player:** Working

**Multiplayer:** In development

**Linux / Proton support:** Working on my setup

I'm continuing to work on making the setup easier to reproduce and getting multiplayer working reliably.

This is currently an independent fork, so Linux-specific changes are being developed here first.

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
