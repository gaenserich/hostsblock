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
                grep -hI $_ipv4_match_patterns "$_cachefile" | _sanitize
            fi 
    done | sort -u | grep -Fvf "$whitelist" >> "$hostsfile".new
    if [ $? -ne 0 ]; then
        _notify 0 "FAILED TO COMPILE BLOCK/REDIRECT ENTRIES FROM URLS IN $1 INTO $hostsfile. EXITING..."
        exit 2
    fi
}

_grep_db() {
    if [ -f "$hostsfile".db.gz ]; then
        _gzip_bin -d -c "$hostsfile".db.gz | grep "$@"
    else
        grep "$@" "$hostsfile".db
    fi
}

_urlcheck_scrape_url() {
    # $1 = url to be scraped, stdout = list of urls, stripped to url domain names, contained therein
    curl -L --location-trusted -s "$1" | tr ' "' '\n' | tr "'" "\n" | sed "s/http/\nhttp/g" | grep "https*:\/\/" | sed -e "s/.*https*:\/\///g" -e "s/\/.*$//g" | sort -u
}

_urlcheck_line_check() {
    # $1 = complete domain name to check, outputs variables
    _urlcheck_status_line="$1"
    _urlcheck_is_blacklisted=0
    _urlcheck_is_whitelisted=0
    _urlcheck_is_blocked=0
    _urlcheck_is_redirected=0
    _url_lines=$(_grep_db -F " $1 ")
    if echo "$_url_lines" | grep -Fqf "$blacklist"; then
	_urlcheck_is_blacklisted=1
        _urlcheck_status_line="$_urlcheck_status_line BLACKLISTED"
    fi
    if ! echo " $1" | grep -Fvqf "$whitelist"; then
	_urlcheck_is_whitelisted=1
        _urlcheck_status_line="$_urlcheck_status_line WHITELISTED"
    fi
    _url_blocklist_lines=$(echo "$_url_lines" | grep -v " $blacklist$" | grep "^$redirecturl " | cut -d' ' -f3 | sed "s/^/    /g")
    if echo "$_url_blocklist_lines" | grep -q "[[:alnum:]]"; then
	_urlcheck_is_blocked=1
        _urlcheck_status_line="$_urlcheck_status_line BLOCKED by\n$_url_blocklist_lines\n"
    fi
    _url_redirectlist_lines=$(echo "$_url_lines" | grep -ve " $blacklist$" -ve "^$redirecturl" | sed "s/^\(.*\) .* \(.*\)$/    by \2 to \1/g")
    if echo "$_url_redirectlist_lines" | grep -q "[[:alnum:]]"; then
	_urlcheck_is_redirected=1
        _urlcheck_status_line="$_urlcheck_status_line REDIRECTED\n$_url_redirectlist_lines\n"
    fi
    if [ $_urlcheck_is_blacklisted -eq 0 ] && [ $_urlcheck_is_whitelisted -eq 0 ] && [ $_urlcheck_is_blocked -eq 0 ] && [ $_urlcheck_is_redirected -eq 0 ]; then
        _urlcheck_status_line="$_urlcheck_status_line is not blacklisted, whitelisted, blocked, or redirected."
    fi
}

_urlcheck_block() {
    # $1=a complete domain name, e.g. "sub.domain.org" or "domain.org"
    _urlcheck_line_check "$1"
    if [ $_urlcheck_is_blocked -eq 0 ]; then
        echo "$redirecturl $1" >> "$hostsfile"
        if [ -f "$hostsfile".db.gz ]; then
            echo "$redirecturl $1 [Temporary]" | _gzip_bin -c - >> "$hostsfile".db.gz
        else
            echo "$redirecturl $1 [Temporary]" >> "$hostsfile".db
        fi
    else
        echo "$1 already blocked."
        return 1
    fi
}

