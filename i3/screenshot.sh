#!/bin/bash
slop=$(slop -f "%g") || exit 1
read -r G < <(echo $slop)
datetime=$(date '+%Y-%m-%d_%H-%M-%S')
filename="$HOME/Pictures/screenshot_${datetime}.png"
import -window root -crop $G "$filename" && eog "$filename"
