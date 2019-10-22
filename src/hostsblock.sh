#!%SHPATH%
if [ -n "$ZSH_VERSION" ]; then emulate -L sh; fi

################################# SUBROUTINES #################################

# Send notifications to stderr
_notify() {
    [ $_verbosity -ge $1 ] && printf %s\\n "$2" 1>&2
}

# Download individual urls
_job_download_list() {
    # $2=$_url
    _outfile="$cachedir"/$(printf %s "${1#*//}" | tr '/%&+?=' '.')
    [ ! -d "$tmpdir"/downloads ] && mkdir -p $_v -- "$tmpdir"/downloads
    touch "$tmpdir"/downloads/"${_outfile##*/}"
    [ -f "$_outfile" ] && _old_cksum=$(cksum < "$_outfile")
    if curl $_v_curl --compressed -L --connect-timeout $connect_timeout \
      --retry $retry -z "$_outfile" "$1" -o "$_outfile"; then
        _new_cksum=$(cksum < "$_outfile")
        if [ "$_old_cksum" != "$_new_cksum" ]; then
            _notify 1 "  Changes found to $1."
            [ ! -d "$tmpdir" ] && mkdir -p $_v -- "$tmpdir"
            touch "$tmpdir"/changed
        fi
    else
        _notify 1 "    FAILED to refresh/download blocklist $1"
    fi
    rm -rf $_v -- "$tmpdir"/downloads/"${_outfile##*/}"
}


# Extract complete domain names from text, zip, and 7zip cache files
_job_extract_from_cachefiles() {
    # $1 = $blocklists or $redirectlists, i.e. files listing url files
    sed "s/#.*//g" "$1" | grep "[[:alnum:]]" | while read _url; do
        _cachefile="$cachedir"/$(printf %s "${_url#*//}" | tr '/%&+?=' '.')
        _cachefile_type=$(file -bi "$_cachefile")
        if printf %s "$_cachefile_type" | grep -Fq 'application/zip'; then
            if [ $_unzip_available != 0 ]; then
                if ! _unzip "$_cachefile"; then 
                    _notify 1 "    Zip-extraction of ${_cachefile##*/} failed."
                fi
            else
                _notify 1 "${_cachefile##*/} is a zip archive, but an extractor is NOT FOUND. Skipping..."
            fi
        elif printf %s "$_cachefile_type" | \
          grep -Fq 'application/x-7z-compressed'; then
            if [ $_un7zip_available != 0 ]; then
                if ! _un7zip "$_cachefile"; then
                    _notify 1 "    7zip-extraction of ${_cachefile##*/} failed."
                fi
            else
                _notify 1 "${_cachefile##*/} is a 7z archive, but an extractor is NOT FOUND. Skipping..."
            fi
        else
            if grep -qE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}[[:space:]]" "$_cachefile"; then
                _sanitize < "$_cachefile"
            else
                _sanitize_raw < "$_cachefile"
            fi
        fi 
    done | sort -u | grep -ve " localhost$" -ve " localhost\.localdomain$" -ve " broadcasthost$" -ve ".* .* .*" | \
      grep -Fvf "$whitelist" >> "$hostsfile".new
    if [ $? -ne 0 ]; then
        _notify 0 "FAILED TO COMPILE BLOCK/REDIRECT ENTRIES FROM URLS IN $1 INTO $hostsfile. EXITING..."
        exit 2
    fi
}

## Identify whether a temporary hosts.block file has been created yet
_urlcheck_get_hostsfile() {
    #Stdout file to be edited
    if [ -f "$tmpdir"/"${hostsfile##*/}".tmp ]; then
        printf %s "$tmpdir"/"${hostsfile##*/}".tmp
    else
        printf %s "$hostsfile"
    fi
}

## Find urls (and their complete domain names) within a given url
_urlcheck_scrape_url() {
    # $1 = url to be scraped, stdout = list of urls,
    #  stripped to url domain names, contained therein
    curl -L --location-trusted $_v_curl "$1" | tr ' "{}[]()' '\n' | \
      tr "'" "\n" | sed "s/http/\nhttp/g" | grep "https*:\/\/" | \
      sed -e "s/.*https*:\/\///g" -e "s/\/.*$//g" | grep "[[:alnum:]]" | \
      sort -u
}

