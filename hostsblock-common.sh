#!/bin/bash
# SUBROUTINES

## Present messages at varying verbosity levels:
### Level 0: Only fatal errors
### Level 1: Level 0 + non-fatal errors
### Level 2: Level 1 + updates to cache files
### Level 3: Level 2 + narration of each major phase
### Level 4: Level 3 + step-by-step details of all processes
### Level 5: Level 4 + stdout/stderr from sub-processes like curl, zip, 7za, etc.

_notify() {
    if [ -z "$PS1" ] && [[ $- =~ i ]]; then
        case $1 in
            0) _level="[\e[1;31mFATAL\e[0m]" ;;
            1) _level="[\e[1;31mWARN\e[0m]" ;;
            2) _level="[\e[0;33mNOTE\e[0m]" ;;
            3) _level="[\e[0;33mINFO\e[0m]" ;;
            4) _level="[\e[0;32mDETAIL\e[0m]" ;;
            5) _level="[\e[0;32mDEBUG\e[0m]" ;;
        esac
    else
        case $1 in
            0) _level="[FATAL]" ;;
            1) _level="[WARN]" ;;
            2) _level="[NOTE]" ;;
            3) _level="[INFO]" ;;
            4) _level="[DETAIL]" ;;
            5) _level="[DEBUG]" ;;
        esac
    fi
    if [ $verbosity -ge $1 ]; then
        echo -e "${_level} $2"
    else
        true
    fi
}

## Report counts of addresses from a given hosts-like file
_count_hosts() {
    grep -ah -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" "$@" | cut -d" " -f1 | sort -u | while read _addr; do
        _number=$(grep -c -- "^$_addr" "$@")
        _notify 3 "$@: $_number urls redirected to $_addr."
    done
}

## Backup and/or recycle existing hostsfile
_backup_old() {
    if [ $recycle_old == 1 ] || [ "$recycle_old" == "1" ] || [ "$recycle_old" == "yes" ] || [ "$recycle_old" == "true" ]; then
        _notify 3 "Recycling old $hostsfile into new version..."
        sort -u "$hostsfile" | sed "s|$| ! /etc/hosts.block.old|g" > "$tmpdir"/hostsblock/hosts.block.d/hosts.block.old && \
          _notify 3 "Recycled old $hostsfile into new version." || \
          _notify 1 "FAILED to recycle old $hostsfile into new version."
    else
        _notify 3 "Old $hostsfile will not be recycled into new version."
    fi
    if [ $backup_old == 0 ] || [ "$backup_old" == "0" ] && [ "$backup_old" == "no" ] && [ "$backup_old" == "false" ]; then
        _notify 4 "Old $hostfile will not be backed up."
    else
        _notify 4 "Backing up old version of $hostsfile..."
        ls "$hostsfile".old* &>/dev/null && rm "$hostsfile".old*
        cp $_v -f -- "$hostsfile" "$hostsfile".old && \
        if [ $backup_old == 1 ] || [ "$backup_old" == "1" ] || [ "$backup_old" == "yes" ] || [ "$backup_old" == "true" ]; then
            _notify 3 "Backed up old $hostsfile."
        else
            eval $backup_old $_v -- "$hostsfile".old && \
            _notify 3 "Backed up and compressed old $hostsfile with $backup_old." || _notify 1 "FAILED to compress $hostsfile with $backup_old."
        fi || \
        _notify 1 "FAILED to backup $hostsfile."
    fi
}