_urlcheck_unblock() {
    _urlcheck_line_check "$1"
    if [ $_urlcheck_is_blocked -eq 1 ]; then
        grep -Fv " ${1}$" "$hostsfile" > "$hostsfile".tmp && mv $_v "$hostsfile".tmp "$hostsfile"
        if [ -f "$hostsfile".db.gz ]; then
            _gzip_bin -d -c "$hostsfile".db.gz | grep -Fv " ${1} " | _gzip_bin -c - > "$hostsfile".db.tmp.gz && mv $_v "$hostsfile".db.tmp.gz "$hostsfile".db.gz
        else
	    grep -Fv " ${1} " "$hostsfile".db > "$hostsfile".db.tmp && mv $_v "$hostsfile".tmp "$hostsfile"
        fi
    else
        echo "$1 already unblocked."
        return 1
    fi
}

_urlcheck_blacklist() {
    _urlcheck_block "$1"
    if [ $_urlcheck_is_blacklisted -eq 0 ]; then
        echo "$1" >> "$blacklist"
    else
        echo "$1 already blacklisted."
        return 1
    fi	    
}

_urlcheck_deblacklist() {
    _urlcheck_line_check "$1"
    if [ $_urlcheck_is_blacklisted -eq 1 ]; then
        grep -vF "$1" "$blacklist" > "$blacklist".tmp && mv $_v "$blacklist".tmp "$blacklist"
    else
        echo "$1 not in blacklist."
        return 1
    fi
}

_urlcheck_whitelist() {
    _urlcheck_unblock "$1"
    if [ $_urlcheck_is_whitelisted -eq 0 ]; then
        echo " $1" >> "$whitelist"
    else
        echo "$1 already in whitelist."
        return 1
    fi
}

_urlcheck_dewhitelist() {
    _urlcheck_line_check "$1"
    if [ $_urlcheck_is_whitelisted -eq 1 ]; then
        grep -vF " $1" "$whitelist" > "$whitelist".tmp && mv $_v "$whitelist".tmp "$whitelist"
    else
        echo "$1 not in whitelist."
        return 1
    fi
}

_urlcheck_check() {
    _urlcheck_line_check "$1"
    echo -e "\n$_urlcheck_status_line"
    _block_yn="n"
    if [ $_urlcheck_is_blocked -eq 0 ]; then
     	read -p "Block $1 now? [y/N]: " _block_yn
	if [ "$_block_yn" = "Y" ] || [ "$_block_yn" = "y" ]; then
            [ ! -f "$hostsfile".tmp ] && cp $_v "$hostsfile" "$hostsfile".tmp
	    echo "$redirecturl $1" >> "$hostsfile".tmp
            if [ ! -f "$hostsfile".db.tmp ]; then
                if [ -f "$hostsfile".db.gz ]; then
                    _gzip_bin -d -c "$hostsfile".db.gz > "$hostsfile".db.tmp
		else
                    cp $_v "$hostsfile".db "$hostsfile".db.tmp
		fi
            fi
	    echo "$redirecturl $1 [Temporary]" >> "$hostsfile".db.tmp
        fi
    else
	read -p "Unblock $1 now? [y/N]: " _block_yn
	if [ "$_block_yn" = "Y" ] || [ "$_block_yn" = "y" ]; then
            if [ ! -f "$hostsfile".tmp ]; then
                grep -v " $1$" "$hostsfile" > "$hostsfile".tmp
            else
                grep -v " $1$" "$hostsfile".tmp > "$hostsfile".tmp.tmp && mv $_v "$hostsfile".tmp.tmp "$hostsfile".tmp
            fi
	    if [ ! -f "$hostsfile".db.tmp ]; then
                if [ -f "$hostsfile".db.gz ]; then
                    _gzip_bin -d -c "$hostsfile".db.gz | grep -Fv " $1 " > "$hostsfile".db.tmp
                else
                    grep -Fv " $1 " "$hostsfile".db > "$hostsfile".db.tmp
		fi
            else
		grep -Fv " $1 " "$hostsfile".db.tmp > "$hostsfile".db.tmp.tmp && mv $_v "$hostsfile".db.tmp.tmp "$hostsfile".db.tmp
            fi
	fi
    fi
    _blacklist_yn="n"
    if [ $_urlcheck_is_blacklisted -eq 0 ]; then
        read -p "Blacklist $1? [y/N]: " _blacklist_yn
	if [ "$_blacklist_yn" = "Y" ] || [ "$_blacklist_yn" = "y" ]; then
            echo "$1" >> "$blacklist"
	fi
    else
	read -p "Remove $1 from blacklist? [y\N]: " _blacklist_yn
	if [ "$_blacklist_yn" = "Y" ] || [ "$_blacklist_yn" = "y" ]; then
            grep -vFx "$1" "$blacklist" > "$blacklist".tmp && mv $_v -- "$blacklist".tmp "$blacklist"
	fi
    fi
    _whitelist_yn="n"
    if [ $_urlcheck_is_whitelisted -eq 0 ]; then
        read -p "Whitelist $1? [y/N]: " _whitelist_yn
	if [ "$_whitelist_yn" = "Y" ] || [ "$_whitelist_yn" = "y" ]; then
            echo " $1" >> "$whitelist"
	fi
    else
	read -p "Remove $1 from whitelist? [y\N]: " _whitelist_yn
	if [ "$_whitelist_yn" = "Y" ] || [ "$_whitelist_yn" = "y" ]; then
            grep -vFx " $1" "$whitelist" > "$whitelist".tmp && mv $_v -- "$whitelist".tmp "$whitelist"
	fi
    fi
}