## Get information about a given list of complete domain names
_urlcheck_status_lines() {
    # $1 = line break-split list of complete domain names to inspect
    # $2 = status to inspect, e.g. block, blacklist, whitelist, redirect
    # Outputs "are_" variables (line break-split list of complete domain
    #  names) for each parameter
    case "$2" in
        block)
            are_not_blocked="$(printf %s "$1" | grep "[[:alnum:]]" | \
              sed "s/^/$redirecturl /g" | grep -Fxvf "$(_urlcheck_get_hostsfile)" |\
              tee "$tmpdir"/are-not-blocked.grep | cut -d' ' -f2)"
            are_blocked="$(printf %s "$1" | grep "[[:alnum:]]" | \
              sed "s/^/$redirecturl /g" | \
              grep -Fxvf "$tmpdir"/are-not-blocked.grep | \
              cut -d' ' -f2)"
            rm -f $_v "$tmpdir"/are-not-blocked.grep
        ;;
        blacklist)
            are_not_blacklisted="$(printf %s "$1" | grep "[[:alnum:]]" | \
              grep -Fxvf "$blacklist" | \
              tee -a "$tmpdir"/are-not-blacklisted.grep)"
            are_blacklisted="$(printf %s "$1" | grep "[[:alnum:]]" | \
              grep -Fxvf "$tmpdir"/are-not-blacklisted.grep)"
            rm -f $_v "$tmpdir"/are-not-blacklisted.grep
        ;;
        whitelist)
            are_not_whitelisted="$(printf %s "$1" | grep "[[:alnum:]]" | \
              sed "s/^/ /g" | grep -Fxvf "$whitelist" | \
              tee -a "$tmpdir"/are-not-whitelisted.grep | cut -d' ' -f2)"
            are_whitelisted="$(printf %s "$1" | grep "[[:alnum:]]" | \
              sed "s/^/ /g" | grep -Fxvf "$tmpdir"/are-not-whitelisted.grep |\
              cut -d' ' -f2)"
            rm -f $_v "$tmpdir"/are-not-whitelisted.grep
        ;;
        redirect)
            # separate out just redirections from hostsfile
            grep -v "^$redirecturl " "$(_urlcheck_get_hostsfile)" \
              > "$tmpdir"/redirections.grep
            # create a filter file from the list given via $1
            printf %s "$1" | grep "[[:alnum:]]" | sed -e "s/^/ /g" \
              -e "s|$|\$|g" > "$tmpdir"/redirect-filter.grep
            # $are_redirected includes the ipv4 address as well
            are_redirected="$(grep -f "$tmpdir"/redirect-filter.grep \
              "$tmpdir"/redirections.grep)"
            # strip the ipv4 address before reporting as not redirected
            printf %s "$are_redirected" | cut -d' ' -f2 \
              > "$tmpdir"/are-redirected.grep
            are_not_redirected="$(printf %s "$1" | grep "[[:alnum:]]" | \
              grep -vf "$tmpdir"/are-redirected.grep)"
            rm -f $_v "$tmpdir"/redirect-filter.grep \
              "$tmpdir"/redirections.grep
        ;;
        inspect)
            _urlcheck_status_lines "$1" block
            _urlcheck_status_lines "$1" blacklist
            _urlcheck_status_lines "$1" whitelist
        ;;
        status)
            _urlcheck_status_lines "$1" block
            _urlcheck_status_lines "$1" blacklist
            _urlcheck_status_lines "$1" whitelist
            _urlcheck_status_lines "$1" redirect
        ;;
    esac
}

_urlcheck_status_url() {
    # $1 = single complete domain name to inspect
    _urlcheck_is_blocked=0
    _urlcheck_is_blacklisted=0
    _urlcheck_is_whitelisted=0
    _urlcheck_is_redirected=0
    _urlcheck_status_single_line="$1:"
    if printf %s "$are_blocked" | grep -Fqx "$1"; then
        _urlcheck_status_single_line="$_urlcheck_status_single_line BLOCKED"
        _urlcheck_is_blocked=1
    fi
    if printf %s "$are_blacklisted" | grep -Fqx "$1"; then
        _urlcheck_status_single_line="$_urlcheck_status_single_line BLACKLISTED"
        _urlcheck_is_blacklisted=1
    fi
    if printf %s "$are_whitelisted" | grep -Fqx "$1"; then
        _urlcheck_status_single_line="$_urlcheck_status_single_line WHITELISTED"
        _urlcheck_is_whitelisted=1
    fi
    if printf %s "$are_redirected" | grep -q "[[:alnum:]]" && \
      printf %s "$are_not_redirected" | grep -q "[[:alnum:]]"; then
        if printf %s "$are_redirected" | grep -Fqx "$1"; then
            _urlcheck_status_single_line="$_urlcheck_status_single_line REDIRECTED"
            _urlcheck_is_redirected=1
        fi
    fi
    [ "$_urlcheck_status_single_line" = "$1:" ] && \
        _urlcheck_status_single_line="$_urlcheck_status_single_line not managed"
}

## _urlcheck_*_lines: do the selected action (block, blacklist,
##  whitelist, and their opposites) to a list (in a string)
##  provided via $1 split by newline

