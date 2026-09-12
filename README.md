# ThermalTools

Cuatro scripts de Bash para un portátil que se apagaba de golpe jugando. No son un
monitor bonito: son el resultado de diagnosticar el problema y ponerle una red de
seguridad que no cueste rendimiento cuando no hace falta.

Septiembre de 2026.

## El problema, y por qué importa el diagnóstico

El equipo se apagaba en seco durante las partidas. La explicación fácil era "se
calienta", y era **falsa**: el crítico del paquete de CPU está en 100 °C, en carga real
iba a 77-83 °C, y en todo el *journal* no había un solo mensaje térmico. El log cortaba
de golpe, sin secuencia de apagado.

Eso apunta a otra cosa: **corte eléctrico por pico de consumo**. La pista que lo confirma
es que la batería se pone a descargarse *estando enchufado* — la fuente no da abasto y la
batería entra a ayudar. Ese es el síntoma que vigila `cpu-cool.sh`.

Capar los vatios arregla el apagón igual que capar la temperatura, pero **si diagnosticas
"calor" te quedas con un equipo lento sin motivo**.

## Los scripts

### `cpu-cool.sh` — el anillo de seguridad

Reparto dinámico de vatios entre CPU y GPU, con vigilancia cada segundo. La idea no es
poner un límite bajo permanente (eso cuesta fps siempre), sino un límite **alto pero que
se aplique rápido**:

- **Ventana corta (`tau` de 5 s en vez de 56 s)**: el hardware aplica el límite en
  segundos, así un techo alto ya es seguro porque no hay un minuto de barra libre.
- **Presupuesto compartido**: la CPU se queda los vatios que la GPU no está usando,
  leídos en vivo con `nvidia-smi`.
- **Techo adaptativo**: si detecta que la batería está ayudando a la fuente, baja el techo
  10 W y lo recupera muy despacio (5 W cada 10 minutos limpios). El síntoma serio se
  castiga rápido y se perdona lento.
- **Dos presupuestos**: uno enchufado y otro a batería, cambiando solo al detectar el
  cable.
- Vigila también la **VRAM**, porque a 7258 MiB ya fallaba abrir una terminal.

```bash
sudo ./cpu-cool.sh watch      # modo servicio: vigila y reparte
sudo ./cpu-cool.sh status     # qué límites hay puestos ahora
sudo ./cpu-cool.sh medio      # perfil intermedio
sudo ./cpu-cool.sh cool       # apretar de verdad
sudo ./cpu-cool.sh restore    # dejarlo como venía de fábrica
```

Se instala como servicio permanente con `sudo ./instalar.sh` (copia el script a
`/usr/local/bin/`, habilita `cpu-cool.service` y comprueba que arranca). El servicio lleva
`Restart=always`, porque quedarse sin anillo es justo el fallo que se quiere evitar.

### `caja-negra.sh` — saber a qué temperatura murió

Registra temperatura y VRAM cada 2 segundos **con volcado inmediato a disco**. Ese detalle
es todo el invento: en un corte duro lo que queda en el buffer se pierde, y es exactamente
lo que interesa leer después.

```bash
./caja-negra.sh "partida de la tarde"   # etiqueta la sesión y deja corriendo
./caja-negra.sh ultimas                 # las últimas líneas antes del corte
./caja-negra.sh resumen                 # estadísticas de la última sesión
```

Lee la temperatura directamente de `hwmon`, sin invocar `sensors`, para que el muestreo
sea barato.

### `modo-juego.sh` — perfil de energía automático

Pone el perfil `performance` mientras hay un juego abierto y `balanced` el resto del
tiempo. Medido: con `balanced` 35 fps; con `performance` 45 fps, pero la CPU sube de
72 a 95 °C. La conclusión no es elegir uno, es **no pagar ese calor cuando no estás
jugando**.

Detecta el juego **por la memoria de vídeo que ocupa un proceso**, no por una lista de
nombres: así vale para cualquier juego y no hay nada que mantener. Con antirrebote de dos
lecturas seguidas para no cambiar de perfil por un parpadeo.

No necesita root: `powerprofilesctl` va por polkit.

### `vigilante-96.sh` — red de seguridad puntual

Si la CPU **se asienta** en 96 °C, baja el perfil y se quita de en medio.

Mira la **media de las últimas 30 muestras (~1 minuto)**, no el pico. Los picos sueltos de
96-100 °C son constantes incluso con el equipo estable a 93 de media: disparar por pico
quitaría fps por un parpadeo. Lo que importa es que el equipo se quede ahí.

Detalle que costó encontrar: hay que **parar también `modo-juego.sh`**, porque si no el
vigilante de juego vuelve a poner `performance` cinco segundos después.

## Antes de usarlo en otro equipo

Los números están calibrados para un portátil concreto: Intel con `intel-rapl` e
`intel_pstate`, GPU NVIDIA leída con `nvidia-smi`, 8 GB de VRAM y una fuente que se queda
corta por encima de ~170 W. Todo eso son variables al principio de cada script
(`TOTAL`, `BAT_TOTAL`, `T_ALTO`, `VRAM_AVISO`…), pero **los umbrales hay que medirlos en
cada máquina**, no copiarlos.

Los scripts escriben en `/sys/class/powercap` y `/sys/devices/system/cpu`: eso toca
límites de potencia reales del procesador. Leer lo que hacen antes de ejecutarlos como
root no es paranoia, es sentido común.
