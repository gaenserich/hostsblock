#!/bin/bash

# Install script for hostsblock.

if [ "$(whoami)" != "root" ]; then
    echo "$0 must be run as root or via sudo, e.g. 'sudo $0'. Exiting..."
    exit 1
fi

for dep in getent grep useradd usermod groupadd gpasswd cut ps chmod chown pidof stat; do
    if command -v $dep &>/dev/null; then
        true
    else
        echo "$dep utility missing. Please install before running this script. Exiting..."
        exit 2
    fi
done

DESTDIR="/usr/bin"
_destdir_ok=0
until [ $_destdir_ok -eq 1 ]; do
    echo "Destination directory for hostsblock is $DESTDIR. Enter a new path or press Enter to keep as is."
    read -p "$DESTDIR " d
    if echo "$d" | grep -q "\/$"; then
        DESTDIR="${d%/}"
    elif [ "$d" != "" ]; then
        DESTDIR="$d"
    fi
    if  echo $PATH | tr ':' '\n' | grep -q "^${DESTDIR}$"; then
        _destdir_ok=1
    else
        y="n"
        read -p "Your destination directory $DESTDIR is not in your \$PATH. Use $DESTDIR anyway? [y/N] " y
        if [ "$y" != "y" ] || [ "$y" != "Y" ]; then
            _destdir_ok=0
        else
            _destdir_ok=1
        fi
    fi
    if [ $_destdir_ok -eq 1 ]; then
        n="y"
        read -p "Are you sure you want to use $DESTDIR as your destination directory? [Y/n] " n
        if [ "$n" == "n" ] || [ "$n" == "N" ]; then
            _destdir_ok=0
        fi
    fi
done

if getent passwd | grep -q "^hostsblock:"; then
    echo "Using preexisting user 'hostsblock'"
    _homedir_ok=0
    _homedir_changed=0
    HOMEDIR=$(getent passwd | grep "^hostsblock:" | cut -d':' -f6)
    until [ $_homedir_ok -eq 1 ]; do
        echo "User 'hostsblock' has home directory $HOMEDIR. Enter a new path or press Enter to keep as is."
        read -p "$HOMEDIR " h
        if echo "$h" | grep -q "\/$"; then
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
                echo "$HOMEDIR already exists. Installing hostsblock here will potentially overwrite existing files."
                read -p "Are you sure you want to use $HOMEDIR as hostsblock's home directory? [y/N] " y
                if [ "$y" == "y" ] || [ "$y" == "Y" ]; then
                    _homedir_ok=1
                fi
            fi
        else
            _homedir_ok=1
        fi
        if [ $_homedir_ok -eq 1 ]; then
            n="y"
            read -p "Are you sure you want to use $HOMEDIR as hostsblock's home directory? [Y/n] " n
            if [ "$n" == "n" ] || [ "$n" == "N" ]; then
                _homedir_ok=0
            fi
        fi
    done
    if [ $_homedir_changed -eq 1 ]; then
        n="y"
        read -p "Should the content from the previous home directory be moved to this new directory? [Y/n] " n
        if [ "$n" == "n" ] || [ "$n" == "N" ]; then
            usermod -d "$HOMEDIR" -m hostsblock
        else
            usermod -d "$HOMEDIR" hostsblock
        fi
    fi
    if getent group | grep -q "^hostsblock:"; then
        echo "Using preexisting group 'hostsblock'"
    else
        echo "Creating group 'hostsblock'..."
        groupadd hostsblock
    fi
    gpasswd -a hostsblock hostsblock
else
    HOMEDIR="/var/lib/hostsblock"
    _homedir_ok=0
    until [ $_homedir_ok -eq 1 ]; do
        echo "Creating user and group 'hostsblock' with home directory $HOMEDIR. Enter a new path or press Enter to keep as is."
        read -p "$HOMEDIR " h
        if echo "$h" | grep -q "\/$"; then
            HOMEDIR="${h%/}"
        elif [ "$h" != "" ]; then
            HOMEDIR="$h"
        if
        if [ -d "$HOMEDIR" ]; then
            y="n"
            echo "$HOMEDIR already exists. Installing hostsblock here will potentially overwrite existing files."
            read -p "Are you sure you want to use $HOMEDIR as hostsblock's home directory? [y/N] " y
            if [ "$y" == "y" ] || [ "$y" == "Y" ]; then
                _homedir_ok=1
            fi
        else
            _homedir_ok=1
        fi
        if [ $_homedir_ok -eq 1 ]; then
            n="y"
            read -p "Are you sure you want to use $HOMEDIR as hostsblock's home directory? [Y/n] " n
            if [ "$n" == "n" ] || [ "$n" == "N" ]; then
                _homedir_ok=0
            fi
        fi
    done
    echo "Creating user and group 'hostsblock' with home directory $HOMEDIR..."
    useradd -d "$HOMEDIR" -c "hostblock" -m -U hostsblock
fi

gpasswd -A hostsblock hostsblock

if pidof dnsmasq; then
    dnsmasq_user=$(ps -o user= -p $(pidof dnsmasq))
    echo -e "You appear to be running dnsmasq under user $dnsmasq_user. If you will be using hostsblock\nwith dnsmasq as a caching daemon, dnsmasq needs read access to hostsblock's home directory."
    e="n"
    read -p "To do so, should I add $dnsmasq_user to the hostblock group? [y/N] " e
    if [ "$e" == "y" ] || [ "$e" == "Y" ]; then
        gpasswd -a "$dnsmasq_user" hostsblock
        gpasswd -M "$dnsmasq_user" hostsblock
    fi
else
    echo -e "If you are using hostsblock with a dns cacher, you should add the user under which the cacher\nruns to the 'hostsblock' group so that the daemon can access your generated host file.\nEnter the user of the DNS daemon or leave blank to add no additional user."
    read -p "[No DNS user] " dns
    if [ "$dns" != "" ]; then
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

echo "Setting up permissions for hostsblock home directory $HOMEDIR..."
chown -R hostsblock:hostsblock "$HOMEDIR"
chmod 755 "$HOMEDIR"
_dir="$HOMEDIR"
while [ ${#_dir} -gt 0 ]; do
    if [ $(stat -c%G "$_dir") == "hostsblock" ]; then
        chmod g+x "$_dir"
    else
        chmod o+x "$_dir"
    fi
done

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