_urlcheck_block_lines() {
    [ ! -f "$tmpdir"/"${hostsfile##*/}".tmp ] && \
      cp $_v -- "$hostsfile" "$tmpdir"/"${hostsfile##*/}".tmp
    printf %s\\n "$1" | grep "[[:alnum:]]" | sed "s/^/$redirecturl /g" \
      >> "$tmpdir"/"${hostsfile##*/}".tmp
    _exit=$?
    [ $_exit -ne 0 ] &&  _return=$(( $_return + 2 ))
    return $_exit
}

_urlcheck_unblock_lines() {
    printf %s "$1" | grep "[[:alnum:]]" | sed -e "s/^/$redirecturl /g" \
      -e "s|$|\$|g" > "$tmpdir"/deblock-filter.grep
    grep -vf "$tmpdir"/deblock-filter.grep "$(_urlcheck_get_hostsfile)" \
      > "$tmpdir"/"${hostsfile##*/}".tmp.tmp && \
      mv -f $_v -- "$tmpdir"/"${hostsfile##*/}".tmp.tmp \
      "$tmpdir"/"${hostsfile##*/}".tmp
    _exit=$?
    [ $_exit -ne 0 ] && _return=$(( $_return + 2 ))
    rm -f $_v -- "$tmpdir"/deblock-filter.grep
    return $_exit
}

_urlcheck_blacklist_lines() {
    printf %s\\n "$1" | grep "[[:alnum:]]" >> "$blacklist"
    _exit=$?
    [ $_exit -ne 0 ] && _return=$(( $_return + 8 ))
    return $_exit
}

_urlcheck_deblacklist_lines() {
    printf %s "$1" | grep "[[:alnum:]]" > "$tmpdir"/deblacklist-filter.grep
    grep -Fvxf "$tmpdir"/deblacklist-filter.grep "$blacklist" \
      > "$blacklist".new && \
      mv -f $_v "$blacklist".new "$blacklist"
    _exit=$?
    [ $_exit -ne 0 ] && _return=$(( $_return + 8 ))
    rm -f $_v -- "$tmpdir"/deblacklist-filter.grep
    return $_exit
}

_urlcheck_whitelist_lines() {
    printf %s\\n "$1" | grep "[[:alnum:]]" | sed "s/^/ /g" >> "$whitelist"
    _exit=$?
    [ $_exit -ne 0 ] && _return=$(( $_return + 32 ))
    return $_exit
}

_urlcheck_dewhitelist_lines() {
    printf %s "$1" | grep "[[:alnum:]]" | sed "s/^/ /g" \
      > "$tmpdir"/dewhitelist-filter.grep
    grep -Fvxf "$tmpdir"/dewhitelist-filter.grep "$whitelist" \
      > "$whitelist".new && \
      mv -f $_v "$whitelist".new "$whitelist"
    _exit=$?
    [ $_exit -ne 0 ] && _return=$(( $_return + 32 ))
    rm -f $_v -- "$tmpdir"/dewhitelist-filter.grep
    return $_exit
}

## _urlcheck_*_dialog: Provides feedback and exit code info
##  for select actions (block, blacklist, whitelist, and their
##  opposites). Input is string list, separated by newlines, via $1

_urlcheck_block_dialog() {
    _urlcheck_status_lines "$1" block
    if printf %s "$are_not_blocked" | grep -q "[[:alnum:]]"; then
        _urlcheck_block_lines "$are_not_blocked"
        if [ $? -eq 0 ]; then
            [ $_verbosity -ge 1 ] && printf %s\\n "$are_not_blocked" | \
              sed "s|$| blocked|g" 1>&2
        else
            _notify 0 "Blocking failed."
        fi
    fi
    if [ $_verbosity -ge 1 ] && \
      printf %s "$are_blocked" | grep -q "[[:alnum:]]"; then
        printf %s\\n "$are_blocked" | sed  "s|$| already blocked|g" 1>&2
        _return=$(( $_return + 4 ))
    fi
}

_urlcheck_unblock_dialog() {
    _urlcheck_status_lines "$1" block
    if printf %s "$are_blocked" | grep -q "[[:alnum:]]"; then
        _urlcheck_unblock_lines "$are_blocked"
        if [ $? -eq 0 ]; then
            [ $_verbosity -ge 1 ] && printf %s\\n "$are_blocked" | \
              sed "s|$| unblocked|g" 1>&2
        else
            _notify 0 "Unblocking failed."
        fi
    fi
    if [ $_verbosity -ge 1 ] && \
      printf %s "$are_not_blocked" | grep -q "[[:alnum:]]"; then
        printf %s\\n "$are_not_blocked" | sed "s|$| already unblocked|g" 1>&2
        _return=$(( $_return + 4 ))
    fi
}

