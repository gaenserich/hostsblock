#!/bin/bash
# DO NOT MODIFY THIS FILE. MODIFY SETTINGS VIA THE CONFIGURATION FILES IN
# /etc/hostsblock.conf

# DEFAULT SETTINGS
hostsfile="/etc/hosts.block"
redirecturl="127.0.0.1"
postprocess(){
    /etc/rc.d/dnsmasq restart
}
USECOLOR="yes"
blacklist="/etc/hostsblock/black.list"
whitelist="/etc/hostsblock/white.list"
hostshead="0"
optimize="0"

# SOURCE MAIN CONFIGURATION FILE
if [ -f /etc/hostsblock/rc.conf ]; then
    . /etc/hostsblock/rc.conf
else
    echo "Config file /etc/hostsblock/rc.conf not found. Using defaults."
fi

# CHECK SUBROUTINE
check(){
    if grep "[[:space:]]`echo $@ | sed 's|\.|\\\.|g'`$" "$hostsfile" &>/dev/null; then
	printf "\e[1;31mBLOCKED: \e[0;37m'$@' \e[0;32mUnblock? \e[0;37m[y/N] "
        read a
        if [[ $a == "y" || $a == "Y" ]]; then
            echo "Unblocking $@"
            echo " $@" >> "$whitelist"
            sed -i "/$@/d" "$blacklist"
            sed -i "/ $@/d" "$hostsfile"
            changed=1
        fi
    else
        printf "\e[0;32mNOT BLOCKED: \e[0;37m'$@' \e[1;31mBlock? \e[0;37m[y/N] "
        read a
        if [[ $a == "y" || $a == "Y" ]]; then
            echo "Blocking $@"
            echo "$@" >> "$blacklist"
            sed -i "/$@/d" "$whitelist"
            echo "$redirecturl $@" >> "$hostsfile"
            changed=1
        fi
    fi
}

# MAIN ROUTINE
if [[ "$@" == "-h" || "$@" == "--help" ]]; then
    cat << EOF

usage: $0 http[s]://[url]

$0 will first verify that [url] is blocked or unblocked,
and then scan that url for further contained subdomains.
EOF
else
    changed=0
    echo "Verifying that the given page is blocked or unblocked"
    check `echo "$@" | sed -e "s/.*https*:\/\///g" -e "s/[\/?'\" :<>\(\)].*//g"`
    [ "$changed" == "1" ] && postprocess &>/dev/null
    printf "Page domain verified. Scan the whole page for other domains for (un)blocking? [y/N] "
    read a
    if [[ $a == "y" || $a == "Y" ]]; then
        for LINE in `curl -s "$@" | tr ' ' '\n' | grep -- "http" | sed -e "s/.*https*:\/\///g" -e "s/[\/?'\" :<>\(\)].*//g" |\
        sort -u | grep -- "\."`; do
            check "$LINE"
        done
        echo "Whole-page scan completed."
    fi
    [ "$changed" == "1" ] && postprocess &>/dev/null
fi
