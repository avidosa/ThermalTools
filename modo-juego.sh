#!/bin/bash
# Cambia el perfil de energia automaticamente: 'performance' mientras hay un
# juego abierto, 'balanced' el resto del tiempo.
#
# POR QUE: con 'balanced' el sistema es conservador subiendo frecuencias y la
# GPU se queda esperando ordenes -> 35 fps. Con 'performance' -> 45 fps, pero
# la CPU pasa de 72 a 95 C, que es temperatura de riesgo de apagon. La solucion
# es no pagar ese calor cuando no se esta jugando. (Medido el 12 sep 2026.)
#
# COMO DETECTA EL JUEGO: por la memoria de video que ocupa un proceso. Asi vale
# para cualquier juego, no solo Bodycam, y no hay que mantener una lista.
#
# No necesita root: powerprofilesctl va por polkit, y al cambiar de perfil el
# propio power-profiles-daemon ajusta el EPP de los 32 nucleos.

UMBRAL_MIB=${UMBRAL_MIB:-1500}   # plasmashell ronda 900 MiB; un juego pasa de 2000
INTERVALO=${INTERVALO:-5}        # segundos entre comprobaciones
CONFIRMAR=${CONFIRMAR:-2}        # lecturas seguidas iguales antes de cambiar (anti-rebote)
LOG=${HOME}/modo-juego.log

# Procesos que usan VRAM pero NO son juegos
EXCLUIR='plasmashell|kwin_wayland|Xwayland|steamwebhelper|krunner|kitty|firefox|chrome|obs'

hay_juego() {
  nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null |
  while IFS=', ' read -r pid mib; do
    [ "${mib:-0}" -ge "$UMBRAL_MIB" ] 2>/dev/null || continue
    nombre=$(cat /proc/$pid/comm 2>/dev/null)
    echo "$nombre" | grep -qE "$EXCLUIR" && continue
    echo "SI"; break
  done | grep -q SI
}

poner() {
  actual=$(powerprofilesctl get 2>/dev/null)
  [ "$actual" = "$1" ] && return
  if powerprofilesctl set "$1" 2>/dev/null; then
    echo "$(date '+%F %T')  perfil -> $1   (motivo: $2)" >> "$LOG"
  else
    echo "$(date '+%F %T')  FALLO al poner $1" >> "$LOG"
  fi
}

# Al salir, dejar el equipo fresco
trap 'poner balanced "servicio detenido"; exit 0' TERM INT

echo "$(date '+%F %T')  vigilante de perfil arrancado (umbral ${UMBRAL_MIB} MiB, cada ${INTERVALO}s)" >> "$LOG"

seguidas=0; estado_previo=""
while true; do
  if hay_juego; then estado=juego; else estado=escritorio; fi

  if [ "$estado" = "$estado_previo" ]; then
    seguidas=$((seguidas+1))
  else
    seguidas=1; estado_previo="$estado"
  fi

  if [ "$seguidas" -ge "$CONFIRMAR" ]; then
    [ "$estado" = juego ] && poner performance "juego detectado" || poner balanced "sin juego"
  fi

  sleep "$INTERVALO"
done