_urlcheck_blacklist_dialog() {
    _urlcheck_status_lines "$1" blacklist
    if printf %s "$are_not_blacklisted" | grep -q "[[:alnum:]]"; then
        _urlcheck_blacklist_lines "$are_not_blacklisted"
        if [ $? -eq 0 ]; then
            [ $_verbosity -ge 1 ] && printf %s\\n "$are_not_blacklisted" | \
              sed "s|$| added to blacklist|g" 1>&2
        else
            _notify 0 "Blacklisting failed."
        fi
    fi
    if [ $_verbosity -ge 1 ] && \
      printf %s "$are_blacklisted" | grep -q "[[:alnum:]]"; then
        printf %s\\n "$are_blacklisted" | sed "s|$| already in blacklist|g" 1>&2
        _return=$(( $_return + 16 ))
    fi
}

_urlcheck_deblacklist_dialog() {
    _urlcheck_status_lines "$1" blacklist
    if printf %s "$are_blacklisted" | grep -q "[[:alnum:]]"; then
        _urlcheck_deblacklist_lines "$are_blacklisted"
        if [ $? -eq 0 ]; then
            [ $_verbosity -ge 1 ] && printf %s\\n "$are_blacklisted" | \
              sed "s|$| removed from blacklist|g" 1>&2
        else
            _notify 0 "Deblacklisting failed."
        fi
    fi
    if [ $_verbosity -ge 1 ] && \
      printf %s "$are_not_blacklisted" | grep -q "[[:alnum:]]"; then
        printf %s\\n "$are_not_blacklisted" | \
          sed "s|$| already removed from blacklist|g" 1>&2
        _return=$(( $_return + 4 ))
    fi
}

_urlcheck_whitelist_dialog() {
    _urlcheck_status_lines "$1" whitelist
    if printf %s "$are_not_whitelisted" | grep -q "[[:alnum:]]"; then
        _urlcheck_whitelist_lines "$are_not_whitelisted"
        if [ $? -eq 0 ]; then
            [ $_verbosity -ge 1 ] && printf %s\\n "$are_not_whitelisted" | \
              sed "s|$| added to whitelist|g" 1>&2
        else
            _notify 0 "Whitelisting failed."
        fi
    fi
    if [ $_verbosity -ge 1 ] && printf %s "$are_whitelisted" | \
      grep -q "[[:alnum:]]"; then
        printf %s\\n "$are_whitelisted" | sed "s|$| already in whitelist|g" 1>&2
        _return=$(( $_return + 16 ))
    fi
}

_urlcheck_dewhitelist_dialog() {
    _urlcheck_status_lines "$1" whitelist
    if printf %s "$are_whitelisted" | grep -q "[[:alnum:]]"; then
        _urlcheck_dewhitelist_lines "$are_whitelisted"
        if [ $? -eq 0 ]; then
            [ $_verbosity -ge 1 ] && printf %s\\n "$are_whitelisted" | \
              sed "s|$| removed from whitelist|g" 1>&2
        else
            _notify 0 "Dewhitelisting failed."
        fi
    fi
    if [ $_verbosity -ge 1 ] && printf %s "$are_not_whitelisted" | \
      grep -q "[[:alnum:]]"; then
        printf %s\\n "$are_not_whitelisted" | \
          sed "s|$| already removed from whitelist|g" 1>&2
        _return=$(( $_return + 4 ))
    fi
}


