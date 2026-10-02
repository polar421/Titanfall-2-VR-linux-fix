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

### Check board

✅ done and tested · 🟡 **in testing phase** · ❌ not working / not started

#### Done

| | What | Verified how |
| --- | --- | --- |
| ✅ | Campaign / single-player VR | Full Titanfall 2 campaign completed in VR on this setup |
| ✅ | `tf2vr` launch path | Starts Proton, WiVRn and EA Desktop and drops into the game; 1832x1919 per eye at 72 Hz |
| ✅ | `mmdevapi.dll` audio fix | Removes the audio-init `0xC0000409` fastfail and re-applies itself after a Proton update |
| ✅ | `install.sh` | `--check`, a full install, and an `--uninstall` → reinstall round trip all verified |
| ✅ | Multiplayer script compile fix | The `Encountered CLIENT script compilation error` on `mp_*` is gone; the Multiplayer menu loads |
| ✅ | Plugin fastfail patches | The `unrecognized pilot hand model` and `seated pilot model changed` fastfails are nop'd; a private match now loads |

#### In testing

| | What | Status |
| --- | --- | --- |
| 🟡 | **Private match / listen server** | **In testing phase.** The lobby, `mp_lobby` and a hosted private match on `mp_forwardbase_kodai` load, and the holster / pickup / grenade glue now lives in the companion mod — but no match has been played through yet, so nothing here is claimed as working |
| 🟡 | Northstar multiplayer | Same session as above; the fly-in and titan-entry crashes are patched but not retested in a real match |
| 🟡 | Official Respawn servers in VR | `tf2vr --vanilla` reaches the main menu; no session on an official server has been completed |

#### Not done

| | What | Why |
| --- | --- | --- |
| ❌ | Voice lines / grunt chatter | No pilot or grunt dialogue is audible in game; not investigated yet |
| ❌ | Frontier Defense | `_gamemode_fd.nut` ships with the mod and has never been launched |
| ❌ | Weapon damage in multiplayer | Pilot weapons have not been confirmed to deal damage |
| ❌ | Vanilla clients connecting to our server | Needs `ns_auth_allow_insecure 1` on the server plus UDP 37015 forwarded; nobody has connected |
| ❌ | H.264 memory recorder | A separate `0xC0000409` from `writer->SetInputMediaType` returning `E_NOTIMPL` under Proton — the `mmdevapi` patch does not address it |

**Bottom line:** single-player and the Linux launch path are done and tested. Multiplayer is in the testing phase — treat only the ✅ rows as working.

I'm continuing to work on making the setup easier to reproduce and on getting multiplayer working reliably. This is an independent fork, so Linux-specific changes land here first.

### Planned features

Nothing below is implemented yet.

| | Requested |
| --- | --- |
| ❌ | HUD always visible instead of fading out |
| ❌ | Physical turning while piloting a titan |
| ❌ | Titan vertical look sensitivity (currently lower than horizontal, and the look-up cutoff is hard to predict) |
| ❌ | First-person titan entry in multiplayer |
| ❌ | Automatically move the *Interact* trigger to the free hand when the other hand is holding a gun |
| ❌ | Aim camera-locked titan abilities (Scorch's incendiary launcher wall, Tone's sonar pulse, …) where the player is actually looking |
| ❌ | Toggle to turn off VR reloads and VR grenade throwing — always auto-reload as a pilot, and throw ordnance with the normal trajectory aimed by hand |
| ❌ | Update the packaged mod to a newer upstream release |

## Linux setup

My current setup:

- **OS:** CachyOS
- **GPU:** NVIDIA RTX 3060 12GB
- **VR headset:** Meta Quest 3
- **VR runtime:** WiVRn / OpenXR
- **Refresh rate:** 72 Hz
- **Compatibility layer:** Proton

## Repository contents

Everything Linux-specific lives in [`titanfall2-linux-fix/`](titanfall2-linux-fix/):

| Path | Purpose |
| --- | --- |
| `install.sh` | Preflight checks, copies everything below into place, applies the mmdevapi and VR plugin fixes |
| `launcher/tf2vr` | Launcher: starts Proton, checks WiVRn/Steam/EA, builds the launch arguments, optional `--vanilla` |
| `launcher/tf2vr-patch-mmdevapi` | Re-applies the Wine `mmdevapi.dll` fix after a Proton update replaces it |
| `launcher/tf2vr-patch-titanfall2vr` | Re-applies the VR plugin fastfail fixes after a mod reinstall replaces the DLL |
| `desktop/tf2vr.desktop` | App menu entry (campaign) |
| `desktop/tf2vr-vanilla.desktop` | App menu entry (`tf2vr --vanilla`) |
| `icon/tf2vr.png` | Icon used by both entries |
| `northstar-mod/Titanfall2VR.MPFix/` | Companion Northstar mod that makes the Multiplayer menu load and drives holster / pickup / grenade / titan-pose glue in MP |

