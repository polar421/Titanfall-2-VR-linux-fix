#!/usr/bin/env bash
# Install, check, or remove the Titanfall 2 VR Linux launcher.
#
# Usage:
#   ./install.sh               install (preflight, copy files, patch binaries)
#   ./install.sh --check       run the preflight checks only, change nothing
#   ./install.sh --no-patch    install without patching mmdevapi.dll or the VR plugin
#   ./install.sh --no-mp-fix   install without adding TF2VR/mods/Titanfall2VR.MPFix
#   ./install.sh --uninstall   remove everything this script installed
#
# Steam libraries, Titanfall 2 and its Proton prefix are detected
# automatically from Steam's own libraryfolders.vdf; nothing has to be
# hardcoded.  Overrides: STEAM_DIR (Steam root), TF2VR_GAME (game directory),
# TF2VR_PROTON (proton binary).  If detection fails you are asked for the
# game directory instead.
#
# Installs into $HOME. Inside the game directory it adds the Titanfall2VR.MPFix
# mod folder and patches the VR plugin: its fastfail sites and the cockpit HUD
# fade flag (*.orig-tf2vr backup).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# ---------------------------------------------------------- error reporting --
# Installed before anything else can fail. A failure in here is an installer
# problem, not a game crash: keep whatever the failing command already printed,
# say which command it was, point at the issue trackers and leave with a
# non-zero status. Nothing is uploaded and no issue is opened automatically.
report_installer_error() {
  local rc="$1"
  set +e
  trap - EXIT
  {
    echo
    echo "=============================================================="
    echo " Titanfall 2 VR Linux Fix - installer error"
    echo "=============================================================="
    echo
    echo "install.sh failed while running:"
    echo "  ${BASH_COMMAND:-unknown}"
    echo "Exit status: $rc"
    echo
    echo "The original output above is kept as it was. This is a problem with"
    echo "the installer itself, not a report that the game crashed."
    echo
    echo "Report it at:"
    echo "  https://github.com/polar421/Titanfall-2-VR-linux-fix/issues"
    echo "  https://github.com/Monkellie/tf2vr-linux/issues"
    echo
    echo "Please include your Linux distribution, kernel, GPU, Proton version,"
    echo "VR runtime, VR headset, the terminal output above and the output of"
    echo "    ./install.sh --check"
    echo "=============================================================="
  } >&2
}
# Driven from EXIT rather than ERR: bash never runs the ERR trap, so this is
# what reports a bootstrap failure. Expected, user-facing exits go through
# installer_exit() instead of a bare `exit`, so they keep their plain message
# and print no banner.
installer_exit() {
  INSTALLER_EXPECTED=1
  exit "$1"
}
trap 'rc=$?; trap - EXIT; if [ "$rc" -ne 0 ] && [ "${INSTALLER_EXPECTED:-0}" != 1 ]; then report_installer_error "$rc"; fi; exit "$rc"' EXIT

# Steam / Titanfall 2 / Proton path detection, inlined so this script is
# self-contained: it auto-detects the install with no second file to ship.
# The tf2vr launcher still needs the same detection at runtime and gets it
# from launcher/tf2vr-detect.sh - keep the two in step.
#
# Public functions:
#   find_steam_libraries          every configured Steam library root
#   validate_titanfall2_install   is this directory really Titanfall 2?
#   find_titanfall2_install       every Titanfall 2 installation found
#   pick_titanfall2_install       the one Steam itself keeps an appmanifest for
#   validate_proton_prefix        does this compatdata dir hold a wine prefix?
#   find_titanfall2_prefix        the compatdata/1237970 prefix for a game
#   find_proton                   the proton binary to launch with
#   tf2vr_library_of              <lib> from an install path
#
# Environment:
#   STEAM_DIR, STEAM  override the primary Steam root
#   TF2VR_PROTON      override the proton binary
#   TF2VR_APPID       Steam appid of Titanfall 2 (default 1237970)
#
# Everything below works with paths containing spaces and with Steam
# libraries living on other drives, which is what libraryfolders.vdf is for.

TF2VR_APPID="${TF2VR_APPID:-1237970}"

_tf2vr_unique() { awk 'NF && !seen[$0]++'; }

