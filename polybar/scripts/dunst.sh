#!/bin/sh
if [ $(dunstctl is-paused | grep "false" | wc -c) -eq 0 ]
then
  echo "%{F#FB543F}"
else
  if [ $(echo info | dunstctl is-paused | grep "true"| wc -c) -eq 0 ]
  then
    echo "%{F#7E8772}"
  fi
  
    echo ""
fi
  
 