Install it with:

```sh
cd titanfall2-linux-fix
./install.sh
```

`install.sh` is idempotent. It verifies Steam, Titanfall 2, Proton, the TF2VR mod and WiVRn before touching anything, then copies the launcher to `~/.local/bin`, fills in `@BIN@`/`@ICON@`/`@GAMEDIR@` in the `.desktop` templates with your own paths, installs the icon, adds the multiplayer companion mod described below, and applies the two binary fixes — the Proton `mmdevapi.dll` edit and the VR plugin fastfail edits. `--check` runs the preflight only and changes nothing, `--no-patch` skips both binary fixes, `--no-mp-fix` skips the game-side folder, `--uninstall` removes everything it installed and restores the original `Titanfall2VR.dll`.

WiVRn is registered as the OpenXR runtime through `~/.config/openxr/1/active_runtime.json`, which `install.sh` creates if it is missing and otherwise leaves alone. The launcher deliberately unsets `XR_RUNTIME_JSON` so that file is what OpenXR loads; it is a machine-level setting and is intentionally not tracked in this repo.

**The only change inside the game directory is one new folder and three nop'd bytes.** `install.sh` adds `TF2VR/mods/Titanfall2VR.MPFix/` and turns three fastfail sites in `TF2VR/plugins/Titanfall2VR.dll` into NOPs, keeping the original as `Titanfall2VR.dll.orig-tf2vr` (restored by `--uninstall`). Everything else in the installed `TF2VR/` tree stays byte-for-byte identical to the upstream mod package — checked with SHA-256 against `Titanfall2VR-1.0.7.zip`, all 84 files matching before either fix is applied. `xr_probe.exe` and `Titanfall2VR.dll` are therefore the stock shipped binaries, not rebuilt ones, and are deliberately not committed here; this repo ships only the patcher that edits them.

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

### Multiplayer compile fix

Clicking *Multiplayer* used to immediately fail with `Encountered CLIENT script compilation error, see console for details.` The compiler stops at the first undefined name, so it surfaced one at a time:

```
Undefined variable "TF2VR_PickupKind"       sh_codecallbacks.gnut line [97]
Undefined variable "TF2VR_IsPickupTarget"   sh_highlight.gnut line [1505]
Undefined variable "TF2VR_VortexControlled" weapons/_vortex.nut line [1003]
```

Ten helpers are involved. Titanfall2VR.Cockpit declares them only in its SP-gated files (`tf2vr_pickups.gnut`, `tf2vr_titan.gnut`, `tf2vr_interactions.gnut`, `tf2vr_prompts.nut`), while twelve other Cockpit scripts compile ungated on `SERVER || CLIENT` and call back into them:

| Declared by `Titanfall2VR.MPFix` | Referenced from |
| --- | --- |
| `TF2VR_PickupKind` | `_utility.gnut:3038`, `sh_codecallbacks.gnut:97`, `sh_highlight.gnut:975` |
| `TF2VR_IsPickupTarget` | `sh_highlight.gnut:1505` |
| `TF2VR_VortexControlled` / `VortexOrigin` / `VortexDirection` / `PlaceVortex` | `weapons/_vortex.nut`, `weapons/mp_titanweapon_heat_shield.nut` |
| `TF2VR_TitanViewDot` / `TitanViewTrace` | `weapons/mp_titancore_salvo_core.nut` |
| `TF2VR_EmptyHands` | `client/rui/cl_weapon_status.gnut` |
| `TF2VR_TitanKeyHint` | `client/rui/cl_weapon_status.gnut`, `earn_meter/cl_earn_meter.gnut` |

So on `mp_*` levels none of them is declared and the VM fails to compile. This is an upstream mod bug, not a Linux or Proton problem — it also happens with `-vanilla`.

`install.sh` therefore adds `TF2VR/mods/Titanfall2VR.MPFix/`, a two-file companion mod that declares all of them for MP levels only. `"RunOn": "MP"` mirrors upstream's `"RunOn": "SP"`, so the two can never both be loaded: this file is off on SP maps and the real definitions are off on MP maps.

The bodies are **not** no-ops. `tf2vr_mp_stubs.gnut` is a port of the SP implementation onto engine calls that exist in MP:

