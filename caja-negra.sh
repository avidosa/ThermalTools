#!/bin/bash
# Caja negra: registra temperatura y VRAM a disco cada 2s.
# Objetivo: si el equipo se apaga de golpe, saber a que temperatura y con
# cuanta VRAM murio. La clave es el flush inmediato: en un corte duro, lo que
# esta en el buffer se pierde, y justo eso es lo que nos interesa.
#
# Uso:  ~/caja-negra.sh "partida bodycam"   (etiqueta la sesion; dejarlo corriendo)
#       ~/caja-negra.sh ultimas             (ultimas lineas antes del ultimo corte)
#       ~/caja-negra.sh resumen             (estadisticas de la ultima sesion)

LOG=${HOME}/caja-negra.log

# Temperatura del paquete de CPU, leida de hwmon (barato, no invoca `sensors`)
HW=""
for h in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$h/name" 2>/dev/null)" = coretemp ] && { HW="$h/temp1_input"; break; }
done

if [ "$1" = ultimas ]; then
  echo "=== ultimas 25 lineas antes del ultimo corte ==="
  tail -25 "$LOG" 2>/dev/null || echo "(no hay registro todavia)"
  exit 0
fi

# Resumen de la ULTIMA sesion (desde el ultimo ARRANQUE). Sirve para comparar
# una partida con otra, p.ej. con y sin Cooler Boost.
if [ "$1" = resumen ]; then
  [ -r "$LOG" ] || { echo "(no hay registro todavia)"; exit 1; }
  awk '
    /^===== ARRANQUE/ { inicio=$0; n=0; delete cpu; cmax=0; gmax=0; fmax=0; vmax=0;
                        csum=0; gsum=0; wsum=0; vsum=0; fsum=0; c95=0; f6=0; ini=""; next }
    $1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && $3+0>0 {
        n++; csum+=$3; gsum+=$4; wsum+=$5; vsum+=$6; fsum+=$7
        if ($3>cmax) cmax=$3; if ($4>gmax) gmax=$4
        if ($6>vmax) vmax=$6; if ($7>fmax) fmax=$7
        if ($3>=95) c95++
        if ($7>=6000) f6++
        fin=$1" "$2; if (!ini) ini=$1" "$2
    }
    END {
        if (n==0) { print "(la ultima sesion no tiene muestras validas)"; exit }
        printf "%s\n", inicio
        printf "Periodo : %s  ->  %s   (%d muestras, ~%.1f min)\n", ini, fin, n, n*2/60
        printf "CPU     media %3d C   PICO %3d C   muestras >=95 C: %d\n", csum/n, cmax, c95
        printf "GPU     media %3d C   pico %3d C\n", gsum/n, gmax
        printf "GPU W   media %3d W   (de 140 disponibles)\n", wsum/n
        printf "VRAM    media %4d     pico %4d / 8188\n", vsum/n, vmax
        printf "Fan1    media %4d rpm   PICO %4d rpm   (maximo del equipo ~7870)\n", fsum/n, fmax
        printf "Cooler Boost: %s (%d%% de las muestras con ventiladores >=6000 rpm)\n", (f6>n*0.5?"SI, activo":(f6>0?"a ratos":"NO")), f6*100/n
    }
  ' "$LOG"
  echo "Alarmas criticas en esta sesion: $(awk '/^===== ARRANQUE/{n=0} /ALARMA CRITICA/{n++} END{print n+0}' "$LOG")"
  exit 0
fi

# Aviso que se ve aunque el juego este a pantalla completa
# Avisos de pantalla DESACTIVADOS a peticion del usuario (2026-09-12): el
# detector de subidon de rpm daba falsos positivos constantes con Cooler Boost,
# que oscila entre 6500 y 7700 rpm. Las alarmas siguen quedando en el LOG, que
# es para lo que existe la caja negra. Para reactivarlas, descomentar.
avisar() {  # $1=urgencia  $2=titulo  $3=texto
  : # silencioso
  # notify-send -u "$1" -t 10000 "$2" "$3" 2>/dev/null
  # paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null &
}

