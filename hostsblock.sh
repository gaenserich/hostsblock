#!/bin/bash

# DO NOT MODIFY THIS FILE. MODIFY SETTINGS VIA THE CONFIGURATION FILES IN
# /etc/hostsblock/

# CHECK FOR NEEDED AND OPTIONAL UTILITIES AND PERMISSIONS
if [ `whoami` != "root" ]; then
    echo "Insufficient permissions. Run as root."
    exit 1
fi

for dep in curl grep sed tr cut; do
    if which "$dep" &>/dev/null; then
        true
    else
        if [ "$dep" == "tr" ]; then
            echo "coreutils is not installed or not in your PATH. Please remedy. Exiting."
        else
            echo "Utility $dep not installed or not in your PATH. Please remedy. Exiting."
        fi
        exit 1
    fi
done

if which unzip &>/dev/null; then
    zip="1"
else
    echo "Dearchiver unzip not found. URLs which use this format will be skipped."
    zip="0"
fi
if which 7za &>/dev/null; then
    zip7="1"
else
    echo "Dearchiver 7za not found. URLs which use this format will be skipped."
    zip7="0"
fi

# DEFAULT SETTINGS
tmpdir="/dev/shm"
hostsfile="/etc/hosts.block"
redirecturl="127.0.0.1"
postprocess(){
    /etc/rc.d/dnsmasq restart
}
blocklists=("http://support.it-mate.co.uk/downloads/HOSTS.txt")
logfile="/var/log/hostsblock.log"
blacklist="/etc/hostsblock/black.list"
whitelist="/etc/hostsblock/white.list"
hostshead="0"
cachedir="/var/cache/hostsblock"
redirects="0"

# CHECK TO SEE IF WE ARE LOGGING THIS
if [ "$logfile" != "0" ]; then
    exec > "$logfile" 2>&1
fi

echo -e "\nHostsblock started at `date +'%x %T'`"

# READ CONFIGURATION FILE.
if [ -f /etc/hostsblock/rc.conf ]; then
    . /etc/hostsblock/rc.conf
else
    echo "Config file /etc/hostsblock/rc.conf not found. Using defaults."
fi

# CREATE CACHE DIRECTORY IF NOT ALREADY EXISTANT
[ -d "$cachedir" ] || mkdir -p "$cachedir"

# DOWNLOAD BLOCKLISTS
changed=0
printf "\nChecking blocklists for updates..."
for url in ${blocklists[*]}; do
    printf "\n   `echo $url | tr -d '%'`..."
    outfile=`echo $url | sed "s|http:\/\/||g" | tr '/%&+?=' '.'`
    [ -f "$cachedir"/"$outfile" ] && old_ls=`ls -l "$cachedir"/"$outfile"`
    if curl --compressed --connect-timeout 60 -sz "$cachedir"/"$outfile" "$url" -o "$cachedir"/"$outfile"; then
        new_ls=`ls -l "$cachedir"/"$outfile"`
        if [ "$old_ls" != "$new_ls" ]; then
            changed=1
            printf "UPDATED"
        else
            printf "no changes"
        fi
    else
        printf "FAILED\nScript exiting @ `date +'%x %T'`"
        exit 1
    fi
done

