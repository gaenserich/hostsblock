#!/bin/sh

_msg() {
    printf %s\\n "$1" 1>&2
}

# Parameters
SRCDIR="${SRCDIR:-./}"                         # Assuming we are running this script from the root directory of our source code
PREFIX="${PREFIX:-/usr}"                       # Default installation of hostsblock.sh under /usr/bin/
SYSTEMD_DIR="${SYSTEMD_DIR:-/usr/lib/systemd/system}" #

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

If you are read to install, execute '$0 install'"
 exit 0
fi

# Check if this script is running as root.
if [ "$$(id -un)" != "root" ]; then
    _msg "Run this script as root or via sudo, e.g. sudo $0 install"
    exit 2
fi

# Dependency check for both this installation script and host block
for _dep in groupadd install useradd gpasswd chown tr mkdir cksum curl touch rm sed grep file sort tee cut cp mv chmod find xargs id wc; do
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
[ -d "$_HOME" ] && mkdir -p -m 755 "$_HOME" || chmod 755 "$_HOME"
install -Dm500 "$SRCDIR"/src/hostsblock.sh "$PREFIX"/lib/hostsblock.sh
sed "s/%PREFIX%/$PREFIX/g" "$SRCDIR"/src/hostsblock-wrapper.sh > "$PREFIX"/bin/hostsblock
chmod 550 "$PREFIX"/hostsblock
install -Dm600 -g hostsblock -o hostsblock "$SRCDIR"/conf/hostsblock.conf "$_HOME"/config.examples/hostsblock.conf
install -Dm600 -g hostsblock -o hostsblock "$SRCDIR"/conf/black.list "$_HOME"/config.examples/black.list
install -Dm600 -g hostsblock -o hostsblock "$SRCDIR"/conf/white.list "$_HOME"/config.examples/white.list
install -Dm600 -g hostsblock -o hostsblock "$SRCDIR"/conf/hosts.head "$_HOME"/config.examples/hosts.head
install -Dm600 -g hostsblock -o hostsblock "$SRCDIR"/conf/block.urls "$_HOME"/config.examples/block.urls
install -Dm600 -g hostsblock -o hostsblock "$SRCDIR"/conf/redirect.urls "$_HOME"/config.examples/block.urls
install -Dm444 "$SRCDIR"/systemd/hostsblock.service "$SYSTEMD_DIR"/hostsblock.service
install -Dm444 "$SRCDIR"/systemd/hostsblock.timer "$SYSTEMD_DIR"/hostsblock.timer
install -Dm444 "$SRCDIR"/systemd/hostsblock-dnsmasq-restart.path "$SYSTEMD_DIR"/hostsblock-dnsmasq-restart.path
install -Dm444 "$SRCDIR"/systemd/hostsblock-dnsmasq-restart.service "$SYSTEMD_DIR"/hostsblock-dnsmasq-restart.service
install -Dm444 "$SRCDIR"/systemd/hostsblock-hosts-clobber.path "$SYSTEMD_DIR"/hostsblock-hosts-clobber.path
install -Dm444 "$SRCDIR"/systemd/hostsblock-hosts-clobber.service "$SYSTEMD_DIR"/hostsblock-hosts-clobber.service

systemctl daemon-reload

_msg "hostsblock installed. To configure it, please follow the
directions here: https://github.com/gaenserich/hostsblock#config"
