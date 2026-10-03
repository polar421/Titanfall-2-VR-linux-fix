#!/usr/bin/env bash
# Shared Steam / Titanfall 2 / Proton path detection for the Titanfall 2 VR
# Linux fix.  Sourced by install.sh and by the tf2vr launcher so neither one
# hardcodes a Steam location; it is not meant to be executed directly.
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