_urlcheck_inspect() {
    # $1 = list of complete domain names to check
    # the $are_* variables are available
    _urlcheck_to_be_blocked=""
    _urlcheck_to_be_unblocked=""
    _urlcheck_to_be_blacklisted=""
    _urlcheck_to_be_deblacklisted=""
    _urlcheck_to_be_whitelisted=""
    _urlcheck_to_be_dewhitelisted=""
    for _urlcheck_inspect_domain in $(printf %s\\n "$1" | tr '\n' ' '); do
        _urlcheck_status_url "$_urlcheck_inspect_domain"
        _notify 0 ""
        _notify 0 "$_urlcheck_status_single_line"
        _block_yn="n"
        if [ $_urlcheck_is_blocked -eq 0 ]; then
            printf %s "    Block until next update? [y/N]: " 1>&2
            read _block_yn
            if [ "$_block_yn" = "Y" ] || [ "$_block_yn" = "y" ]; then
                _urlcheck_to_be_blocked="$_urlcheck_to_be_blocked
$_urlcheck_inspect_domain"
            fi
        else
            printf %s "    Unblock until next update? [y/N]: " 1>&2
            read _block_yn
            if [ "$_block_yn" = "Y" ] || [ "$_block_yn" = "y" ]; then
                _urlcheck_to_be_unblocked="$_urlcheck_to_be_unblocked
$_urlcheck_inspect_domain"
            fi
        fi
        _blacklist_yn="n"
        if [ $_urlcheck_is_blacklisted -eq 0 ]; then
            printf %s "    Blacklist (Block permanently after next update)? [y/N]: " 1>&2
            read _blacklist_yn
            if [ "$_blacklist_yn" = "Y" ] || [ "$_blacklist_yn" = "y" ]; then
                _urlcheck_to_be_blacklisted="$_urlcheck_to_be_blacklisted
$_urlcheck_inspect_domain"
            fi
        else
            printf %s "    Remove from blacklist? [y/N]: " 1>&2
            read _blacklist_yn
            if [ "$_blacklist_yn" = "Y" ] || [ "$_blacklist_yn" = "y" ]; then
                _urlcheck_to_be_deblacklisted="$_urlcheck_to_be_deblacklisted
$_urlcheck_inspect_domain"
            fi
        fi
        _whitelist_yn="n"
        if [ $_urlcheck_is_whitelisted -eq 0 ]; then
            printf %s "    Whitelist (Unblock permanently after next update)? [y/N]: " 1>&2
            read _whitelist_yn
            if [ "$_whitelist_yn" = "Y" ] || [ "$_whitelist_yn" = "y" ]; then
                _urlcheck_to_be_whitelisted="$_urlcheck_to_be_whitelisted
$_urlcheck_inspect_domain"
            fi
        else
            printf %s "    Remove from whitelist? [y/N]: " 1>&2
            read _whitelist_yn
            if [ "$_whitelist_yn" = "Y" ] || [ "$_whitelist_yn" = "y" ]; then
                _urlcheck_to_be_dewhitelisted="$_urlcheck_to_be_dewhitelisted
$_urlcheck_inspect_domain" 
            fi
        fi
    done
    printf %s "$_urlcheck_to_be_blocked" | grep -q "[[:alnum:]]" && _urlcheck_block_lines "$_urlcheck_to_be_blocked"
    printf %s "$_urlcheck_to_be_unblocked" | grep -q "[[:alnum:]]" && _urlcheck_unblock_lines "$_urlcheck_to_be_unblocked"
    printf %s "$_urlcheck_to_be_blacklisted" | grep -q "[[:alnum:]]" && _urlcheck_blacklist_lines "$_urlcheck_to_be_blacklisted"
    printf %s "$_urlcheck_to_be_deblacklisted" | grep -q "[[:alnum:]]" && _urlcheck_deblacklist_lines "$_urlcheck_to_be_deblacklisted"
    printf %s "$_urlcheck_to_be_whitelisted" | grep -q "[[:alnum:]]" && _urlcheck_whitelist_lines "$_urlcheck_to_be_whitelisted"
    printf %s "$_urlcheck_to_be_dewhitelisted" | grep -q "[[:alnum:]]" && _urlcheck_dewhitelist_lines "$_urlcheck_to_be_dewhitelisted"
}

_urlcheck() {
    #$1=command $2=full domain name $3=raw URL
    case "$1" in
        status)
            if [ $_urlcheck_recursive -eq 0 ]; then
                _urlcheck_status_list="$2"
                _urlcheck_status_lines "$_urlcheck_status_list" status
            elif [ $_urlcheck_recursive -eq 1 ]; then
                _urlcheck_status_list="$2
$(_urlcheck_scrape_url "$3")"
                _urlcheck_status_lines "$_urlcheck_status_list" status
            else
                _urlcheck_status_lines "$2
$(_urlcheck_scrape_url "$3")" status
                _urlcheck_status_list="$are_blocked"
            fi
            _urlcheck_status_display=$(printf %s "$_urlcheck_status_list" | \
              grep "[[:alnum:]]" | \
              while read _urlcheck_status_check_domain; do
                _urlcheck_status_url "$_urlcheck_status_check_domain"
                printf %s\\n "$_urlcheck_status_single_line"
            done)
            printf %s\\n "$_urlcheck_status_display"
        ;;
        blacklist)
            if [ $_urlcheck_opposite -eq 0 ]; then
                if [ $_urlcheck_recursive -eq 0 ]; then
                    _urlcheck_blacklist_dialog "$2"
                    [ $_urlcheck_block_01 -eq 1 ] && \
                      _urlcheck_block_dialog "$2"
                else
                    _urlcheck_blacklist_scraped="$2
$(_urlcheck_scrape_url "$3")"
                    _urlcheck_blacklist_dialog "$_urlcheck_blacklist_scraped"
                    [ $_urlcheck_block_01 -eq 1 ] && \
                      _urlcheck_block_dialog "$_urlcheck_blacklist_scraped"
                fi
            else
                if [ $_urlcheck_recursive -eq 0 ]; then
                    _urlcheck_deblacklist_dialog "$2"
                else
                    _urlcheck_deblacklist_dialog "$2