# Resolve symlinks so ~/.steam/root and ~/.local/share/Steam collapse into one
# library instead of looking like two separate installs.
_tf2vr_canon() {
  local p="$1" real
  real=$(readlink -f -- "$p" 2>/dev/null) || real=""
  if [ -n "$real" ]; then p="$real"; fi
  printf '%s\n' "$p"
}

# Lowercase alphanumeric only, so "Proton - Experimental" and the Steam tool
# name "proton_experimental" can be compared.
_tf2vr_norm() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'; }

# Steam roots that actually exist on this machine.
_tf2vr_steam_roots() {
  local -a candidates=()
  local r
  if [ -n "${STEAM_DIR:-}" ]; then candidates+=("$STEAM_DIR"); fi
  if [ -n "${STEAM:-}" ]; then candidates+=("$STEAM"); fi
  candidates+=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.steam/root"
    "$HOME/.steam"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
  )
  for r in "${candidates[@]}"; do
    if [ -n "$r" ] && [ -d "$r" ]; then printf '%s\n' "$r"; fi
  done
}

# Every absolute path a libraryfolders.vdf declares.  Handles both the current
# format ("path"  "/x") and the legacy one ("1"  "/x").
_tf2vr_parse_vdf_paths() {
  if [ ! -f "$1" ]; then return 0; fi
  awk '
    function unesc(s) { gsub(/\\+/, "\\", s); return s }
    function emit( i) {
      for (i = 1; i <= n; i++) {
        if (t[i] == "path" && i < n && t[i + 1] ~ /^\//) { print unesc(t[i + 1]) }
        else if (t[i] ~ /^[0-9]+$/ && i < n && t[i + 1] ~ /^\//) { print unesc(t[i + 1]) }
      }
      n = 0
    }
    {
      n = 0
      line = $0
      while (match(line, /"[^"]*"/)) {
        n++
        t[n] = substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
      emit()
    }
  ' "$1"
}

# All configured Steam libraries, primary root first, duplicates and
# non-libraries removed.  A directory only counts as a library when it carries
# a steamapps/ folder.
find_steam_libraries() {
  local root v p
  {
    _tf2vr_steam_roots
    while IFS= read -r root; do
      for v in "$root/steamapps/libraryfolders.vdf" "$root/config/libraryfolders.vdf"; do
        if [ -f "$v" ]; then _tf2vr_parse_vdf_paths "$v"; fi
      done
    done < <(_tf2vr_steam_roots)
  } | while IFS= read -r p; do
        if [ -d "$p/steamapps" ]; then _tf2vr_canon "$p"; fi
      done | _tf2vr_unique
}

# <lib> from "<lib>/steamapps/common/<name>"; empty when the path does not
# look like a Steam library layout.
tf2vr_library_of() {
  case "${1:-}" in
    */steamapps/common/*) printf '%s\n' "${1%%/steamapps/common/*}" ;;
    *) return 1 ;;
  esac
}

validate_titanfall2_install() {
  local dir="${1:-}"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then return 1; fi
  if [ ! -f "$dir/Titanfall2.exe" ]; then return 1; fi
  if [ ! -d "$dir/vpk" ]; then return 1; fi
  return 0
}

# One value from a Valve KeyValues .acf file:  _tf2vr_acf_field file key
_tf2vr_acf_field() {
  if [ ! -f "$1" ]; then return 0; fi
  awk -v key="$2" '
    {
      line = $0
      if (!match(line, /"[^"]*"/)) next
      if (substr(line, RSTART + 1, RLENGTH - 2) != key) next
      rest = substr(line, RSTART + RLENGTH)
      if (match(rest, /"[^"]*"/)) print substr(rest, RSTART + 1, RLENGTH - 2)
      exit
    }
  ' "$1"
}

# Every valid Titanfall 2 installation found across every configured library.
find_titanfall2_install() {
  local lib acf name dir
  while IFS= read -r lib; do
    name=""
    acf="$lib/steamapps/appmanifest_$TF2VR_APPID.acf"
    if [ -f "$acf" ]; then name=$(_tf2vr_acf_field "$acf" installdir); fi
    if [ -z "$name" ]; then name="Titanfall2"; fi
    dir="$lib/steamapps/common/$name"
    if validate_titanfall2_install "$dir"; then
      printf '%s\n' "$dir"
      continue
    fi
    if validate_titanfall2_install "$lib/steamapps/common/Titanfall2"; then
      printf '%s\n' "$lib/steamapps/common/Titanfall2"
    fi
  done < <(find_steam_libraries) | _tf2vr_unique
}

# The installation to use when more than one exists: Steam only keeps an
# appmanifest_1237970.acf in the library it currently installs into, so that
# copy wins.  Fails when there is no reliable way to choose, and the caller
# asks the user instead of guessing.
pick_titanfall2_install() {
  local installs install lib winner="" count=0
  installs=$(find_titanfall2_install)
  if [ -z "$installs" ]; then return 1; fi
  if [ "$(printf '%s\n' "$installs" | wc -l | tr -d ' ')" -eq 1 ]; then
    printf '%s\n' "$installs"
    return 0
  fi
  while IFS= read -r install; do
    if lib=$(tf2vr_library_of "$install") \
       && [ -f "$lib/steamapps/appmanifest_$TF2VR_APPID.acf" ]; then
      winner="$install"
      count=$((count + 1))
    fi
  done <<< "$installs"
  if [ "$count" -eq 1 ]; then
    printf '%s\n' "$winner"
    return 0
  fi
  return 1
}

validate_proton_prefix() {
  local prefix="${1:-}"
  if [ -z "$prefix" ] || [ ! -d "$prefix/pfx" ]; then return 1; fi
  if [ -f "$prefix/pfx/system.reg" ] || [ -d "$prefix/pfx/drive_c" ]; then return 0; fi
  return 1
}

# The compatdata directory for the given installation.  Steam keeps the prefix
# in the same library as the game, so derive it from the install path rather
# than assuming it lives on the primary drive.
find_titanfall2_prefix() {
  local install="${1:-}" root p
  case "$install" in
    */steamapps/common/*)
      root="${install%%/steamapps/common/*}"
      printf '%s\n' "$root/steamapps/compatdata/$TF2VR_APPID"
      return 0
      ;;
  esac
  while IFS= read -r p; do
    if validate_proton_prefix "$p/steamapps/compatdata/$TF2VR_APPID"; then
      printf '%s\n' "$p/steamapps/compatdata/$TF2VR_APPID"
      return 0
    fi
  done < <(find_steam_libraries)
  return 1
}

# The proton binary Steam is configured to use for Titanfall 2, then the
# historical default of this launcher, then anything else installed.
find_proton() {
  local -a tools=()
  local p dir name want

  if [ -n "${TF2VR_PROTON:-}" ] && [ -x "${TF2VR_PROTON:-}" ]; then
    printf '%s\n' "$TF2VR_PROTON"
    return 0
  fi

  local lib
  while IFS= read -r lib; do
    for p in "$lib/steamapps/common/"*/proton "$lib/compatibilitytools.d/"*/proton; do
      if [ -x "$p" ]; then tools+=("$p"); fi
    done
  done < <(find_steam_libraries)

  if [ "${#tools[@]}" -eq 0 ]; then return 1; fi

  want=$(_tf2vr_compat_tool_name)
  if [ -n "$want" ]; then
    name=$(_tf2vr_norm "$want")
    for p in "${tools[@]}"; do
      dir=$(basename "$(dirname "$p")")
      if [ "$(_tf2vr_norm "$dir")" = "$name" ]; then
        printf '%s\n' "$p"
        return 0
      fi
    done
  fi

  for p in "${tools[@]}"; do
    if [ "$(basename "$(dirname "$p")")" = "Proton - Experimental" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  printf '%s\n' "${tools[@]}" | sort | head -n 1
}

# The "name" Steam stores under CompatToolMapping for TF2VR_APPID, if any.
_tf2vr_compat_tool_name() {
  local root v name
  while IFS= read -r root; do
    v="$root/config/config.vdf"
    if [ -f "$v" ]; then
      name=$(_tf2vr_read_compat_tool "$v")
      if [ -n "$name" ]; then printf '%s\n' "$name"; return 0; fi
    fi
  done < <(_tf2vr_steam_roots)
  return 0
}

_tf2vr_read_compat_tool() {
  awk -v app="$TF2VR_APPID" '
    function braces(s, a, b) { a = gsub(/{/, "", s); b = gsub(/}/, "", s); return a - b }
    !in_ctm {
      if ($0 ~ /"CompatToolMapping"/) { in_ctm = 1 }
      next
    }
    {
      d += braces($0)
      if (!found && index($0, "\"" app "\"")) { found = 1; next }
      if (found && $0 ~ /"name"/) {
        s = $0
        sub(/^.*"name"[ \t]*/, "", s)
        gsub(/^"|"$/, "", s)
        print s
        exit
      }
      if (d <= 0) exit
    }
  ' "$1"
}

# Filled in by resolve_paths() once detection has succeeded.
STEAM=""
GAME=""
PROTON=""
PREFIX=""
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
ICON="$HOME/.local/share/icons/hicolor/256x256/apps/tf2vr.png"
OPENXR="$HOME/.config/openxr/1/active_runtime.json"
WIVRN_LIB="/usr/lib/wivrn/libopenxr_wivrn.so"

# Companion Northstar mod: without it, entering multiplayer fails to compile the
# CLIENT script VM with `Undefined variable "TF2VR_PickupKind"`.
MPFIX_NAME="Titanfall2VR.MPFix"
MPFIX_SRC="$HERE/northstar-mod/$MPFIX_NAME"
MPFIX_DST=""

# VR plugin: it fastfails (0xC0000409) on any pilot hand model it does not
# recognise, which every multiplayer pilot is.  Two `int 0x29` sites are nop'd.
PLUGIN=""
PATCHER="$HERE/launcher/tf2vr-patch-titanfall2vr"

MODE=install
PATCH=1
MPFIX=1
for a in "$@"; do
  case "$a" in
    --check)    MODE=check ;;
    --uninstall) MODE=uninstall ;;
    --no-patch) PATCH=0 ;;
    --no-mp-fix) MPFIX=0 ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "install.sh: unknown option '$a' (try --help)" >&2; installer_exit 2 ;;
  esac
