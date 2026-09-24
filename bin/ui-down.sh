#!/bin/sh
# Stops the Factory UI: removes the container and closes every herdr tab factory-ui-relay. With neither running
# it does nothing.
#
#   ui-down.sh
set -eu

name=${FACTORY_UI_CONTAINER:-claude-factory-ui}

if docker inspect "$name" >/dev/null 2>&1; then
  docker rm -f "$name" >/dev/null
fi

command -v herdr >/dev/null 2>&1 || exit 0
herdr tab list 2>/dev/null | tr '{' '\n' | grep -E '"label":"factory-ui-relay"[,}]' \
  | grep -o '"tab_id":"[^"]*"' | cut -d'"' -f4 | while IFS= read -r tab; do
    herdr tab close "$tab" >/dev/null
  done