## Extract entries from cachefiles
_extract_entries() {
    _notify 4 "Extracting entries from $_cachefile..."
    [ -d "$_cachefile_dir" ] || mkdir $_v -- "$_cachefile_dir" && \
      _notify 4 "Created directory $_cachefile_dir." || _notify 1 "FAILED to create directory $_cachefile_dir." 
    cd "$_cachefile_dir"
    case "$_decompresser" in
        none)
            _compress_exit=0
            _notify 4 "No need to decompress $_basename_cachefile."
            cp $_v -- "$_cachefile" "$_cachefile_dir"/ && _notify 4 "Moved $_basename_cachefile to $_cachefile_dir." || \
              _notify 1 "FAILED to move $_basename_cachefile to $_cachefile_dir."
        ;;
        unzip)
            unzip -B -o -j $_v_unzip -- "$_cachefile" && _compress_exit=0 || _compress_exit=1
            [ $_compress_exit == 0 ] && _notify 3 "Unzipped $_basename_cachefile." || _notify 1 "FAILED to unzip $_basename_cachefile."
        ;;
        7z*)
            if [ $verbosity -le 4 ]; then
                eval $_7zip_available e "$_cachefile" &>/dev/null && _compress_exit=0 || _compress_exit=1
            else
                eval $_7zip_available e "$_cachefile" && _compress_exit=0 || _compress_exit=1
            fi
            [ $_compress_exit == 0 ] && _notify 3 "Un7zipped $_basename_cachefile." || _notify 1 "FAILED to un7zip $_basename_cachefile."
        ;;
    esac
    if [ $_compress_exit == 0 ]; then
        _target_hostsfile="$tmpdir/hostsblock/hosts.block.d/$_basename_cachefile.hosts"
        _notify 4 "Extracting obvious entries from $_basename_cachefile..."
        _cachefile_url=$(cat "$cachedir"/"$_basename_cachefile".url | head -n1)
        if grep -rah -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" ./* | sed -e 's/[[:space:]][[:space:]]*/ /g' -e \
          "s/\#.*//g" -e "s/[[:space:]]$//g" -e "s/$_notredirect/$redirecturl/g" | sort -u | grep -vf "$whilelist" | \
           sed "s|$| \! $_cachefile_url|g" > "$_target_hostsfile"; then
            _notify 4 "Extracted obvious entries from $_basename_cachefile."
            if [ $verbosity -ge 4 ]; then
                _count_hosts "$_target_hostsfile"
            fi
        else
            _notify 1 "FAILED to extract any obvious entries from $_basename_cachefile."
        fi
        _notify 4 "Extracting less-obvious entries from $_basename_cachefile"
        if grep -rahv "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" ./* | grep -v "^\." | grep -v "\.$" | grep -v "\*" |\
          grep -v "\"" | grep -v "\$" | grep "[a-z]" | grep "\." | sed "s/^/$redirecturl /g" | sed -e 's/[[:space:]][[:space:]]*/ /g' \
          -e "s/\#.*//g" -e "s/[[:space:]]$//g" | sort -u | grep -vf "$whilelist" | sed "s|$| \! $_cachefile_url|g" |\
           >> "$_target_hostsfile"; then
            _notify 4 "Extracted less-obvious entries from $_basename_cachefile."
            if [ $verbosity -ge 4 ]; then
                _count_hosts "$_target_hostsfile"
            fi
        else
            _notify 1 "FAILED to extract any less-obvious entries from $_basename_cachefile." 
        fi
        _notify 4 "Deleting $_cachefile_dir..."
        cd "$tmpdir"/hostsblock && \
        rm $_v -r -- "$_cachefile_dir" && _notify 4 "Deleted $_cachefile_dir." || _notify 1 "FAILED to delete $_cachefile_dir."
    fi
}

# OVERRIDE VERBOSITY SETTING IF SPECIFIED ON THE COMMAND LINE
_verbosity_check() {
    if [ $_verbosity_override ]; then
        _notify 4 "Overriding verbosity from $verbosity to $_verbosity_override given from the command line."
        verbosity=$_verbosity_override
    fi
}

# SET VERBOSITY VARIABLES FOR SUB-PROCESSES
_set_subprocess_verbosity() {
    if [ $verbosity -le 2 ]; then
        _v=""
        _v_curl="-s"
        _v_unzip="-qq"
    elif [ $verbosity -le 4 ]; then
        _v=""
        _v_curl="-s"
        _v_unzip="-q"
    else
       _v="-v"
       _v_curl="-v"
       _v_unzip="-v"
    fi
}