done

fails=0
warns=0
ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# ---------------------------------------------------------------- detection --
# Ask for the game directory when nothing was found automatically.  Prompts go
# to stderr so the function stays safe to capture on stdout.
prompt_install() {
  local input
  while true; do
    if [ ! -t 0 ]; then
      echo "No interactive terminal available to ask where Titanfall 2 is." >&2
      return 1
    fi
    printf 'Path to your Titanfall 2 directory\n%s: ' \
      "  (e.g. <SteamLibrary>/steamapps/common/Titanfall2)" >&2
    IFS= read -r input || return 1
    input="${input%\"}"
    input="${input#\"}"
    if [ -n "$input" ] && validate_titanfall2_install "$input"; then
      GAME="$input"
      return 0
    fi
    echo "  that is not a Titanfall 2 installation - it needs Titanfall2.exe" >&2
    echo "  and a vpk/ directory: ${input:-<empty>}" >&2
    printf 'Try another path? [y/N] ' >&2
    IFS= read -r input || return 1
    case "$input" in
      [Yy]*) ;;
      *) return 1 ;;
    esac
  done
}

# More than one installation and no reliable way to tell them apart: let the
# user pick rather than silently choosing one.
choose_install() {
  local installs="$1" d i=0 pick
  local -a options=()
  echo "More than one Titanfall 2 installation was found:" >&2
  while IFS= read -r d; do
    i=$((i + 1))
    options[i]="$d"
    printf '  %d) %s\n' "$i" "$d" >&2
  done <<< "$installs"
  if [ ! -t 0 ]; then
    echo "No interactive terminal to choose from." >&2
    return 1
  fi
  while true; do
    printf 'Which one should be used? [1-%d]: ' "$i" >&2
    IFS= read -r pick || return 1
    case "$pick" in
      ''|*[!0-9]*) ;;
      *)
        if [ "$pick" -ge 1 ] && [ "$pick" -le "$i" ]; then
          printf '%s\n' "${options[$pick]}"
          return 0
        fi
        ;;
    esac
    echo "  enter a number from 1 to $i" >&2
  done
}

