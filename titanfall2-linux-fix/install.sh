#!/usr/bin/env bash
# Install, check, or remove the Titanfall 2 VR Linux launcher.
#
#   ./install.sh              install (preflight, copy files, patch mmdevapi)
#   ./install.sh --check      run the preflight checks only, change nothing
#   ./install.sh --no-patch   install without touching Proton's mmdevapi.dll
#   ./install.sh --uninstall  remove everything this script installed
#
# Nothing here ever writes inside the game directory.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

STEAM="${STEAM_DIR:-$HOME/.local/share/Steam}"
GAME="$STEAM/steamapps/common/Titanfall2"
PROTON="$STEAM/steamapps/common/Proton - Experimental/proton"
PREFIX="$STEAM/steamapps/compatdata/1237970"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
ICON="$HOME/.local/share/icons/hicolor/256x256/apps/tf2vr.png"
OPENXR="$HOME/.config/openxr/1/active_runtime.json"
WIVRN_LIB="/usr/lib/wivrn/libopenxr_wivrn.so"

MODE=install
PATCH=1
for a in "$@"; do
  case "$a" in
    --check)    MODE=check ;;
    --uninstall) MODE=uninstall ;;
    --no-patch) PATCH=0 ;;
    -h|--help)
      sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "install.sh: unknown option '$a' (try --help)" >&2; exit 2 ;;
  esac
done

fails=0
warns=0
ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# ---------------------------------------------------------------- preflight --
preflight() {
  echo "Preflight:"

  [ -d "$STEAM" ] \
    && ok "Steam library: $STEAM" \
    || fail "Steam library not found at $STEAM (set STEAM_DIR=... if it lives elsewhere)"

  [ -d "$GAME" ] \
    && ok "Titanfall 2: $GAME" \
    || fail "Titanfall 2 not found under $STEAM/steamapps/common"

  [ -x "$PROTON" ] \
    && ok "Proton: Proton - Experimental" \
    || fail "Proton - Experimental missing (Steam -> Library -> right-click the game -> Properties -> Compatibility)"

  [ -d "$PREFIX" ] \
    && ok "Wine prefix: compatdata/1237970" \
    || warn "No Wine prefix yet - it is created on the first Proton run"

  [ -f "$GAME/TF2VR/tools/crash_monitor.exe" ] \
    && ok "TF2VR mod installed (crash_monitor.exe present)" \
    || fail "TF2VR mod not installed - run CircuitLordVRModInstaller first"

  if [ -f "$WIVRN_LIB" ] || command -v wivrn-server >/dev/null 2>&1; then
    ok "WiVRn runtime present"
  else
    fail "WiVRn not found ($WIVRN_LIB) - install WiVRn, this setup targets it"
  fi

  if [ -f "$OPENXR" ]; then
    if grep -qi wivrn "$OPENXR"; then
      ok "OpenXR active runtime selects WiVRn"
    else
      warn "OpenXR active runtime exists but does not mention WiVRn: $OPENXR"
    fi
  else
    warn "No OpenXR active runtime at $OPENXR (created for you on install)"
  fi

  command -v python3 >/dev/null 2>&1 \
    && ok "python3 available (for tf2vr-patch-mmdevapi)" \
    || warn "python3 missing - the mmdevapi patch cannot be applied"

  case ":$PATH:" in
    *":$BIN:"*) ok "$BIN is on PATH" ;;
    *)          warn "$BIN is not on PATH - add it:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.profile" ;;
  esac
}

# ------------------------------------------------------------------ install --
install_files() {
  echo
  echo "Installing:"

  install -Dm755 "$HERE/launcher/tf2vr"                 "$BIN/tf2vr"
  install -Dm755 "$HERE/launcher/tf2vr-patch-mmdevapi" "$BIN/tf2vr-patch-mmdevapi"
  ok "$BIN/tf2vr, tf2vr-patch-mmdevapi"

  install -d -m755 "$APPS"
  local f out
  for f in "$HERE"/desktop/*.desktop; do
    out="$APPS/$(basename "$f")"
    sed -e "s|@BIN@|$BIN|g" -e "s|@ICON@|$ICON|g" "$f" > "$out"
    if [ -d "$GAME" ]; then
      sed -i "s|^Path=@GAMEDIR@\$|Path=$GAME|" "$out"
    else
      sed -i "/^Path=@GAMEDIR@\$/d" "$out"
    fi
    chmod 644 "$out"
    ok "$(basename "$out") -> $APPS"
  done

  install -Dm644 "$HERE/icon/tf2vr.png" "$ICON"
  ok "icon -> $ICON"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS" 2>/dev/null || true
    ok "desktop database refreshed"
  fi

  if [ ! -f "$OPENXR" ] && [ -f "$WIVRN_LIB" ]; then
    install -d -m755 "$(dirname "$OPENXR")"
    cat > "$OPENXR" <<JSON
{
    "file_format_version": "1.0.0",
    "runtime": {
        "name": "WiVRn",
        "library_path": "$WIVRN_LIB",
        "MND_libmonado_path": "/usr/lib/wivrn/libmonado_wivrn.so"
    }
}
JSON
    ok "registered WiVRn as the OpenXR runtime ($OPENXR)"
  fi

  if [ "$PATCH" = 1 ]; then
    if command -v python3 >/dev/null 2>&1; then
      echo
      echo "mmdevapi.dll:"
      # Only newly patched files plus the summary; the per-Proton "skipped"
      # lines are just noise on a machine with many Proton builds installed.
      if out=$("$BIN/tf2vr-patch-mmdevapi" 2>&1); then
        printf '%s\n' "$out" \
          | grep -E '^  patched:|patched of [0-9]+ checked' \
          || printf '%s\n' "$out"
      else
        printf '%s\n' "$out"
        warn "the patcher reported a problem (re-run tf2vr-patch-mmdevapi for details)"
      fi
    fi
  else
    echo
    echo "Skipping the mmdevapi patch (--no-patch); the launcher will abort with 0xC0000409 unless it is applied."
  fi
}

uninstall_files() {
  echo
  echo "Uninstalling:"
  local f
  for f in "$BIN/tf2vr" "$BIN/tf2vr-patch-mmdevapi" \
           "$APPS/tf2vr.desktop" "$APPS/tf2vr-vanilla.desktop" "$ICON"; do
    if [ -e "$f" ]; then rm -f "$f"; ok "removed $f"; else ok "not present: $f"; fi
  done
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
  echo
  echo "Left alone: the game directory, your Proton install, and $OPENXR."
}

# -------------------------------------------------------------------- main ---
preflight

case "$MODE" in
  check) ;;
  install)
    if [ "$fails" -gt 0 ]; then
      echo
      echo "$fails required check(s) failed - fixing them first is recommended, but installing anyway."
    fi
    install_files
    ;;
  uninstall)
    uninstall_files
    ;;
esac

echo
if [ "$fails" -gt 0 ]; then
  echo "Done with $fails failure(s) and $warns warning(s)."
  exit 1
fi
echo "Done, no failures ($warns warning(s))."
[ "$MODE" = install ] && echo "Start the game with:  tf2vr      (or the 'Titanfall 2 VR' launcher entry)"
exit 0
