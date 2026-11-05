#!/bin/bash
# Instala el anillo como servicio permanente. Ejecutar una sola vez:
#   sudo ~/cpu-cool-instalar.sh
set -e
[ "$(id -u)" -eq 0 ] || { echo "necesita root: sudo $0"; exit 1; }

echo "==> instalando unidad"
install -m 644 "$(dirname "$0")/cpu-cool.service" /etc/systemd/system/cpu-cool.service
systemctl daemon-reload

echo "==> habilitando y arrancando"
systemctl enable --now cpu-cool.service

sleep 3
echo
echo "==> estado"
systemctl is-enabled cpu-cool.service && echo "   arrancara solo en cada reinicio"
systemctl --no-pager --lines=10 status cpu-cool.service || true
echo
echo "==> comprobacion del anillo"
/usr/local/bin/cpu-cool.sh status
echo
echo "Listo. Para verlo trabajar en directo:  journalctl -fu cpu-cool"
