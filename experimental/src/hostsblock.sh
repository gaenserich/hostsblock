#!/bin/sh

# SUBROUTINES

# Send notifications to stderr
_notify() {
    [ $_verbosity -ge $1 ] && echo "$2" 1>&2
}

_extract_from_cachefiles() {
    # $1 = $blocklists or $redirectlists, i.e. files containing lists of url files
    sed "s/#.*//g" "$1" | grep "[[:alnum:]]" | while read _url; do
        _cachefile="$cachedir"/$(echo $_url | sed -e "s|http:\/\/||g" -e "s|https:\/\/||g" | tr '/%&+?=' '.')
	_notify 1 "    Extracting from cached $_url..."
        _cachefile_type=$(file -bi "$_cachefile")
        if echo "$_cachefile_type" | grep -q 'application/zip'; then
            if [ $_unzip_available != 0 ]; then
                if ! _unzip -- "$_cachefile"; then 
                    _notify 1 "    Zip-extraction of ${_cachefile##*/} failed."
		fi
            else
                _notify 1 "${_cachefile##*/} is a zip archive, but an extractor is NOT FOUND. Skipping..."
            fi
        elif echo "$_cachefile_type" | grep -q 'application/x-7z-compressed'; then
            if [ $_un7zip_available != 0 ]; then
                if ! _un7zip -- "$_cachefile"; then
                    _notify 1 "    7zip-extraction of ${_cachefile##*/} failed."
                fi
            else
                _notify 1 "${_cachefile##*/} is a 7z archive, but an extractor is NOT FOUND. Skipping..."
            fi
        elif echo "$_cachefile_type" | grep -q 'application/x-gzip'; then
            if [ $_gunzip_available != 0]; then
                if ! _gunzip -- "$_cachefile"; then
                    _notify 1 "    Gzip-extraction of ${_cachefile##*/} failed."
                fi
            else
                _notify 1 "${_cachefile##*/} is a gzip archive, but an extractor is NOT FOUND. Skipping..."
            fi
        else
            cat "$_cachefile" 
        fi
    done | grep -I $_ipv4_match_patterns | sed -e "s/#.*//g" -e "s/^[[:space:]]*//g" -e \
      "s/[[:space:]]*$//g" -e "s/[[:space:]]/ /g" -e "s/$_notredirecturl/$redirecturl/g" | tr -s ' ' | \
      sort -u | grep -Fvf "$whitelist" >> "$hostsfile".new

    if [ $? -ne 0 ]; then
        _notify 0 "FAILED TO COMPILE BLOCK/REDIRECT ENTRIES FROM URLS IN $1 INTO $hostsfile. EXITING..."
        exit 2
    fi
}

# VARIABLE DEFAULTS
HOME="$(getent passwd hostsblock | cut -d':' -f 6)"
hostsfile="$HOME/hosts.block"
redirecturl='127.0.0.1'
blocklists="$HOME/block.urls"
redirectlists="" # Otherwise "$HOME/redirect.urls"
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
        q)  _verbosity=0;;
	v)  _verbosity=2;;
        u)
            touch "$HOME"/changed
        ;;
        *)
            cat << EOF 1>&2
Usage:
  $0 [ OPTIONS ] - generate a HOSTS file from downloaded block and redirection lists

Help Options:
  -h                  Show help options

Application Options:
  -f CONFIGFILE       Specify an alternative configuration file (instead of /var/lib/hostsblock/hostsblock.conf)
  -q                  Show only fatal errors
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
    elif [ $(whoami) != "root" ] && [ -f ${HOME}/.config/hostsblock/hostsblock.conf ]; then
        . ${HOME}/.config/hostsblock/hostsblock.conf
    elif [ $(whoami) != "root" ] && [ -f ${HOME}/hostsblock.conf ]; then
        . ${HOME}/hostsblock.conf
    elif [ -f /etc/hostsblock/hostsblock.conf ]; then
        . /etc/hostsblock/hostsblock.conf
    fi
elif [ $(whoami) != "root" ] && [ -f ${HOME}/.config/hostsblock/hostsblock.conf ]; then
    . ${HOME}/.config/hostsblock/hostsblock.conf
elif [ $(whoami) != "root" ] && [ -f ${HOME}/hostsblock.conf ]; then
    . ${HOME}/hostsblock.conf
elif [ -f /etc/hostsblock/hostsblock.conf ]; then
    . /etc/hostsblock/hostsblock.conf
fi

# SET VERBOSITY FOR SCRIPT AND ITS SUBPROCESSES
if [ $_verbosity -eq 0 ]; then
    _v=""
    _v_curl="-s"
    _v_unzip="-qq"
    _v_gzip="-q"
    set +x
elif [ $_verbosity -eq 1 ]; then
   _v=""
   _v_curl="-s"
   _v_unzip="-qq"
   _v_gzip="-q"
   set +x
else
   _v="-v"
   _v_curl="-v"
   _v_unzip="-v"
   _v_gzip="-v"
   set -x
fi

# CHECK FOR CORRECT PRIVILEDGES AND DEPENDENCIES
if [ $(whoami) != "hostsblock" ]; then
    _notify 0 "WRONG PERMISSIONS. RUN AS USER hostsblock, EITHER DIRECTLY OR VIA SUDO, E.G. sudo -u hostsblock $0 $@\n\nYou may have to add the following line to the end of sudoers after typing 'sudo visudo':\n $(whoami)	ALL	=	(hostblock)	NOPASSWD:	$0\n\nExiting..."
    exit 3
fi