no_install_selected() {
  echo
  echo "No Titanfall 2 installation selected - nothing was changed."
  echo "Run it again and answer the prompt, or point it at the game directly:"
  echo "    TF2VR_GAME=<SteamLibrary>/steamapps/common/Titanfall2 ./install.sh"
  installer_exit 1
}

# Resolve every path once here, then hand the results to the rest of the
# script.  Nothing below hardcodes a Steam location.
resolve_paths() {
  local installs install

  if [ -n "${TF2VR_GAME:-}" ]; then
    if ! validate_titanfall2_install "$TF2VR_GAME"; then
      echo "TF2VR_GAME is not a Titanfall 2 installation: $TF2VR_GAME" >&2
      echo "  it needs Titanfall2.exe and a vpk/ directory" >&2
      installer_exit 1
    fi
    GAME="$TF2VR_GAME"
  else
    installs=$(find_titanfall2_install)
    if [ -z "$installs" ]; then
      echo
      echo "Titanfall 2 could not be found automatically."
      prompt_install || no_install_selected
    elif install=$(pick_titanfall2_install); then
      GAME="$install"
    else
      install=$(choose_install "$installs") || no_install_selected
      GAME="$install"
    fi
  fi

  STEAM=$(tf2vr_library_of "$GAME" || true)
  if [ -z "$STEAM" ]; then
    STEAM=$(find_steam_libraries | head -n 1 || true)
  fi

  PREFIX=$(find_titanfall2_prefix "$GAME" || true)
  if [ -z "$PREFIX" ] && [ -n "$STEAM" ]; then
    PREFIX="$STEAM/steamapps/compatdata/$TF2VR_APPID"
  fi

  PROTON=$(find_proton || true)
}

