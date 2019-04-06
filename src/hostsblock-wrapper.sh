#!/bin/sh
_home=$(sudo -u hostsblock -H sh -l -c "cd; pwd")
pwd=$(pwd)
if [ "$(id -un)" = "hostsblock" ]; then
    exec %PREFIX%/lib/hostsblock.sh "$@"
else
    exec sudo -u hostsblock -H %PREFIX%/lib/hostsblock.sh "$@"
fi
cd "$pwd"
