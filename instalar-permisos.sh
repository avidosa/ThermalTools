#!/bin/bash
# Parte con root, una sola vez:  sudo ./instalar-permisos.sh
# Crea el grupo `powercap`, mete en el a quien lanzo sudo e instala la regla
# udev que deja a ese grupo cambiar PL1/PL2 en cada arranque.
# Deshacer:  sudo ./instalar-permisos.sh --quitar
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Necesita root: sudo $0"; exit 1; }

REGLA=/etc/udev/rules.d/90-thermaltools-powercap.rules
USUARIO=${SUDO_USER:-}

if [ "${1:-}" = --quitar ]; then
  rm -f "$REGLA"
  [ -n "$USUARIO" ] && gpasswd -d "$USUARIO" powercap 2>/dev/null || true
  udevadm control --reload
  echo "Regla quitada. Los permisos vuelven a root en el proximo arranque."
  exit 0
fi

[ -n "$USUARIO" ] && [ "$USUARIO" != root ] || { echo "Lanzalo con sudo desde tu usuario, no como root directamente."; exit 1; }
[ -d /sys/class/powercap/intel-rapl:0 ] || { echo "No hay intel-rapl: este equipo no expone PL1/PL2 por powercap."; exit 1; }

groupadd -f -r powercap
usermod -aG powercap "$USUARIO"
install -m 644 "$(dirname "$(readlink -f "$0")")/modos/90-thermaltools-powercap.rules" "$REGLA"
udevadm control --reload
udevadm trigger --subsystem-match=powercap --action=add
sleep 1
ls -l /sys/class/powercap/intel-rapl:0/constraint_{0,1}_power_limit_uw
echo
echo "Listo. Cierra sesion y vuelve a entrar para que '$USUARIO' tenga el grupo powercap."
