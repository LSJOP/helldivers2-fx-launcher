#!/bin/zsh
cd -- "${0:A:h}" || exit 1
exec /usr/bin/python3 ./launcher-20261026/legacy_menu.py "$@"
