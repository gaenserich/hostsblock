#!/bin/bash

# Install script for hostsblock.

msg() {
    echo "$@" | fold -s
}

if [ "$(whoami)" != "root" ]; then
    msg "$0 must be run as root or via sudo, e.g. 'sudo $0'. Exiting..."
    exit 1
fi

for dep in getent grep useradd usermod groupadd gpasswd cut ps chmod chown pidof stat fold; do
    if command -v $dep &>/dev/null; then
        true
    else
        msg "$dep utility missing. Please install before running this script. Exiting..."
        exit 2
    fi
done

DESTDIR="/usr/bin"
_destdir_ok=0
until [ $_destdir_ok -eq 1 ]; do
    msg "Destination directory for hostsblock is $DESTDIR. Enter a new path or press Enter to keep as is."
    read -rp "[$DESTDIR] " d
    if echo "$d" | grep -q "\\/$"; then
        DESTDIR="${d%/}"
    elif [ "$d" != "" ]; then
        DESTDIR="$d"
    fi
    if  echo "$PATH" | tr ':' '\n' | grep -q "^${DESTDIR}$"; then
        _destdir_ok=1
    else
        y="n"
        msg "Your destination directory $DESTDIR is not in your \$PATH. Use $DESTDIR anyway?"
        read -rp "[y/N] " y
        if [ "$y" != "y" ] || [ "$y" != "Y" ]; then
            _destdir_ok=0
        else
            _destdir_ok=1
        fi
    fi
    if [ $_destdir_ok -eq 1 ]; then
        n="y"
        msg "Are you sure you want to use $DESTDIR as your destination directory?"
        read -rp "[Y/n] " n
        if [ "$n" == "n" ] || [ "$n" == "N" ]; then
            _destdir_ok=0
        fi
    fi
done

if getent passwd | grep -q "^hostsblock:"; then
    echo "Using preexisting user 'hostsblock'"
    _homedir_ok=0
    _homedir_changed=0
    HOMEDIR=$(getent passwd hostsblock | cut -d':' -f6)
    until [ $_homedir_ok -eq 1 ]; do
        msg "User 'hostsblock' has home directory $HOMEDIR. Enter a new path or press Enter to keep as is."
        read -rp "[$HOMEDIR] " h
        if echo "$h" | grep -q "\\/$"; then
            HOMEDIR="${h%/}"
            _homedir_changed=1
        elif [ "$h" != "" ]; then
            HOMEDIR="$h"
            _homedir_changed=1
        fi
        if [ -d "$HOMEDIR" ]; then
            if [ $_homedir_changed -eq 0 ]; then
                _homedir_ok=1
            else
                y="n"
                msg "$HOMEDIR already exists. Installing hostsblock here will potentially overwrite existing files. Are you sure you want to use $HOMEDIR as hostsblock's home directory?"
                read -rp "[y/N] " y
                if [ "$y" == "y" ] || [ "$y" == "Y" ]; then
                    _homedir_ok=1
                fi
            fi
        else
            _homedir_ok=1
        fi
        if [ $_homedir_ok -eq 1 ]; then
            n="y"
            msg "Are you sure you want to use $HOMEDIR as hostsblock's home directory?"
            read -rp "[Y/n] " n
            if [ "$n" == "n" ] || [ "$n" == "N" ]; then
                _homedir_ok=0
            fi
        fi
    done
    if [ $_homedir_changed -eq 1 ]; then
        n="y"
        msg "Should the content from the previous home directory be moved to this new directory?"
        read -rp "[Y/n] " n
        if [ "$n" == "n" ] || [ "$n" == "N" ]; then
            usermod -d "$HOMEDIR" -m hostsblock
        else
            usermod -d "$HOMEDIR" hostsblock
        fi
    fi
    if getent group hostsblock; then
        msg "Using preexisting group 'hostsblock'"
    else
        msg "Creating group 'hostsblock'..."
        groupadd hostsblock
    fi
    gpasswd -a hostsblock hostsblock
else
    HOMEDIR="/var/lib/hostsblock"
    _homedir_ok=0
    until [ $_homedir_ok -eq 1 ]; do
        msg "Creating user and group 'hostsblock' with home directory $HOMEDIR. Enter a new path or press Enter to keep as is."
        read -rp "[$HOMEDIR] " h
        if echo "$h" | grep -q "\\/$"; then
            HOMEDIR="${h%/}"
        elif [ "$h" != "" ]; then
            HOMEDIR="$h"
        fi
        if [ -d "$HOMEDIR" ]; then
            y="n"
            msg "$HOMEDIR already exists. Installing hostsblock here will potentially overwrite existing files. Are you sure you want to use $HOMEDIR as hostsblock's home directory?"
            read -rp "[y/N] " y
            if [ "$y" == "y" ] || [ "$y" == "Y" ]; then
                _homedir_ok=1
            fi
        else
            _homedir_ok=1
        fi
        if [ $_homedir_ok -eq 1 ]; then
            n="y"
            msg "Are you sure you want to use $HOMEDIR as hostsblock's home directory?"
            read -rp "[Y/n] " n
            if [ "$n" == "n" ] || [ "$n" == "N" ]; then
                _homedir_ok=0
            fi
        fi
    done
    msg "Creating user and group 'hostsblock' with home directory $HOMEDIR..."
    useradd -d "$HOMEDIR" -c "hostblock" -m -U hostsblock
