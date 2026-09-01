#!/bin/sh
# Lo ejecuta flatpak automáticamente tras descargar el extra-data (el .deb
# oficial) en /app/extra, en el primer arranque. cwd = /app/extra.
set -e
bsdtar -Oxf firmaec.deb data.tar.xz |
  bsdtar -xf - --strip-components=3 ./usr/share/firmaec
rm -f firmaec.deb
