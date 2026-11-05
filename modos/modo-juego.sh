#!/bin/bash
# Vigilante de juego: con el modo chill o equilibrado elegido, sube a "juego"
# mientras hay un juego abierto y vuelve al modo elegido al cerrarlo. Con
# juego o nolimit elegidos no hace nada distinto.
#
# COMO DETECTA EL JUEGO: por la memoria de video que ocupa un proceso, no por
# una lista de nombres. Vale para cualquier juego y no hay nada que mantener.
#
# Ademas reaplica el modo en cada vuelta: algunos firmwares (MSI, por ejemplo)
# restablecen PL1/PL2 al cambiar de fuente de alimentacion.

UMBRAL_MIB=${UMBRAL_MIB:-1500}   # el escritorio ronda 900 MiB; un juego pasa de 2000
INTERVALO=${INTERVALO:-5}        # segundos entre comprobaciones
CONFIRMAR=${CONFIRMAR:-2}        # lecturas seguidas iguales antes de cambiar
EXCLUIR='plasmashell|kwin_wayland|Xwayland|steamwebhelper|krunner|kitty|firefox|chrome|obs'

MODO=$(dirname "$(readlink -f "$0")")/modo
ESTADO=${XDG_CONFIG_HOME:-$HOME/.config}/thermaltools/modo
LOG=${XDG_STATE_HOME:-$HOME/.local/state}/thermaltools/modo.log
mkdir -p "$(dirname "$LOG")"

hay_juego() {
  command -v nvidia-smi >/dev/null || return 1
  nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null |
  while IFS=', ' read -r pid mib; do
    [ "${mib:-0}" -ge "$UMBRAL_MIB" ] 2>/dev/null || continue
    grep -qE "$EXCLUIR" "/proc/$pid/comm" 2>/dev/null && continue
    echo SI; break
  done | grep -q SI
}

ultimo=""
poner() {
  local base objetivo
  base=$(cat "$ESTADO" 2>/dev/null || echo equilibrado)
  case "$base" in
    chill|equilibrado) [ "$1" = juego ] && objetivo=juego || objetivo=$base ;;
    juego|nolimit)     objetivo=$base ;;
    *)                 objetivo=equilibrado ;;
  esac
  "$MODO" --aplicar "$objetivo" >/dev/null 2>&1
  if [ "$objetivo" != "$ultimo" ]; then
    echo "$(date '+%F %T')  activo -> $objetivo   (elegido: $base, $2)" >> "$LOG"
    ultimo=$objetivo
  fi
}

trap '"$MODO" --aplicar equilibrado; exit 0' TERM INT
echo "$(date '+%F %T')  vigilante arrancado (umbral ${UMBRAL_MIB} MiB, cada ${INTERVALO}s)" >> "$LOG"

seguidas=0; previo=""
while true; do
  hay_juego && estado=juego || estado=escritorio
  [ "$estado" = "$previo" ] && seguidas=$((seguidas+1)) || { seguidas=1; previo=$estado; }
  [ "$seguidas" -ge "$CONFIRMAR" ] && poner "$estado" "$estado"
  sleep "$INTERVALO"
done