# ---------------------------------------------------------------- preflight --
preflight() {
  echo "Preflight:"

  if [ -z "$GAME" ]; then
    warn "Titanfall 2 not detected - only the files outside the game directory are checked"
  else
    [ -d "$STEAM" ] \
      && ok "Steam library: $STEAM" \
      || fail "Steam library not detected (set STEAM_DIR=... if it lives elsewhere)"

    validate_titanfall2_install "$GAME" \
      && ok "Titanfall 2: $GAME" \
      || fail "Titanfall 2 not found at $GAME"

    [ -x "$PROTON" ] \
      && ok "Proton: $PROTON" \
      || fail "no Proton found - install one (Steam -> Library -> right-click the game -> Properties -> Compatibility), or set TF2VR_PROTON=..."

    [ -d "$PREFIX" ] \
      && ok "Wine prefix: $PREFIX" \
      || warn "No Wine prefix at $PREFIX yet - it is created on the first Proton run"

    [ -f "$GAME/TF2VR/tools/crash_monitor.exe" ] \
      && ok "TF2VR mod installed (crash_monitor.exe present)" \
      || fail "TF2VR mod not installed - run CircuitLordVRModInstaller first"

    if [ -f "$MPFIX_DST/mod.json" ]; then
      ok "multiplayer compile fix installed ($MPFIX_NAME)"
    elif [ "$MODE" = uninstall ]; then
      ok "multiplayer compile fix not present (nothing to remove)"
    elif [ "$MPFIX" = 0 ]; then
      ok "multiplayer compile fix will be skipped (--no-mp-fix)"
    elif [ "$MODE" = install ]; then
      ok "multiplayer compile fix will be installed ($MPFIX_NAME)"
    else
      warn "no $MPFIX_NAME in the game dir - clicking Multiplayer hits a CLIENT script compile error"
    fi

    if [ "$MODE" != uninstall ] && command -v python3 >/dev/null 2>&1 && [ -f "$PLUGIN" ]; then
      local ph
      ph=$("$PATCHER" -n 2>/dev/null || true)
      if printf '%s\n' "$ph" | grep -q '^  already patched:'; then
        ok "VR plugin patches applied (Titanfall2VR.dll)"
      elif [ "$MODE" = install ] && [ "$PATCH" = 1 ]; then
        ok "VR plugin patches will be applied (Titanfall2VR.dll)"
      elif [ "$PATCH" = 0 ]; then
        ok "VR plugin patches will be skipped (--no-patch)"
      else
        warn "Titanfall2VR.dll is unpatched - multiplayer dies with 'unrecognized pilot hand model' or 'seated pilot model changed', and the cockpit HUD fades out when the gun is holstered"
      fi
    fi
  fi

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
    && ok "python3 available (for the binary patchers)" \
    || warn "python3 missing - the mmdevapi and VR plugin patches cannot be applied"

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
  install -Dm755 "$HERE/launcher/tf2vr-patch-mmdevapi"  "$BIN/tf2vr-patch-mmdevapi"
  install -Dm755 "$HERE/launcher/tf2vr-patch-titanfall2vr" "$BIN/tf2vr-patch-titanfall2vr"
  install -Dm644 "$HERE/launcher/tf2vr-detect.sh"       "$BIN/tf2vr-detect.sh"
  ok "$BIN/tf2vr, tf2vr-detect.sh, tf2vr-patch-mmdevapi, tf2vr-patch-titanfall2vr"

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

  if [ "$MPFIX" = 1 ]; then
    if [ -d "$GAME/TF2VR/mods" ]; then
      rm -rf "$MPFIX_DST"
      cp -a "$MPFIX_SRC" "$MPFIX_DST"
      ok "$MPFIX_NAME -> $GAME/TF2VR/mods/"
    else
      warn "no $GAME/TF2VR/mods - skipping the multiplayer compile fix"
    fi
  else
    rm -rf "$MPFIX_DST"
    ok "skipped the multiplayer compile fix (--no-mp-fix)"
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

      echo
      echo "Titanfall2VR.dll:"
      if out=$("$BIN/tf2vr-patch-titanfall2vr" 2>&1); then
        printf '%s\n' "$out" \
          | grep -E '^  (already )?patched:|patched of [0-9]+ checked' \
          || printf '%s\n' "$out"
      else
        printf '%s\n' "$out"
        warn "the patcher reported a problem (re-run tf2vr-patch-titanfall2vr for details)"
      fi
    fi
  else
    echo
    echo "Skipping the binary patches (--no-patch); without them the launcher aborts with"
    echo "0xC0000409 and multiplayer dies with 'unrecognized pilot hand model' or"
    echo "'seated pilot model changed'."
  fi
}

