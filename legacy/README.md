# Hostsblock

An **ad-** and **malware-blocking** script for *Linux*

## Description

**`Hostsblock`** is a `bash` script designed to take advantage of
[`/etc/hosts`][h] file to provide [**system-wide blocking**][0] of
**internet advertisements, malicious domains, trackers, and
other undesirable content**.

To do so, it downloads a **configurable** set of blocklists and processes their
entries into a single [`/etc/hosts`][h] file.

`Hostsblock` also acts as a command-line utility that
allows you to block and unblock certain websites and any other domains
contained in that website.

## Features

*   **NEW: Enhanced security** - Runs as an unpriviledged user instead of
  root.

*   **System-wide blocking** - *All non-proxied* connections use the HOSTS
  file (Proxied connections can be modified to use the HOSTS file)

*   **Compression-friendly** - Can download and process zip- and 7zip-compressed files
  **automatically**. (Provided that `unzip` and `p7zip` are installed)

*   **Non-interactive** - Can be run as a periodic `cronjob` or `systemd timer`
  without needing user interaction.

*   **Extensive configurability** - Allows for custom **black & white listing**,
  **redirection**, **post-processing scripting**, *etc.*

*   **Bandwith-efficient** - *Only* downloads blocklists that have been changed,
  using *http compression* when available.

*   **Resource-efficient** - *Only* processes blocklists when changes are
  registered, uses *minimal pipes*.

*   **High performance blocking** - **Only** when using *dns caching* and
  *pseudo-server* daemons.

