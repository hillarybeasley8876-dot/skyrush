#!/bin/zsh
# usage: ./run.sh <seconds> <godot args...>   (macOS has no `timeout`; SIGALRM kills godot)
secs=$1; shift
perl -e 'alarm shift; exec @ARGV' "$secs" /opt/homebrew/bin/godot "$@"
