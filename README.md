# FirmaEC Flatpak (`ec.gob.firmadigital.FirmaEC`)

Empaquetado Flatpak de [FirmaEC](https://www.firmadigital.gob.ec/) 5.2.0, el
software oficial del Ecuador para firmar documentos electrónicos, a partir del
instalador oficial `.deb` (que a su vez contiene los jars oficiales + un JRE
Temurin 17 incluido).

## Contenido del paquete

| Componente | Origen | Uso |
|---|---|---|
| `firmador` (GUI) | `firmador-jar-with-dependencies.jar` | Firma standalone de PDF/XML/OOXML/ODF con .p12 o token |
| `firmaec` (transversal) | `cliente-jar-with-dependencies.jar` | Firma desde portales web vía protocolo `firmaec://` |
| JRE Temurin 17.0.13 | incluido en el `.deb` oficial | Ejecución de los jars |
| pcsc-lite (solo librería cliente) | compilada en el build | Módulo `java.smartcardio` para tokens USB |

## Instalar sin compilar

Descargar el bundle del [último release](https://github.com/brAvEiitoOr/firmaec-flatpak/releases/latest) e instalarlo:

```bash
flatpak install ./firmaec-5.2.0.flatpak
```

El bundle single-file incluye la app; solo requiere Flathub para descargar el
runtime `org.freedesktop.Platform 25.08` y el `.deb` oficial (extra-data).

## Cómo funciona el empaquetado

Patrón estándar de Flathub para apps distribuidas como `.deb` (igual que
`com.google.Chrome`):

1. El manifest declara el `.deb` oficial como `extra-data` (URL + sha256 +
   tamaño fijados). No se almacena en el repo OSTree.
2. Al instalar (o al primer arranque), flatpak descarga el `.deb` a
   `/app/extra/`.
3. Flatpak ejecuta automáticamente `/app/bin/apply_extra` (con `bsdtar` del
   runtime), que descomprime los jars + JRE en `/app/extra/firmaec/`.
4. Los lanzadores `/app/bin/firmador` y `/app/bin/firmaec` arrancan el JRE
   incluido con el jar correspondiente.

## Compilar

```bash
flatpak-builder --user --install --force-clean build-dir ec.gob.firmadigital.FirmaEC.yml
```

Requiere los remotes/runtimes 25.08 disponibles para la instalación `--user`
(`org.freedesktop.Sdk` + `org.freedesktop.Platform`). La primera vez descarga
~1.5 GB.

## Permisos solicitados y por qué

- `--socket=x11` + `--share=ipc`: la GUI es Swing; en JDK 17 no existe toolkit
  Wayland, corre bajo XWayland.
- `--share=network`: el cliente transversal descarga/sube los documentos a
  firmar; el standalone consulta la versión en `api.firmadigital.gob.ec`.
- `--filesystem=home`: abrir y guardar los documentos que se firman.
- `--socket=pcsc`: acceso al socket de `pcscd` **del host** para los tokens
  criptográficos USB (verificado end-to-end: el sandbox alcanza pcscd). Requiere
  el servicio activo en el host:

  ```bash
  sudo systemctl enable --now pcscd.socket
  ```

- Rutas `:ro` de drivers PKCS#11: FirmaEC carga directamente los drivers de
  tokens instalados en el host (`/usr/lib/libeTPkcs11.so` para ePass2003/SafeWeb
  — el token más común en Ecuador —, bit4id, SafeNet, SecurityData). Los
  drivers se instalan en el host como siempre (instaladores oficiales de
  [drivers de tokens](https://www.firmadigital.gob.ec/drivers-tokens/)) y el
  sandbox los ve en la misma ruta, en modo lectura.

## Integración con el navegador (`firmaec://` — Quipux y sistemas transversales)

Cadena verificada end-to-end en esta máquina:

1. El usuario pulsa "Firmar" en Quipux → el navegador recibe un enlace
   `firmaec://firmar?archivo=...&token=...`.
2. El navegador delega el esquema al escritorio (xdg-open / portal OpenURI;
   funciona también con Firefox/Chrome empaquetados como flatpak).
3. La base de datos de MIME del escritorio resuelve
   `x-scheme-handler/firmaec` → `ec.gob.firmadigital.FirmaEC.Transversal.desktop`
   (exportado por el flatpak).
4. Flatpak lanza el sandbox con la URL como argumento
   (`flatpak run --command=/app/bin/firmaec ... <url>`).
5. El jar cliente oficial (auto-actualizado, corre desde la copia escribible)
   descarga el documento del servidor, lo firma (token o .p12) y lo sube de
   vuelta. Red y `home` ya están concedidas.

Diferencia con la instalación nativa: el `.deb` escribe
`/etc/firefox/pref/firmaec.js` para registrar el handler sin preguntar; el
flatpak no puede (ni debe) tocar la config del Firefox del host. La primera
vez, Firefox muestra "¿Abrir con...?" → elegir **FirmaECTransversal** y
marcar *recordar*; a partir de ahí el comportamiento es idéntico. Si el
escritorio no lo resuelve solo, forzar el handler:

```bash
xdg-mime default ec.gob.firmadigital.FirmaEC.Transversal.desktop x-scheme-handler/firmaec
```

## Soporte Java Web Start (JNLP)

Algunos sistemas de gestión documental firman mediante clientes Java Web
Start que el navegador abre con enlaces `jnlp://`/`jnlps://` (archivos
`.jnlp`). Este repo incluye un mini-lanzador autocontenido que no requiere
root ni paquetes del sistema:

- Parsea el JNLP (codebase, jars, main-class, argumentos, versión de Java).
- Descarga y cachea los jars (revalidando tamaño con HEAD; re-descarga si
  el servidor los actualiza).
- Gestiona el JRE exigido por el JNLP (p. ej. Java 8) en
  `~/.local/share/jnlp-launcher/`, descargándolo de Adoptium/Temurin la
  primera vez.
- Ejecuta el cliente con `os.execv` (este proceso se convierte en la JVM).

Los clientes JNLP corren en el host con permisos plenos, igual que en el
Web Start clásico (el jar suele firmarse con `<all-permissions/>`); el
acceso a tokens (pcscd y drivers PKCS#11 del host) es nativo.

Instalación:

```bash
mkdir -p ~/.local/bin ~/.local/share/applications
cp jnlp-launcher ~/.local/bin/ && chmod +x ~/.local/bin/jnlp-launcher
sed "s|^Exec=.*|Exec=$HOME/.local/bin/jnlp-launcher %u|" \
  jnlp-launcher.desktop > ~/.local/share/applications/jnlp-launcher.desktop
update-desktop-database ~/.local/share/applications
xdg-mime default jnlp-launcher.desktop x-scheme-handler/jnlps \
  x-scheme-handler/jnlp application/x-java-jnlp-file
```

Uso directo:

```bash
jnlp-launcher 'jnlps://servidor.ejemplo/ruta/cliente.jnlp'
```

En el navegador, el primer clic en un enlace `jnlp(s)://` mostrará el
selector de aplicaciones una vez; elegir **JNLP Launcher** y marcar
*recordar*.

## Limitaciones conocidas

1. **Solo x86_64**: el paquete oficial incluye un JRE Temurin 17 x86_64. No
   existe build oficial aarch64.
2. **Drivers de tokens**: se cargan desde el host vía las rutas mapeadas
   read-only. Si un driver depende de librerías que no existen en el runtime
   (p. ej. OpenSSL 1.1), podría fallar su carga dentro del sandbox; el
   ePass2003/SafeWeb depende solo de glibc/libcrypto y funciona.
3. **Firefox / protocolo `firmaec://`**: el instalador nativo escribe un pref
   en `/etc/firefox/pref` (imposible desde el sandbox). Con el flatpak basta
   el `.desktop` exportado con `MimeType=x-scheme-handler/firmaec;`: al abrir
   un enlace `firmaec://`, Firefox preguntará con qué aplicación abrirlo una
   vez (elegir "FirmaECTransversal" y marcar "recordar").
4. **Autoupdate oficial (`firmador --update`) — SOPORTADO con una salvedad**:
   el gobierno actualiza la app sobrescribiendo los jars desde
   `api.firmadigital.gob.ec` (no republicando el `.deb`). Como `/app` es de
   solo lectura en runtime, los lanzadores ejecutan los jars desde una copia
   escribible en `~/.var/app/ec.gob.firmadigital.FirmaEC/data/firmaec/`
   (gestionada por `/app/bin/firmaec-sync`); ahí el mecanismo oficial funciona
   sin sudo (verificado: ambos jars se actualizan desde la API, exit 0). No
   ejecutar con `sudo` — dentro del sandbox no existe y no hace falta.
5. **Licencia**: el `.deb` no declara licencia (`LicenseRef-proprietary` en el
   metainfo); confirmar con upstream antes de publicar en Flathub.

## Actualizaciones de la app

El gobierno no republica el `.deb`: actualiza los jars vía
`api.firmadigital.gob.ec`. El flatpak lo soporta así:

- **Actualización de jars (la habitual)**: la GUI la ofrece al arrancar, o
  manualmente (sin sudo):

  ```bash
  flatpak run --command=firmador ec.gob.firmadigital.FirmaEC --update
  ```

  Escribe los jars nuevos en el dir de datos privado del app; las siguientes
  ejecuciones usan los jars actualizados.

- **Actualización del paquete base** (solo si upstream cambia el instalador,
  p. ej. nuevo JRE): actualizar `sha256`/`size` del `extra-data` en el
  manifest y `flatpak update`; `firmaec-sync` detecta el cambio de base y
  regenera las copias escribibles.

## Verificación realizada (Arch Linux, flatpak 1.18.2, runtime 25.08)

- `flatpak-builder` compila e instala sin errores; AppStream `validate` OK.
- `firmador` (GUI standalone) arranca y se mantiene vivo; verifica versión
  contra `api.firmadigital.gob.ec` (red OK).
- `firmaec` (cliente transversal) responde `{"resultado":"Version enabled"}`
  y espera el parámetro `firmaec://...` — el handler del protocolo se registra
  vía el `.desktop` exportado (Firefox preguntará la primera vez).
- PC/SC: `SCardEstablishContext` devuelve `SCARD_S_SUCCESS` dentro del sandbox
  con `pcscd.socket` activo en el host (queda activado en esta máquina).
- Extracción en primer arranque (`apply_extra`) verificada: jars + JRE
  disponibles en `/app/extra/firmaec/`.
- Autoupdate oficial verificado end-to-end en el flatpak: `firmador --update`
  sin sudo detecta ambas versiones nuevas en la API, descarga, verifica hash y
  actualiza firmador + cliente (exit 0); la GUI corre con los jars
  actualizados.

## Para publicar en Flathub (pendiente)

- Confirmar el uso del app-id `ec.gob.firmadigital.FirmaEC` (política de
  Flathub: el ID debe estar respaldado por el dueño del dominio
  `firmadigital.gob.ec`, o con su autorización).
- Completar el metainfo: capturas de pantalla, `<update_contact>`, OARS final,
  y `<releases>` actualizables con un `x-checker-data` sobre la URL oficial.
- Añadir verificación de versión con `flatpak-external-data-checker` (el
  extra-data apunta a la URL oficial; cuando upstream publique 5.2.1+, hay que
  actualizar `sha256`/`size`).
