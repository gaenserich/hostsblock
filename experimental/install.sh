#!/bin/sh

_msg() {
    printf %s\\n "$1" 1>&2
}

# Parameters
SRCDIR="${SRCDIR:-./}"                         # Assuming we are running this script from the root directory of our source code
PREFIX="${PREFIX:-/usr}"                       # Default installation of hostsblock.sh under /usr/bin/
SYSTEMD_DIR="${SYSTEMD_DIR:-/usr/lib/systemd/system}" #
DNSMASQ_CONF="${DNSMASQ_CONF:-/etc/dnsmasq.conf}"

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
 \$DNSMASQ_CONF (currently $DNSMASQ_CONF): file where hostsblock
  will append its configuration for dnsmasq

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
    _msg "Optional dependency unzip missing. You will not be able to extract zipped block files without it."
fi
if ! ( command -v 7zr >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1 ); then
    _msg "Optional dependency p7zip missing. You will not be able to extract 7zipped block files without it."
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
install -D -m500 -g hostsblock -o hostsblock -d "$_HOME"/config.examples
install -D -b -m600 -g hostsblock -o hostsblock "$SRCDIR"/conf/* "$_HOME"/config.examples/

# Install the script under $PREFIX/lib and the wrapper under $PREFIX/bin
install -m500 -g hostsblock -o hostsblock "$SRCDIR"/src/hostsblock.sh "$PREFIX"/lib/hostsblock.sh
[ ! -d "$PREFIX"/bin ] && mkdir -p "$PREFIX"/bin
sed "s/%PREFIX%/$PREFIX/g" "$SRCDIR"/bin/hostsblock > "$PREFIX"/bin/hostsblock
chown hostsblock:hostsblock "$PREFIX"/bin/hostsblock
chmod 550 "$PREFIX"/bin/hostsblock

# Install the systemd unit files
install -D -m444 -g root -o root "$SRCDIR"/systemd/* "$SYSTEMD_DIR"/

# Configure sudoers
_sudoers_conf_yn="y"
_msg 'Add the following line via visudo to allow select users other than root to manage hostsblock. Copy and paste this line:

    %hostsblock    ALL    =    (hostsblock)    NOPASSWD:    $PREFIX/lib/hostsblock.sh

Should I open visudo so that you can paste the above line in? [n/Y]: ' 
read _sudoers_conf_yn
if [ "$_sudoers_conf_yn" !="n" ] || [ "$_sudoers_conf_yn" != "N" ]; then
    visudo
fi
_msg "Add any users you want to allow to administer hostsblock by adding them to the
'hostsblock' group:

    gpasswd -a [your user name here] hostsblock

As that user, you will then be able to use hostsblock-urlcheck or the
hostsblock -c option through sudo, e.g.

    sudo -u hostsblock hostsblock -c 'www.google.com' status"

if command -v dnsmasq >/dev/null 2>&1; then
    _dnsmasq_conf_yn="n"
    _msg '
Do you want me to automatically configure dnsmasq to be used with hostsblock? [y/N]: '
read _dnsmasq_conf_yn
else
    _dnsmasq_conf_yn="n"
    _msg "DNSMASQ not available, so I won't attempt to configure it."
fi
if [ "$_dnsmasq_conf_yn = "y" ] || [ "$_dnsmasq_conf_yn = "Y" ]; then
    sed "s/#.*//g" "$DNSMASQ_CONF" | grep -q "\baddn-hosts=$_HOME/hosts.block\b" || printf %s "addn-hosts=$_HOME/hosts.block" >> "$DNSMASQ_CONF"
    _msg "DNSMASQ will now read $_HOME/hosts.block on start up. If you
change the $hostsfile variable in $_HOME/hostsblock.conf to
something other than $_HOME/hosts.block, make sure to also change
the add-hosts variable in $DNSMASQ_CONF as well.

Hostsblock has not configured DNSMASQ as your local dns server. To do that,
please follow the directions here:
https://wiki.archlinux.org/index.php/Dnsmasq#DNS_server"
fi

_msg "Hostsblock now uses systemd to manage postprocessing. If you want to have
dnsmasq reload after hostsblock updates or modifies its target file, type:

    sudo systemctl enable --now hostsblock-dnsmasq-restart.path

If you want replace the system's hosts file under /etc/hosts after hostblock
updates or modifies, type:

    sudo systemctl enable --now hostsblock-hosts-clobber.path

 Note: Remember to enable hostshead and include your localhost entries for this
  latter configuration.

If you deviated from the default installation settings, you may need to modify
these unit files."

##### Add legacy urllist check here #####
