#!/bin/sh
# Imprime la ruta del jar a ejecutar: una copia escribible en
# $XDG_DATA_HOME/firmaec.
#
# Por qué: el autoupdate oficial de FirmaEC (firmador --update) sobrescribe
# el jar del que corre y además actualiza el otro jar del mismo directorio;
# en el flatpak /app es de solo lectura en runtime, así que ambos jars
# viven en el directorio de datos privado del app (siempre escribible) y el
# mecanismo oficial funciona sin sudo. Ambos jars se siembran juntos porque
# el actualizador exige que ambos existan (File.canWrite() da false sobre
# archivos inexistentes).
#
# Si el jar base de /app/extra cambia (nuevo .deb tras un flatpak update),
# la copia se regenera; entre tanto se conservan los jars auto-actualizados.
set -eu
data=${XDG_DATA_HOME:-$HOME/.local/share}/firmaec
sum() { sha256sum "$1" | cut -d' ' -f1; }
for jar_name in firmador-jar-with-dependencies.jar cliente-jar-with-dependencies.jar; do
  base=/app/extra/firmaec/$jar_name
  target=$data/$jar_name
  if [ ! -f "$target" ] ||
     [ "$(sum "$base")" != "$(cat "$data/$jar_name.base-sha256" 2>/dev/null || echo none)" ]; then
    mkdir -p "$data"
    install -m 644 "$base" "$target"
    sum "$base" > "$data/$jar_name.base-sha256"
  fi
done
printf '%s\n' "$data/$1"