$(_urlcheck_scrape_url "$3")"
                fi
            fi
        ;;
        whitelist)
            if [ $_urlcheck_opposite -eq 0 ]; then
                if [ $_urlcheck_recursive -eq 0 ]; then
                    _urlcheck_whitelist_dialog "$2"
                    [ $_urlcheck_block_01 -eq 1 ] && \
                      _urlcheck_unblock_dialog "$2"
                else
                    _urlcheck_whitelist_scraped="$2
$(_urlcheck_scrape_url "$3")"
                    _urlcheck_whitelist_dialog "$_urlcheck_whitelist_scraped"
                    [ $_urlcheck_block_01 -eq 1 ] && \
                      _urlcheck_unblock_dialog "$_urlcheck_whitelist_scraped"
                fi
            else
                if [ $_urlcheck_recursive -eq 0 ]; then
                    _urlcheck_dewhitelist_dialog "$2"
                else
                    _urlcheck_dewhitelist_dialog "$2
$(_urlcheck_scrape_url "$3")"
                fi
            fi
        ;;
        inspect)
            if [ $_urlcheck_recursive -eq 0 ]; then
                _urlcheck_status_lines "$2" "inspect"
                _urlcheck_inspect "$2"
            elif [ $_urlcheck_recursive -eq 1 ]; then
                _urlcheck_status_scrape="$2
$(_urlcheck_scrape_url "$3")"
                _urlcheck_status_lines "$_urlcheck_status_scrape" "inspect"
                _urlcheck_inspect "$_urlcheck_status_scrape"
            else
                _urlcheck_status_lines "$2
$(_urlcheck_scrape_url "$3")" "inspect"
                _urlcheck_inspect "$are_blocked"
            fi
        ;;
        *)
            if [ $_urlcheck_block_01 -eq 1 ] || [ "$1" = "block" ]; then
                if [ $_urlcheck_opposite -eq 0 ]; then
                    if [ $_urlcheck_recursive -eq 0 ]; then
                        _urlcheck_block_dialog "$2"
                    else
                        _urlcheck_block_dialog "$2
$(_urlcheck_scrape_url "$3")"
                    fi
                else
                    if [ $_urlcheck_recursive -eq 0 ]; then
                        _urlcheck_unblock_dialog "$2"
                    else
                        _urlcheck_unblock_dialog "$2
$(_urlcheck_scrape_url "$3")"
                    fi
                fi
            fi
        ;;
    esac
    if [ -f "$tmpdir"/"${hostsfile##*/}".tmp ]; then
        mv $_v -- "$tmpdir"/"${hostsfile##*/}".tmp "$hostsfile"
        chmod 644 "$hostsfile"
    elif [ -f "$tmpdir"/changed ]; then
        touch "$hostsfile"
    fi
}

