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

## Linux compatibility fix

One of the main problems I ran into was a crash caused by the VR mod's audio handling under Wine/Proton.

I found that patching Proton's `mmdevapi.dll` fixes the issue and allows the VR mod to continue running.

The patcher in this fork checks the DLL before modifying it and creates a backup of the original file.

## Multiplayer

Another major goal of this fork is getting **Titanfall 2 VR multiplayer working on Linux**.

The campaign is already working on my setup, and I'm currently working on the remaining multiplayer compatibility issues.

The goal is to make it possible to:

- Launch Titanfall 2 VR multiplayer through Proton
- Use Northstar multiplayer
- Connect to multiplayer servers
- Play multiplayer normally in VR

Multiplayer support is still being worked on, so this part of the project may require additional fixes and testing.

## Testing

This setup has been tested through actual gameplay rather than just launching the game.

I've completed the Titanfall 2 campaign in VR using this Linux/Proton setup.

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