*   **Redirection capability** - **Enchances security** by combating [DNS cache
  poisoning](https://en.wikipedia.org/wiki/DNS_cache_poisoning).

*   **Extensive choice of blocklists included** - Allowing the *user* to
  **choose** how much or how little is blocked/redirected.

## Dependencies

*   [curl](http://curl.haxx.se/)
*   [GNU bash](http://www.gnu.org/software/bash/bash.html)
*   [GNU sed](http://www.gnu.org/software/sed)
*   [GNU grep](http://www.gnu.org/software/grep/grep.html)
*   [GNU coreutils](http://www.gnu.org/software/coreutils)
*   [GNU gzip](https://www.gnu.org/software/gzip/) (or [pigz](http://www.zlib.net/pigz/) for multi-core systems)

### Optional dependencies for **additional features**

**Unarchivers** to use archive blocklists instead of plain text:

*   [unzip][unzip] (for zip archives)
*   [p7zip][7zip] (for 7z archives) must include either 7z or 7za executables!

**A DNS caching daemon** to help *speed up DNS resolutions*:

*   [dnsmasq](http://www.thekelleys.org.uk/dnsmasq/doc.html) (recommended)
*   [pdnsd](http://members.home.nl/p.a.rombouts/pdnsd/) (untested)

**A pseudo-server** that serves *blank pages* to remove boilerplate page and
speed up page resolution on blocked domains:

*   [kwakd](https://github.com/fetchinson/kwakd/) (recommended)
*   [pixelserv](http://proxytunnel.sourceforge.net/pixelserv.php)

## Installation

### Arch Linux

If you have yaourt installed: `yaourt -S hostsblock` or `yaourt -S hostsblock-git`

Or use one of the *AUR* packages:
[hostsblock](https://aur.archlinux.org/packages/hostsblock/),
[hostsblock-git](https://aur.archlinux.org/packages/hostsblock-git/)

**Don't forget** to *enable* and *start* the systemd timer with:
```sh
systemctl enable --now hostsblock.timer
```

### For Other Linux Distros (The Easy Way)

First download the archive [here](https://github.com/gaenserich/hostsblock/archive/master.zip) or with curl like so: `curl -O "https://github.com/gaenserich/hostsblock/archive/master.zip"`

Unzip the archive, e.g. `unzip hostsblock-master.zip`

Execute the `install.sh` script, which will guide you through installation.

### For Any Others (The Hard Way)

#### Create a 'hostsblock' user and group

```sh
sudo useradd -d /var/lib/hostsblock -c "hostsblock" -m -U hostsblock
```

#### Install the files

After downloading the archive [here](https://github.com/gaenserich/hostsblock/archive/master.zip) and unzipping, go into the resulting directory.

```sh
install -Dm755 src/hostsblock.sh /usr/bin/hostsblock
install -Dm644 conf/hostsblock.conf /var/lib/hostsblock/hostsblock.conf
install -Dm644 conf/black.list /var/lib/hostsblock/black.list
install -Dm644 conf/white.list /var/lib/hostsblock/white.list
install -Dm644 conf/hosts.head /var/lib/hostsblock/hosts.head
install -Dm644 systemd/hostsblock.service /usr/lib/systemd/system/hostsblock.service
install -Dm644 systemd/hostsblock.timer /usr/lib/systemd/system/hostsblock.timer
```

#### Enable the systemd service

**Don't forget** to *enable* and *start* the systemd timer with:
```sh
systemctl enable --now hostsblock.timer
```

## Configuration

All the `hostsblock` configuration is done in the [`hostsblock.conf`][conf].
This file is commented really well, so please read through it before first use.

By default, `hostsblock` does not write to `/etc/hosts` or manipulate any dns caching daemons.
Instead, it will just compile a hosts-formatted file to `/var/lib/hostsblock/hosts.block`.
To make this file actually work, you have one of two options:

### OPTION 1: Using a DNS Caching Daemon (Here: dnsmasq)

Using a DNS caching daemon like `dnsmasq` offers (theoretically) better performance.

To use `hostsblock` together with `dnsmasq`, configure `dnsmasq` as DNS caching daemon.
Please refer to your distribution's manual. For ArchLinux read the following:
[Wiki section](https://wiki.archlinux.org/index.php/dnsmasq#DNS_cache_setup).

#### hostsblock.conf

Edit the `hostsblock.conf` file (by default under `/var/lib/hostsblock/hostsblock.conf`)

In the *POSTPROCESSING SUBROUTINE* section comment out:

```conf
postprocess() {
    true
}
```

And uncomment (that is, remove the '#'s from in front of):

```conf
postprocess() {
    sudo systemctl reload dnsmasq.service
}
```

#### dnsmasq.conf

Edit `dnsmasq.conf` (e.g. `/etc/dnsmasq.conf`).

Set `addn-hosts=` to `addn-hosts=/var/lib/hostsblock/hosts.block`

#### sudoers

Edit `sudoers` by typing `sudo visudo`. Add the following line to the end:
```conf
hostsblock              ALL     =       (root)  NOPASSWD:       /usr/bin/systemctl reload dnsmasq.service
```

### OPTION 2: Copy /var/lib/hostsblock/hosts.block to /etc/hosts

It is possible to make hostsblock copy its generated file over to /etc/hosts, just make sure that you configure `hostshead=` in `hostsblock.conf` to make sure you don't remove the default system loopback address(es).

#### hostsblock.conf

Edit the `hostsblock.conf` file (by default under `/var/lib/hostsblock/hostsblock.conf`):

In the *POSTPROCESSING SUBROUTINE* section comment out:

```conf
postprocess() {
    true
}
```

And uncomment (that is, remove the '#'s from in front of):

```conf
postprocess() {
    sudo cp -f $_v "$hostsfile" /etc/hosts
}
```

#### sudoers

Edit `sudoers` by typing `sudo visudo`. Add the following line to the end:
```conf
hostsblock	ALL	=	(root)	NOPASSWD:	/usr/bin/cp
```

## Usage

hostsblock now executes as an unpriviledged user (instead of root). If you need to execute it outside of systemd, this means that you must use sudo, e.g.:
```sh
sudo -u hostsblock hostsblock
```

To allow other users to manually execute hostsblock (and also hostsblock-urlcheck), edit `sudoers` by typing `sudo visudo` and add the following line to the end:
```conf
jake	ALL	=	(hostsblock)	NOPASSWD:	/usr/bin/hostsblock,/usr/bin/hostsblock-urlcheck
```

Replacing "jake" with whatever user you want to execute hostsblock from.

### hostsblock [OPTIONS] - generate a HOSTS file with block and redirection lists

Without the `-c URL` option, hostsblock will check to see if its monitored blocklists have changed. If it detects changes in them (or if forced by the `-u` flag), it will download the changed blocklist(s) and recompile the target HOSTS file.

```sh
Help Options:
  -h                            Show help options

Application Options:
  -f CONFIGFILE                 Specify an alternative configuration file (instead of /var/lib/hostsblock/hostsblock.conf)
  -q                            Only show fatal errors
  -v                            Be verbose.
  -u                            Force hostsblock to update its target file, even if no changes to source files are found
```

### hostsblock [OPTIONS] -c URL - Check if URL and other urls contained therein are blocked

With the `-c URL` flag option, hostsblock will check to see if the specified URL is presently blocked or not, and then prompt the user for action (e.g. to block, unblock, or leave as-is).
It will then prompt if it should inspect the URLs contained on the page summoned by the original URL, and likewise prompt the user what to do.

The other flags (e.g. `-f`, `-q`, `-v`) except for `-u` (which is ignored) remain available when using `-c URL`.

This option replaces the `hostsblock-urlcheck` script, which now comprises a symlink to `hostsblock` that automatically triggers `-c URL`.

Example:
```sh
sudo -u hostsblock hostsblock -c "http://www.example.com"
```

This will check to see if "http://www.example.com" is blocked by hostsblock. If it is, it will tell the user which blocklist is responsible, and prompt as to whether it should continue blocking it or unblock it.
If "http://www.example.com" is NOT blocked, hostsblock will ask if it should block it.
Should the user decide to change the status of "http://www.example.com", it will place entries into either its allowlist or denylist and then recompile the target HOSTS file, executing any postprocessing routines laid out in `hostsblock.conf`.

## FAQ

*   Why isn't it working with Chrome/Chromium?

    *   Because they bypass the system's DNS settings and use their own.
    To force them to use the system's DNS settings, refer to this
    [superuser.com](https://superuser.com/questions/723703/why-is-chromium-bypassing-etc-hosts-and-dnsmasq) question.

## News & Bugs

*   [Issue Tracker](https://github.com/gaenserich/hostsblock/issues)
*   [Arch Linux AUR](https://aur.archlinux.org/packages/hostsblock/)
*   [Arch Linux Forum](https://bbs.archlinux.org/viewtopic.php?id=139784)

## License

Hostsblock is licensed under [GNU GPL](http://www.gnu.org/licenses/gpl-3.0.txt)

[h]: https://en.wikipedia.org/wiki/Hosts_file
[0]: http://winhelp2002.mvps.org/hosts.htm
[conf]: https://github.com/gaenserich/hostsblock/blob/master/conf/hostsblock.conf
[unzip]: http://www.info-zip.org/UnZip.html
[7zip]: http://members.home.nl/p.a.rombouts/pdnsd/