_job() {
    # CHECK FOR OPTIONAL DECOMPRESSION DEPENDENCIES, SET UP FUNCTIONS THEREOF
    # THAT DUMP TO STDOUT
    if command -v bsdtar >/dev/null 2>&1; then
        _unzip_available=1
        _unzip() {
            bsdtar $_v_bsdtar -Oxf "$1" -- | _sanitize
        }
    elif command -v unzip >/dev/null 2>&1; then
        _unzip_available=1
        _unzip() {
            if unzip -l "$1" | tail -n1 | grep -q "\b1 file\b"; then
                unzip -c -a $_v_unzip -- "$1" | _sanitize
            else
                mkdir -p $_v -- "$tmpdir"/"${1##*/}".d
                unzip -B -o -j -a -d "$tmpdir"/"${1##*/}".d $_v_unzip -- "$1" && \
                { find "$tmpdir"/"${1##*/}".d -type f -print0 | \
                  xargs -0 cat ; } | _sanitize
                _exit=$?
                rm -rf $_v -- "$tmpdir"/"${1##*/}".d
                return $_exit
            fi
        }
    else
        _notify 1 "Dearchiver for zip NOT FOUND. Optional functions which use this format will be skipped."
        _unzip_available=0
    fi
    if command -v bsdtar >/dev/null 2>&1; then
        _un7zip_available=1
        _un7zip() {
            bsdtar $_v_bsdtar -Oxf "$1" -- | _sanitize
        }
    else
        if command -v 7zr >/dev/null 2>&1; then
            _un7zip_available=1
            _7zip_bin() {
                7zr "$@"
            }
        elif command -v 7za >/dev/null 2>&1; then
            _un7zip_available=1
            _7zip_bin() {
                7za "$@"
            }
        elif command -v 7z >/dev/null 2>&1; then
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
                if _7zip_bin l "$1" | \
                  grep -A1 "^Scanning the drive for archives:" | \
                  grep -q "^1 file\b"; then
                    _7zip_bin e -so -- "$1" | _sanitize
                else
                    mkdir -p $_v -- "$tmpdir"/"${1##*/}".d
                    _7zip_bin e -so -o "$tmpdir"/"${1##*/}".d -- "$1" && \
                    { find "$tmpdir"/"${1##*/}".d -type f -print0 | \
                      xargs -0 cat ; } | _sanitize
                    _exit=$?
                    rm -rf $_v -- "$tmpdir"/"${1##*/}".d
                    return $_exit
                fi
            }
        fi
    fi
    # DOWNLOAD BLOCKLISTS AND/OR REDIRECT LISTS
    _notify 1 "Checking blocklists and/or redirectlists for updates..."

    [ -d "$tmpdir"/downloads/ ] && rm -rf $_v -- "$tmpdir"/downloads/
    mkdir -p $_v -- "$tmpdir"/downloads/
    sed "s/#.*//g" $blocklists $redirectlists | grep "[[:alnum:]]" | \
      while read _url; do
        if [ $max_simultaneous_downloads -gt 0 ]; then
            while [ $(find "$tmpdir"/downloads -type f | wc -l) -ge $max_simultaneous_downloads ]; do
                sleep 0.1
            done
        fi
        _job_download_list "$_url" & 
    done
    wait
    while [ $(find "$tmpdir"/downloads -type f | wc -l) -ne 0 ]; do
        sleep 0.1
    done

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
            _sanitize() {
                tr -s '\t\r ' ' ' | sed -e "s/[#;<].*//g" -e "s/^ //g" \
                  -e "s/ $//g" | grep -hIe "^0\.0\.0\.0 " -e "^127\.0\.0\.1 " \
                  -e "^0 " -e "^:: " | cut -d' ' -f2 | \
                  grep -I "^[[:alnum:]]*\.[[:alnum:]]*" | sed "s/^/$redirecturl /g"
            }
            _sanitize_raw() {
                grep -Ih "^[[:alnum:]]*\.[[:alnum:]]*" | tr -s '\t\r ' ' ' | \
                  sed -e "s/[#;<].*//g" -e "s/^ //g" -e "s/ $//g" | grep -Ihv " " | \
                  grep -I "^[[:alnum:]]*\.[[:alnum:]]*" | sed "s/^/$redirecturl /g"
            }
            _job_extract_from_cachefiles "$blocklists"
        fi
    
        # EXTRACT REDIRECT ENTRIES DIRECTLY FROM CACHED FILES
        if [ "$redirectlists" ]; then
            _notify 1 "  Extracting redirectlists..."
            _sanitize() {
                grep -IE "[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}" | \
                  tr -s '\t\r ' ' ' | sed -e "s/[#;<].*//g" -e "s/^ //g" -e "s/ $//g" | \
                  grep -IE "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} "
            }
            _sanitize_raw() {
                _sanitize
            }
            _job_extract_from_cachefiles "$redirectlists"
        fi

        # APPEND BLACKLIST ENTRIES
        _notify 1 "  Appending blacklist entries..."

        while read _blacklistline; do
            grep -Fqx "$redirecturl $_blacklistline" "$hostsfile".new || \
              printf %s\\n "$redirecturl $_blacklistline" >> "$hostsfile".new
        done < "$blacklist" && \
        mv $_v -- "$hostsfile".new "$hostsfile" && \
        chmod 644 "$hostsfile"
        _notify 1 "$hostsfile successfully compiled. DONE."
    else
        _notify 1 "No new changes. DONE."
    fi

}

################### MAIN PROCESS COMMON TO URLCHECK AND JOB ###################

# VARIABLE DEFAULTS
command -v getent >/dev/null 2>&1 && HOME="$(getent passwd hostsblock | cut -d: -f6)"
HOME="${HOME:-/var/lib/hostsblock}"
hostsfile="$HOME/hosts.block"
redirecturl='0.0.0.0'
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
_urlcheck_recursive=0
_urlcheck_opposite=0
_urlcheck_block_01=0
_urlcheck_command="status"

# GET OPTIONS
while getopts "f:qvduc:sblwirko" _option; do
    case "$_option" in
        f)  [ "$OPTARG" != "" ] && _configfile="$OPTARG";;
        q)  _verbosity=0;;
        v)  _verbosity=2;;
        d)  _verbosity=3;;
        u)  _changed=1;;
        c)  [ "$OPTARG" != "" ] && _URL="$OPTARG";;
        s)  _urlcheck_command="status";;
        b)  _urlcheck_block_01=1;;
        l)  _urlcheck_command="blacklist";;
        w)  _urlcheck_command="whitelist";;
        i)  _urlcheck_command="inspect";;
        r)  _urlcheck_recursive=1;;
        k)  _urlcheck_recursive=2;;
        o)  _urlcheck_opposite=1;;
        *)
            cat << EOF 1>&2
