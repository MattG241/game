#!/bin/bash
# rec.sh NAME FRAMES WxH [extra args]
name=$1; frames=$2; res=$3; shift 3
out=/tmp/claude-0/trailer/hd/$name.avi
rm -rf /tmp/claude-0/trailerhome/$name; mkdir -p /tmp/claude-0/trailerhome/$name
cd /home/user/game/godot
XDG_DATA_HOME=/tmp/claude-0/trailerhome/$name timeout 2400 xvfb-run -a -s "-screen 0 ${res}x24" godot --rendering-driver opengl3 --resolution $res --write-movie $out --fixed-fps 30 --path . res://tests/trailer.tscn -- --clip=$name --frames=$frames "$@" > /tmp/claude-0/trailer/hd/$name.log 2>&1
echo "$name $(ls -la $out 2>/dev/null | awk '{print $5}')"
