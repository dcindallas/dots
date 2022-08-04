#!/usr/bin/env bash

# Add this script to your wm startup file.

DIR="$HOME/.config/polybar"

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch the bar
# polybar -q date -c "$DIR"/config.ini &
#polybar -q main -c "$DIR"/config.ini &
# polybar -q music -c "$DIR"/config.ini &
# polybar -q power -c "$DIR"/config.ini &
# polybar -q tray -c "$DIR"/config.ini &
polybar -q left -c "$DIR"/config.ini &
