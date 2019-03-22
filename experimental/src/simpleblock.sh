#!/bin/sh

# SUBROUTINES

# Send notifications to stderr
_notify() {
    [ $_verbosity -gt 0 ] && echo "$1" 1>&2
}


# VARIABLE DEFAULTS
HOME="$(getent passwd hostsblock | cut -d':' -f 6)"
hostsfile="$HOME/hosts.block"
redirecturl="127.0.0.1"
blocklists="$HOME/simpleblock.list"
blacklist="$HOME/black.list"
whitelist="$HOME/white.list"
hostshead="0"
cachedir="$HOME/cache"
connect_timeout=60
retry=0
_verbosity=1
_check=0
max_simultaneous_downloads=4
[ -f "$HOME"/changed ] && rm -f "$HOME"/changed

# GET OPTIONS
while getopts "qvf:huc:" _option; do
    case "$_option" in
        f)  [ "$OPTARG" != "" ] && _configfile="$OPTARG";;
        v)  _verbosity=2;;
        u)
            touch "$HOME"/changed
        ;;
        *)
            cat << EOF
Usage:
  $0 [ OPTIONS ] - generate a HOSTS file with block and redirection lists

Help Options:
  -h                  Show help options

Application Options:
  -f CONFIGFILE       Specify an alternative configuration file (instead of /var/lib/hostsblock/simpleblock.conf)
  -v                  Be verbose
  -u                  Force hostsblock to update its target file, even if no changes to source files are found
EOF
            exit 1
        ;;
    esac
done

# SOURCE CONFIG FILE
if [ $_configfile ]; then
    if [ -f "$_configfile" ]; then
    . "$_configfile"
    elif [ $(whoami) != "root" ] && [ -f ${HOME}/.config/hostsblock/simpleblock.conf ]; then
        . ${HOME}/.config/hostsblock/simpleblock.conf
    elif [ $(whoami) != "root" ] && [ -f ${HOME}/simpleblock.conf ]; then
        . ${HOME}/simpleblock.conf
    elif [ -f /etc/hostsblock/simpleblock.conf ]; then
        . /etc/hostsblock/simpleblock.conf
    fi
elif [ $(whoami) != "root" ] && [ -f ${HOME}/.config/hostsblock/simpleblock.conf ]; then
    . ${HOME}/.config/hostsblock/simpleblock.conf
elif [ $(whoami) != "root" ] && [ -f ${HOME}/simpleblock.conf ]; then
    . ${HOME}/simpleblock.conf
elif [ -f /etc/hostsblock/simpleblock.conf ]; then
    . /etc/hostsblock/simpleblock.conf
fi

# SET VERBOSITY FOR SCRIPT AND ITS SUBPROCESSES
if [ $_verbosity -eq 0 ]; then
    _v=""
    _v_curl="-s"
    _v_unzip="-qq"
    set +x
else
   _v="-v"
   _v_curl="-v"
   _v_unzip="-v"
   set -x
fi

# CHECK FOR CORRECT PRIVILEDGES AND DEPENDENCIES
if [ $(whoami) != "hostsblock" ]; then
    _notify "WRONG PERMISSIONS. RUN AS USER hostsblock, EITHER DIRECTLY OR VIA SUDO, E.G. sudo -u hostsblock $0 $@\n\nYou may have to add the following line to the end of sudoers after typing 'sudo visudo':\n $(whoami)	ALL	=	(hostblock)	NOPASSWD:	$0\n\nExiting..."
    exit 3
fi

# MAKE SURE NECESSARY DEPENDENCIES ARE PRESENT
for _depends in mv cp rm b2sum curl grep sed tr cut mkdir file; do
    if which "$_depends" >/dev/null 2>&1; then
        true
    else
        _notify "MISSING REQUIRED DEPENDENCY $_depends. PLEASE INSTALL. EXITING..."
        exit 5
    fi
done


# NORMAL PROCESS
# CHECK FOR OPTIONAL DECOMPRESSION DEPENDENCIES
if which unzip >/dev/null 2>&1; then
    _unzip_available=1
else
    _notify "Dearchiver for zip NOT FOUND. Optional functions which use this format will be skipped."
    _unzip_available=0
