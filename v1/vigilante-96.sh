#!/bin/bash
# Red de seguridad puntual (12 sep 2026): si la CPU se asienta en 96 C, baja el
# perfil a 'balanced' y se quita de en medio.
#
# POR QUE LA MEDIA Y NO EL PICO: la caja negra mira cada 2 s y los picos sueltos
# a 96-100 C son constantes incluso con el equipo estable a 93 de media. Un
# disparo por pico saltaria al instante y quitaria fps por un parpadeo. Lo que
# importa es que el equipo se ASIENTE ahi. Media de las ultimas 30 muestras (~1 min).
#
# Hay que parar modo-juego.sh ademas de cambiar el perfil: si no, el vigilante de
# juego vuelve a poner 'performance' a los 5 segundos. Su trap ya deja 'balanced'.

UMBRAL=${UMBRAL:-96}
MUESTRAS=${MUESTRAS:-30}
LOG=${HOME}/caja-negra.log
MIO=${HOME}/vigilante-96.log

echo "$(date '+%F %T')  vigilante armado: media de $MUESTRAS muestras >= $UMBRAL C -> balanced" >> "$MIO"

while true; do
  media=$(grep "^2026" "$LOG" | tail -n "$MUESTRAS" | awk '$3+0>0{s+=$3;n++} END{if(n>0) printf "%.1f", s/n; else print 0}')

  if awk -v m="$media" -v u="$UMBRAL" 'BEGIN{exit !(m>=u)}'; then
    echo "$(date '+%F %T')  DISPARO: media $media C >= $UMBRAL C" >> "$MIO"

    # 1. Parar el vigilante de juego, o volveria a subir a performance en 5 s
    pkill -TERM -f "bash .*modo-juego.sh" 2>/dev/null
    sleep 1
    # 2. Asegurar el perfil (el trap de modo-juego.sh ya deberia haberlo hecho)
    powerprofilesctl set balanced 2>/dev/null
    echo "$(date '+%F %T')  perfil ahora: $(powerprofilesctl get)" >> "$MIO"

    notify-send -u critical -t 20000 "Temperatura: bajando a balanced" \
      "CPU asentada en ${media} C. Perfil -> balanced y vigilante de juego parado. Perderas ~10 fps." 2>/dev/null
    paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null &

    echo "$(date '+%F %T')  vigilante terminado" >> "$MIO"
    exit 0
  fi
  sleep 5
done
