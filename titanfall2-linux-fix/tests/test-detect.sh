#!/usr/bin/env bash
# Tests for Steam / Titanfall 2 / Proton detection and for exit reporting.
#
#   ./tests/test-detect.sh
#
# Everything runs against throwaway fixture trees in a temporary directory,
# with HOME redirected so the real Steam installation is never touched.

set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DETECT="$HERE/launcher/tf2vr-detect.sh"
LAUNCHER="$HERE/launcher/tf2vr"
INSTALLER="$HERE/install.sh"
REAL_HOME="$HOME"

APPID=1237970
passed=0
failed=0
skipped=0

pass() { printf '  ok    %s\n' "$1"; passed=$((passed + 1)); }
nope() { printf '  FAIL  %s\n' "$1"; failed=$((failed + 1)); }
skip() { printf '  skip  %s\n' "$1"; skipped=$((skipped + 1)); }
check() { # check <description> <actual> <expected>
  if [ "$2" = "$3" ]; then pass "$1"; else
    nope "$1"
    printf '        expected: %s\n        actual  : %s\n' "$3" "$2"
  fi
}
has() { # has <description> <haystack> <needle>
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) nope "$1" ;;
  esac
}
lacks() { # lacks <description> <haystack> <needle>
  case "$2" in
    *"$3"*) nope "$1" ;;
    *) pass "$1" ;;
  esac
}

TMP=$(mktemp -d)
EA_PID=""

