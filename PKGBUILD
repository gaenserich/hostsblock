# Maintainer: Jake VanderKolk <jakevanderkolk@gmail.com>
pkgname=hostsblock
pkgver=0.11.2
pkgrel=1
pkgdesc="A script and cronjob that downloads, sorts, and installs multiple ad- and malware-blocking hosts files."
arch=(any)
url="http://gaenserich.github.com/hostsblock/"
license=('GPL')
depends=(bash curl grep sed coreutils)
optdepends=('dnsmasq: helps speed up DNS resolutions'
	    'pixelserv: removes boilerplate page on blocked urls'
	    'kwakd: removes boilerplate page on blocked urls (recommended)'
	    'unzip: allows the use of zipped downloads'
	    'p7zip: allows the use of 7zipped downloads')
backup=('etc/hostsblock/rc.conf' 'etc/hostsblock/black.list' 'etc/hostsblock/white.list' 'etc/hostsblock/hosts.head')
changelog=$pkgname.changelog
install=$pkgname.install
source=('hostsblock.sh' 'hostsblock-urlcheck.sh' 'rc.conf' 'black.list' 'white.list' 'hosts.head')
md5sums=('e636a0a587673b794bcdbcc42ce375e8' '4e9d4d8d9583bb1881124f48dbd6c240' '88465d9b326a6a6eeed5be895289f9f5' '216d5af213e0eb3690ea3c27d4cc6258' '3a6ea9f5b0eef002b6ca1dd57388d78a' '949af91b7a40582de127eb43a96f001e')

package() {
  install -Dm755 "$srcdir"/hostsblock.sh "$pkgdir"/usr/sbin/hostsblock
  install -Dm755 "$srcdir"/hostsblock-urlcheck.sh "$pkgdir"/usr/sbin/hostsblock-urlcheck
  install -Dm644 "$srcdir"/rc.conf "$pkgdir"/etc/hostsblock/rc.conf
  install -Dm644 "$srcdir"/black.list "$pkgdir"/etc/hostsblock/black.list
  install -Dm644 "$srcdir"/white.list "$pkgdir"/etc/hostsblock/white.list
  install -Dm644 "$srcdir"/hosts.head "$pkgdir"/etc/hostsblock/hosts.head
}
