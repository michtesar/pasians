# Maintainer: Michael Tesař <michtesar at github>
pkgname=pasians
pkgver=0.1.0
pkgrel=1
pkgdesc='Keyboard-first Klondike and FreeCell that follows the Omarchy theme'
arch=('x86_64' 'aarch64')
url='https://github.com/michtesar/pasians'
license=('MIT')
# Odin's bundled raylib links GLFW for X11; it runs under XWayland, which
# Omarchy keeps unscaled (force_zero_scaling) so the table stays sharp.
depends=('libx11' 'libxrandr' 'libxinerama' 'libxcursor' 'libxi' 'libglvnd')
makedepends=('odin' 'git')
optdepends=('fontconfig: use the system monospace font for ranks')
install=pasians.install
source=("git+$url.git#tag=v$pkgver")
sha256sums=('SKIP')

check() {
  cd "$pkgname"
  odin test game -o:speed
}

build() {
  cd "$pkgname"
  odin build . -out:pasians -o:speed
}

package() {
  cd "$pkgname"
  install -Dm755 pasians "$pkgdir/usr/bin/pasians"
  install -Dm644 extras/pasians.desktop "$pkgdir/usr/share/applications/pasians.desktop"
  install -Dm644 extras/pasians.svg "$pkgdir/usr/share/icons/hicolor/scalable/apps/pasians.svg"
  install -Dm644 extras/hypr.lua "$pkgdir/usr/share/pasians/hypr.lua"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