# Marca de arranque: asi se distingue una sesion de la siguiente en el fichero
{
  echo "===== ARRANQUE $(date '+%F %T')${1:+  --  $1} ====="
  echo "fecha_hora            cpuC  gpuC  gpuW  vram_MiB  fan1_rpm  carga   AC  bateria      mA"
} >> "$LOG"

echo "Caja negra en marcha${1:+ — sesion: $1}. Registrando a $LOG cada 2 s."
echo "Si suena la alarma de ventiladores: NO cortes la prueba, dejala llegar al final."

while true; do
  cpu=$([ -r "$HW" ] && echo $(( $(cat "$HW") / 1000 )) || echo "?")
  read -r gpuc gpuw vram <<< "$(nvidia-smi \
      --query-gpu=temperature.gpu,power.draw,memory.used \
      --format=csv,noheader,nounits 2>/dev/null | tr -d ',' )"
  fan=$(sensors 2>/dev/null | awk '/fan1/{print $2; exit}')
  load=$(cut -d' ' -f1 /proc/loadavg)
  # Firma ELECTRICA: si la bateria se descarga estando enchufado, es que la fuente
  # no da abasto y la bateria esta ayudando. Ese es el sintoma previo al corte seco.
  ac=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null)
  bat=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null)
  ma=$(( $(cat /sys/class/power_supply/BAT1/current_now 2>/dev/null || echo 0) / 1000 ))

  printf '%s  %4s  %4s  %5s  %8s  %8s  %5s  %3s  %-11s %5s\n' \
    "$(date '+%F %T')" "$cpu" "${gpuc:-?}" "${gpuw%%.*}" "${vram:-?}" "${fan:-?}" "$load" \
    "${ac:-?}" "${bat:-?}" "$ma" >> "$LOG"

  # Alarma electrica: descargando bateria CON el cargador puesto = la fuente no llega.
  if [ "$ac" = 1 ] && [ "$bat" = Discharging ]; then
    echo "  *** LA FUENTE NO DA ABASTO: bateria aportando ${ma} mA con el cargador puesto ***" >> "$LOG"
    avisar normal "Sangrado de bateria" "La fuente no llega: ${ma} mA saliendo de la bateria con el cargador puesto."
  fi

  # ALARMA. El umbral antiguo (rpm > 6000 a secas) no vale: con Cooler Boost
  # puesto los ventiladores van a ~7700 toda la partida y pitaria sin parar.
  # Las dos condiciones que SI significan peligro:
  #   a) ventiladores al maximo Y la CPU aun asi muy caliente -> la refrigeracion no llega
  #   b) subidon brusco de rpm -> el patron que describe el usuario justo antes del corte
  salto=$(( ${fan:-0} - ${fan_ant:-${fan:-0}} ))
  motivo=""
  if [ "${fan:-0}" -gt 6000 ] 2>/dev/null && [ "${cpu:-0}" -ge 90 ] 2>/dev/null; then
    motivo="ventiladores al maximo (${fan} rpm) y CPU AUN A ${cpu} C: la refrigeracion no llega"
  elif [ "$salto" -gt 1200 ] 2>/dev/null && [ "${cpu:-0}" -ge 85 ] 2>/dev/null; then
    motivo="subidon brusco de ventiladores (+${salto} rpm de golpe -> ${fan} rpm, CPU ${cpu} C)"
  fi
  if [ -n "$motivo" ]; then
    echo "  *** ALARMA CRITICA: $motivo ***" >> "$LOG"
    avisar critical "CAJA NEGRA: apagon posible" "$motivo. NO cortes la caja negra."
  fi
  fan_ant=${fan:-$fan_ant}

  # sync: fuerza la escritura al disco AHORA. Sin esto, un corte duro se lleva
  # los ultimos segundos, que son precisamente los que hay que leer.
  sync -d "$LOG" 2>/dev/null

  sleep 2
done