fi

if which 7za >/dev/null 2>&1; then
    _7zip_available="7za"
elif which 7z >/dev/null 2>&1; then
    _7zip_available="7z"
else
    _notify "Dearchiver for 7za NOT FOUND. Optional functions which use this format will be skipped."
    _7zip_available=0
fi

# IDENTIFY WHAT WILL not BE OUR REDIRECTION URL
if [ "$redirecturl" = "127.0.0.1" ]; then
    _notredirect="0.0.0.0"
else
    _notredirect="127.0.0.1"
fi

# DOWNLOAD BLOCKLISTS
_notify "Checking blocklists for updates..."

sed "s/#.*//g" "$blocklists" | grep -ve "^$" -ve "^[:space:]*$" | while read _url; do
    _outfile=$(echo $_url | sed -e "s|http:\/\/||g" -e "s|https:\/\/||g" | tr '/%&+?=' '.')
    [ -f "$cachedir"/"$_outfile" ] && _old_sha1sum=$(b2sum < "$cachedir"/"$_outfile")

    # Make process wait until the number of curl processes are less than $max_simultaneous_downloads
    until [ $(pidof curl | wc -w) -lt $max_simultaneous_downloads ]; do
        sleep $(pidof sleep | wc -w)
    done

# Add a User-Agent and referer string when needed
    if curl $_v_curl --compressed -L --connect-timeout $connect_timeout --retry $retry -z "$cachedir"/"$_outfile" "$_url" -o "$cachedir"/"$_outfile"; then
        _new_sha1sum=$(b2sum < "$cachedir"/"$_outfile")
        if [ "$_old_sha1sum" != "$_new_sha1sum" ]; then
            _notify 1 "Changes found to $_url"
            touch "$HOME"/changed
        fi
    else
        _notify 0 "FAILED to refresh/download blocklist $_url"
    fi
done &
wait

# IF THERE ARE CHANGES...
if [ -f "$HOME"/changed ]; then
    _notify "Changes found among blocklists. Extracting and preparing cached files to working directory..."

    # INCLUDE HOSTS.HEAD FILE AS THE BEGINNING OF THE NEW TARGET HOSTS FILE
    [ "$hostshead" != "0" ] && cp $_v -f -- "$hostshead" "$hostsfile"

    # EXTRACT ENTRIES DIRECTLY FROM CACHED FILES 
    for _cachefile in "$cachedir"/*; do
            _cachefile_type=$(file -bi "$_cachefile")
            if echo "$_cachefile_type" | grep -q 'application/zip'; then
                if [ $_unzip_available != 0 ]; then
                    unzip -B -o -j -p $_v_unzip -- "$_cachefile" 
                else
                    _notify 2 "${_cachefile##*/} is a zip archive, but an extractor is NOT FOUND. Skipping..."
                    continue
                fi
            elif echo "$_cachefile_type" | grep -q 'application/x-7z-compressed'; then
                if [ $_7zip_available != 0 ]; then
                    eval $_7zip_available e -so "$_cachefile" 
                else
                    _notify 2 "${_cachefile##*/} is a 7z archive, but an extractor is NOT FOUND. Skipping..."
                    continue
                fi
            else
                grep -e "0\.0\.0\.0" -e "127\.0\.0\.1" "$_cachefile" 
            fi
    done | grep -e "127\.0\.0\.1" -e "0\.0\.0\.0" sed -e "s/#.*//g" -e "s/^[[:space:]]*//g" -e \
      "s/[[:space:]]*$//g" -e "s/[[:space:]]/ /g" -e "s/$_notredirect/$redirecturl/g" | tr -s ' ' | \
      sort -u | grep -Fvf "$whitelist" >> "$hostsfile"

    if [ $? -ne 0 ]; then
        _notify 0 "FAILED TO COMPILE BLOCK ENTRIES INTO $hostsfile. EXITING..."
        exit 2
    fi

    # APPEND BLACKLIST ENTRIES
    while read _blacklistline; do
        grep -Fqx "$_blacklistline" "$hostsfile" || echo "$redirecturl $_blacklistline" >> "$hostsfile"
    done < "$blacklist" 
else
    _notify "No new changes. DONE."
fi

