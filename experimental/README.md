# Hostsblock

An **ad-** and **malware-blocking** utility for *POSIX*

## Description

**`Hostsblock`** is a POSIX-compatible script designed to take advantage of
[`/etc/hosts`][h] file to provide [**system-wide blocking**][0] of
**internet advertisements, malicious domains, trackers, and
other undesirable content**.

To do so, it downloads a **configurable** set of blocklists and processes their
entries into a single [`/etc/hosts`][h] file.

`Hostsblock` also acts as a command-line utility that
allows you to block and unblock certain websites and any other domains
contained in that website.

## Features

*   **Enhanced security** - Runs as an unpriviledged user instead of
  root. **New:** Includes systemd service files that heavily sandbox the
  background process.

*   **System-wide blocking** - *All non-proxied* connections use the HOSTS
  file (Proxied connections can be modified to use the HOSTS file)

*   **Compression-friendly** - Can download and process zip- and 7zip-compressed files
  **automatically**. (Provided that `unzip` and `p7zip` are installed)

*   **Non-interactive** - Can be run as a periodic `cronjob` or via a `systemd timer`
  without needing user interaction.

*   **Extensive configurability** - Allows for custom **black & white listing**,
  **redirection**, ~~**post-processing scripting**~~ (now provided via systemd configuration), *etc.*

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
*   A POSIX environment (which should already be in place on most Linux, \*BSD, and macOS environments, including the following commands:
  `sh` (e.g. [bash](http://www.gnu.org/software/bash/bash.html) or [dash](http://gondor.apana.org.au/~herbert/dash/), 
  `chmod`, `cksum`, `cp`, `cut`, `file`, `find`, `grep`, `id`, `mkdir`, `mv`, `rm`, `sed`, `sort`, `tee`, `touch`, `tr`, `wc`, and `xargs`.

### Optional dependencies for **additional features**

*   [sudo](https://www.sudo.ws/) to enable the user-friendly wrapper script (highly recommended)

**Unarchivers** to use archive blocklists instead of plain text:

*   [unzip][unzip] (for zip archives)
*   [p7zip][7zip] (for 7z archives) must include either 7z or 7za executables!

**A DNS caching daemon** to help *speed up DNS resolutions*:

*   [dnsmasq](http://www.thekelleys.org.uk/dnsmasq/doc.html) (recommended)
*   [pdnsd](http://members.home.nl/p.a.rombouts/pdnsd/) (untested)

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

### For Other POSIX Flavors and Distros

#### The Best and Easiest Way

Please check with your distribution to see if a package is available. If there is not, ask for it or contribute your own!

If you are a package maintainer, let [me](mailto:jakevanderkolk@protonmail.com) know so that I can post the instructions here.

#### The Easy Way

First download the archive [here](https://github.com/gaenserich/hostsblock/archive/master.zip) or with curl like so: `curl -O "https://github.com/gaenserich/hostsblock/archive/master.zip"`

Unzip the archive, e.g. `unzip hostsblock-master.zip`

Execute the `install.sh` script, which will guide you through installation.

#### The Complicated Way

##### Create a 'hostsblock' user and group

```sh
sudo useradd -d /var/lib/hostsblock -c "hostsblock" -m -U hostsblock
```

##### Install the files

After downloading the archive [here](https://github.com/gaenserich/hostsblock/archive/master.zip) and unzipping, go into the resulting directory and execute the following as root:

```sh
install -Dm500 -g hostsblock -o hostsblock src/hostsblock.sh /usr/lib/hostsblock.sh
sed "s/%PREFIX%/\/usr/g" src/hostsblock-wrapper.sh /usr/bin/hostsblock
chown hostsblock:hostsblock /usr/bin/hostsblock
chmod 550 /usr/bin/hostsblock
install -Dm600 -g hostsblock -o hostsblock conf/* /var/lib/hostsblock/
install -Dm444 -g root -o root systemd/* /usr/lib/systemd/system/
```

## After Installation

### Enable the systemd service

**Don't forget** to *enable* and *start* the systemd timer with:
```sh
systemctl enable --now hostsblock.timer
```

### Configuration

By default, the configuration files are included in the `/var/lib/hostsblock/config.examples/` directory. Copy them over to `/var/lib/hostsblock/` to customize your setup.

Most of the `hostsblock` configuration is done in the [`hostsblock.conf`][conf].
This file is commented really well, so please read through it before first use.

`Hostsblock` does not write to `/etc/hosts` or manipulate any dns caching daemons.
Instead, it will just compile a hosts-formatted file to `/var/lib/hostsblock/hosts.block`.
To make this file actually do work, you have one of two options:

***Note: In order to enhance security, `hostsblock` no longer directly manipulates other process or asks for rights to write to `/etc/hosts`. Other services like `systemd` handle such sensitive operations.***

### OPTION 1: Using a DNS Caching Daemon (Here: dnsmasq)

Using a DNS caching daemon like `dnsmasq` offers better performance.

To use `hostsblock` together with `dnsmasq`, configure `dnsmasq` as DNS caching daemon.
Please refer to your distribution's manual. For ArchLinux read the following:
[Wiki section](https://wiki.archlinux.org/index.php/dnsmasq#DNS_cache_setup).

After that, add the following line to `dnsmasq.conf` (usually under `/etc/dnsmasq.conf`) so that `dnsmasq` will reference the file:

```conf
addn-hosts=/var/lib/hostsblock/hosts.block
```

Enable and start `hostsblock-dnsmasq-restart.path`:

```
systemctl enable --now hostsblock-dnsmasq-restart.path
```

This has systemd watch the target file `/var/lib/hostsblock/hosts.block` for changes and then restart `dnsmasq` whenever they are found.

### OPTION 2: Copy /var/lib/hostsblock/hosts.block to /etc/hosts

It is possible to have `systemd` copy the generated file over to `/etc/hosts`.

Configure `hostshead=` in `hostsblock.conf` to make sure you don't remove the default system loopback address(es), e.g.:

```conf
hostshead="/var/lib/hostsblock/hosts.head"
```

Then put your necessary loopback entries in `/var/lib/hostsblock/hosts.head`. For example, you can copy over your existing `/etc/hosts` to this file:

```
cp /etc/hosts /var/lib/hostsblock/hosts.head
chown hostsblock:hostsblock /var/lib/hostsblock/hosts.head
chmod 600 /var/lib/hostsblock/hosts.head
```

Enable and start `hostsblock-hosts-clobber.path`:

```
systemctl enable --now hostsblock-hosts-clobber.path
```

This has systemd watch the target file `/var/lib/hostsblock/hosts.block` for changes and then copy `/var/lib/hostsblock/hosts.block` to `/etc/hosts`.


## Usage

As a cronjob/systemd-job, `hostsblock` executes as a heavily sandboxed unpriviledged user (instead of root).

If you need to manually execute it outside of systemd, or if you want to use the urlcheck tool (`hostsblock -c URL`), this means that you must configure sudo, e.g.:

To allow other users to manually execute hostsblock (and also hostsblock-urlcheck), edit `sudoers` by typing `sudo visudo` and add the following line to the end:

```conf
%hostsblock	ALL	=	(hostsblock)	NOPASSWD:	/usr/lib/hostsblock.sh
```

Add any users you want to be able to manually execute or use the urlcheck mode to the `hostsblock` group:

```sh
gpasswd -a [MY USER NAME] hostsblock
```

The wrapper script installed in your PATH will automatically use sudo to execute the main script as the user `hostsblock`.

### hostsblock [OPTION...] - download and combine HOSTS files

Without the `-c URL` option, hostsblock will check to see if its monitored blocklists have changed. If it detects changes in them (or if forced by the `-u` flag), it will download the changed blocklist(s) and recompile the target HOSTS file.

```sh
Help Options:
  -h                            Show help options

Options:
  -f CONFIGFILE         Specify an alternative configuration file
  -q                    Show only fatal errors
  -v                    Be verbose
  -d                    Be very verbose/debug
  -u                    Force hostsblock to update its target file
```

### hostsblock [OPTION...] -c URL [COMMANDS...] - Manage how URL is handled

With the `-c URL` flag option, hostsblock can check and manipulate how it handles specific domains.

***Note: The `hostsblock-urlcheck` symlink is now officially depreciated. Use `hostsblock -c` instead.***

```sh
hostsblock -c URL (urlCheck) Commands:
  -s [-r -k]            State how hostblock modifies URL
  -b [-o -r]            Temporarily (un)block URL
  -l [-o -r -b]         Add/remove URL to/from blacklist
  -w [-o -r -b]         Add/remove URL to/from whitelist
  -i [-o -r -k]         Interactively inspect URL

hostsblock -c URL Command Subcommands:
  -r                    COMMAND recurses to all domains on URL's page
  -k                    COMMAND recurses for all BLOCKED domains on page
  -o                    Perform opposite of COMMAND (e.g UNblock)
  -b                    With "-l", immediately block URL
                        With "-w", immediately unblock URL
```

Note that the `-o` subcommand turns a blocking command into an UNblocking command, a blacklisting command into a DEblacklisting command, etc.

#### Examples:

##### See if "http://github.com/gaenserich/hostsblock" is blocked, blacklisted, whitelisted, or redirected by `hostsblock`:

```sh
hostsblock -c "http://github.com/gaenserich/hostsblock" -s
```

##### Do the same thing for any of the sites referenced on this page:

```sh
hostsblock -c "http://github.com/gaenserich/hostsblock" -s -r
```

##### Do the same thing for any of the sites referenced on this page that are presently blocked:

```sh
hostsblock -c "http://github.com/gaenserich/hostsblock" -s -k
```

##### Block the domain containing "http://github.com/gaenserich/hostsblock" (that is, "github.com"):

```sh
hostsblock -c "http://github.com/gaenserich/hostsblock" -b
```

***Note that "blocking" (and "unblocking", i.e. `-b -o`) a domain only works until the next time hostsblock refreshes `/var/lib/hostsfile/hosts.block`, unless you use a blocklist that does include it. To permanently block this domain, use the blacklist (`-l`) command.***

##### Permanently block (blacklist) the domain containing "http://github.com/gaenserich/hostsblock" (that is, "github.com"):

```sh
hostsblock -c "http://github.com/gaenserich/hostsblock" -l
```

***Note that "blacklisting" on its own will not block the target domain until hostblock refreshes. You can combine both "blocking" and "blacklisting" in one command, however:***

##### Permanently and immediately block the domain containing "http://github.com/gaenserich/hostsblock" (that is, "github.com"):

```sh
hostsblock -c "http://github.com/gaenserich/hostsblock" -l -b
```

##### Temporarily unblock all blocked domains on "http://github.com/gaenserich/hostsblock" (helpful if the page isn't working quite right):

```sh
hostsblock -c "http://github.com/gaenserich/hostsblock" -b -o -k
```

##### Interactively scan through "http://github.com/gaenserich/hostsblock", prompting you if you want the domains referenced therein to be blocked, blacklisted, or whitelisted

```sh
hostsblock -c "http://github.com/gaenserich/hostsblock" -i -r
```

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
