#!/bin/sh

_msg() {
    printf %s\\n "$1" 1>&2
}

_mkdir() {
    # $1 = dir to be made; $2 = chmod hex; $3 = owner:group
    if [ ! -d "$1" ]; then
        mkdir -p -m "$2" "$1"
        chown "$3" "$1"
    fi
}

_install() {
    #$1 = source; $2 = destination; $3 = chmod hex $4 = owner:group
    sed -e "s/%PREFIX%/$PREFIX/g" -e "s/%SYSTEMCTLPATH%/$SYSTEMCTLPATH/g" -e "s/%SHPATH%/$SHPATH/g" -e "s/%_HOME%/$_HOME/g" "$1" > "$2"
    chmod "$3" "$2"
    chown "$4" "$2"
}

# Parameters
SRCDIR="${SRCDIR:-./}"                         # Assuming we are running this script from the root directory of our source code
PREFIX="${PREFIX:-/usr}"                       # Default installation of hostsblock.sh under /usr/bin/

# If these paths are not asserted via environment variables, autodetect them
if [ ! -d "$SYSTEMD_DIR" ]; then
    if [ -d /usr/lib/systemd/system ]; then
        SYSTEMD_DIR="/usr/lib/systemd/system"
    elif [ -d /lib/systemd/system ]; then
        SYSTEMD_DIR="/lib/systemd/system/"
    elif [ -d /etc/systemd/system ]; then
        SYSTEMD_DIR="/etc/systemd/system"
    else
        SYSTEMD_DIR="$PREFIX"/lib/systemd/system
    fi
fi
if [ ! -x "$SYSTEMCTLPATH" ]; then
    SYSTEMCTLPATH=$(command -v systemctl)
    if [ ! -x "$SYSTEMCTLPATH" ]; then
        if [ -x /usr/bin/systemctl ]; then
            SYSTEMCTLPATH="/usr/bin/systemctl"
        elif [ -x /bin/systemctl ]; then
            SYSTEMCTLPATH="/bin/systemctl"
        else
            SYSTEMCTLPATH="$PREFIX"/bin/systemctl
        fi
    fi
fi
if [ ! -x "$SHPATH" ]; then
    SHPATH=$(command -v sh)
    if [ ! -x "$SHPATH" ]; then
        if [ -x /usr/bin/sh ]; then
            SHPATH="/usr/bin/sh"
        elif [ -x /bin/sh ]; then
            SHPATH="/bin/sh"
        else
            SHPATH="$PREFIX"/bin/sh
        fi
    fi
fi

if [ "$1" != "install" ]; then
# Warning
_msg "WARNING: This script will install hostblock and its configuration files with
exclusive permissions for their owner, the user 'hostsblock'. If this user does
not yet exist, it will create it with a home directory under
/var/lib/hostsblock. If you do not want the home directory here, please create
user hostsblock and set its home directory yourself before running this script,
or install hostsblock manually.

Variables effecting installation:
 \$SRCDIR (currently $SRCDIR): the root directory of the source code
 \$PREFIX (currently $PREFIX): parent directory of bin folder into which
  hostsblock.sh installs
 \$SYSTEMD_DIR (currently $SYSTEMD_DIR): where systemd unit files
  will install
 \$SYSTEMCTLPATH (currently $SYSTEMCTLPATH): where systemd unit files
  will look for the systemctl executable
 \$SHPATH (currently $SHPATH): where hostsblock and its systemd unit
  files will look for the shell command. (Hint: Point this to dash instead
  of bash if you want a performance boost)

If you are read to install, execute '$0 install'"
 exit 0
fi

# Check if this script is running as root.
if [ "$$(id -un)" != "root" ]; then
    _msg "Run this script as root or via sudo, e.g. sudo $0 install"
    exit 2
fi

# Dependency check for both this installation script and host block
for _dep in groupadd useradd gpasswd chown tr mkdir cksum curl touch rm sed grep file sort tee cut cp mv chmod find xargs id wc; do
    if ! command -v $_dep >/dev/null 2>&1; then
        _msg "Dependency $_dep missing. Please install."
        exit 3
    fi
done

# Opt dependency checks
if ! command -v unzip >/dev/null 2>&1; then
    _msg "WARNING: Optional dependency unzip missing. You will not be able to extract zipped block files without it."
fi
if ! ( command -v 7zr >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1 ); then
    _msg "WARNING: Optional dependency p7zip missing. You will not be able to extract 7zipped block files without it."
fi

# Check for/create hostsblock user
if ! getent user hostsblock >/dev/null 2>&1 && ! getent group hostsblock >/dev/null 2>&1; then
    useradd -m -d /var/lib/hostsblock -s /bin/sh -U hostsblock
elif ! getent user hostsblock >/dev/null 2>&1; then
    useradd -m -d /var/lib/hostsblock -s /bin/sh -G hostsblock hostsblock
elif ! getent group hostsblock >/dev/null 2>&1; then
    groupadd hostsblock
    gpasswd -a hostsblock hostsblock
fi
_HOME=$(getent passwd hostsblock | cut -f6 -d:)

# Install config examples into home directory
_mkdir "$_HOME" 755 hostsblock:hostsblock
_install "$SRCDIR"/src/hostsblock.sh "$PREFIX"/lib/hostsblock.sh 500 hostsblock:hostsblock
_install "$SRCDIR"/src/hostsblock-wrapper.sh "$PREFIX"/bin/hostsblock 550 hostsblock:hostsblock
_mkdir "$_HOME"/config.examples 700 hostsblock:hostsblock
for _conffile in hostsblock.conf black.list white.list hosts.head block.urls redirect.urls; do
    _install "$SRCDIR"/conf/"$_conffile" "$_HOME"/config.examples/"$_conffile" 600 hostsblock:hostsblock
done
_mkdir "$SYSTEMD_DIR" 755 root:root
for _sysdfile in hostsblock.service hostsblock.timerhostsblock-dnsmasq-restart.path hostsblock-dnsmasq-restart.service hostsblock-hosts-clobber.path hostsblock-hosts-clobber.service; do
    _install "$SRCDIR"/systemd/"$_sysdfile" "$SYSTEMD_DIR"/"$_sysdfile" 444 root:root
done

systemctl daemon-reload

_msg "hostsblock installed. To configure it, please follow the
directions here: https://github.com/gaenserich/hostsblock#config"