# PRELIMINARY CHECK FOR CORRECT PRIVALEDGES AND DEPENDENCIES
_check_root() {
    if [ $(whoami) != "root" ]; then
        _notify 0 "INSUFFICIENT PERMISSIONS. RUN AS ROOT OR VIA SUDO. EXITING."
        exit 3
    else
        _notify 4 "Running as root, which is what we want."
    fi
}

# MAKE SURE NECESSARY DEPENDENCIES ARE PRESENT
_check_depends() {
    for _depends in $@; do
        if which "$_depends" &>/dev/null; then
            _notify 4 "$_depends found."
        else
            _notify 0 "MISSING REQUIRED DEPENDENCY $_depends. PLEASE INSTALL. EXITING."
            exit 5
        fi
    done
}

# CHECK FOR OPTIONAL DECOMPRESSION DEPENDENCIES
_check_unzip() {
    if which unzip &>/dev/null; then
        _notify 4 "unzip found. Will use it to extract zip archives."
        _unzip_available=1
    else
        _notify 1 "Dearchiver for zip NOT FOUND. Optional functions which use this format will be skipped."
        _unzip_available=0
    fi
}

_check_7z() {
    if which 7za &>/dev/null; then
        _notify 4 "7za found. Will use it to handle 7z archives."
        _7zip_available="7za"
    elif which 7z &>/dev/null; then
        _notify 4 "7z found. Will use it to handle 7z archives."
        _7zip_available="7z"
    else
        _notify 1 "Dearchiver for 7za NOT FOUND. Optional functions which use this format will be skipped."
        _7zip_available=0
    fi
}

# SOURCE CONFIG FILE
_source_configfile() {
    if [ $_configfile ]; then
        if [ -f "$_configfile" ]; then
            . "$_configfile"
            _notify 4 "Using configuration file $_configfile."
        elif [ -f /etc/hostsblock/hostsblock.conf ]; then
            . /etc/hostsblock/hostsblock.conf
            _notify 1 "Configuration file $_configfile NOT FOUND, using /etc/hostsblock/hostsblock.conf."
        else
            _notify 1 "Both configuration files $_configfile and /etc/hostsblock/hostsblock.conf NOT FOUND, using defaults."
        fi
    elif [ -f /etc/hostsblock/hostsblock.conf ]; then
        . /etc/hostsblock/hostsblock.conf
        _notify 4 "Using configuration file /etc/hostsblock/hostsblock.conf."
    else
        _notify 1 "Configuration file /etc/hostsblock/hostsblock.conf NOT FOUND, using defaults."
    fi
}

# REWRITE A GIVEN FILE SANS REGEX STATEMENT
_strip_entries() {
    grep -v "$1" "$2" > "$2".tmp && \
      mv $_v -f -- "$2".tmp "$2"
}


