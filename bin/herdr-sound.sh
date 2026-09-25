#!/bin/sh
# Turns herdr's own agent sounds on or off: `[ui.sound] enabled` in herdr's config.toml, then
# `herdr server reload-config`. herdr plays them when an agent in a background workspace turns done or asks, and has
# no runtime switch for them, so the Mute sound switch of the UI reaches them only through the config. The file is
# left alone when it already says so; a missing key or section counts as on, herdr's default.
#
#   herdr-sound.sh on|off
set -eu

case "${1:-}" in on) want=true ;; off) want=false ;; *) printf 'usage: herdr-sound.sh on|off\n' >&2; exit 1 ;; esac
conf=${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml

have=$(awk '/^[ \t]*\[/ { sec = $0; gsub(/[ \t]/, "", sec) }
  sec == "[ui.sound]" && /^[ \t]*enabled[ \t]*=/ { v = $0; sub(/^[^=]*=[ \t]*/, "", v); sub(/[ \t#].*/, "", v) }
  END { print (v == "false" ? "false" : "true") }' "$conf" 2>/dev/null || echo true)
[ "$have" != "$want" ] || exit 0

mkdir -p "${conf%/*}"
[ -f "$conf" ] || : > "$conf"
awk -v w="$want" '
  /^[ \t]*\[/ { sec = $0; gsub(/[ \t]/, "", sec) }
  sec == "[ui.sound]" && /^[ \t]*enabled[ \t]*=/ { next }
  { print }
  sec == "[ui.sound]" && !done { print "enabled = " w; done = 1 }
  END { if (!done) printf "\n[ui.sound]\nenabled = %s\n", w }' "$conf" > "$conf.sound.$$"
cat "$conf.sound.$$" > "$conf"
rm -f "$conf.sound.$$"
command -v herdr >/dev/null 2>&1 && herdr server reload-config >/dev/null 2>&1 || :