_urlcheck_interactive() {
    _urlcheck_check "$1"
    _recursive_yn="n"
    read -p "Scan $2 for other urls to (un)block/(de)blacklist/(de)whitelist [y/N]: " _recursive_yn
    if [ "$_recursive_yn" = "Y" ] || [ "$_recursive_yn" = "y" ]; then
	for _domain_name in $(_urlcheck_scrape_url "$2" | grep -Fvx "$1" | tr '\n' ' '); do
	    _urlcheck_check "$_domain_name"
        done
    fi
    if [ -f "$hostsfile".db.tmp ]; then
        if [ -f "$hostsfile".db.gz ]; then
            _gzip_bin -c "$hostsfile".db.tmp > "$hostsfile".db.gz && rm $_v -- "$hostsfile".db.tmp
	else
            mv $_v -- "$hostsfile".db.tmp "$hostsfile".db
	fi
    fi
    if [ -f "$hostsfile".tmp ]; then
        mv $_v -- "$hostsfile".tmp "$hostsfile"
    fi
}

_urlcheck() {
    #$1=command $2=full domain name $3=raw URL
    case "$1" in
        status*)
            _urlcheck_line_check "$2"
            echo -e "$_urlcheck_status_line"
            if [ "$1" = "status-all" ]; then
                _urlcheck_scrape_url "$3" | while read _domain_name; do
                    _urlcheck_line_check "$_domain_name"
	            echo -e "$_urlcheck_status_line" | sed "s/^/    /g"
	        done
            fi
        ;;
        block)
            _urlcheck_block "$2"
        ;;
        unblock)
            _urlcheck_unblock "$2"
	;;
        blacklist)
            _urlcheck_blacklist "$2"
        ;;
        deblacklist)
            _urlcheck_deblacklist "$2"
	;;
        whitelist)
            _urlcheck_whitelist "$2"
        ;;
        dewhitelist)
            _urlcheck_dewhitelist "$2"
        ;;
        *)
	    _urlcheck_interactive "$2" "$3"
        ;;
    esac
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
_URL=""

# GET OPTIONS
while getopts "qvf:huc:s:mbalwi" _option; do
    case "$_option" in
        f)  [ "$OPTARG" != "" ] && _configfile="$OPTARG";;
        q)  _verbosity=0;;
	v)  _verbosity=2;;
	u)  _changed=1;;
        c)  [ "$OPTARG" != "" ] && _URL="$OPTARG";;
        *)
            cat << EOF 1>&2
Usage:
  $0 [ OPTIONS ] - generate a HOSTS file from downloaded block and redirection lists

  $0 -c URL [ COMMANDS ] - Manage how hostsblock treats URL

Help Options:
  -h                  Show help options

Application Options:
  -f CONFIGFILE       Specify an alternative configuration file (instead of /var/lib/hostsblock/hostsblock.conf)
  -q                  Show only fatal errors
  -v                  Be verbose
  -u                  Force hostsblock to update its target file, even if no changes to source files are found
  -c URL [ COMMAND ]  Check Mode: (Un)block, (un)blacklist, or (un)whitelist an url 

