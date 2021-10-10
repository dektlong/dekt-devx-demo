#!/usr/bin/env bash

case $1 in
octant)
    open -a Terminal scripts/octant-wrapper.sh
    ;;
dogfacts)
    open -a Terminal scripts/dogfacts-wrapper.sh
    ;;
*)
    ;;
esac

osascript -e 'tell application "Terminal" to set miniaturized of every window to true'