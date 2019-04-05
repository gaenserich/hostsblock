#!/bin/sh
_home=$(getent passwd hostsblock | cut -d':' -f6)
pwd=$(pwd)
if [ "$(whoami)" = "hostsblock" ]; then
    exec %PREFIX%/lib/hostsblock.sh "$@"
else
    exec sudo -u hostsblock -H %PREFIX%/lib/hostsblock.sh "$@"
fi
cd "$pwd"