$0 -c URL Commands:
  status              State whether URL is blocked, blacklisted, whitelisted, or redirected
  status-all          Recursively inspect all urls contained on URL's target page
  block               Temporarily block URL
  unblock             Temporarily unblock URL
  blacklist           Add URL to blacklist and block it immediately
  deblacklist         Remove URL from blacklist
  whitelist           Add URL to whitelist and unblock it immediately
  dewhitelist         Remove URL from whitelist
  inspect             Interactively inspect URL and any other urls contained on its page (default if no command given)
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
if which pigz >/dev/null 2>&1; then
    _gzip_available=1
    _gzip_bin() {
        pigz "$@"
    }
elif which gzip >/dev/null 2>&1; then
    _gzip_available=1
    _gzip_bin() {
        gzip "$@"
    }
else
    _notify 1 "Dearchiver for gzip NOT FOUND. Optional functions which use this format will be skipped."
    _gzip_available=0
fi

# IDENTIFY WHAT WILL not BE OUR REDIRECTION URL
if [ "$redirecturl" != '127.0.0.1' ]; then
    _notredirecturl='127.0.0.1'
else
    _notredirecturl='0.0.0.0'
fi

if [ "$_URL" ] || [ "${0##*/}" = "hostblock-urlcheck" ]; then
    shift $((OPTIND-1))
    if [ "${0##*/}" = "hostsblock-urlcheck" ]; then
        _URL="$1"
	_cmd="$2"
     else
        _cmd="$1"
    fi
    _complete_domain_name=$(echo "$_URL" | sed -e "s/.*https*:\/\///g" -e "s/\/.*//g")
    _urlcheck "$_cmd" "$_complete_domain_name" "$_URL"
    exit $?
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
	sed "s|$| $hostshead|g" "$hostshead" > "$hostsfile".db.new
    fi

    # EXTRACT BLOCK ENTRIES DIRECTLY FROM CACHED FILES
    if [ "$blocklists" ]; then
        _notify 1 "  Extracting blocklists..."
        _ipv4_match_patterns="-e 0\\.0\\.0\\.0 -e 127\\.0\\.0\\.1"
        _sanitize() {
            tr -d '\r' | tr '\t' ' ' | tr -s ' ' | sed -e "s/#.*//g" -e "s/^ //g" -e "s/ $//g" -e "s/$_notredirecturl/$redirecturl/g" | grep -I "^$redirecturl " | sed "s|$| $_url|g" | tee -a "$hostsfile".db.new | cut -d' ' -f1-2
        }
	_extract_from_cachefiles "$blocklists"
    fi
    
    # EXTRACT REDIRECT ENTRIES DIRECTLY FROM CACHED FILES
    if [ "$redirectlists" ]; then
        _notify 1 "  Extracting redirectlists..."
        _ipv4_match_patterns="-E [0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}"
        _sanitize() {
            tr -d '\r' | tr '\t' ' ' | tr -s ' ' | sed -e "s/#.*//g" -e "s/^ //g" -e "s/ $//g" | grep -IE "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} " | sed "s|$| $_url|g" | tee -a "$hostsfile".db.new | cut -d' ' -f1-2 
        }
        _extract_from_cachefiles "$redirectlists"
    fi

    # APPEND BLACKLIST ENTRIES
    _notify 1 "  Appending blacklist entries..."
    while read _blacklistline; do
        grep -Fqx "$redirecturl $_blacklistline" "$hostsfile" || echo "$redirecturl $_blacklistline" >> "$hostsfile".new
        echo "$redirecturl $_blacklistline $blacklist" >> "$hostsfile".db.new
    done < "$blacklist" && \
    mv $_v "$hostsfile".new "$hostsfile" && \
    _notify 1 "Compiling database..." && \
    if [ $_gzip_available -eq 1 ]; then
        sort -u "$hostsfile".db.new | _gzip_bin -c - > "$hostsfile".db.gz
    else
        sort -u "$hostsfile".db.new > "$hostsfile".db
    fi && \
    rm $_v "$hostsfile.db.new"
    _notify 1 "$hostsfile successfully compiled. DONE."
else
    _notify 1 "No new changes. DONE."
fi
rm -rf "$tmpdir"
