#!/bin/bash
# Anillo de seguridad termico/electrico adaptativo.
# Uso: cpu-cool.sh watch|juego|medio|cool|restore|status
#
# La idea: en vez de un cinturon flojo permanente (limite bajo + frecuencia
# capada, que cuesta fps siempre), un cinturon ajustado que solo aprieta
# cuando hace falta:
#   1) tau corto: el hardware aplica el limite en 5s en vez de en 56s,
#      asi un limite ALTO ya es seguro (no hay minuto de barra libre).
#   2) presupuesto compartido: la CPU se queda los vatios que la GPU no usa.
#   3) vigilancia a 1s sobre las senales que de verdad avisan:
#      temperatura, la fuente sangrando bateria, y la VRAM.
#
# Pensado para correr permanentemente como servicio (cpu-cool.service).
# En reposo no aprieta nada: el presupuesto sobra.

R=/sys/class/powercap/intel-rapl:0
P=/sys/devices/system/cpu/intel_pstate

TOTAL=${TOTAL:-170}        # presupuesto CPU+GPU en vatios, enchufado
BAT_TOTAL=${BAT_TOTAL:-45} # presupuesto con el portatil a bateria
CPU_MIN=${CPU_MIN:-35}
CPU_MAX=${CPU_MAX:-95}
T_ALTO=${T_ALTO:-94}       # paquete CPU; el critico de verdad son 100
T_BAJO=${T_BAJO:-86}
TECHO_MIN=${TECHO_MIN:-130}   # suelo al que puede bajar el techo por sangrado
RECUP_S=${RECUP_S:-600}       # tras 10 min limpios, recupera 5W del techo
VRAM_AVISO=${VRAM_AVISO:-7300}   # MiB - a 7258 ya fallaba abrir kitty
VRAM_CRIT=${VRAM_CRIT:-7700}
VRAM_ESPERA=${VRAM_ESPERA:-120}  # segundos entre avisos, para no ser pesado
AVISOS=${AVISOS:-0}          # 0 = sin notificaciones de escritorio, solo journal

[ "$(id -u)" -eq 0 ] || { echo "necesita root: sudo $0 $*"; exit 1; }

pl1()   { echo $(( $1 * 1000000 )) > $R/constraint_0_power_limit_uw 2>/dev/null; }
pl2()   { echo $(( $1 * 1000000 )) > $R/constraint_1_power_limit_uw 2>/dev/null; }
tau()   { echo "$1" > $R/constraint_0_time_window_us 2>/dev/null; }   # 1) anillo estrecho
pct()   { echo "$1" 2>/dev/null > $P/max_perf_pct; }
epp()   { for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo "$1" 2>/dev/null > "$c"; done; }
boost() { echo "$1" > $P/hwp_dynamic_boost 2>/dev/null; }

# El paquete de CPU via hwmon: leerlo cuesta ~0 frente a invocar `sensors`
# cada segundo, que es justo lo que no queremos en un equipo con este problema.
HW=""
for h in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$h/name" 2>/dev/null)" = coretemp ] && { HW="$h/temp1_input"; break; }
done
temp() {
  if [ -n "$HW" ] && [ -r "$HW" ]; then echo $(( $(cat "$HW") / 1000 ))
  else sensors 2>/dev/null | awk '/Package id 0/{gsub(/[^0-9.]/,"",$4); print int($4); exit}'; fi
}

# Una sola llamada a nvidia-smi por vuelta para vatios y VRAM: invocarla dos
# veces por segundo se nota en la CPU y seria contraproducente.
GPU_W=90; GPU_VRAM=0
gpu_lee() {
  local o
  o=$(nvidia-smi --query-gpu=power.draw,memory.used --format=csv,noheader,nounits 2>/dev/null)
  GPU_W=$(echo "$o" | cut -d, -f1 | cut -d. -f1 | tr -cd '0-9')
  GPU_VRAM=$(echo "$o" | cut -d, -f2 | cut -d. -f1 | tr -cd '0-9')
  [ -z "$GPU_W" ] && GPU_W=90        # si no se puede leer, asumir lo peor
  [ -z "$GPU_VRAM" ] && GPU_VRAM=0
}

