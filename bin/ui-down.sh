#!/bin/sh
# Stops the Factory UI: removes the container and closes every herdr relay tab (`ui relay (no agent)`, or
# `factory-ui-relay` from an older plugin), and turns herdr's own agent sounds back on, which the relay turns off
# while the Mute sound switch is on. With neither running it does nothing.
#
#   ui-down.sh
set -eu

name=${FACTORY_UI_CONTAINER:-claude-factory-ui}

if docker inspect "$name" >/dev/null 2>&1; then
  docker rm -f "$name" >/dev/null
fi

command -v herdr >/dev/null 2>&1 || exit 0
sh "$(dirname -- "$0")/herdr-sound.sh" on || :
herdr tab list 2>/dev/null | tr '{' '\n' | grep -E '"label":"(ui relay \(no agent\)|factory-ui-relay)"[,}]' \
  | grep -o '"tab_id":"[^"]*"' | cut -d'"' -f4 | while IFS= read -r tab; do
    herdr tab close "$tab" >/dev/null
  done
