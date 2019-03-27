#!/bin/sh

if [ -n "$ZSH_VERSION" ]; then emulate -L sh; fi

# SUBROUTINES

# Send notifications to stderr
_notify() {
    [ $_verbosity -ge $1 ] && echo "$2" 1>&2
}

_download_list() {
    # $1=$_url
    _outfile=$(echo $1 | sed -e "s|http:\/\/||g" -e "s|https:\/\/||g" | tr '/%&+?=' '.')
    touch "$tmpdir"/downloads/"$_outfile"
    [ -f "$cachedir"/"$_outfile" ] && _old_sha1sum=$(b2sum < "$cachedir"/"$_outfile")
    if curl $_v_curl --compressed -L --connect-timeout $connect_timeout --retry $retry -z "$cachedir"/"$_outfile" "$1" -o "$cachedir"/"$_outfile"; then
        _new_sha1sum=$(b2sum < "$cachedir"/"$_outfile")
        if [ "$_old_sha1sum" != "$_new_sha1sum" ]; then
            _notify 1 "  Changes found to $1."
	    [ ! -d "$tmpdir" ] && mkdir -p "$tmpdir"
            touch "$tmpdir"/changed
        fi
    else
        _notify 1 "    FAILED to refresh/download blocklist $1"
    fi
    rm -rf "$tmpdir"/downloads/"$_outfile"
}

_extract_from_cachefiles() {
    # $1 = $blocklists or $redirectlists, i.e. files containing lists of url files
    sed "s/#.*//g" "$1" | grep "[[:alnum:]]" | while read _url; do
            _cachefile="$cachedir"/$(echo $_url | sed -e "s|http:\/\/||g" -e "s|https:\/\/||g" | tr '/%&+?=' '.')
            _cachefile_type=$(file -bi "$_cachefile")
	    if echo "$_cachefile_type" | grep -q 'application/zip'; then
                if [ $_unzip_available != 0 ]; then
                    if ! _unzip "$_cachefile"; then 
                        _notify 1 "    Zip-extraction of ${_cachefile##*/} failed."
		    fi
                else
                    _notify 1 "${_cachefile##*/} is a zip archive, but an extractor is NOT FOUND. Skipping..."
                fi
            elif echo "$_cachefile_type" | grep -q 'application/x-7z-compressed'; then
                if [ $_un7zip_available != 0 ]; then
                    if ! _un7zip "$_cachefile"; then
                        _notify 1 "    7zip-extraction of ${_cachefile##*/} failed."
                    fi
                else
                    _notify 1 "${_cachefile##*/} is a 7z archive, but an extractor is NOT FOUND. Skipping..."
                fi
            else
                grep -hI $_ipv4_match_patterns "$_cachefile"
            fi 
    done | _sanitize | sort -u | grep -Fvf "$whitelist" >> "$hostsfile".new
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
max_simultaneous_downloads=8
tmpdir="/tmp/hostsblock"
_changed=0

# GET OPTIONS
while getopts "qvf:huc:" _option; do
    case "$_option" in
        f)  [ "$OPTARG" != "" ] && _configfile="$OPTARG";;
        q)  _verbosity=0;;
	v)  _verbosity=2;;
        u)  _changed=1;;
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
TMPDIR="$tmpdir"
mkdir -p "$tmpdir"
[ $_changed -eq 1 ] && touch "$tmpdir"/changed

# SET VERBOSITY FOR SCRIPT AND ITS SUBPROCESSES
if [ $_verbosity -eq 0 ]; then
    _v=""
    _v_curl="-s"
    _v_unzip="-qq"
    set +x
elif [ $_verbosity -eq 1 ]; then
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
    _unzip() {
        if unzip -l "$1" | tail -n1 | grep -q "\b1 file\b"; then
            unzip -c -a $_v_unzip -- "$1" | grep -hI $_ipv4_match_patterns | _sanitize
	else
            mkdir -p "$tmpdir"/"${1##*/}".d
	    unzip -B -o -j -a -d "$tmpdir"/"${1##*/}".d $_v_unzip -- "$1" && \
            ( find "$tmpdir"/"${1##*/}".d -type f -print0 | xargs -0 grep -hI $_ipv4_match_patterns ) | _sanitize
	    _exit=$?
	    rm -rf "$tmpdir"/"${1##*/}".d
	    return $_exit
        fi
    }