en_ac()   { [ "$(cat /sys/class/power_supply/ADP1/online 2>/dev/null)" = 1 ]; }
sangra()  { en_ac && [ "$(cat /sys/class/power_supply/BAT1/status 2>/dev/null)" = Discharging ]; }

# Avisos al escritorio. Corremos como root, asi que hay que entrar al bus de
# sesion del usuario que tenga sesion grafica abierta.
avisar() {
  [ "$AVISOS" = 1 ] || return 0
  local urg="$1" tit="$2" cuerpo="$3" bus uid usuario
  for bus in /run/user/*/bus; do
    [ -S "$bus" ] || continue
    uid=$(basename "$(dirname "$bus")")
    usuario=$(id -nu "$uid" 2>/dev/null) || continue
    sudo -u "$usuario" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
      notify-send -a "anillo" -u "$urg" -i cpu "$tit" "$cuerpo" 2>/dev/null
  done
}

log() { echo "$(date '+%H:%M:%S')  $*"; }

apply() {
  case "$1" in
    juego)   pl1 75; pl2 110; tau 5000000; pct 100; epp balance_performance; boost 1 ;;
    medio)   pl1 55; pl2  85; tau 5000000; pct 100; epp balance_performance; boost 1 ;;
    cool)    pl1 40; pl2  60; tau 2000000; pct  90; epp balance_power;       boost 0 ;;
    restore) pl1 157; pl2 200; tau 55967744; pct 100; epp performance;       boost 1 ;;
  esac
}

status() {
  gpu_lee
  echo "PL1: $(($(cat $R/constraint_0_power_limit_uw)/1000000))W en $(($(cat $R/constraint_0_time_window_us)/1000000))s   PL2: $(($(cat $R/constraint_1_power_limit_uw)/1000000))W"
  echo "max_perf_pct: $(cat $P/max_perf_pct)%   EPP: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)   hwp_boost: $(cat $P/hwp_dynamic_boost)"
  echo "CPU pico: $(grep 'cpu MHz' /proc/cpuinfo | sort -t: -k2 -rn | head -1 | awk '{printf "%d MHz",$4}')   paquete: $(temp)C"
  echo "GPU: ${GPU_W}W   VRAM: ${GPU_VRAM}/8188 MiB"
  echo "bateria: $(cat /sys/class/power_supply/BAT1/status 2>/dev/null)   AC: $(cat /sys/class/power_supply/ADP1/online 2>/dev/null)"
  systemctl is-active --quiet cpu-cool.service && echo "servicio: activo" || echo "servicio: parado"
}

# Los 3 mecanismos juntos: reparte el presupuesto cada segundo y vigila.
watch_loop() {
  local techo=$TOTAL t nuevo actual=0 caliente=0
  local incidente=0 ahora vram_ultimo=0 vram_nivel=0 ac_previo=-1 ac_ahora
  tau 5000000; pct 100; epp balance_performance; boost 1; pl2 110
  log "vigilando: presupuesto CPU+GPU ${techo}W, reparto cada 1s"
  trap 'echo; log "fin (PL1 queda en ${actual}W)"; exit 0' INT TERM

  while true; do
    gpu_lee; t=$(temp); [ -z "$t" ] && t=0
    ahora=$(date +%s)

    # --- enchufado o a bateria: son dos presupuestos distintos ---
    if en_ac; then ac_ahora=1; else ac_ahora=0; fi
    if [ "$ac_ahora" -ne "$ac_previo" ]; then
      if [ "$ac_ahora" = 1 ]; then
        techo=$TOTAL; epp balance_performance; boost 1; pl2 110
        log "AC conectada -> presupuesto ${techo}W"
      else
        epp balance_power; boost 0; pl2 60
        log "a bateria -> presupuesto ${BAT_TOTAL}W"
      fi
      ac_previo=$ac_ahora
    fi

    if [ "$ac_ahora" = 0 ]; then
      nuevo=$(( BAT_TOTAL - GPU_W ))
    else
      # si la fuente no da abasto, el techo baja. Es el sintoma mas serio
      # (corte seco sin logs), asi que solo se recupera muy despacio.
      if sangra; then
        [ "$techo" -gt "$TECHO_MIN" ] && techo=$(( techo - 10 ))
        [ "$techo" -lt "$TECHO_MIN" ] && techo=$TECHO_MIN
        incidente=$ahora
        log "la bateria esta ayudando a la fuente -> bajo el techo a ${techo}W"
        avisar critical "Anillo: la fuente no da abasto" \
          "El techo baja a ${techo}W. Es el sintoma del apagon seco."
      elif [ "$techo" -lt "$TOTAL" ] && [ $(( ahora - incidente )) -ge "$RECUP_S" ]; then
        techo=$(( techo + 5 )); [ "$techo" -gt "$TOTAL" ] && techo=$TOTAL
        incidente=$ahora
        log "$((RECUP_S/60)) min sin incidentes -> subo el techo a ${techo}W"
      fi
      nuevo=$(( techo - GPU_W ))
    fi

    # --- temperatura: dos vueltas seguidas por encima, no una punta suelta ---
    if [ "$t" -ge "$T_ALTO" ]; then
      caliente=$((caliente+1))
      [ "$caliente" -ge 2 ] && nuevo=$(( nuevo - 20 ))
    elif [ "$t" -le "$T_BAJO" ]; then caliente=0; fi

    [ "$nuevo" -lt "$CPU_MIN" ] && nuevo=$CPU_MIN
    [ "$nuevo" -gt "$CPU_MAX" ] && nuevo=$CPU_MAX
    if [ "$nuevo" -ne "$actual" ]; then pl1 "$nuevo"; actual=$nuevo; fi

    # --- VRAM: el cuello real. No se puede limitar, asi que se avisa ---
    # a tiempo, que es lo unico que evita que kwin (o kitty) se caiga.
    if [ "$GPU_VRAM" -ge "$VRAM_CRIT" ]; then
      if [ "$vram_nivel" -lt 2 ] || [ $(( ahora - vram_ultimo )) -ge "$VRAM_ESPERA" ]; then
        log "VRAM CRITICA: ${GPU_VRAM}/8188 MiB"
        avisar critical "VRAM al limite: ${GPU_VRAM}/8188 MiB" \
          "A punto de fallar. Cierra ventanas de Steam (~340MB) YA."
        vram_ultimo=$ahora; vram_nivel=2
      fi
    elif [ "$GPU_VRAM" -ge "$VRAM_AVISO" ]; then
      if [ "$vram_nivel" -lt 1 ] || [ $(( ahora - vram_ultimo )) -ge "$VRAM_ESPERA" ]; then
        log "VRAM alta: ${GPU_VRAM}/8188 MiB"
        avisar normal "VRAM alta: ${GPU_VRAM}/8188 MiB" \
          "Queda poco margen. Cerrar ventanas de Steam libera ~340MB."
        vram_ultimo=$ahora; vram_nivel=1
      fi
    elif [ "$GPU_VRAM" -lt $(( VRAM_AVISO - 300 )) ]; then
      vram_nivel=0   # histeresis: no re-avisar por oscilar en el umbral
    fi

    sleep 1
  done
}

case "$1" in
  watch)  watch_loop ;;
  juego|medio|cool|restore) apply "$1"; echo "perfil: $1"; status ;;
  status) status ;;
  *) echo "uso: $0 watch|juego|medio|cool|restore|status"; exit 1 ;;
esac
