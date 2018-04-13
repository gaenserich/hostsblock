#!/bin/bash

# Install script for hostsblock.

if [ "$(whoami)" != "root" ]; then
    echo "$0 must be run as root or via sudo, e.g. 'sudo $0'. Exiting..."
    exit 1
fi

for dep in getent grep useradd groupadd gpasswd cut ps chmod chown; do
    if which $dep &>/dev/null; then
        true
    else
        echo "$dep utility missing. Please install before running this script. Exiting..."
        exit 2
    fi
done

DESTDIR="/usr/bin/"
echo "Destination directory for hostsblock is $DESTDIR. Enter a new path or press Enter to keep as is."
read -p "$DESTDIR " d
if [ "$d" != "" ] || [[ -n $d ]]; then
    DESTDIR="$d"
fi

if getent passwd | grep -q "^hostsblock:"; then
    echo "Using preexisting user 'hostsblock'"
else
    HOMEDIR="/var/lib/hostsblock"
    echo "Creating user and group 'hostsblock' with home directory $HOMEDIR. Enter a new path or press Enter to keep as is."
    read -p "$HOMEDIR " h
    if [ "$h" != "" ] || [[ -n $h ]]; then
        HOMEDIR="$h"
    fi
    echo "Creating user and group 'hostsblock' with home directory $HOMEDIR..."
    useradd -d "$HOMEDIR" -c "hostblock" -m -U hostsblock
fi

if getent group | grep -q "^hostsblock:"; then
    echo "Using preexisting group 'hostsblock'"
else
    echo "Creating group 'hostsblock'..."
    groupadd hostsblock
fi

gpasswd -a hostsblock hostsblock
gpasswd -A hostsblock hostsblock

if ps aux | grep '[d]nsmasq' | tr -s ' ' | cut -d' ' -f 11- | grep -q '[d]nsmasq'; then
    dnsmasq_user=$(ps aux | grep '[d]nsmasq' | tr -s ' ' | cut -d' ' -f 1)
    echo -e "You appear to be running dnsmasq under user $dnsmasq_user. If you will be using hostsblock\nwith dnsmasq as a caching daemon, dnsmasq needs read access to hostsblock's home directory.\nTo do so, should I add $dnsmasq_user to the hostblock group?"
    read -p "y/N " e
    if [ "$e" == "y" ] || [ "$e" == "Y" ]; then
        gpasswd -a "$dnsmasq_user" hostsblock
        gpasswd -M "$dnsmasq_user" hostsblock
    fi
else
    echo -e "If you are using hostsblock with a dns cacher, you should add the user under which the cacher\nruns to the 'hostsblock' group so that the daemon can access your generated host file.\nEnter the user of the DNS daemon or leave blank to add no additional user."
    read -p "[No DNS user] " dns
    if [ "$dns" != "" ] || [[ -n $dns ]]; then
        gpasswd -a "$dns" hostsblock
        gpasswd -M "$dns" hostsblock
    fi
fi

echo -e "In order to manage hostsblock correctly, you must run the script as the user 'hostsblock',\neven when using the 'hostsblock-urlcheck' script (aka 'hostsblock -c').\nTo do so, type 'sudo -u hostsblock hostsblock' or 'sudo -u hostsblock hostsblock-urlcheck', etc.\nBefore you can do this, however, the following line must be added to sudoers:\n\njake	ALL	=	(hostsblock)	NOPASSWD: $DESTDIR/hostsblock,$DESTDIR/hostsblock-urlcheck\n\nwhere 'jake' is the user from which you want to manage hostsblock.\nDo you want to add this line to the bottom of sudoers right now? (if so, make sure to copy the text now)."
read -p "[y/N] " dosu
if [ "$dosu" == "Y" ] || [ "$dosu" == "y" ]; then
    visudo
fi


if [ -d /usr/lib/systemd/system ]; then
    systemd_dir="/usr/lib/systemd/system"
elif [ -d /lib/systemd/system ]; then
    systemd_dir="/lib/systemd/system"
else
    systemd_dir="/etc/systemd/system"
fi

install -Dm755 src/hostsblock.sh "$DESTDIR"/hostsblock
ln -sf "$DESTDIR"/hostsblock "$DESTDIR"/hostsblock-urlcheck
install -Dm644 conf/hostsblock.conf "$HOMEDIR"/hostsblock.conf
install -Dm644 conf/black.list "$HOMEDIR"/black.list
install -Dm644 conf/white.list "$HOMEDIR"/white.list
install -Dm644 conf/hosts.head "$HOMEDIR"/hosts.head
install -Dm644 systemd/hostsblock.service "$systemd_dir"/
install -Dm644 systemd/hostsblock.timer "$systemd_dir"/

echo "Setting up permissions for hostsblock home directory $HOMEDIR..."
chown -R hostsblock:hostsblock "$HOMEDIR"
chmod 755 "$HOMEDIR"

echo -e "Should I enable and/or start the hostsblock service? (Requires systemd)\n\t1) Only Enable\n\t2) Only Start\n\t3)Start and Enable\n\t4) Do Nothing (Default)"
read -p "[1-4] " start
case "$start" in
    1)
        systemctl daemon-reload
        systemctl enable hostsblock.timer
    ;;
    2)
        systemctl daemon-reload
        systemctl start hostsblock.timer hostsblock.service
    ;;
    3)
        systemctl daemon-reload
        systemctl --now enable hostsblock.timer
        systemctl start hostsblock.service
    ;;
    *)
        true
    ;;
esac

echo -e "hostsblock is now installed. Check out the configuration file under $HOMEDIR/hostsblock.conf.\nBy default, hostsblock does not directly write to /etc/hosts or manipulate your dnsmasq daemon.\nTo make it do so, see the instructions included in $HOMEDIR/hostsblock.conf"
