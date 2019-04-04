#!/bin/sh
if [ "$(whoami)" = "hostsblock" ]; then
    exec %PREFIX%/lib/hostsblock.sh "$@"
else
    exec sudo -u hostsblock %PREFIX%/lib/hostsblock.sh "$@"
fi