# MAKE SURE NECESSARY DEPENDENCIES ARE PRESENT
for _depends in cp rm b2sum curl grep sed tr cut file; do
    if which "$_depends" >/dev/null 2>&1; then
        true
    else
        _notify 0 "MISSING REQUIRED DEPENDENCY $_depends. PLEASE INSTALL. EXITING..."
        exit 5
    fi
done


# NORMAL PROCESS
# CHECK FOR OPTIONAL DECOMPRESSION DEPENDENCIES, SET UP FUNCTIONS THEREOF THAT DUMP TO STDOUT
if which unzip >/dev/null 2>&1; then
    _unzip_available=1
    if [ $_verbosity -ge 1 ]; then
        _unzip() {
            unzip -B -o -j -p $_v_unzip "$@"
        }
    else
        _unzip() {
            unzip -B -o -j -p $_v_unzip "$@" 2>/dev/null
        }
    fi
else
    _notify 1 "Dearchiver for zip NOT FOUND. Optional functions which use this format will be skipped."
    _unzip_available=0
fi

if which 7za >/dev/null 2>&1; then
    _un7zip_available=1
    if [ $_verbosity -ge 1 ]; then
        _un7zip() {
            7za e -so "$@"
        }
    else
        _un7zip() {
            7za e -so "$@" 2>/dev/null
        }
    fi
elif which 7z >/dev/null 2>&1; then
    _un7zip_available=1
    if [ $_verbosity -ge 1 ]; then
        _un7zip() {
            7z e -so "$@"
        }
    else
        _un7zip() {
            7z e -so "$@" 2>/dev/null
        }
    fi       
else
    _notify 1 "Dearchiver for 7za NOT FOUND. Optional functions which use this format will be skipped."
    _un7zip_available=0
fi

if which pigz >/dev/null 2>&1; then
    _gunzip_available=1
    if [ $_verbosity -ge 1 ]; then
        _gunzip() {
            pigz -d -c $_v_gzip "$@"
        }
    else
        _gunzip() {
            pigz -d -c $_v_gzip "$@" 2>/dev/null
        }
    fi
elif which gzip >/dev/null 2>&1; then
    _gunzip_available=1
    if [ $_verbosity -ge 1 ]; then
        _gunzip() {
            gzip -d -c $_v_gzip "$@"
        }
    else
        _gunzip() {
            gzip -d -c $_v_gzip "$@" 2>/dev/null
        }
    fi
else
    _notify 1 "Dearchiver for gzip NOT FOUND. Optional functions which use this format will be skipped."
    _gunzip_available=0
fi

# IDENTIFY WHAT WILL not BE OUR REDIRECTION URL
if [ "$redirecturl" != '127.0.0.1' ]; then
    _notredirecturl='127.0.0.1'
else
    _notredirecturl='0.0.0.0'
fi

# DOWNLOAD BLOCKLISTS AND/OR REDIRECT LISTS
_notify 1 "Checking blocklists and/or redirectlists for updates..."


sed "s/#.*//g" $blocklists $redirectlists | grep "[[:alnum:]]" | while read _url; do
    _outfile=$(echo $_url | sed -e "s|http:\/\/||g" -e "s|https:\/\/||g" | tr '/%&+?=' '.')
    [ -f "$cachedir"/"$_outfile" ] && _old_sha1sum=$(b2sum < "$cachedir"/"$_outfile")

    # Make process wait until the number of curl processes are less than $max_simultaneous_downloads
    until [ $(pidof curl | wc -w) -lt $max_simultaneous_downloads ]; do
        sleep 1 
    done

    if curl $_v_curl --compressed -L --connect-timeout $connect_timeout --retry $retry -z "$cachedir"/"$_outfile" "$_url" -o "$cachedir"/"$_outfile"; then
        _new_sha1sum=$(b2sum < "$cachedir"/"$_outfile")
        if [ "$_old_sha1sum" != "$_new_sha1sum" ]; then
            _notify 1 "    Changes found to $_url"
            touch "$HOME"/changed
        fi
    else
        _notify 1 "    FAILED to refresh/download blocklist $_url"
    fi &
done 
wait

# IF THERE ARE CHANGES...
if [ -f "$HOME"/changed ]; then
    _notify 1 "Changes found among blocklists and/or redirectlists. Extracting to $hostsfile.new..."

    # INCLUDE HOSTS.HEAD FILE AS THE BEGINNING OF THE NEW TARGET HOSTS FILE
    if [ "$hostshead" != "0" ]; then
        _notify 1 "  Appending $hostshead to $hostsfile.new..."
        cp $_v -f -- "$hostshead" "$hostsfile".new
    fi

    # EXTRACT BLOCK ENTRIES DIRECTLY FROM CACHED FILES
    if [ "$blocklists" ]; then
        _notify 1 "  Extracting blocklists..."
        _ipv4_match_patterns="-e 0\\.0\\.0\\.0 -e 127\\.0\\.0\\.1"
        _extract_from_cachefiles "$blocklists"
    fi
    
    # EXTRACT REDIRECT ENTRIES DIRECTLY FROM CACHED FILES
    if [ "$redirectlists" ]; then
        _notify 1 "  Extracting redirectlists..."
        _ipv4_match_patterns="-E [0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}"
        _extract_from_cachefiles "$redirectlists"
    fi

    # APPEND BLACKLIST ENTRIES
    _notify 1 "  Appending blacklist entries..."
    while read _blacklistline; do
        grep -Fqx "$_blacklistline" "$hostsfile" || echo "$redirecturl $_blacklistline" >> "$hostsfile".new
    done < "$blacklist" && \
    mv "$hostsfile".new "$hostsfile" && \
    _notify 1 "$hostsfile successfully compiled. DONE."
else
    _notify 1 "No new changes. DONE."
fi