else
    _notify 1 "Dearchiver for zip NOT FOUND. Optional functions which use this format will be skipped."
    _unzip_available=0
fi
if which 7zr >/dev/null 2>&1; then
    _un7zip_available=1
    _7zip_bin() {
        7zr "$@"
    }
elif which 7za >/dev/null 2>&1; then
    _un7zip_available=1
    _7zip_bin() {
        7za "$@"
    }
elif which 7z >/dev/null 2>&1; then
    _un7zip_available=1
    _7zip_bin() {
        7z "$@"
    }
else
    _notify 1 "Dearchiver for 7z NOT FOUND. Optional functions which use this format will be skipped."
    _un7zip_available=0
fi
if [ $_un7zip_available -eq 1 ]; then
    _un7zip() {
        if _7zip_bin l "$1" | grep -A1 "^Scanning the drive for archives:" | grep -q "^1 file"; then
            _7zip_bin e -so -- "$1" | grep -hI $_ipv4_match_patterns | _sanitize
	else
            mkdir -p "$tmpdir"/"${1##*/}".d
	    _7zip_bin e -so -o "$tmpdir"/"${1##*/}".d -- "$1" && \
            ( find "$tmpdir"/"${1##*/}".d -type f -print0 | xargs -0 grep -hI $_ipv4_match_patterns ) | _sanitize
	    _exit=$?
	    rm -rf "$tmpdir"/"${1##*/}".d
            return $_exit
	fi
    }
fi

# IDENTIFY WHAT WILL not BE OUR REDIRECTION URL
if [ "$redirecturl" != '127.0.0.1' ]; then
    _notredirecturl='127.0.0.1'
else
    _notredirecturl='0.0.0.0'
fi

# DOWNLOAD BLOCKLISTS AND/OR REDIRECT LISTS
_notify 1 "Checking blocklists and/or redirectlists for updates..."

[ -d "$tmpdir"/downloads/ ] && rm -rf "$tmpdir"/downloads/
mkdir -p "$tmpdir"/downloads/
sed "s/#.*//g" $blocklists $redirectlists | grep "[[:alnum:]]" | while read _url; do
    if [ $max_simultaneous_downloads -gt 0 ]; then
        while [ $(find "$tmpdir"/downloads -type f | wc -l) -ge $max_simultaneous_downloads ]; do
            sleep 0.1
        done
    fi
    _download_list "$_url" & 
done
wait
while [ $(find "$tmpdir"/downloads -type f | wc -l) -gt 0 ]; do
    sleep 0.1
done
rm -rf "$tmpdir"/downloads

# IF THERE ARE CHANGES...
if [ -f "$tmpdir"/changed ]; then
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
        _sanitize() {
            tr -d '\r' | tr '\t' ' ' | tr -s ' ' | sed -e "s/#.*//g" -e "s/^ //g" -e "s/ $//g" -e "s/$_notredirecturl/$redirecturl/g" | grep -I "^$redirecturl " 
        }
	_extract_from_cachefiles "$blocklists"
    fi
    
    # EXTRACT REDIRECT ENTRIES DIRECTLY FROM CACHED FILES
    if [ "$redirectlists" ]; then
        _notify 1 "  Extracting redirectlists..."
        _ipv4_match_patterns="-E [0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}"
        _sanitize() {
            tr -d '\r' | tr '\t' ' ' | tr -s ' ' | sed -e "s/#.*//g" -e "s/^ //g" -e "s/ $//g" | grep -IE "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} " 
        }
        _extract_from_cachefiles "$redirectlists"
    fi

    # APPEND BLACKLIST ENTRIES
    _notify 1 "  Appending blacklist entries..."
    while read _blacklistline; do
        grep -Fqx "$redirecturl $_blacklistline" "$hostsfile" || echo "$redirecturl $_blacklistline" >> "$hostsfile".new
    done < "$blacklist" && \
    mv "$hostsfile".new "$hostsfile" && \
    _notify 1 "$hostsfile successfully compiled. DONE."
else
    _notify 1 "No new changes. DONE."
fi
rm -rf "$tmpdir"
