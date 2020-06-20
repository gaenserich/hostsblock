# Hostsblock

An **ad-** and **malware-blocking** utility for POSIX systems

### Contents
1.   **[Description](#description):** [Features](#features)
2.   **[Installation](#installation):** [Dependencies](#depends), [Arch Linux](#archinstall), [Other POSIX](#posixinstall)
3.   **[Configuration](#config):** [Edit `hostsblock.conf`](#hostblockconf), [Enable Timer](#enabletimer), [Enable Postprocessing](#enablepostprocess)
4.   **[Usage](#usage):** [Configuring `sudo`](#sudo), [Manual Usage](#manual), [UrlCheck Usage](#urlcheck) ([examples](#examples))
5.   **[FAQ](#faq)**
6.   **[News & Bugs](#news):** [Upgrading to 0.999.8](#upgrade09998)
7.   **[License](#license)**

## Description <a name="description"></a>

**Hostsblock** is a POSIX-compatible script designed to take advantage of the [`/etc/hosts`][h] file to provide [**system-wide blocking**][0] of **internet advertisements, malicious domains, trackers, and other undesirable content**.

To do so, it downloads a **configurable** set of blocklists and processes their entries into a single [HOSTS][h] file.

Hostsblock also provides a command-line utility that allows you to configure how individual websites and any other domains contained in that website are handled.

### Features <a name="features"></a>

*   **Enhanced security** - Runs as an unprivileged user instead of root. **New:** Includes systemd service files that heavily sandbox the background process.

*   **System-wide blocking** - *All non-proxied* connections use the HOSTS file (Proxied connections can be modified to use the HOSTS file)

*   **Compression-friendly** - Can download and process zip- and 7zip-compressed files **automatically**. (Provided that `unzip` and `p7zip` are installed)

*   **Non-interactive** - Can be run as a periodic background job without needing user interaction.

*   **Extensive configurability** - Allows for custom **black & white listing**, **redirection**, ~~**post-processing scripting**~~ (now provided via systemd configuration), *etc.*

*   **Bandwith-efficient** - *Only* downloads blocklists that have been changed, using *http compression* when available.

*   **Resource-efficient** - *Only* processes blocklists when changes are registered.

*   **High performance blocking** - **Only** when using *dns caching*.

*   **Redirection capability** - **Enchances security** by combating [DNS cache poisoning](https://en.wikipedia.org/wiki/DNS_cache_poisoning).

*   **Extensive choice of blocklists included** - Allowing the *user* to **choose** how much or how little is blocked/redirected.

## Installation <a name="installation"></a>

### Dependencies <a name="depends"></a>

*   [curl](http://curl.haxx.se/)
*   A POSIX environment (which should already be in place on most Linux, \*BSD, and macOS environments, including the following commands: `sh` (e.g. [bash](http://www.gnu.org/software/bash/bash.html) or [dash](http://gondor.apana.org.au/~herbert/dash/), `chmod`, `cksum`, `cp`, `cut`, `file`, `find`, `grep`, `id`, `mkdir`, `mv`, `rm`, `sed`, `sort`, `tee`, `touch`, `tr`, `wc`, and `xargs`.

#### Optional dependencies for **additional features**

*   [sudo](https://www.sudo.ws/) to enable the user-friendly wrapper script (highly recommended)

**Unarchivers** to use archive blocklists instead of plain text:

*   [unzip][unzip] (for zip archives)
*   [p7zip][7zip] (for 7z archives) must include either `7z`, `7za`, or `7zr` executables!

**A DNS caching daemon** to help *speed up DNS resolutions*:

*   [dnsmasq](http://www.thekelleys.org.uk/dnsmasq/doc.html) (recommended)
*   [pdnsd](http://members.home.nl/p.a.rombouts/pdnsd/) (untested)

If you use 127.0.0.1 as your blocking redirect address (`redirecturl` in `hostsblock.conf`), **a pseudo-server** that serves *blank pages* to remove boilerplate page and speed up page resolution on blocked domains:

*   [kwakd](https://github.com/fetchinson/kwakd/)
*   [pixelserv](http://proxytunnel.sourceforge.net/pixelserv.php)

Note that the default configuration [gets no benefit from having a pseudo-server](https://www.howtogeek.com/225487/what-is-the-difference-between-127.0.0.1-and-0.0.0.0/)

### Arch Linux <a name="archinstall"></a>

If you have yaourt installed: `yaourt -S hostsblock` or `yaourt -S hostsblock-git`

Or use one of the *AUR* packages:
[hostsblock](https://aur.archlinux.org/packages/hostsblock/),
[hostsblock-git](https://aur.archlinux.org/packages/hostsblock-git/)

**Don't forget** to *enable* and *start* the systemd timer by running this:
```sh
$ sudo systemctl enable --now hostsblock.timer
```

### For Other POSIX Flavors and Distros <a name="posixinstall"></a>

#### The Best and Easiest Way

Please check with your distribution to see if a package is available. If there is not, ask for it or contribute your own!

If you are a package maintainer, let [me](mailto:jakevanderkolk@protonmail.com) know so that I can post the instructions here.

#### The Easy Way

First download the archive [here](https://github.com/gaenserich/hostsblock/archive/master.zip) or with curl like so: `curl -O "https://github.com/gaenserich/hostsblock/archive/master.zip"`

Unzip the archive, e.g. `unzip hostsblock-master.zip`

Execute the `install.sh` script *as root*, which will guide you through installation.

## Configuration <a name="config"></a>

By default, the configuration files are included in the `/var/lib/hostsblock/config.examples/` directory. Copy them over to `/var/lib/hostsblock/` to customize your setup.

### Editing `hostsblock.conf` <a name="hostblockconf"></a>

Most of the hostsblock configuration is done in the [`hostsblock.conf`][conf]. This file is commented really well, so please read through it before first use:

```conf
# CACHE DIRECTORY. Directory where blocklists will be downloaded and stored.

#cachedir="$HOME/cache" # DEFAULT


# WORK DIRECTORY. Temporary directory where interim files will be unzipped and
# # processed. This directory will be deleted after hostsblock completes.
#
# #tmpdir="/tmp/hostsblock" # DEFAULT

# FINAL HOSTSFILE. Final hosts file that combines together all downloaded blocklists.

#hostsfile="$HOME/hosts.block" # DEFAULT


# REDIRECT URL. IP address to which blocked hosts will be redirect, either 0.0.0.0 or
# 127.0.0.1. This replaces any entries to 0.0.0.0 and 127.0.0.1. If you run a
# pixelserver such as pixelserv or kwakd, it is advisable to use 127.0.0.1.

#redirecturl="0.0.0.0" # DEFAULT


# HEAD FILE. File containing hosts file entries which you want at the beginning
# of the resultant hosts file, e.g. for loopback devices and IPv6 entries. Use
# your original /etc/hosts file here if you are writing your final blocklist to
# /etc/hosts so as to preserve your loopback devices. Give hostshead="0" to
# disable this feature. For those targeting /etc/hosts, it is advisable to copy
# their old /etc/hosts file to this file so as to preserve existing entries.

#hostshead="0" # DEFAULT


# BLACKLISTED SUBDOMAINS. File containing specific subdomains to denylist which
# may not be in the downloaded denylists. Be sure to provide not just the
# domain, e.g. "google.com", but also the specific subdomain a la
# "adwords.google.com" without quotations.

#denylist="$HOME/black.list" # DEFAULT


# WHITELIST. File containing the specific subdomains to allow through that may
# be blocked by the downloaded blocklists. In this file, put a space in front of
# a string in order to let through that specific site (without quotations), e.g.
# " www.example.com" will unblock "http://www.example.com" but not
# "http://subdomain.example.com". Leave no space in front of the entry to
# unblock all subdomains that contain that string, e.g. ".dropbox.com" will let
# through "www.dropbox.com", "dl.www.dropbox.com", "foo.dropbox.com",
# "bar.dropbox.com", etc.

#allowlist="$HOME/white.list"


# CONNECT_TIMEOUT. Parameter passed to curl. Determines how long to try to
# connect to each blocklist url before giving up.

#connect_timeout=60 # DEFAULT


# RETRY. Parameter passed to curl. Number of times to retry connecting to
# each blocklist url before giving up.

#retry=0 # DEFAULT


# MAX SIMULTANEOUS DOWNLOADS. Hostsblock can check and download files in parallel.
# By default, it will attempt to check and download four files at a time.

#max_simultaneous_downloads=4 # DEFAULT


# BLOCKLISTS FILE. File containing URLs of blocklists to be downloaded,
# each on a separate line. Downloaded files may be either
# plaintext, zip, or 7z files. Hostsblock will automatically
# identify the file type.

#blocklists="$HOME/block.urls"


# REDIRECTLISTS FILE. File containing URLs of redirectlists to be downloaded,
# each on a separate line. Downloaded files may be either
# plaintext, zip, or 7z files. Hostsblock will automatically
# identify the file type.

#redirectlists="" # DEFAULT, otherwise "$HOME/redirect.urls"


# If you have any additional lists, please post a bug report to
# https://github.com/gaenserich/hostsblock/issues 
```

### Enable the systemd service <a name="enabletimer"></a>

**Don't forget** to *enable* and *start* the systemd timer with:

```sh
$ sudo systemctl enable --now hostsblock.timer
```

### Configure Postprocessing <a name="enablepostprocess"></a>

**Hostsblock** does not write to `/etc/hosts` or manipulate any DNS caching daemons anymore. Instead, it will just compile a hosts-formatted file to `/var/lib/hostsblock/hosts.block`. To make this file actually do work, you have one of two options:

#### OPTION 1: Using a DNS Caching Daemon (Here: dnsmasq)

Using a DNS caching daemon like **dnsmasq** offers better performance.

To use hostsblock together with dnsmasq, configure dnsmasq as DNS caching daemon.
Please refer to your distribution's manual. For ArchLinux read the following:
[Wiki section](https://wiki.archlinux.org/index.php/dnsmasq#DNS_cache_setup).

After that, add the following line to `dnsmasq.conf` (usually under `/etc/dnsmasq.conf`) so that **dnsmasq** will reference the file:

```conf
addn-hosts=/var/lib/hostsblock/hosts.block
```

Enable and start `hostsblock-dnsmasq-restart.path`:

```sh
$ sudo systemctl enable --now hostsblock-dnsmasq-restart.path
```

This has systemd watch the target file `/var/lib/hostsblock/hosts.block` for changes and then restart `dnsmasq` whenever they are found.

#### OPTION 2: Copy /var/lib/hostsblock/hosts.block to /etc/hosts

It is possible to have `systemd` overwrite `/etc/hosts` with the generated file.

Configure `hostshead=` in `hostsblock.conf` to make sure you don't remove the default system loopback address(es), e.g.:

```conf
hostshead="/var/lib/hostsblock/hosts.head"
```

Then put your necessary loopback entries in `/var/lib/hostsblock/hosts.head`. For example, you can copy over your existing `/etc/hosts` to this file:

```sh
$ sudo cp /etc/hosts /var/lib/hostsblock/hosts.head
$ sudo chown hostsblock:hostsblock /var/lib/hostsblock/hosts.head
$ sudo chmod 600 /var/lib/hostsblock/hosts.head
```

Enable and start `hostsblock-hosts-clobber.path`:

```sh
$ sudo systemctl enable --now hostsblock-hosts-clobber.path
```

This has systemd watch the target file `/var/lib/hostsblock/hosts.block` for changes and then copy `/var/lib/hostsblock/hosts.block` to `/etc/hosts`.


## Usage <a name="usage"></a>

In its normal systemd-job configuration, hostsblock requires no interaction from the user aside from the steps above. If, however, you want to manually run the process, or to use the UrlCheck tool (`hostsblock -c URL`), you need to configure `sudo`:

### Configuring `sudo` <a name="sudo"></a>

Because hostsblock executes as a heavily sandboxed unpriviledged user (instead of root), you must configure `sudo` to allow other users to manually execute it.

To do so, edit `sudoers` by typing `sudo visudo` and add the following line to the end:

```conf
%hostsblock	ALL	=	(hostsblock)	NOPASSWD:	/usr/lib/hostsblock.sh
```

Add any users you want to be able to manually execute or use the urlcheck mode to the `hostsblock` group:

```sh
$ sudo gpasswd -a [MY USER NAME] hostsblock
```

The wrapper script installed in your PATH will automatically use sudo to execute the main script as the user `hostsblock`.

### hostsblock [OPTION...] - download and combine HOSTS files <a name="manual"></a>

Without the `-c URL` option, hostsblock will check to see if its monitored blocklists have changed. If it detects changes (or if forced by the `-u` flag), it will download the changed blocklist(s) and recompile the target HOSTS file.

```conf
Help Options:
  -h                            Show help options

Options:
  -f CONFIGFILE         Specify an alternative configuration file
  -q                    Show only fatal errors
  -v                    Be verbose
  -d                    Be very verbose/debug
  -u                    Force hostsblock to update its target file
```

### hostsblock [OPTION...] -c URL [COMMANDS...] - Manage how URL is handled <a name="urlcheck"></a>

With the `-c URL` flag option, hostsblock can check and manipulate how it handles specific domains.

***Note: The `hostsblock-urlcheck` symlink is now officially depreciated. Use `hostsblock -c` instead.***

In addition to the above options, the following commands and subcommands can be used with `hostsblock -c URL`:

```conf
hostsblock -c URL (urlCheck) Commands:
  -s [-r -k]            State how hostblock modifies URL
  -b [-o -r]            Temporarily (un)block URL
  -l [-o -r -b]         Add/remove URL to/from denylist
  -w [-o -r -b]         Add/remove URL to/from allowlist
  -i [-o -r -k]         Interactively inspect URL

hostsblock -c URL Command Subcommands:
  -r                    COMMAND recurses to all domains on URL's page
  -k                    COMMAND recurses for all BLOCKED domains on page
  -o                    Perform opposite of COMMAND (e.g UNblock)
  -b                    With "-l", immediately block URL
                        With "-w", immediately unblock URL
```

Note that the `-o` subcommand turns a command into its opposite, e.g.

-   `hostsblock -c URL -b -o` **un**blocks URL
-   `hostsblock -c URL -l -o` **removes** URL from the denylist
-   `hostsblock -c URL -w -o` **removes** URL from the allowlist

#### Examples: <a name="examples"></a>

Once you have configured `sudo`, you can execute the following as any user in the `hostsblock` group:

##### See if "http://github.com/gaenserich/hostsblock" is blocked, denylisted, allowlisted, or redirected by hostsblock:

```sh
$ hostsblock -c "http://github.com/gaenserich/hostsblock" -s
```

##### Do the same thing for any of the sites referenced on this page:

```sh
$ hostsblock -c "http://github.com/gaenserich/hostsblock" -s -r
```

##### Do the same thing for any of the sites referenced on this page that are presently blocked:

```sh
$ hostsblock -c "http://github.com/gaenserich/hostsblock" -s -k
```

##### Block the domain containing "http://github.com/gaenserich/hostsblock" (that is, "github.com"):

```sh
$ hostsblock -c "http://github.com/gaenserich/hostsblock" -b
```

Note that "blocking" (and "unblocking", i.e. `-b -o`) a domain only works until the next time hostsblock refreshes `/var/lib/hostsfile/hosts.block`, unless you use a blocklist that does include it. To permanently block this domain, use the denylist (`-l`) command.

##### Permanently block (denylist) the domain containing "http://github.com/gaenserich/hostsblock" (that is, "github.com"):

```sh
$ hostsblock -c "http://github.com/gaenserich/hostsblock" -l
```

Note that "denylisting" on its own will not block the target domain until hostblock refreshes. You can combine both "blocking" and "denylisting" in one command, however:

##### Permanently and immediately block the domain containing "http://github.com/gaenserich/hostsblock" (that is, "github.com"):

```sh
$ hostsblock -c "http://github.com/gaenserich/hostsblock" -l -b
```

##### Temporarily unblock all blocked domains on "http://github.com/gaenserich/hostsblock" (helpful if the page isn't working quite right):

```sh
$ hostsblock -c "http://github.com/gaenserich/hostsblock" -b -o -k
```

##### Interactively scan through "http://github.com/gaenserich/hostsblock", prompting you if you want the domains referenced therein to be blocked, denylisted, or allowlisted

```sh
$ hostsblock -c "http://github.com/gaenserich/hostsblock" -i -r
```

## FAQ <a name="faq"></a>

*   Why isn't it working with Chrome/Chromium?

    *   Because they bypass the system's DNS settings and use their own.

    To force them to use the system's DNS settings, refer to this
    [superuser.com](https://superuser.com/questions/723703/why-is-chromium-bypassing-etc-hosts-and-dnsmasq) question.

*   Hostsblock's systemd job fails with error "FAILED TO COMPILE BLOCK/REDIRECT ENTRIES FROM [...]" and leaves an empty `hosts.block.new` file.

    *   You may have a blank line with a single space in your allowlist. Hostsblock matches that line with the space in between the IP address and the domain name that every single line has, i.e. it matches every single would-be entry in your target file. Remove the empty line, and hostsblock will function as expected.

## News & Bugs <a name="news"></a>

*   [Issue Tracker](https://github.com/gaenserich/hostsblock/issues)
*   [Arch Linux AUR](https://aur.archlinux.org/packages/hostsblock/)
*   [Arch Linux Forum](https://bbs.archlinux.org/viewtopic.php?id=139784)

### Upgrading to 0.999.8 <a name="upgrade09998"></a>

For existing hostsblock users, please note the following changes in version 0.999.8:

#### Changes in `hostsblock.conf`

Due to the shift to POSIX-shell compatibility, the list of blocklists to be downloaded cannot be held in `hostsblock.conf` via the `blocklists=` parameter. Instead, this parameter contains the path to a file that contains the list of URLs, e.g. `/var/lib/hostsblock/block.urls`.

The new `block.urls` file is simply a newline separated list of URLs *without quotations*. Whitespace and text after # are ignored. An example `block.urls` file could look like this:

```conf
http://hosts-file.net/download/hosts.zip # General blocking meta-list
http://winhelp2002.mvps.org/hosts.zip

http://hostsfile.mine.nu/Hosts.zip
```

See the example `block.urls` in the `/var/lib/hostsblock/config.examples` directory for details.

#### No more postprocessing within script

Due to enhanced security and sandboxing, hostsblock no longer handles postprocessing on its own. Instead, users should use other systemd capabilities to replace the `postprocess() {}` functionality.

Hostsblock comes with systemd service files that replicate the most common scenarios. See the [directions above for instructions on how to enable them](#enablepostprocess).

#### Changes with `sudo`

`sudo` is no longer as widely used as before. The main systemd service no longer requires it. You only need it if you want to use the `hostsblock -c URL` (urlcheck) utility. [See the above directions for details](#sudo).

#### Other Caveats
*   The `hostsblock-urlcheck` symlink is depreciated. Please use [`hostsblock -c URL`](#urlcheck) instead.
*   In UrlCheck mode, large hosts files will generate large temporary cache files that will eat up a lot of temporary storage. If you have a machine with little RAM (<6GB) and want to block a lot of domains, consider changing your $tmpdir to an HDD- or SSD-backed filesystem instead of the default tmpfs under `/tmp`.
*   UrlCheck mode will not be able to provide information on which blocklist blocked which domains anymore (annotation feature removed)
*   Hostsblock uses 0.0.0.0 as default redirection IP address instead of 127.0.0.1. 0.0.0.0 theoretically offers better performance without the need of a pseudo-server.

#### Other Changes from 0.999.7 to 0.999.8
##### Systemd Job Improvements
*   Systemd service now heavily hardened and sandboxed for enhanced security
*   Fixed simultaneous download feature so that it actually does what it is supposed to
*   Added processing support for source blocklists that just list domain names to be blocked, e.g. `ads.google.com` instead of `0.0.0.0 ads.google.com`
*   Added support to read directly from zip and 7z files containing a single file without decompressing to a cache
*   Optimized filters used to process domains with improved throughput
*   If run with dash instead of bash, hostsblock has significant performance improvements
*   Removed annotation feature to reduce dependencies and overall processing demands
*   Vastly expanded list of potential blocklists (see `block.urls`)

##### POSIX-Compatibility Improvements
*   Supports POSIX shells (dash, ash, zsh) instead of just bash
*   Removed GNU-specific utilities, relies only on POSIX options
*   Should now run on \*BSD and macOS (and perhaps even Android and iOS!) if proper POSIX environments are installed. ***UNTESTED***

##### UrlCheck Mode Improvements
*   User-facing command now a wrapper script that handles `sudo` execution for the user, reducing configuration demands
*   Significant performance improvements by moving from incremental to mass handling of domain names
*   [Added noninteractive commands `-s` (status), `-b` (block), `-l` (denylist), `-w` (allowlist), `-b -o` (unblock), `-l -o` (dedenylist), `-w -o` (deallowlist)](#urlcheck)
*   Interactive and noninteractive commands can now recursively handle URLs contained in target page (with `-r` subcommand), and even target just blocked domains (with `-k` subcommand)
*   To minimize repeated writes, changes to target hosts file now don't write to file until after the whole process completes

## License <a name="license"></a>

Hostsblock is licensed under [GNU GPL](http://www.gnu.org/licenses/gpl-3.0.txt)

[h]: https://en.wikipedia.org/wiki/Hosts_file
[0]: http://winhelp2002.mvps.org/hosts.htm
[conf]: https://github.com/gaenserich/hostsblock/blob/master/conf/hostsblock.conf
[unzip]: http://www.info-zip.org/UnZip.html
[7zip]: http://members.home.nl/p.a.rombouts/pdnsd/