- `TF2VR_PickupKind` / `TF2VR_IsPickupTarget` / `TF2VR_EmptyHands` / `TF2VR_TitanKeyHint` return what a caller would have used without the mod (`-1`, `false`, the untouched hint string).
- `TF2VR_UpdateTitanPose` and the four `TF2VR_Vortex*` / `TF2VR_TitanView*` helpers read head pose from the shared pose struct, so titan aim works again — these were the reason titan view went dead.
- `TF2VR_UpdatePickups` writes `tf2vr_holster_mask` (which the plugin reads to decide what to put in your hand) and selects pickup targets into `tf2vr_pickup_*`.
- `TF2VR_PredictGrenade` actually calls `weapon.FireWeaponGrenade(...)`, so ordnance can be thrown.
- `TF2VR_MPInit` registers the `tf2vr_draw` / `tf2vr_grenade` / `tf2vr_pickup` / `tf2vr_cancel_grenade` / `tf2vr_store_grenade` client commands the plugin sends, and the weapon create/destroy callbacks.

`scripts.rson` documents `MP` as a *map-level* flag rather than a VM one, so a `"RunOn": "MP"` file is also compiled by the menu's UI script VM; nothing in the UI VM calls these names, so the whole file sits inside `#if SERVER || CLIENT` and compiles to nothing there.

`TF2VR_UpdateEyeCase`, `TF2VR_UpdateArcToolPose`, `TF2VR_UpdateBodyMovement`, `TF2VR_UpdateEmbark`, `TF2VR_PrepareMemory` and `TF2VR_CheckDynamicMemory` stay empty — they are campaign-only glue (SERE eye case, arc tool, embark camera, memory hooks) with no MP equivalent, and `CHARGE_TOOL` does not exist outside SP.

### Native plugin pose lookup

Fixing the compiler gets you into the menu; `Titanfall2VR.dll` then hit a second, unrelated failure. The plugin resolves a set of script callbacks by name and fastfails with `0xC0000409` when a lookup misses:

```
Titanfall2VR: pose script function unavailable
script_error context=client function=TF2VR_UpdateEyeCase operation=lookup ... the index doesn't exist
```

Nine of the fifty-one `TF2VR_*` names in the DLL live only in SP-gated files, so they were absent on `mp_*`:

| Supplied by the companion mod | Originally defined in |
| --- | --- |
| `TF2VR_UpdateEyeCase` | `tf2vr_eye_case.gnut` |
| `TF2VR_UpdatePickups` | `tf2vr_pickups.gnut` |
| `TF2VR_UpdateTitanPose` | `tf2vr_titan.gnut` |
| `TF2VR_UpdateArcToolPose` | `tf2vr_arc_tool.gnut` |
| `TF2VR_UpdateBodyMovement` | `tf2vr_body.nut` |
| `TF2VR_UpdateEmbark` | `tf2vr_embark_camera.nut` |
| `TF2VR_PredictGrenade` | `tf2vr_interactions.gnut` |
| `TF2VR_PrepareMemory`, `TF2VR_CheckDynamicMemory` | `tf2vr_memories.nut` |

Rendering, head tracking and hand tracking stay on the native side, so the campaign-only ones are safe as empty bodies; the signatures are copied verbatim because the plugin calls them with fixed argument lists. `install.sh` reports the folder as `22` declarations in total.

**Not yet verified in game** — see [Project status](#project-status).

### Plugin fastfail patches

Fixing the pose lookups gets a private match to load; the dropship fly-in on `mp_forwardbase_kodai` then produced the next native failure:

```
Titanfall2VR: unrecognized pilot hand model
```

The plugin derives its hand IK parameters from the first-person arm model *name* and only knows three of them — `pov_mlt_hero_jack_rifleman.mdl`, `pov_mlt_hero_jack.mdl` and `pov_mlt_hero_jack_st.mdl`, all campaign Jack Cooper. The list is compiled into the binary with no config file, and every multiplayer pilot uses a different model. That error path is a `lea rcx,[rip+…]` that loads the address of the message string, a `call`, then `mov ecx,7 ; int 0x29`.

Tolerating that one exposed a second, shared failure: after hand-model resolution the plugin runs a single invariant-report helper for every `… changed` / `… failed` check, and that helper fastfails too.

```
Titanfall2VR: seated pilot model changed
```

Unlike the two hand-model sites, this helper prints its message and then returns — its fastfail sits immediately before the function epilogue, so NOP-ing `int 0x29` turns it into "warn and continue". On `mp_forwardbase_kodai` it fires when the MP pilot body is swapped for the seated titan model during embark.

`tf2vr-patch-titanfall2vr` therefore patches **three** sites: the two hand-model fastfalls (falling through to the same rig table it uses for `pov_mlt_hero_jack.mdl`) and the shared invariant helper's fastfail. It is signature-guarded (message string → its RIP-relative reference → the exact following bytes), idempotent, writes the `Titanfall2VR.dll.orig-tf2vr` backup only if it does not already exist, and never touches the hundreds of other `int 0x29` fastfails in the binary — a different plugin build is skipped rather than corrupted. `install.sh --uninstall` restores the original, and `tf2vr` re-applies it before every launch in case a VR mod reinstall replaces the DLL.

**Not yet verified in game** — the three patches are applied, but no match has been played since.

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