# CHECK TO SEE IF GIVEN URL IS BLOCKED OR UNBLOCKED AND OFFER TO CHANGE THIS.
_check_url(){
    _url_escaped=$(echo "$@" | sed "s/\./\\\./g")
    _matches=$(grep " $_url_escaped " "$annotate")
    _block_matches=$(echo "$_matches" | grep -- "^$redirecturl" | sed "s/.* \!\(.*\)$/\1/g" | tr '\n' ',' | sed "s/,$//g")
    _redirect_matches=$(echo "$_matches" | grep -v "^$redirecturl" | \
      sed "s/^\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\) .* \! \(.*\)$/to \1 by blocklist \2/g" | tr '\n' ',' | sed "s/,$//g")
    if [ $(echo "$_block_matches" | wc -w) -gt 0 ] || [ $(echo "$_redirect_matches" | wc -w) -gt 0 ]; then
        [ $(echo "$_block_matches" | wc -w) -gt 0 ] && echo -e "\n'$@' \e[1;31mBLOCKED \e[0mby blocklist(s)${_block_matches}"
        [ $(echo "$_redirect_matches" | wc -w) -gt 0 ] && echo -e "\n'$@' \e[1;33mREDIRECTED \e[0m$_redirect_matches" 
        echo -e "\t1) Unblock/unredirect just $@\n\t2) Unblock/unredirect all sites containing url $@\n\t3) Keep blocked/redirected"
        read -p "1-3 (default: 3): " b
        if [[ $b == 1 || "$b" == "1" ]]; then
            echo "Unblocking just $@"
            echo " $@ " >> "$whitelist"
            _strip_entries " $@$" "$annotate"
            _strip_entries " $@$" "$blacklist"
            _strip_entries " $@$" "$hostsfile"
            _changed=1
        elif [[ $b == 2 || "$b" == "2" ]]; then
            echo "Unblocking all sites containing url $@"
            echo "$@" >> "$whitelist"
            _strip_entries "$@" "$annotate"
            _strip_entries "$@" "$blacklist"
            _strip_entries "$@" "$hostsfile"
            _changed=1
        fi
    else
        echo -e "\n'$@' \e[0;32mNOT BLOCKED/REDIRECTED\e[0m\n\t1) Block $@\n\t2) Block $@ and delete all whitelist url entries containing $@\n\t3) Keep unblocked (default)"
        read -p "1-3 (default: 3): " c
        if [[ $c == 1 || "$c" == "1" ]]; then
            echo "Blocking $@"
            echo "$@" >> "$blacklist"
            echo "$redirecturl $@ \! $blacklist" >> "$annotate" &
            _strip_entries "^$@$" "$whitelist" &
            echo "$redirecturl $@" >> "$hostsfile" &
            _changed=1
            wait
        elif [[ $c == 2 || "$c" == "2" ]]; then
            echo "Blocking $@ and deleting all whitelist url entries containing $@"
            echo "$@" >> "$blacklist" &
            echo "$redirecturl $@ \! $blacklist" >> "$annotate" &
            _strip_entries "$@" "$whitelist" &
            echo "$redirecturl $@" >> "$hostsfile" &
            _changed=1
        fi
    fi
}

_check_dhcpcd_config() {
    if [ -f /etc/resolv.conf.head ] && grep -v -- "^\#" /etc/resolv.conf.head | grep -- "nameserver" | grep -q -- "127\.0\.0\.1"; then
        _notify 4 "/etc/resolv.conf.head exists and is properly configured."
        _notify 4 "DHCPCD configured correctly."
        true
    else
        _notify 3 "/etc/resolv.conf.head does NOT exist or does NOT have the correct entry."
        _notify 4 "Please add 'nameserver 127.0.0.1' to /etc/resolv.conf.head to correct the last error."
        _notify 3 "DHCPCD incorrectly configured."
        false
    fi
}

_check_dhclient_config() {
    _dhclient_config=$(find /etc/ -type f -iname 'dhclient.conf' | head -n1)
    if [ -f "$_dhclient_config" ] && grep -v -- "^\#" "$_dhclient_config" | grep -- "prepend" | grep -q -- "127\.0\.0\.1"; then
        _notify 4 "/etc/dhclient.conf exists and is properly configured."
        _notify 3 "DHCLIENT configured correctly."
        true
    else
        _notify 3 "dhclient.conf does NOT exist or does NOT have the correct entry."
        _notify 4 "Please add 'prepend domain-name-servers 127.0.0.1;' to dhclient.conf to correct the last error."
        _notify 3 "DHCLIENT incorrectly configured."
        false
    fi
}

_detect_dhcp_client() {
    if pidof dhcpcd &>/dev/null && _check_dhcpcd_config; then
        _notify 4 "DHCPCD found and properly configured."
        _dhcp_client=dhcpcd
    elif pidof dhclient &>/dev/null && _check_dhclient_config; then
        _notify 4 "DHCLIENT found and properly configured."
        _dhcp_client=dhclient
    else
        _notify 0 "DHCP CLIENT NOT FOUND OR NOT OPERATIONAL. EXITING..."
        exit 1
    fi
}