fi

gpasswd -A hostsblock hostsblock

if pidof dnsmasq; then
    dnsmasq_user=$(ps -o user= -p "$(pidof dnsmasq)")
    if getent group hostsblock | cut -d":" -f4 | tr ',' '\n' | grep -q "^${dnsmasq_user}$"; then
        gpasswd -M "$dnsmasq_user" hostsblock
    else
        msg "You appear to be running dnsmasq under user $dnsmasq_user. If you will be using hostsblock with dnsmasq as a caching daemon, dnsmasq needs read access to hostsblock's home directory. To do so, should I add $dnsmasq_user to the hostblock group?"
        e="n"
        read -rp "[y/N] " e
        if [ "$e" == "y" ] || [ "$e" == "Y" ]; then
            gpasswd -a "$dnsmasq_user" hostsblock
            gpasswd -M "$dnsmasq_user" hostsblock
        fi
    fi
else
    msg "If you are using hostsblock with a dns cacher, you should add the user under which the cacher runs to the 'hostsblock' group so that the daemon can access your generated host file. Enter the user of the DNS daemon or leave blank to add no additional user."
    read -rp "[No DNS user] " dns
    if [ "$dns" != "" ]; then
        gpasswd -a "$dns" hostsblock
        gpasswd -M "$dns" hostsblock
    fi
fi

msg "In order to manage hostsblock correctly, you must run the script as the user 'hostsblock', even when using the 'hostsblock-urlcheck' script (aka 'hostsblock -c'). To do so, type 'sudo -u hostsblock hostsblock' or 'sudo -u hostsblock hostsblock-urlcheck', etc. Before you can do this, however, the following line must be added to sudoers:"
printf "\\n"
echo "jake	ALL	=	(hostsblock)	NOPASSWD: $DESTDIR/hostsblock,$DESTDIR/hostsblock-urlcheck"
printf "\\n"
msg "where 'jake' is the user from which you want to manage hostsblock. Do you want to add this line to the bottom of sudoers right now? (if so, make sure to copy the text now)."
read -rp "[y/N] " dosu
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

[ ! -d "$DESTDIR" ] && mkdir -p "$DESTDIR"
install -Dm755 src/hostsblock.sh "$DESTDIR"/hostsblock
ln -sf "$DESTDIR"/hostsblock "$DESTDIR"/hostsblock-urlcheck
[ ! -d "$HOMEDIR" ] && mkdir -p "$HOMEDIR"
install -Dm644 conf/hostsblock.conf "$HOMEDIR"/hostsblock.conf
install -Dm644 conf/black.list "$HOMEDIR"/black.list
install -Dm644 conf/white.list "$HOMEDIR"/white.list
install -Dm644 conf/hosts.head "$HOMEDIR"/hosts.head
install -Dm644 systemd/hostsblock.service "$systemd_dir"/
install -Dm644 systemd/hostsblock.timer "$systemd_dir"/

msg "Setting up permissions for hostsblock home directory $HOMEDIR..."
chown -R hostsblock:hostsblock "$HOMEDIR"
chmod 755 "$HOMEDIR"
_dir="$HOMEDIR"
while [ ${#_dir} -gt 0 ]; do
    if [ "$(stat -c%G "$_dir")" == "hostsblock" ]; then
        chmod g+x "$_dir"
    else
        chmod o+x "$_dir"
    fi
    _dir="${_dir%/*}"
done

msg "Should I enable and/or start the hostsblock service? (Requires systemd)"
printf "\\t"
msg "1) Only Enable"
printf "\\t"
msg "2) Only Start"
printf "\\t"
msg "3)Start and Enable"
printf "\\t"
msg "4) Do Nothing (Default)"
read -rp "[1-4] " start
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

msg "hostsblock is now installed. Check out the configuration file under $HOMEDIR/hostsblock.conf. By default, hostsblock does not directly write to /etc/hosts or manipulate your dnsmasq daemon. To make it do so, see the instructions included in $HOMEDIR/hostsblock.conf"