cleanup() {
  [ -n "$EA_PID" ] && kill "$EA_PID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

# ---------------------------------------------------------------- fixtures --
FAKEHOME="$TMP/home"
STEAM1="$TMP/Steam"                      # primary library, holds the game
STEAM2="$TMP/Secondary Library"          # second drive, path contains a space
GAMEDIR="$STEAM1/steamapps/common/Titanfall 2 VR"   # installdir contains a space
GAMEDIR2="$STEAM2/steamapps/common/Titanfall2"      # stock installdir name
PREFIX="$STEAM1/steamapps/compatdata/$APPID"

make_game() { # make_game <dir> [<library root to write an appmanifest into>]
  mkdir -p "$1/vpk" "$1/TF2VR/tools" "$1/TF2VR/logs" "$1/TF2VR/plugins"
  : >"$1/Titanfall2.exe"
  : >"$1/gameversion.txt"
  : >"$1/TF2VR/tools/crash_monitor.exe"
  printf '"Titanfall2VR"\n' >"$1/TF2VR/logs/nslog fixture.txt"
  if [ -n "${2:-}" ]; then
    printf 'SteamAppID=%s\n\t"installdir"\t\t"Titanfall 2 VR"\n' "$APPID" \
      >"$2/steamapps/appmanifest_$APPID.acf"
  fi
}

make_game_plain() { # make_game_plain <dir>   (no appmanifest, stock installdir)
  mkdir -p "$1/vpk" "$1/TF2VR/tools" "$1/TF2VR/logs" "$1/TF2VR/plugins"
  : >"$1/Titanfall2.exe"
  : >"$1/gameversion.txt"
  : >"$1/TF2VR/tools/crash_monitor.exe"
  printf '"Titanfall2VR"\n' >"$1/TF2VR/logs/nslog fixture.txt"
}

make_proton() { # make_proton <library-root> <tool name>
  mkdir -p "$1/steamapps/common/$2"
  printf '#!/bin/sh\nexit 0\n' >"$1/steamapps/common/$2/proton"
  chmod +x "$1/steamapps/common/$2/proton"
}

make_library_vdf() { # make_library_vdf <root> [<second library>]
  mkdir -p "$1/steamapps"
  {
    printf '"libraryfolders"\n{\n'
    printf '\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n' "$STEAM1"
    if [ -n "${2:-}" ]; then
      printf '\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n' "$2"
    fi
    printf '}\n'
  } >"$1/steamapps/libraryfolders.vdf"
}

mkdir -p "$FAKEHOME"
make_library_vdf "$STEAM1" "$STEAM2"
make_game "$GAMEDIR" "$STEAM1"
make_game_plain "$GAMEDIR2"
make_library_vdf "$STEAM2"
make_proton "$STEAM1" "Proton - Experimental"
mkdir -p "$PREFIX/pfx/drive_c"

detect() { # run shell code with the fixture environment
  env -i HOME="$FAKEHOME" STEAM_DIR="$STEAM1" PATH="$PATH" bash -c "
    set -euo pipefail
    . '$DETECT'
    $1
  "
}

echo "Detection:"

r=$(detect 'validate_titanfall2_install "'"$GAMEDIR"'" && echo valid')
check "validate_titanfall2_install accepts a real install" "$r" "valid"

r=$(detect 'validate_titanfall2_install "'"$TMP"'/nowhere" || echo rejected')
check "validate_titanfall2_install rejects a missing path" "$r" "rejected"
mkdir -p "$TMP/notthegame"
r=$(detect 'validate_titanfall2_install "'"$TMP"'/notthegame" || echo rejected')
check "validate_titanfall2_install rejects a directory without the game" "$r" "rejected"

# both libraries are discovered, the primary first, spaces intact
r=$(detect 'find_steam_libraries')
check "find_steam_libraries lists both configured libraries" "$r" "$STEAM1"$'\n'"$STEAM2"

# the game in the secondary library is found through libraryfolders.vdf even
# though it carries no appmanifest (stock installdir name)
r=$(detect 'find_titanfall2_install | wc -l | tr -d " "')
check "both installations are found across both libraries" "$r" "2"

# the appmanifest says which installdir is the real one, spaces included
r=$(detect 'pick_titanfall2_install')
check "pick_titanfall2_install prefers the appmanifest library" "$r" "$GAMEDIR"

# two libraries both claiming the game -> refuse to guess
make_game "$GAMEDIR2" "$STEAM2"
sed -i 's/"Titanfall 2 VR"/"Titanfall2"/' "$STEAM2/steamapps/appmanifest_$APPID.acf"
r=$(detect 'pick_titanfall2_install || echo ambiguous')
check "pick_titanfall2_install refuses to guess between two appmanifests" "$r" "ambiguous"

# restore the unambiguous fixture
rm -f "$STEAM2/steamapps/appmanifest_$APPID.acf"
r=$(detect 'pick_titanfall2_install')
check "pick_titanfall2_install recovers once the duplicate is gone" "$r" "$GAMEDIR"

# prefixes follow the install, not the primary drive
r=$(detect 'find_titanfall2_prefix "'"$GAMEDIR"'"')
check "find_titanfall2_prefix derives it from the install path" "$r" "$PREFIX"
r=$(detect 'validate_proton_prefix "'"$PREFIX"'" && echo valid')
check "validate_proton_prefix accepts a created prefix" "$r" "valid"
r=$(detect 'validate_proton_prefix "'"$TMP"'/nope" || echo invalid')
check "validate_proton_prefix rejects a prefix that does not exist" "$r" "invalid"

r=$(detect 'find_proton')
check "find_proton finds the historical default" "$r" \
  "$STEAM1/steamapps/common/Proton - Experimental/proton"

r=$(env -i HOME="$FAKEHOME" STEAM_DIR="$STEAM1" TF2VR_PROTON=/bin/true PATH="$PATH" \
  bash -c "set -euo pipefail; . '$DETECT'; find_proton")
check "TF2VR_PROTON overrides Proton discovery" "$r" "/bin/true"

echo
echo "Filesystem:"

r=$(detect 'tf2vr_filesystem "'"$GAMEDIR"'"')
if [ -n "$r" ]; then
  pass "tf2vr_filesystem names the filesystem behind the game ($r)"
else
  nope "tf2vr_filesystem names the filesystem behind the game"
fi

r=$(detect 'tf2vr_write_probe "'"$GAMEDIR"'" && echo writable')
check "tf2vr_write_probe accepts a writable directory" "$r" "writable"

RODIR="$TMP/read-only"
mkdir -p "$RODIR"
chmod 555 "$RODIR"
r=$(detect 'tf2vr_write_probe "'"$RODIR"'" >/dev/null || echo refused')
check "tf2vr_write_probe refuses a read-only directory" "$r" "refused"
r=$(detect 'tf2vr_write_probe "'"$RODIR"'" || true')
has "the refusal names the exact path that failed" "$r" "$RODIR/.tf2vr-write-test"
has "the refusal carries the operating system's own reason" "$r" "Permission denied"
chmod 755 "$RODIR"

# the risky list is a pattern match on the mount type, so it can be exercised
# without a Windows filesystem being available
r=$(detect 'tf2vr_filesystem() { printf "ntfs3\n"; }; if tf2vr_filesystem_is_risky "'"$GAMEDIR"'"; then echo risky; fi')
check "tf2vr_filesystem_is_risky flags an ntfs mount" "$r" "risky"
r=$(detect 'tf2vr_filesystem() { printf "exfat\n"; }; if tf2vr_filesystem_is_risky "'"$GAMEDIR"'"; then echo risky; fi')
check "tf2vr_filesystem_is_risky flags an exfat mount" "$r" "risky"
r=$(detect 'tf2vr_filesystem() { printf "ext4\n"; }; if tf2vr_filesystem_is_risky "'"$GAMEDIR"'"; then echo risky; else echo fine; fi')
check "tf2vr_filesystem_is_risky accepts ext4" "$r" "fine"

echo
echo "Installer:"
HOME="$FAKEHOME"
export HOME
export STEAM_DIR="$STEAM1"

out=$("$INSTALLER" --bogus 2>&1); rc=$?
check "installer rejects an unknown option with status 2" "$rc" "2"
has "installer prints the unknown option message" "$out" "unknown option"

out=$(env HOME="$FAKEHOME" STEAM_DIR="$TMP/no-such-steam" \
  "$INSTALLER" --check </dev/null 2>&1); rc=$?
check "installer exits non-zero when Titanfall 2 is not found" "$rc" "1"
has "installer says detection failed" "$out" "could not be found automatically"
has "installer documents the manual path override" "$out" "TF2VR_GAME="
if [ ! -e "$FAKEHOME/.local/bin/tf2vr" ]; then
  pass "nothing is installed when no game was found"
else
  nope "nothing is installed when no game was found"
fi

out=$(env HOME="$FAKEHOME" TF2VR_GAME="$TMP/notthegame" \
  "$INSTALLER" --check </dev/null 2>&1); rc=$?
check "installer refuses an invalid TF2VR_GAME" "$rc" "1"
has "installer explains why the path was refused" "$out" "not a Titanfall 2 installation"
if [ ! -e "$FAKEHOME/.local/bin/tf2vr" ]; then
  pass "an invalid path installs nothing"
else
  nope "an invalid path installs nothing"
fi

out=$(env HOME="$FAKEHOME" TF2VR_GAME="$GAMEDIR" \
  "$INSTALLER" --check </dev/null 2>&1); rc=$?
check "installer accepts a valid TF2VR_GAME" "$rc" "0"
has "installer reports the supplied game directory" "$out" "Titanfall 2: $GAMEDIR"

out=$(env HOME="$FAKEHOME" STEAM_DIR="$STEAM1" \
  "$INSTALLER" --check </dev/null 2>&1); rc=$?
check "preflight passes on the fixture" "$rc" "0"
has "preflight reports no failures" "$out" "Done, no failures"
lacks "a clean run prints no installer error banner" "$out" "installer error"

# an internal failure: the original output is kept, the status is non-zero and
# both issue trackers are named.  --check guards every file read it makes, so
# the only way to break the installer for real is to take away a file it has to
# copy during an install - hence install mode here rather than --check.
broken="$TMP/broken"
cp -a "$HERE" "$broken"
rm -f "$broken/launcher/tf2vr"
out=$(env HOME="$FAKEHOME" STEAM_DIR="$STEAM1" \
  "$broken/install.sh" </dev/null 2>&1); rc=$?
check "an internal installer failure exits non-zero" "$rc" "1"
has "the original error output is preserved" "$out" "No such file or directory"
has "the installer prints its error banner" "$out" "installer error"
has "the Linux-fix issue tracker is named" "$out" "Titanfall-2-VR-linux-fix/issues"
has "the VR mod issue tracker is named" "$out" "Monkellie/tf2vr-linux/issues"

# A read-only game directory is the "write error" users report with no path
# attached to it.  Name the directory, carry the operating system's own reason,
# and stop before anything is copied halfway in.
ROGAME="$TMP/read-only-game"
make_game_plain "$ROGAME"
chmod 555 "$ROGAME"
out=$(env HOME="$FAKEHOME" STEAM_DIR="$STEAM1" TF2VR_GAME="$ROGAME" \
  "$INSTALLER" --check </dev/null 2>&1); rc=$?
check "a read-only game directory fails the preflight" "$rc" "1"
has "the failure names the directory" "$out" "cannot write to $ROGAME"
has "the failure names the filesystem behind it" "$out" "$ROGAME ("
has "the failure carries the operating system's own reason" "$out" "Permission denied"
lacks "a refused write prints no installer error banner" "$out" "installer error"
chmod 755 "$ROGAME"

echo
echo "Updater:"

UPDATER="$HERE/tf2vr-update"

out=$("$UPDATER" --help </dev/null 2>&1); rc=$?
check "tf2vr-update --help exits 0" "$rc" "0"
has "tf2vr-update --help lists the dry run" "$out" "--dry-run"
has "tf2vr-update --help lists the cache override" "$out" "TF2VR_CACHE"

out=$("$UPDATER" --bogus </dev/null 2>&1); rc=$?
check "tf2vr-update rejects an unknown option" "$rc" "1"
has "tf2vr-update explains the unknown option" "$out" "unknown option"

out=$(env HOME="$FAKEHOME" TF2VR_GAME="$TMP/notthegame" \
  "$UPDATER" --check </dev/null 2>&1); rc=$?
check "tf2vr-update refuses a directory that is not the game" "$rc" "1"
has "tf2vr-update says why the path was refused" "$out" "not a Titanfall 2 installation"
lacks "the refusal never reaches the manifest" "$out" "fetching https://"

# version comparison lives in the updater and is reachable by sourcing it,
# which is what keeps this testable without a network round trip
vnr() {
  bash -c ". '$UPDATER' >/dev/null 2>&1 || exit 9
if version_is_newer '$1' '$2'; then echo yes; else echo no; fi" 2>&1
}
check "1.0.12 is newer than 1.0.8" "$(vnr 1.0.12 1.0.8)" "yes"
check "1.0.12 is newer than 1.0.9" "$(vnr 1.0.12 1.0.9)" "yes"
check "1.0.9 is not newer than 1.0.12" "$(vnr 1.0.9 1.0.12)" "no"
check "an equal version is not newer" "$(vnr 1.0.8 1.0.8)" "no"
check "a longer version line still compares" "$(vnr 2.0 1.9.9)" "yes"
check "a shorter version line still compares" "$(vnr 1.0.12 1)" "yes"

echo
echo "Launcher:"

# A stand-in for Proton drives the exit status; a fake EA Desktop process keeps
# the launcher from trying to start the real one.
EA_EXE='C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe'
EA_EXE="$EA_EXE" bash -c 'exec -a "$EA_EXE" sleep 120' &
EA_PID=$!
sleep 0.3

run_launcher() { # run_launcher <exit status>
  printf '#!/bin/sh\necho "FAKE PROTON OUTPUT: $*"\nexit %s\n' "$1" >"$TMP/fake-proton"
  chmod +x "$TMP/fake-proton"
  env HOME="$FAKEHOME" STEAM_DIR="$STEAM1" \
      TF2VR_PROTON="$TMP/fake-proton" TF2VR_NO_PATCH=1 \
      "$LAUNCHER" </dev/null 2>&1
}

out=$(run_launcher 0); rc=$?
check "a normal exit reports status 0" "$rc" "0"
lacks "a normal exit prints no unexpected-exit banner" "$out" "Unexpected Exit"
has "the game's own output stays visible on a normal exit" "$out" "FAKE PROTON OUTPUT"

out=$(run_launcher 7); rc=$?
check "an unexpected exit keeps the game's exit status" "$rc" "7"
has "the game's output is not swallowed" "$out" "FAKE PROTON OUTPUT"
has "the unexpected-exit banner is printed" "$out" "Titanfall 2 VR Linux Fix - Unexpected Exit"
has "the wording does not claim a definite crash" "$out" "exited unexpectedly"
has "the banner links the Linux-fix tracker" "$out" "Titanfall-2-VR-linux-fix/issues"
has "the banner links the VR mod tracker" "$out" "Monkellie/tf2vr-linux/issues"
has "the banner points at a log" "$out" "Relevant log:"
has "the named log actually exists" "$out" "nslog fixture.txt"

has "a local diagnostic report is written" "$out" "Diagnostic report written to:"
report=$(printf '%s\n' "$out" | sed -n '/Diagnostic report written to:/{n;s/^[[:space:]]*//;p;}')
if [ -n "$report" ] && [ -f "$report" ]; then
  pass "the diagnostic report exists at the printed path"
  for field in "Steam library" "Proton prefix" "Proton version" "Kernel" "GPU" \
               "VR runtime" "Linux-fix version" "exit status"; do
    if grep -qi -- "$field" "$report"; then
      pass "diagnostic report records $field"
    else
      nope "diagnostic report records $field"
    fi
  done
  if grep -qiE 'password|passwd|token=|api[_-]?key' "$report"; then
    nope "the diagnostic report leaks no credentials"
  else
    pass "the diagnostic report leaks no credentials"
  fi
else
  nope "the diagnostic report exists at the printed path"
fi

out=$(run_launcher 130); rc=$?
check "status 130 is treated as an interrupted run" "$rc" "130"
lacks "an interrupted run prints no crash banner" "$out" "Unexpected Exit"

echo
echo "Existing installation:"
REAL_GAME=$(env -i HOME="$REAL_HOME" PATH="$PATH" bash -c "
  . '$DETECT'
  pick_titanfall2_install 2>/dev/null || true
")
if [ -z "$REAL_GAME" ]; then
  skip "real Titanfall 2 installation not reachable from this environment"
else
  if [ -f "$REAL_GAME/TF2VR/plugins/Titanfall2VR.dll" ] && command -v python3 >/dev/null 2>&1; then
    out=$(env HOME="$REAL_HOME" "$HERE/launcher/tf2vr-patch-titanfall2vr" -n 2>&1)
    case "$out" in
      *"already patched"*|*"would patch"*)
        pass "the VR plugin patcher still recognises the installed build" ;;
      *)
        nope "the VR plugin patcher still recognises the installed build"
        printf '%s\n' "$out" | sed 's/^/        /' ;;
    esac
    if python3 -c '
import sys
d = open(sys.argv[1], "rb").read()
ok = (b"wine_get_version" in d
      and "ntdll.dll".encode("utf-16-le") in d
      and b"memories=" in d)
sys.exit(0 if ok else 1)
' "$REAL_GAME/TF2VR/plugins/Titanfall2VR.dll" 2>/dev/null; then
      pass "the installed plugin still gates memory capture on Wine detection"
    else
      nope "the installed plugin still gates memory capture on Wine detection"
    fi
  else
    skip "no installed VR plugin to check"
  fi
  if out=$(env -u STEAM_DIR -u TF2VR_GAME HOME="$REAL_HOME" \
      "$INSTALLER" --check </dev/null 2>&1); then
    pass "install.sh --check still passes on the real installation"
  else
    nope "install.sh --check still passes on the real installation"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
fi

echo
printf 'passed %d, failed %d, skipped %d\n' "$passed" "$failed" "$skipped"
[ "$failed" -eq 0 ]