# IF THERE ARE CHANGES...
if [ "$changed" != "0" ]; then
    echo -e "\nDONE. Changes found."

    # CREATE TMPDIR
    [ -d "$tmpdir"/hostsblock/hosts.block.d ] || mkdir -p "$tmpdir"/hostsblock/hosts.block.d

    # BACK UP EXISTING HOSTSFILE
    printf "\nBacking up $hostsfile to $hostsfile.old..."
    cp "$hostsfile" "$hostsfile".old && printf "done" || printf "FAILED"

    # EXTRACT CACHED FILES TO HOSTS.BLOCK.D
    printf "\n\nExtracting and preparing cached files to working directory..."
    n=1
    for url in ${blocklists[*]}; do
        FILE=`echo $url | sed "s|http:\/\/||g" | tr '/%&=?' '.'`
        printf "\n    `basename $FILE | tr -d '\%'`..."
        case "$FILE" in
            *".zip")
                if [ $zip == "1" ]; then
                    mkdir "$tmpdir"/hostsblock/tmp
                    cp "$cachedir"/"$FILE" "$tmpdir"/hostsblock/tmp
                    cd "$tmpdir"/hostsblock/tmp
                    printf "extracting..."
                    unzip -jq "$FILE" &>/dev/null && printf "extracted..." || printf "FAILED"
                    grep -rIh -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" ./* > "$tmpdir"/hostsblock/hosts.block.d/hosts.block.$n
                    cd "$tmpdir"/hostsblock
                    rm -r "$tmpdir"/hostsblock/tmp
                    printf "prepared"
                else
                    printf "unzip not found. Skipping"
                fi
            ;;
            *".7z")
                if [ $zip7 == "1" ]; then
                    mkdir "$tmpdir"/hostsblock/tmp
                    cp "$cachedir"/"$FILE" "$tmpdir"/hostsblock/tmp
                    cd "$tmpdir"/hostsblock/tmp
                    printf "extracting..."
                    7za e "$FILE" &>/dev/null && printf "extracted..." || printf "FAILED"
                    grep -rIh -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" ./* > "$tmpdir"/hostsblock/hosts.block.d/hosts.block.$n
                    cd "$tmpdir"/hostsblock
                    rm -r "$tmpdir"/hostsblock/tmp
                    printf "prepared"
                else
                    printf "7za not found. Skipping"
                fi
            ;;
            *)
                cp "$cachedir"/"$FILE" "$tmpdir"/hostsblock/hosts.block.d/hosts.block.$n && printf "prepared" || printf "FAILED"
            ;;
        esac
        let "n+=1"
    done

    # INCLUDE LOCAL BLACKLIST FILE
    printf "\n    Local blacklist..."
    cat "$blacklist" |\
    sed "s|^|$redirecturl |g" >> "$tmpdir"/hostsblock/hosts.block.d/hosts.block.0 && printf "prepared" || printf "FAILED"

    # GENERATE WHITELIST SED SCRIPT
    printf "\n    Local whitelist..."
    cat "$whitelist" |\
    sed -e 's/.*/\/&\/d/' -e 's/\./\\./g' >> "$tmpdir"/hostsblock/whitelist.sed && printf "prepared" || printf "FAILED"

    printf "\nDONE.\n\nProcessing files..."
    # DETERMINE THE REDIRECT URL NOT BEING USED
    if [ "$redirecturl" == "127.0.0.1" ]; then
        notredirect="0.0.0.0"
    else
        notredirect="127.0.0.1"
    fi

    # PROCESS BLOCKLIST ENTRIES INTO TARGET FILE
    if [ "$hostshead" == "0" ]; then
        rm "$hostsfile"
    else
        cp -f "$hostshead" "$hostsfile"
    fi

    # DETERMINE WHETHER TO INCLUDE REDIRECTIONS
    if [ "$redirects" == "1" ]; then
        grep_eval='grep -Ih -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" "$tmpdir"/hostsblock/hosts.block.d/*'
    else
        grep_eval='grep -IhE -- "^127\.0\.0\.1|^0\.0\.0\.0" "$tmpdir"/hostsblock/hosts.block.d/*'
    fi

    # PROCESS AND WRITE TO FILE
    eval $grep_eval | sed -e 's/[[:space:]][[:space:]]*/ /g' -e "s/\#.*//g" -e "s/[[:space:]]$//g" -e \
    "s/$notredirect/$redirecturl/g" | sort -u | sed -f "$tmpdir"/hostsblock/whitelist.sed >> "$hostsfile" && printf "done\n"

    # REPORT COUNT OF MODIFIED OR BLOCKED URLS
    for addr in `grep -Ih -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" "$hostsfile" | cut -d" " -f1 | sort -u |\
    tr '\n' ' '`; do
        number=`grep -c -- "^$addr" "$hostsfile"`
        if [ "$addr" == "$redirecturl" ]; then
            printf "\n$number urls blocked"
        else
            printf "\n$number urls redirected to $addr"
        fi
    done

    # COMMANDS TO BE EXECUTED AFTER PROCESSING
    printf "\n\nRunning postprocessing..."
    postprocess && printf "done\n" || printf "FAILED"

    # CLEAN UP
    rm -r "$tmpdir"/hostsblock
else
    echo -e "\nDONE. No new changes."
fi
echo -e "\nHostsblock completed at `date +'%x %T'`\n"