_check_dnsmasq_config() {
    _dnsmasq_config_correct=1
    _dnsmasq_ps=$(ps -eo comm,args | grep -- "^[d]nsmasq")
    if echo "$_dnsmasq_ps" | grep -q -- " -C | --config-file="; then
        _dnsmasq_config_file_tmp=$(echo "$_dnsmasq_ps" | grep -- " -C | --config-file=" | sed -e "s/.* -C \(.*\)[ $]/\1/g" -e \
          "s/.* --config-file=\(.*\)[ $]/\1/g")
        _dnsmasq_config_file="${dnsmasq_config_file_tmp%%[ $]*}"
    else
        _dnsmasq_config_file="/etc/dnsmasq.conf"
    fi
    _notify 4 "Detected $_dnsmasq_config_file as DNSMASQ's configuration file."
    if grep -v -- "^\#" "$_dnsmasq_config_file" | grep -q -- "addn-hosts=$hostsfile"; then
        _notify 4 "DNSMASQ has correct 'addn-hosts' entry."
    else
        _notify 3 "DNSMASQ does NOT have the correct 'addn-hosts' entry."
        _notify 4 "Please add 'addn-hosts=$hostsfile' to $_dnsmasq_config_file to correct the last error."
        _dnsmasq_config_correct=0
    fi
    if grep -v -- "^\#" "$_dnsmasq_config_file" | grep -q -- "listen-address=127.0.0.1"; then
        _notify 4 "DNSMASQ has correct 'listen-address' entry."
    else
        _notify 3 "DNSMASQ does NOT have the correct 'listen-address' entry."
        _notify 4 "Please add 'listen-address=127.0.0.1' to $_dnsmasq_config_file to correct the last error."
        _dnsmasq_config_correct=0
    fi
    if [ $_dnsmasq_config_correct == 1 ]; then
        _notify 4 "DNSMASQ configured correctly."
        _dnscacher() {
            pkill -HUP -- dnsmasq
        }
        true
    else
        _notify 3 "DNSMASQ incorrectly configured."
        false
   fi
}

_detect_dnscacher() {
    case $dnscacher in
        *none*)
            if [ "$hostsfile" == "/etc/hosts" ]; then
                _notify 4 "Using NO dnscacher."
            else
                _notify 0 "USING no DNSCACHER, BUT THE 'hostsfile' VARIABLE IS NOT SET TO /etc/hosts."
                _notify 0 "YOU MISCONFIGURED hostsblock."
                _notify 0 "IF YOU THINK YOU GOT THIS MESSAGE IN ERROR, TRY 'manual' AS YOUR 'dnscacher' ENTRY."
                _notify 0 "EXITING..."
                exit 1
            fi
        ;;
        *dnsmasq*)
            if _check_dnsmasq_config && _detect_dhcp_client; then
                _notify 4 "Using DNSMASQ and $_dhcp_client..."
            else
                _notify 0 "DNSMASQ AND/OR THE DHCP CLIENT ARE NOT CONFIGURED CORRECTLY. EXITING..."
                exit 1
            fi
        ;;
        *manual*)
            _notify 4 "Using manual configuration of dnscacher (see the postprocess entry in $configfile)"
        ;;
        *auto*)
            _notify 3 "Auto-detecting dnscaching settings..."
            if _check_dnsmasq_config && _detect_dhcp_client; then
                _notify 4 "Using DNSMASQ and $_dhcp_client..."
            elif [ "$hostsfile" == "/etc/hosts" ]; then
                _notify 4 "Using NO dnscacher."
            else
                _notify 0 "NO VIABLE DNSCACHER CONFIGURATION FOUND. EXITING..."
                exit 1
            fi
        ;;
    esac
}

# SET DEFAULT SETTINGS
export tmpdir="/dev/shm"
export hostsfile="/etc/hosts"
export redirecturl="127.0.0.1"
export dnscacher="auto"
postprocess() {
     /bin/true
}
export blocklists=("http://support.it-mate.co.uk/downloads/HOSTS.txt")
export blacklist="/etc/hostsblock/black.list"
export whilelist="/etc/hostsblock/white.list"
export hostshead="0"
export cachedir="/var/cache/hostsblock"
export redirects="0"
export connect_timeout=60
export retry=0
if which pigz &>/dev/null; then
    export backup_old="pigz"
elif which gzip &>/dev/null; then
    export backup_old="gzip"
else
    export backup_old=0
fi
export recycle_old=1
export verbosity=1
export annotate=/var/lib/hostsblock.db
