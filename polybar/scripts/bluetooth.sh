#!/bin/sh
if [ $(bluetoothctl show | grep "Powered: yes" | wc -c) -eq 0 ]
then
  echo "%{F#FB543F}"
else
  if [ $(echo info | bluetoothctl | grep 'Device' | wc -c) -eq 0 ]
  then
    echo "%{F#EEEEEE}"
  fi
#connected
  echo "%{F#3083DC}"
fi