Usage:
  $0 [OPTION...] - download and combine HOSTS files

  $0 [OPTION...] -c URL [COMMANDS...] - Manage how URL is handled

Help Options:
  -h                    Show help options

Options:
  -f CONFIGFILE         Specify an alternative configuration file
  -q                    Show only fatal errors
  -v                    Be verbose
  -d                    Be very verbose/debug
  -u                    Force hostsblock to update its target file
  -c URL COMMAND        urlCheck Mode (see below)

$0 -c URL (urlCheck) Commands:
  -s [-r -k]            State how hostblock modifies URL
  -b [-o -r]            Temporarily (un)block URL
  -l [-o -r -b]         Add/remove URL to/from blacklist
  -w [-o -r -b]         Add/remove URL to/from whitelist
  -i [-o -r -k]         Interactively inspect URL

$0 -c URL Command Subcommands:
  -r                    COMMAND recurses to all domains on URL's page
  -k                    COMMAND recurses for all BLOCKED domains on page
  -o                    Perform opposite of COMMAND (e.g UNblock)
  -b                    With "-l", immediately block URL
                        With "-w", immediately unblock URL
EOF
            exit 1
        ;;
    esac
done 

# SET VERBOSITY FOR SCRIPT AND ITS SUBPROCESSES
if [ $_verbosity -eq 0 ]; then
    _v=""
    _v_curl="-s"
    _v_bsdtar=""
    _v_unzip="-qq"
    set +x
elif [ $_verbosity -eq 1 ]; then
    _v=""
    _v_curl="-s"
    _v_bsdtar=""
    _v_unzip="-qq"
    set +x
elif [ $_verbosity -eq 2 ]; then
    _v="-v"
    _v_curl="-v"
    _v_bsdtar="-v"
    _v_unzip="-v"
    set +x
else
    _v="-v"
    _v_curl="-v"
    _v_unzip="-v"
    set -x
fi

# CHECK FOR CORRECT PRIVILEDGES AND DEPENDENCIES
if [ "$(id -un)" != "hostsblock" ]; then
    _notify 0 "WRONG PERMISSIONS. RUN AS USER hostsblock, EITHER DIRECTLY OR VIA SUDO, E.G. sudo -u hostsblock $0 $@\n\nYou may have to add the following line to the end of sudoers after typing 'sudo visudo':\n %hostsblock  ALL  =  (hostblock)  NOPASSWD:  $0\nAnd then add your current user to the hostsblock group:\nsudo gpasswd -a $(id -un) hostsblock\n\nExiting..."
    exit 3
fi

# SOURCE CONFIG FILE
if [ $_configfile ] && [ -f "$_configfile" ]; then
    . "$_configfile"
elif [ "$(id -un)" = "hostsblock" ] && [ -f ${HOME}/hostsblock.conf ]; then
    . ${HOME}/hostsblock.conf
elif [ -f /var/lib/hostsblock/hostsblock.conf ]; then
    . /var/lib/hostsblock/hostsblock.conf
    _notify 1 "Configuration file not found. Using defaults."
fi
TMPDIR="$tmpdir"

mkdir -p $_v -- "$tmpdir"
[ $_changed -eq 1 ] && touch "$tmpdir"/changed

[ -f "$whitelist" ] || touch "$whitelist"
[ -f "$blacklist" ] || touch "$blacklist"

# MAKE SURE NECESSARY DEPENDENCIES ARE PRESENT
for _depends in chmod cksum cp curl cut file find grep id mkdir \
    mv rm sed sort tee touch tr wc xargs; do
    if ! command -v "$_depends" >/dev/null 2>&1; then
        _notify 0 "MISSING REQUIRED DEPENDENCY $_depends. PLEASE INSTALL. EXITING..."
        exit 5
    fi
done

_return=0

# DECIDE IF RUNNING AS JOB OR AS URLCHECK
if [ "$_URL" ]; then
    if [ $_urlcheck_command = "status" ] && [ $_urlcheck_block_01 -eq 1 ]; then
        _urlcheck_command="block"
    fi
    _complete_domain_name=$(printf %s "${_URL#*//}" | sed "s/\/.*//g")
    _urlcheck "$_urlcheck_command" "$_complete_domain_name" "$_URL"
else
    _job
fi

# CLEAN UP
rm -rf $_v -- "$tmpdir"

# EXIT
exit $_return
# exit codes for non-interactive commands
# 0   = no errors
# +1  any status scans failed
# +2  block/unblock failed
# +4  block/unblock not applied because it was already in that state
# +8  blacklist/deblacklist failed
# +16 blacklist/deblacklist not applied because it was already in that state
# +32 whitelist/dewhitelist failed
# +64 whitelist/dewhitelist not applied because it was already in that state
