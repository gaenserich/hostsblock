hostsblock
==========
An ad- and malware-blocking cronscript for Linux

News & Bugs
-----------
For the latest news about hostsblock, and to submit questions, bugs, patches, and feedback in general, go to the [Arch Linux forum on this script](https://bbs.archlinux.org/viewtopic.php?id=139784) or make use of this Github page.

Description
-----------
Hostsblock is a bash script for Linux designed to take advantage of the HOSTS file available in all operating systems to provide system-wide blocking of internet advertisements, malicious domains, trackers, and other undesirable content. To do so, it downloads a configurable set of blocklists and processes and their entries into a singular HOSTS file.Hostsblock also includes hostsblock-urlcheck, a command-line utility that allows you to block and unblock certain websites and any other domains contained in that website, in the event that the included blocklists don't block enough or block too little on a specific site.

Features
--------
* System-wide blocking (all non-proxied connections use the HOSTS file)
* Zip- and 7zip-capable (can download and process zip- and 7zip-compressed files)
* Non-interactive (can be run as a periodic cronjob without needing user interaction)
* Extensive configurability (allows for custom black and white listing, redirection, post-processing scripting, target HOSTS file, etc.)
* Bandwith-efficient (only downloads blocklists that have been changed, uses compression when available)
* Resource-efficient (only processes blocklists when changes are registered, uses minimal pipes)
* High performance blocking (when using dns caching and pseudo-server daemons)
* Extensive choice of blocklists included (allows user to customize how much or how little is blocked)
* Redirection capability (combats DNS cache poisoning)

Dependencies
------------
Hostsblock only requires a few utilities that are standard on most Linux distros, including GNU bash, curl, GNU grep, GNU sed, and GNU coreutils.

Optional dependencies. Hostsblock allows for additional features if the following utilities are installed and in the path:

Unarchivers, so that archive blocklists can be used instead of just plaintext, e.g.:
* unzip for zip archives, AND
* p7zip for 7z archives

A DNS caching daemon to help speed up DNS resolutions, such as:
* dnsmasq (recommended), OR
* pdnsd (untested)

A pseudo-server that serves blank pages in order to remove the boilerplate page and speed up page resolution on blocked domains. Examples include:
* kwakd (recommended), OR
* pixelserv

Todo
----
