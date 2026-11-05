#!/bin/bash
# Instala ThermalTools v2 para tu usuario (sin root):
#   ./instalar.sh            comandos, configuracion, servicio y widget
#   ./instalar.sh --quitar   lo deshace (deja tu modos.conf)
# Los permisos de los vatios van aparte: sudo ./instalar-permisos.sh
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Lanzalo con tu usuario, sin sudo."; exit 1; }

DIR=$(dirname "$(readlink -f "$0")")
BIN=$HOME/.local/bin
CONF=${XDG_CONFIG_HOME:-$HOME/.config}/thermaltools
UNIT=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
WIDGET=org.thermaltools.modotemp

if [ "${1:-}" = --quitar ]; then
  systemctl --user disable --now modo-juego.service 2>/dev/null || true
  rm -f "$BIN/modo" "$BIN/modo-juego.sh" "$BIN/prueba-termica" "$UNIT/modo-juego.service"
  systemctl --user daemon-reload
  kpackagetool6 -t Plasma/Applet -r "$WIDGET" 2>/dev/null || true
  echo "Quitado. Tu configuracion sigue en $CONF"
  exit 0
fi

for c in powerprofilesctl; do command -v "$c" >/dev/null || { echo "Falta $c (power-profiles-daemon)."; exit 1; }; done

mkdir -p "$BIN" "$CONF" "$UNIT"
install -m 755 "$DIR/modos/modo" "$DIR/modos/modo-juego.sh" "$DIR/herramientas/prueba-termica" "$BIN/"
[ -e "$CONF/modos.conf" ] || install -m 644 "$DIR/modos/modos.conf" "$CONF/modos.conf"
install -m 644 "$DIR/modos/modo-juego.service" "$UNIT/"
systemctl --user daemon-reload
systemctl --user enable --now modo-juego.service

if command -v kpackagetool6 >/dev/null; then
  kpackagetool6 -t Plasma/Applet -u "$DIR/modos/plasmoid/$WIDGET" 2>/dev/null ||
  kpackagetool6 -t Plasma/Applet -i "$DIR/modos/plasmoid/$WIDGET"
  echo "Widget instalado: clic derecho en el panel -> Anadir widgets -> 'Modo y temperatura'."
fi

case ":$PATH:" in *":$BIN:"*) ;; *) echo "Ojo: $BIN no esta en tu PATH." ;; esac
echo
echo "Hecho. Configura los vatios en $CONF/modos.conf"
echo "Si aun no lo hiciste:  sudo ./instalar-permisos.sh  (y vuelve a iniciar sesion)"
echo "Luego escribe:  modo"
