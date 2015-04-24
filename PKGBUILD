# Maintainer: Jake VanderKolk <jakevanderkolk@gmail.com>
pkgname=hostsblock
pkgver=0.999.1
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
	    'p7zip: allows the use of 7zipped downloads'
            'gzip: allows compression of old blockfile')
backup=('etc/hostsblock/hostsblock.conf' 'etc/hostsblock/black.list' 'etc/hostsblock/white.list' 'etc/hostsblock/hosts.head')
changelog=$pkgname.changelog
install=$pkgname.install
source=('hostsblock.sh' 'hostsblock-urlcheck.sh' 'hostsblock-common.sh' 'hostsblock.conf' 'black.list' 'white.list' 'hosts.head')
md5sums=('83e893d082421df273ec897f4462f846'
         'd38e61230e7a8ac60acf6c2b5a5b7ac8'
         '4f656b57eabc620767e21b48eb1aca80'
         '893af87fa051df0fc44995120deea447'
         '216d5af213e0eb3690ea3c27d4cc6258'
         '3a6ea9f5b0eef002b6ca1dd57388d78a'
         '949af91b7a40582de127eb43a96f001e')

package() {
  install -Dm700 "$srcdir"/hostsblock.sh "$pkgdir"/usr/bin/hostsblock
  install -Dm700 "$srcdir"/hostsblock-urlcheck.sh "$pkgdir"/usr/bin/hostsblock-urlcheck
  install -Dm600 "$srcdir"/hostsblock-common.sh "$pkgdir"/usr/lib/hostsblock-common.sh
  install -Dm600 "$srcdir"/hostsblock.conf "$pkgdir"/etc/hostsblock/hostsblock.conf
  install -Dm600 "$srcdir"/black.list "$pkgdir"/etc/hostsblock/black.list
  install -Dm600 "$srcdir"/white.list "$pkgdir"/etc/hostsblock/white.list
  install -Dm600 "$srcdir"/hosts.head "$pkgdir"/etc/hostsblock/hosts.head
}