uninstall_files() {
  echo
  echo "Uninstalling:"
  local f out
  if [ -n "$PLUGIN" ] && [ -f "$PLUGIN.orig-tf2vr" ]; then
    out=$("$PATCHER" -r 2>&1 || true)
    printf '%s\n' "$out" \
      | sed -n 's/^  \(reverted\|already reverted\): \(.*\)$/  ok    restored \2/p'
    if printf '%s\n' "$out" | grep -qE '^  (reverted|already reverted):'; then
      rm -f "$PLUGIN.orig-tf2vr"
      ok "removed $PLUGIN.orig-tf2vr"
    else
      printf '%s\n' "$out" | grep -v '^tf2vr-patch-titanfall2vr:' || true
      warn "the original Titanfall2VR.dll was not restored"
    fi
  fi
  for f in "$BIN/tf2vr" "$BIN/tf2vr-detect.sh" "$BIN/tf2vr-patch-mmdevapi" \
           "$BIN/tf2vr-patch-titanfall2vr" \
           "$APPS/tf2vr.desktop" "$APPS/tf2vr-vanilla.desktop" "$ICON"; do
    if [ -e "$f" ]; then rm -f "$f"; ok "removed $f"; else ok "not present: $f"; fi
  done
  if [ -z "$MPFIX_DST" ]; then
    ok "game directory unknown - the companion mod was left alone"
  elif [ -e "$MPFIX_DST" ]; then
    rm -rf "$MPFIX_DST"; ok "removed $MPFIX_DST"
  else
    ok "not present: $MPFIX_DST"
  fi
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
  echo
  echo "Left alone: the rest of the game directory, your Proton install, and $OPENXR."
}

# -------------------------------------------------------------------- main ---
# Resolve Steam, the game and the prefix once, then hand them to everything
# below. Uninstalling still works when the game itself is already gone.
if [ "$MODE" = uninstall ] && [ -z "$(find_titanfall2_install)" ]; then
  echo "Titanfall 2 was not found - removing only the files outside the game directory."
else
  resolve_paths
fi

if [ -n "$GAME" ]; then
  MPFIX_DST="$GAME/TF2VR/mods/$MPFIX_NAME"
  PLUGIN="$GAME/TF2VR/plugins/Titanfall2VR.dll"
fi

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
  installer_exit 1
fi
echo "Done, no failures ($warns warning(s))."
[ "$MODE" = install ] && echo "Start the game with:  tf2vr      (or the 'Titanfall 2 VR' launcher entry)"
exit 0
