#!/usr/bin/env bash

playerctlstatus=$(playerctl status 2> /dev/null)

if [[ $playerctlstatus ==  "" ]]; then
    echo ""
elif [[ $playerctlstatus =~ "Playing" ]]; then
    echo "%{A1:playerctl pause:}%{A}"
else
    echo "%{A1:playerctl play:}契%{A}"
fi
