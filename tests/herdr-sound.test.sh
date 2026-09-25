#!/bin/sh
# herdr-sound.sh over a throwaway XDG_CONFIG_HOME and the herdr stub: off adds or rewrites `[ui.sound] enabled`,
# keeps every other line, on turns it back, a config that already says so is not written and herdr not reloaded,
# and a missing file is created.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
. "$(dirname -- "$0")/herdr-stub.sh"
herdr_stub "$tmp/stub"
HERDR_STUB_LOG="$tmp/log"
XDG_CONFIG_HOME="$tmp/config"
export HERDR_STUB_LOG XDG_CONFIG_HOME
conf="$tmp/config/herdr/config.toml"

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s:\n  expected [%s]\n  got      [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
reloads() { grep -c 'server reload-config' "$HERDR_STUB_LOG" 2>/dev/null || echo 0; }

sh "$bin/herdr-sound.sh" on
check "on with no file writes nothing" "no" "$([ -e "$conf" ] && echo yes || echo no)"
check "on with no file does not reload" 0 "$(reloads)"

sh "$bin/herdr-sound.sh" off
check "off with no file creates the section" "$(printf '\n[ui.sound]\nenabled = false')" "$(cat "$conf")"
check "off reloads herdr" 1 "$(reloads)"

printf '[ui]\naccent = "blue"\n\n[ui.toast]\ndelivery = "system"\n' > "$conf"
sh "$bin/herdr-sound.sh" off
check "off appends the section, other lines kept" \
  "$(printf '[ui]\naccent = "blue"\n\n[ui.toast]\ndelivery = "system"\n\n[ui.sound]\nenabled = false')" "$(cat "$conf")"
sh "$bin/herdr-sound.sh" off
check "off again does not reload" 2 "$(reloads)"

sh "$bin/herdr-sound.sh" on
check "on rewrites the key in place" \
  "$(printf '[ui]\naccent = "blue"\n\n[ui.toast]\ndelivery = "system"\n\n[ui.sound]\nenabled = true')" "$(cat "$conf")"

printf '[ui.sound]\npath = "a.mp3"\n\n[keys]\nprefix = "ctrl+space"\n' > "$conf"
sh "$bin/herdr-sound.sh" off
check "off puts the key under the header of a section without it" \
  "$(printf '[ui.sound]\nenabled = false\npath = "a.mp3"\n\n[keys]\nprefix = "ctrl+space"')" "$(cat "$conf")"

printf '[ui.sound]\nenabled = false # muted\n' > "$conf"
sh "$bin/herdr-sound.sh" off
check "a trailing comment still reads as off" 4 "$(reloads)"

sh "$bin/herdr-sound.sh" loud 2>/dev/null
check "a bad argument exits 1" 1 "$?"

exit "$fail"
