#!%SHPATH%
if command -v getent >/dev/null 2>&1; then
    _home=$(getent passwd hostsblock | cut -d: -f6)
else
    _home=$(sudo -u hostsblock -H sh -l -c "cd; pwd")
fi
pwd=$(pwd)
if [ "$(id -un)" = "hostsblock" ]; then
    exec %PREFIX%/lib/hostsblock.sh "$@"
else
    exec sudo -u hostsblock -H %PREFIX%/lib/hostsblock.sh "$@"
fi
cd "$pwd"
