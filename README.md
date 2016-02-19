Hostsblock
==========
An **ad-blocking** and **malware-blocking** script for *Linux*

Description
-----------
**`Hostsblock`** is a `bash` script designed to take advantage of
[`/etc/hosts`][h] file to provide [**system-wide blocking**][0] of **internet
advertisements, malicious domains, trackers, and other undesirable content**.

To do so, it downloads a **configurable** set of blocklists and processes their
entries into a single [`/etc/hosts`][h] file.

`Hostsblock` also includes `hostsblock-urlcheck`, a command-line utility that
allows you to block and unblock certain websites and any other domains
contained in that website.

[h]: https://en.wikipedia.org/wiki/Hosts_file
[0]: http://winhelp2002.mvps.org/hosts.htm

Features
--------

* **System-wide blocking** - **_All_ non-proxied** connections use the HOSTS
  file (Proxied connections can adopt the HOSTS file)

* **Compressed-friendly** - Can download and process compressed files
  **automatically**.  (Currently only `zip` and `7zip` are supported)

* **Non-interactive** - Can be run as a periodic **cronjob** or systemd service
  without needing user interaction.

* **Extensive configurability** - Allows for custom **black & white listing**,
  **redirection**, **post-processing scripting**, *etc.*

* **Bandwith-efficient** - *Only* downloads blocklists that have been changed,
  uses *compression* when available.

* **Resource-efficient** - *Only* processes blocklists when changes are
  registered, uses *minimal pipes*.

* **High performance blocking** - **Only** when using *dns caching* and
  *pseudo-server* daemons.

* **Redirection capability** - **Enchance security** and combats [DNS cache
  poisoning](https://en.wikipedia.org/wiki/DNS_cache_poisoning).

* **Extensive choice of blocklists included** - It is up to the *user* to
  **choose** how much or how little is blocked/redirected.

Dependencies
------------

- [curl](http://curl.haxx.se/)
- [GNU bash](http://www.gnu.org/software/bash/bash.html)
- [GNU sed](http://www.gnu.org/software/sed)
- [GNU grep](http://www.gnu.org/software/grep/grep.html)
- [GNU coreutils](http://www.gnu.org/software/coreutils).

### Optional dependencies for **additional features**

**Unarchivers** to use archive blocklists instead of plain text:
* [unzip](http://www.info-zip.org/UnZip.html) for zip archives
* [p7zip](http://p7zip.sourceforge.net/) for 7z archives (must include either 7z or 7za executables)

**_A_ DNS caching daemon** to help *speed up DNS resolutions*:
* [dnsmasq](http://www.thekelleys.org.uk/dnsmasq/doc.html) (recommended)
* [pdnsd](http://members.home.nl/p.a.rombouts/pdnsd/) (untested)

**_A_ pseudo-server** that serves *blank pages* to remove boilerplate page and
speed up page resolution on blocked domains:
* [kwakd](https://code.google.com/p/kwakd/) (recommended)
* [pixelserv](http://proxytunnel.sourceforge.net/pixelserv.php)

**Compressors** to compress backup files and the annotation database:
* [gzip](http://www.gnu.org/software/gzip/)
* [pigz](http://www.zlib.net/pigz/)

Installation
------------
Currently hostsblock only support installation on Arch Linux:

    cd pkg; makepkg -Acsir

Refer to the *man pages* for more info about hostsblock's **usage**.

News & Bugs
-----------
* [Issue Tracker](https://github.com/gaenserich/hostsblock/issues)
* [Arch Linux AUR](https://aur.archlinux.org/packages/hostsblock/)
* [Arch Linux Forum](https://bbs.archlinux.org/viewtopic.php?id=139784)

Hostsblock is licensed under [GNU GPL](http://www.gnu.org/licenses/gpl-3.0.txt)
