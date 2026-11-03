# Balance

Simulación headless bot contra bot (`tools/balance_run.sh [partidas_por_combinación] [etiqueta]`, que lanza `tools/balance_sim.gd` en paralelo
y arma las tablas con `tools/balance_report.py`). Cada partida sortea dos equipos al azar (clases con repetición) y se juega completa con los
bots (dificultad normal) en un mapa; la tasa de victoria de una clase cuenta cada copia en el equipo ganador.

**Salvedad importante:** los números dependen de la habilidad de los bots. Los bots usan las mismas reglas que un humano pero no kitean,
no coordinan ni usan el terreno como lo haría una persona, así que las clases a distancia y de control (mago, cazador) probablemente estén
subestimadas y las de cuerpo a cuerpo sobreestimadas respecto de jugadores reales. Sirve para detectar desbalances groseros (una clase
con 70% o 30%), no para afinar el último punto. Con 1200 partidas el margen de error al 95% es de unos +/-3 puntos.

Objetivo: ninguna clase fuera de ~42-58%. Los cambios están sólo en `data/classes.json` (el mismo archivo que usa el prototipo web).

## Cambios de números

| Clase | Antes | Después |
|---|---|---|
| Mago | vida 480, Bola de fuego 18, Pirotecnia 42 | vida 520, Bola de fuego 30, Pirotecnia 64 |
| Cazador | vida 530, Disparo 13, Disparo certero 38 | vida 600, Disparo 27, Disparo certero 64 |
| Guerrero | vida 530, Golpe 15, Golpe mortal 28 | vida 440, Golpe 11, Golpe mortal 20 |
| Sacerdote | vida 450, Sanar 72, Escudo 77, Renovar 11, Himno 125 | vida 430, Sanar 40, Escudo 42, Renovar 8, Himno 70 |
| Asesino | Puñalada 15 | Puñalada 14 |

## Antes (original, 960 partidas)

matches: 960, unfinished: 2

| Clase | Win rate | +/- (95%) | Partidas-clase |
|---|---|---|---|
| hunter | 31.6% | 3.3 | 904 |
| mage | 30.2% | 3.1 | 1029 |
| priest | 66.3% | 3.1 | 988 |
| rogue | 51.6% | 3.3 | 893 |
| warrior | 69.8% | 3.1 | 978 |

### Por modo

| Clase | mode2 | mode3 |
|---|---|---|
| hunter | 31.3% | 31.9% |
| mage | 25.8% | 32.8% |
| priest | 69.2% | 64.5% |
| rogue | 51.8% | 51.5% |
| warrior | 70.3% | 69.5% |

### Por mapa

| Clase | map_bridge | map_pillars | map_tomb | map_living |
|---|---|---|---|---|
| hunter | 35.4% | 30.8% | 26.8% | 33.6% |
| mage | 28.7% | 32.4% | 31.9% | 28.4% |
| priest | 69.4% | 65.2% | 65.4% | 65.1% |
| rogue | 49.3% | 47.9% | 53.3% | 55.7% |
| warrior | 69.5% | 69.4% | 70.1% | 70.4% |

### Parejas 2v2 (min. 15 partidas)

| Pareja | Win rate | N |
|---|---|---|
| priest+warrior | 90.3% | 72 |
| rogue+warrior | 87.8% | 90 |
| priest+priest | 78.3% | 46 |
| warrior+warrior | 78.0% | 41 |
| priest+rogue | 67.1% | 76 |
| rogue+rogue | 59.1% | 44 |
| hunter+priest | 56.3% | 71 |
| mage+priest | 52.0% | 75 |
| hunter+warrior | 49.4% | 77 |
| mage+warrior | 39.4% | 66 |
| hunter+hunter | 25.0% | 32 |
| mage+rogue | 18.9% | 74 |
| hunter+rogue | 14.3% | 70 |
| mage+mage | 13.0% | 46 |
| hunter+mage | 10.5% | 76 |


## Después (1200 partidas)

matches: 1200, unfinished: 2

| Clase | Win rate | +/- (95%) | Partidas-clase |
|---|---|---|---|
| hunter | 55.0% | 2.8 | 1211 |
| mage | 46.4% | 2.8 | 1253 |
| priest | 50.4% | 2.9 | 1141 |
| rogue | 53.3% | 2.8 | 1226 |
| warrior | 44.9% | 2.9 | 1161 |

### Por modo

| Clase | mode2 | mode3 |
|---|---|---|
| hunter | 54.0% | 55.7% |
| mage | 44.2% | 47.7% |
| priest | 47.7% | 52.2% |
| rogue | 58.2% | 50.1% |
| warrior | 45.5% | 44.4% |

### Por mapa

| Clase | map_bridge | map_pillars | map_tomb | map_living |
|---|---|---|---|---|
| hunter | 52.4% | 53.2% | 54.4% | 59.8% |
| mage | 48.8% | 45.8% | 45.4% | 45.5% |
| priest | 58.7% | 45.6% | 52.2% | 44.8% |
| rogue | 47.5% | 59.8% | 49.3% | 56.4% |
| warrior | 42.3% | 46.2% | 49.0% | 41.5% |

### Parejas 2v2 (min. 15 partidas)

| Pareja | Win rate | N |
|---|---|---|
| rogue+rogue | 63.4% | 41 |
| priest+warrior | 63.2% | 76 |
| priest+rogue | 63.0% | 108 |
| hunter+hunter | 61.3% | 62 |
| hunter+rogue | 60.9% | 110 |
| rogue+warrior | 52.5% | 99 |
| hunter+mage | 51.5% | 99 |
| hunter+warrior | 50.6% | 77 |
| mage+rogue | 49.4% | 79 |
| mage+mage | 45.1% | 51 |
| mage+priest | 41.4% | 87 |
| hunter+priest | 41.3% | 92 |
| mage+warrior | 35.5% | 110 |
| warrior+warrior | 33.3% | 54 |
| priest+priest | 31.4% | 51 |



## v0.3.1 (amortiguación, combate cuerpo a cuerpo con tolerancia, Retina)

Se quitó el círculo de magma que se cierra. Para que no haya partidas eternas hay **amortiguación** (`data/constants.json`):
desde los 40 s de pelea la curación recibida baja 2% por segundo (tope 95%), y se muestra como ícono "Amortiguación X%" en todos.
Se probaron 60 s/1%, 40 s/2% y 30 s/3%: la duración casi no cambia (la mayoría del tiempo se va en acercarse y esquivar, no en curarse),
así que se dejó 40 s/2%. Con ese valor ~75% de las partidas terminan en menos de 3 minutos de pelea; quedan 1-2% de partidas
trabadas por bots que no se alcanzan (límite de 12 minutos del simulador). Los jugadores humanos no tienen ese problema.

Ajustes de este lote: Cazador Disparo 27 -> 25, Sacerdote Castigo 11 -> 12. Los cambios de sensación del cuerpo a cuerpo (cono de 180 grados, +0,8 m de
tolerancia, +0,8 m más contra blancos que se mueven) están en el servidor y también benefician a los bots; el Asesino quedó en 50%.

matches: 960, unfinished: 18

Duración de pelea por partida (s, sin pausas): media 167, mediana 140, p90 256, máx 690; partidas > 180 s: 29%

| Clase | Win rate | +/- (95%) | Partidas-clase |
|---|---|---|---|
| hunter | 54.3% | 3.3 | 889 |
| mage | 54.6% | 3.1 | 1016 |
| priest | 43.7% | 3.2 | 963 |
| rogue | 50.5% | 3.3 | 868 |
| warrior | 47.0% | 3.1 | 970 |

### Por modo

| Clase | mode2 | mode3 |
|---|---|---|
| hunter | 56.8% | 52.7% |
| mage | 55.6% | 54.0% |
| priest | 37.6% | 47.8% |
| rogue | 54.7% | 47.0% |
| warrior | 45.7% | 47.9% |

### Por mapa

| Clase | map_bridge | map_pillars | map_tomb | map_living |
|---|---|---|---|---|
| hunter | 55.3% | 55.8% | 58.3% | 48.0% |
| mage | 57.4% | 49.8% | 56.7% | 54.4% |
| priest | 49.0% | 38.7% | 44.8% | 42.6% |
| rogue | 40.0% | 57.4% | 49.6% | 55.0% |
| warrior | 46.4% | 50.4% | 41.5% | 50.0% |

### Parejas 2v2 (min. 15 partidas)

| Pareja | Win rate | N |
|---|---|---|
| hunter+hunter | 68.8% | 32 |
| rogue+rogue | 63.6% | 44 |
| mage+warrior | 57.6% | 66 |
| hunter+rogue | 56.7% | 67 |
| hunter+mage | 56.6% | 76 |
| mage+rogue | 56.2% | 73 |
| hunter+priest | 55.1% | 69 |
| mage+mage | 54.3% | 46 |
| mage+priest | 54.1% | 74 |
| rogue+warrior | 50.6% | 89 |
| hunter+warrior | 48.7% | 76 |
| priest+rogue | 45.9% | 74 |
| priest+warrior | 44.4% | 72 |
| warrior+warrior | 29.3% | 41 |
| priest+priest | 0.0% | 47 |



## v0.4.0: especializaciones del Mago (Fuego / Escarcha) y sacerdote que acompaña al equipo

El Mago elige **Fuego** (daño explosivo: Bola de fuego con quemadura, Piroexplosión de 1,8 s, Aliento de dragón que desorienta, Lluvia de meteoros)
o **Escarcha** (control: Descarga de escarcha que ralentiza 40%, Lanza de hielo que pega x2,5 a objetivos enraizados o congelados, Nova que enraíza,
Ventisca de 5 s con daño continuo y ralentización del 60%). Los dos kits están en `data/classes.json` (`specs`), con las siete habilidades completas.
La simulación sortea la especialización de cada mago (tablas `mage-fire` y `mage-frost`).

Ajustes hasta entrar en banda (primeras pruebas: Fuego 63% / Escarcha 16%; la Escarcha necesitó más daño y una Nova con menos recarga):
Fuego: Bola 28 -> 26 de daño (quemadura 6/s x 3 s), Piroexplosión 95 -> 75. Escarcha: Descarga 28 -> 45 (lanzamiento 1,3 s), Lanza 13 -> 24 (recarga 2 s),
Nova recarga 10 s y daño 18, Ventisca 9 -> 18 por golpe. Guerrero: Golpe 11 -> 12.

El Sacerdote bot ahora se queda con el equipo (dentro de ~14 m y a la vista de un aliado), se ubica detrás de sus aliados respecto de los enemigos y,
cuando nadie necesita curación, se esconde de la línea de visión de los lanzadores enemigos detrás de pilares.

matches: 960, unfinished: 17

Duración de pelea por partida (s, sin pausas): media 153, mediana 129, p90 239, máx 690; partidas > 180 s: 24%

| Clase | Win rate | +/- (95%) | Partidas-clase |
|---|---|---|---|
| hunter | 50.3% | 3.3 | 907 |
| mage | 53.8% | 3.1 | 976 |
| mage-fire | 53.0% | 4.4 | 504 |
| mage-frost | 54.7% | 4.5 | 472 |
| priest | 48.3% | 3.2 | 967 |
| rogue | 47.2% | 3.3 | 897 |
| warrior | 50.3% | 3.1 | 969 |

### Por modo

| Clase | mode2 | mode3 |
|---|---|---|
| hunter | 52.8% | 48.6% |
| mage | 47.6% | 57.4% |
| mage-fire | 48.6% | 55.4% |
| mage-frost | 46.6% | 59.5% |
| priest | 47.5% | 48.8% |
| rogue | 53.0% | 42.7% |
| warrior | 49.1% | 51.1% |

### Por mapa

| Clase | map_bridge | map_pillars | map_tomb | map_living |
|---|---|---|---|---|
| hunter | 49.1% | 45.8% | 56.4% | 50.0% |
| mage | 54.3% | 54.4% | 53.1% | 53.3% |
| mage-fire | 52.2% | 54.4% | 50.4% | 54.8% |
| mage-frost | 56.7% | 54.4% | 56.2% | 51.6% |
| priest | 54.4% | 47.2% | 46.8% | 44.9% |
| rogue | 41.6% | 51.2% | 45.1% | 51.1% |
| warrior | 49.6% | 51.4% | 49.4% | 50.7% |

### Parejas 2v2 (min. 15 partidas)

| Pareja | Win rate | N |
|---|---|---|
| rogue+rogue | 68.9% | 45 |
| priest+warrior | 64.4% | 87 |
| priest+rogue | 62.7% | 59 |
| hunter+priest | 59.5% | 84 |
| hunter+warrior | 59.1% | 66 |
| hunter+mage | 56.5% | 85 |
| mage+priest | 52.1% | 73 |
| rogue+warrior | 48.9% | 92 |
| mage+warrior | 48.4% | 62 |
| hunter+hunter | 44.0% | 25 |
| mage+rogue | 42.9% | 77 |
| hunter+rogue | 40.6% | 69 |
| mage+mage | 35.5% | 31 |
| warrior+warrior | 29.2% | 48 |
| priest+priest | 0.0% | 39 |



### Tabla final de 0.4.0 (con límite de ronda de 3 min y bots que salen a buscar al enemigo)

Se agregó `ROUND_LIMIT_MS` (180 s en `data/constants.json`): si una ronda se estanca (alguien escondido o encerrado en un hueco del mapa),
gana el equipo con más vida restante y con vida pareja es empate sin puntos. Antes quedaban 2% de partidas trabadas en el simulador; ahora 1 de 960.
Los bots además salen a buscar al equipo enemigo si pasaron 45 s sin ver a nadie.

matches: 960, unfinished: 1

Duración de pelea por partida (s, sin pausas): media 147, mediana 133, p90 236, máx 660; partidas > 180 s: 25%

| Clase | Win rate | +/- (95%) | Partidas-clase |
|---|---|---|---|
| hunter | 52.1% | 3.2 | 919 |
| mage | 50.9% | 3.1 | 989 |
| mage-fire | 48.4% | 4.3 | 508 |
| mage-frost | 53.4% | 4.5 | 481 |
| priest | 49.2% | 3.1 | 996 |
| rogue | 46.7% | 3.2 | 919 |
| warrior | 51.1% | 3.1 | 973 |

### Por modo

| Clase | mode2 | mode3 |
|---|---|---|
| hunter | 54.6% | 50.5% |
| mage | 46.7% | 53.3% |
| mage-fire | 45.9% | 49.8% |
| mage-frost | 47.5% | 57.0% |
| priest | 45.5% | 51.6% |
| rogue | 52.5% | 42.3% |
| warrior | 50.7% | 51.3% |

### Por mapa

| Clase | map_bridge | map_pillars | map_tomb | map_living |
|---|---|---|---|---|
| hunter | 48.3% | 49.1% | 57.3% | 53.8% |
| mage | 53.3% | 46.5% | 47.8% | 55.2% |
| mage-fire | 50.4% | 41.7% | 45.4% | 54.7% |
| mage-frost | 56.5% | 50.8% | 50.5% | 55.6% |
| priest | 54.8% | 49.8% | 46.4% | 45.6% |
| rogue | 44.2% | 50.2% | 46.1% | 46.4% |
| warrior | 48.5% | 54.1% | 52.8% | 48.5% |

### Parejas 2v2 (min. 15 partidas)

| Pareja | Win rate | N |
|---|---|---|
| rogue+rogue | 64.4% | 45 |
| hunter+priest | 61.2% | 85 |
| priest+rogue | 57.6% | 66 |
| mage+warrior | 56.5% | 62 |
| hunter+rogue | 56.3% | 71 |
| priest+warrior | 56.3% | 87 |
| hunter+warrior | 55.2% | 67 |
| mage+priest | 51.9% | 77 |
| hunter+mage | 50.0% | 86 |
| rogue+warrior | 50.0% | 92 |
| hunter+hunter | 48.0% | 25 |
| mage+mage | 41.9% | 31 |
| warrior+warrior | 39.6% | 48 |
| mage+rogue | 33.8% | 77 |
| priest+priest | 0.0% | 39 |


## 0.5.0: Brujo (Aflicción) y 6 clases (1600 partidas, `tools/balance_run.sh 200`)

Primer pase con los números de la primera implementación: Brujo 68.3% (muy fuerte, los bots mantienen las maldiciones sobre varios enemigos
y lo curan con Drenar vida). Ajuste en `data/classes.json`: Descarga de sombras 34 -> 28, Corrupción 9 -> 7 por segundo, Agonía 7 -> 5,
Putrefacción del alma 16 -> 12, Drenar vida 42 -> 32. Resultado final (bots normales, sorteo uniforme entre las 6 clases y ambas especialidades del mago):

| Clase | Win rate | +/- (95%) |
|---|---|---|
| hunter | 50.0% | 2.7 |
| mage (Fuego + Escarcha) | 51.9% | 2.7 |
| mage-fire | 48.1% | 3.9 |
| mage-frost | 55.3% | 3.7 |
| priest | 52.3% | 2.7 |
| rogue | 49.3% | 2.7 |
| warlock | 48.0% | 2.7 |
| warrior | 48.5% | 2.7 |

Todas dentro de 42-58%. Un 2.7% de las rondas largas se cierra por el límite de ronda (ver arriba). El sacerdote bot ahora disipa maldiciones
(sólo si el aliado acumula 9 o más por segundo de daño de maldición), y el Brujo bot aterroriza a sacerdotes y cuerpo a cuerpo cercanos.


## 0.6.0: identidades asimétricas (1600 partidas, `tools/balance_run.sh 200`)

Pedido: que las clases varíen de verdad (el asesino pega mucho y aguanta poco, el guerrero aguanta mucho y pega poco). Se agregaron al núcleo tres números por clase o especialización, todos en `data/classes.json`: `hp` (también por especialización), `armor` (fracción del daño [físico] que no entra; no reduce magia ni efectos periódicos) y `crit` (suma al crítico base de 15%). Cada habilidad ya tenía su daño.

| Clase | Vida (antes) | Armadura | Crítico | Perfil |
|---|---|---|---|---|
| Asesino | 380 (500) | 0% | +10% | Cañón de cristal: Puñalada 17 cada 0,6 s, Evisceración 90, x1,3 desde el sigilo; la menor vida, la mayor movilidad |
| Guerrero | 640 (440) | 18% | 0 | Tanque: Golpe 8, Golpe mortal 15, Tajo 7, Torbellino 9; el control fuerte (Carga, Tajo, Golpe de escudo) |
| Mago Fuego | 440 (520) | 0% | 0 | Mucha explosión (Bola 32, Piroexplosión 110), segunda vida más baja; vive de Traslación y control |
| Mago Escarcha | 480 (520) | 0% | 0 | Menos daño (Rayo 45, Lanza 22) y el mejor control (ralentiza, congela, ventisca) |
| Cazador | 560 (600) | 0% | 0 | Daño sostenido a distancia (Disparo 28, Certero 64) |
| Sacerdote | 480 (430) | 0% | 0 | Poco daño, mucha curación, buenas defensivas |
| Brujo | 570 (540) | 0% | 0 | Desgaste: maldiciones y Drenar vida; el más lento |

Primeras pasadas (sólo para ver el efecto): con el asesino a 150 de Evisceración llegó a 72% y el cazador cayó a 35%; se bajó el daño del asesino y del guerrero y se subió el del cazador y de Escarcha hasta lo siguiente.

Tasas de victoria finales (bots normales, sorteo uniforme, ambos magos):

| Clase | Win rate | +/- (95%) |
|---|---|---|
| hunter | 48.8% | 2.7 |
| mage (Fuego + Escarcha) | 46.0% | 2.7 |
| mage-fire | 45.2% | 3.9 |
| mage-frost | 46.8% | 3.7 |
| priest | 46.8% | 2.7 |
| rogue | 53.9% | 2.7 |
| warlock | 50.1% | 2.7 |
| warrior | 54.5% | 2.7 |

Todas dentro de 42-58%. (Las tasas por modo y por mapa salen de `tools/balance_run.sh`.)

### Matriz 1v1 (fila le gana a columna)

Duelos entre bots (`tools/duel_run.sh 3`: 12 duelos por par, al mejor de 3 rondas; mucho ruido, sirve para ver las tendencias). Los emparejamientos asimétricos son esperables:

| fila vs columna | hunter | mage-fire | mage-frost | priest | rogue | warlock | warrior |
|---|---|---|---|---|---|---|---|
| hunter | 33% | 75% | 100% | 100% | 58% | 8% | 75% |
| mage-fire | 50% | 42% | 100% | 92% | 0% | 33% | 58% |
| mage-frost | 8% | 17% | 58% | 92% | 17% | 42% | 33% |
| priest | 0% | 0% | 8% | 64% | 0% | 0% | 0% |
| rogue | 42% | 92% | 83% | 100% | 42% | 83% | 92% |
| warlock | 92% | 67% | 58% | 100% | 0% | 67% | 42% |
| warrior | 25% | 58% | 83% | 100% | 17% | 50% | 58% |

Tiempo medio hasta la primera baja (s), fila contra columna:

| fila vs columna | hunter | mage-fire | mage-frost | priest | rogue | warlock | warrior |
|---|---|---|---|---|---|---|---|
| hunter | 41.9 | 29.9 | 30.2 | 100.1 | 20.3 | 32.6 | 40.2 |
| mage-fire | 33.5 | 28.2 | 29.5 | 80.9 | 15.9 | 26.0 | 31.9 |
| mage-frost | 35.4 | 29.9 | 32.2 | 91.1 | 14.6 | 28.0 | 37.1 |
| priest | 92.9 | 73.5 | 96.2 | 39.5 | 32.4 | 103.8 | 92.1 |
| rogue | 23.6 | 15.8 | 17.9 | 34.8 | 13.3 | 22.2 | 27.0 |
| warlock | 36.3 | 28.0 | 27.5 | 100.2 | 23.2 | 36.8 | 47.8 |
| warrior | 45.5 | 34.2 | 62.4 | 89.4 | 25.1 | 48.5 | 60.9 |


Lectura (con la salvedad de que los bots no usan el desenganche ni huyen): el asesino domina los duelos 1v1 (75% al Mago Fuego, 92% a Escarcha, 100% al Brujo y al Guerrero) y sólo pierde contra el Cazador (33%) porque éste lo ve venir y lo ralentiza; en equipo, donde no puede elegir presa, queda en 54%. El Guerrero tarda mucho en caer (columna con los tiempos más largos, 27-48 s hasta la primera baja) pero tampoco mata rápido, y le gana a Escarcha y al Brujo (67%) pero pierde contra el asesino (17%). El Brujo les gana a los magos y al Cazador pero no al asesino (0%). El Cazador le gana a Escarcha y al Guerrero y pierde contra el Brujo. El Sacerdote pierde todos los duelos 1v1 (no tiene daño: está hecho para el 2v2 y el 3v3). En la tabla de tiempos, la columna del asesino es la más corta: es el que cae primero (14-23 s contra 28-47 s de los demás). El tiempo incluye el cruce desde las salas de inicio (unos 5 s), por eso no refleja el "4 a 6 s" de una trabada ya encima del objetivo: con la rotación completa sin crítico (Impacto desde sigilo, Evisceración y Puñaladas) el asesino mata a un Mago de Fuego en unos 9 s en la prueba de `tests/test_classes.gd`; con críticos y el aturdimiento, menos.

## 2026-11-02: línea base 1v1 con métricas de límite de tiempo, empates y duelos sin terminar

Estado del código: `balance/duel-metrics`. Ahora el simulador cuenta los duelos sin terminar (antes se descartaban en silencio), no suma 0 s al
tiempo hasta la primera baja cuando no hubo ninguna, usa sólo clases jugables (`GameData.playable_ids()`, sin las deshabilitadas) e incluye
el mapa `spire`. `ArenaMatch` suma contadores de telemetría (`limit_rounds`, `draw_rounds`, `limit_decided`, `limit_hi_hp_wins`) sin cambiar
ninguna regla. Las tablas de arriba están desactualizadas respecto de esto: se midieron con otro conjunto de clases, sin `spire`, y la
sección de números lista al guerrero con vida 440 cuando `data/classes.json` tiene 620 (vidas actuales: guerrero 620, brujo 570, cazador 560,
sacerdote 480, mago Fuego 440 / Escarcha 480, asesino 380).

Comandos (5 procesos en paralelo, uno por mapa: bridge, pillars, tomb, living, spire):

```
tools/duel_run.sh 20 baseline              # normal: N=20 por par ordenado y mapa = 100 duelos por par ordenado, 4900 en total
tools/duel_run.sh 10 baseline_hard hard    # difícil: N=10 (reducido por tiempo) = 2450 duelos
```

N=20 tardó unos 10,5 min de reloj (633 s), corrido a la vez que la corrida difícil; ésa tardó 283 s con N=10. Los bots usan las mismas
reglas que un humano, así que valen las salvedades de arriba. Largo medio = segundos de pelea sin prep ni pausas, sólo duelos terminados.
La columna "gana más HP máx" cuenta, entre las rondas cortadas por el límite de 180 s con ganador y vida máxima total distinta, cuántas ganó
el equipo de mayor vida máxima.

### Normal, N=20

| fila vs columna | hunter | mage-fire | mage-frost | priest | rogue | warlock | warrior |
|---|---|---|---|---|---|---|---|
| hunter | 55% | 54% | 98% | 100% | 78% | 27% | 64% |
| mage-fire | 52% | 45% | 97% | 100% | 20% | 39% | 48% |
| mage-frost | 1% | 2% | 44% | 92% | 4% | 1% | 4% |
| priest | 0% | 0% | 5% | 51% | 0% | 0% | 0% |
| rogue | 22% | 80% | 92% | 100% | 47% | 99% | 23% |
| warlock | 84% | 66% | 96% | 100% | 2% | 51% | 10% |
| warrior | 34% | 42% | 96% | 100% | 73% | 93% | 48% |

Total: 4900 duelos, 0 sin terminar, 11132 rondas, 2.6% al límite, 0 empates, largo medio 107 s; límite decidido a favor de más HP máx: 53/63

Win rate global por variante (sin espejo):

| variante | win rate | duelos |
|---|---|---|
| hunter | 69.0% | 1200 |
| mage-fire | 59.3% | 1200 |
| mage-frost | 18.3% | 1200 |
| priest | 1.1% | 1200 |
| rogue | 69.9% | 1200 |
| warlock | 58.2% | 1200 |
| warrior | 74.1% | 1200 |

Parejas con más rondas al límite (el resto tuvo 0 o 1 ronda al límite; la tabla completa sale del comando):

| pareja | duelos | sin terminar | rondas | rondas al límite | empates | largo medio (s) | límite: gana más HP máx |
|---|---|---|---|---|---|---|---|
| hunter vs rogue | 200 | 0 | 472 | 2% (9) | 0 | 49 | 100% (9/9) |
| mage-fire vs rogue | 200 | 0 | 488 | 2% (8) | 0 | 56 | 88% (7/8) |
| mage-fire vs warrior | 200 | 0 | 513 | 4% (22) | 0 | 118 | 95% (21/22) |
| mage-frost vs priest | 200 | 0 | 436 | 3% (13) | 0 | 243 | - |
| mage-frost vs warrior | 200 | 0 | 438 | 3% (14) | 0 | 113 | 57% (8/14) |
| priest vs priest | 100 | 0 | 250 | 84% (209) | 0 | 433 | - |

### Difícil, N=10

| fila vs columna | hunter | mage-fire | mage-frost | priest | rogue | warlock | warrior |
|---|---|---|---|---|---|---|---|
| hunter | 60% | 96% | 100% | 100% | 100% | 100% | 100% |
| mage-fire | 0% | 40% | 100% | 100% | 48% | 98% | 98% |
| mage-frost | 0% | 0% | 58% | 100% | 8% | 42% | 30% |
| priest | 0% | 0% | 0% | 42% | 0% | 0% | 0% |
| rogue | 0% | 50% | 82% | 100% | 42% | 100% | 14% |
| warlock | 0% | 0% | 52% | 100% | 0% | 58% | 10% |
| warrior | 0% | 2% | 70% | 100% | 90% | 90% | 60% |

Total: 2450 duelos, 0 sin terminar, 5342 rondas, 1.5% al límite, 0 empates, largo medio 65 s; límite decidido a favor de más HP máx: 16/25

| variante | win rate | duelos |
|---|---|---|
| hunter | 99.7% | 600 |
| mage-fire | 74.7% | 600 |
| mage-frost | 31.3% | 600 |
| priest | 0.0% | 600 |
| rogue | 58.3% | 600 |
| warlock | 27.7% | 600 |
| warrior | 58.3% | 600 |

| pareja | duelos | sin terminar | rondas | rondas al límite | empates | largo medio (s) | límite: gana más HP máx |
|---|---|---|---|---|---|---|---|
| hunter vs rogue | 100 | 0 | 200 | 0% (1) | 0 | 14 | 100% (1/1) |
| mage-fire vs rogue | 100 | 0 | 242 | 1% (3) | 0 | 41 | 67% (2/3) |
| mage-fire vs warrior | 100 | 0 | 211 | 4% (9) | 0 | 66 | 78% (7/9) |
| mage-frost vs priest | 100 | 0 | 200 | 0% (0) | 0 | 72 | - |
| mage-frost vs warrior | 100 | 0 | 249 | 4% (10) | 0 | 114 | 40% (4/10) |
| priest vs priest | 50 | 0 | 127 | 42% (53) | 0 | 392 | - |

### Disparadores revisados (sin tocar balance)

| Disparador | Resultado | ¿Dispara? |
|---|---|---|
| Pareja con >15% de rondas al límite o partida media >6 min | Normal: sacerdote vs sacerdote 84% al límite (209/250 rondas), 433 s de media. Difícil: 42% (53/127), 392 s. Ninguna otra pareja pasa de 4% ni de 243 s (Escarcha vs sacerdote). | Sí, sólo el espejo del sacerdote |
| El de mayor vida máxima gana >60% de las decisiones al límite | Normal 53/63 (84%); difícil 16/25 (64%). Salen sobre todo de Fuego vs guerrero (21/22, 7/9) y Fuego vs asesino. Escarcha vs guerrero está en 57% (8/14) y 40% (4/10). | Sí (ojo: el que gana el límite es por definición el de más vida *restante*; mide correlación con la vida máxima, no causa) |
| Bucle de rondas empatadas | 0 empates y 0 duelos sin terminar en ambas corridas (7350 duelos) | No |
| Clase fuera de 35-65% global | Normal: guerrero 74,1%, asesino 69,9%, cazador 69,0% por arriba; Escarcha 18,3% y sacerdote 1,1% por abajo. Difícil: cazador 99,7%, Fuego 74,7%, Escarcha 31,3%, brujo 27,7%, sacerdote 0,0%. | Sí (ver tablas; el sacerdote pierde casi todos los duelos 1v1 en ambas dificultades) |

Límites de la medición: el win rate global por variante promedia sobre las otras 6 variantes con peso igual, no sobre un mix de partidas real;
la columna de límite tiene muestras chicas en la mayoría de las parejas (ver los conteos entre paréntesis); cada celda de la matriz tiene 100 duelos en normal
(unos +/-10 puntos al 95%) y 50 en difícil (unos +/-14). Estos datos son de bots: no se debería decidir balance del
modo 1v1 sólo con ellos.


## 2026-11-02: calibración del torneo con un bot como jugador

`tools/tournament_run.sh [partidas_por_celda] [skill_del_jugador] [semilla]` juega las partidas guionadas reales de `Tournament.next_match`
(rival con el `skill`, vida y daño del nivel; aliados y rivales de `data/tournament.json`) con un bot en tu lugar y cuenta sus victorias por
modalidad, nivel y ronda (cuartos, semifinal, final). Un proceso por nivel, 4 en paralelo. La clase del jugador rota entre las 6 jugables.
"Copa estimada" es el producto de las tres rondas, contando la revancha gratis de Bronce y Plata sobre la ronda más floja.
"Partida media" va desde que empieza hasta que termina la última ronda (sin los 7 s de la pantalla final) y "pelea media" cuenta solo el tiempo en `fight`.

**Salvedad:** un bot no es una persona (no kitea, no coordina, no usa el terreno). Con `skill` 0,55 es un jugador flojo y con 0,85 uno fuerte, pero ninguno
dice cuánto va a ganar alguien real: los porcentajes sirven para comparar niveles, rondas y modalidades entre sí. Con `N=12` el margen de error es de hasta +/-28 puntos por
celda y con `N=20`, +/-22. Los 1v1 salen más bajos de lo esperable porque la rotación incluye al sacerdote, que contra bots pierde casi todos los duelos 1v1 (ver arriba).
Las medidas no cambian nada de lo que `docs/balance.md` dice del balance de clases, y no se tocó `data/classes.json`.

### Antes de ajustar: jugador con skill 0,55, N=20 por celda (720 partidas, semilla 1, 4:46 min)

| modalidad | nivel | cuartos | semifinal | final | copa estimada | partida media (s) | pelea media (s) | sin terminar |
|---|---|---|---|---|---|---|---|---|
| 1v1 | bronze | 80% | 65% | 55% | 41% | 162 | 134 | 0 |
| 1v1 | silver | 60% | 60% | 55% | 29% | 138 | 109 | 0 |
| 1v1 | gold | 45% | 10% | 0% | 0% | 95 | 69 | 0 |
| 1v1 | gladiator | 5% | 30% | 10% | 0% | 91 | 64 | 0 |
| 2v2 | bronze | 65% | 80% | 100% | 70% | 221 | 195 | 0 |
| 2v2 | silver | 70% | 35% | 70% | 28% | 257 | 228 | 0 |
| 2v2 | gold | 5% | 30% | 0% | 0% | 141 | 115 | 0 |
| 2v2 | gladiator | 5% | 5% | 0% | 0% | 119 | 92 | 0 |
| 3v3 | bronze | 90% | 85% | 80% | 73% | 207 | 179 | 0 |
| 3v3 | silver | 90% | 85% | 55% | 61% | 160 | 132 | 0 |
| 3v3 | gold | 25% | 25% | 30% | 2% | 134 | 106 | 0 |
| 3v3 | gladiator | 0% | 15% | 0% | 0% | 99 | 74 | 0 |

### Antes de ajustar: jugador con skill 0,85, N=12 por celda (432 partidas, semilla 2, 2:34 min)

| modalidad | nivel | cuartos | semifinal | final | copa estimada | partida media (s) | pelea media (s) | sin terminar |
|---|---|---|---|---|---|---|---|---|
| 1v1 | bronze | 75% | 67% | 50% | 38% | 122 | 95 | 0 |
| 1v1 | silver | 75% | 83% | 58% | 52% | 129 | 103 | 0 |
| 1v1 | gold | 42% | 25% | 0% | 0% | 87 | 59 | 0 |
| 1v1 | gladiator | 33% | 8% | 17% | 0% | 70 | 45 | 0 |
| 2v2 | bronze | 92% | 75% | 100% | 86% | 199 | 172 | 0 |
| 2v2 | silver | 75% | 75% | 92% | 64% | 210 | 181 | 0 |
| 2v2 | gold | 8% | 58% | 0% | 0% | 118 | 93 | 0 |
| 2v2 | gladiator | 17% | 17% | 17% | 0% | 119 | 94 | 0 |
| 3v3 | bronze | 100% | 100% | 92% | 99% | 168 | 143 | 0 |
| 3v3 | silver | 83% | 75% | 75% | 59% | 155 | 127 | 0 |
| 3v3 | gold | 42% | 42% | 50% | 9% | 117 | 90 | 0 |
| 3v3 | gladiator | 8% | 17% | 8% | 0% | 107 | 80 | 0 |

### Lo que se vio y lo que se cambió

| Observación | Dato | Cambio |
|---|---|---|
| Final de Oro 1v1 imposible | 0/20 y 0/12 (skill 0,85 y 0,55) contra el jefe, y 0/20 en una repetición dedicada (skill 0,85, semilla 3). El jefe era un cazador (en la tabla de duelos en difícil gana 96-100% a las demás clases salvo el espejo). | Jefe de Oro 1v1 (Rey Ceniza): cazador a guerrero. Repetición dedicada, mismas semillas y N=20: final 0/20 a 8/20; cuartos 7/20 a 9/20 y semifinal 10/20 a 11/20 (sin cambios fuera del ruido). |
| Final de Oro 2v2 casi imposible | 0/20 y 0/12 en las dos corridas generales, y 1/15 en la repetición dedicada (skill 0,85, semilla 3) con Los Imbatibles (mago + guerrero). | Probado con sacerdote + guerrero: final 11/15 (demasiado fácil, más que las rondas previas con 4/15). Probado con asesino + guerrero: final 6/15 (cuartos 4/15, semifinal 5/15). Se deja asesino + guerrero. |

El resto de `data/tournament.json` no se tocó: Oro y Gladiador son claramente más duros que Bronce y Plata en las tres modalidades; Bronce y Plata quedan parecidos entre sí con estos N (la copa estimada de Plata 1v1 incluso sale más alta que la de Bronce en una de las corridas, dentro del margen), y no hay partidas sin terminar en ninguna celda.
Gladiador queda muy por encima de lo que un bot logra (0-33% por ronda, copa estimada 0%); es opcional y con un bot de skill 0,85 no se lo puede juzgar, así que no se ajustó.

### Después de ajustar: jugador con skill 0,85, N=12 por celda (432 partidas, semilla 4, 2:30 min)

| modalidad | nivel | cuartos | semifinal | final | copa estimada | partida media (s) | pelea media (s) | sin terminar |
|---|---|---|---|---|---|---|---|---|
| 1v1 | bronze | 67% | 83% | 50% | 42% | 126 | 100 | 0 |
| 1v1 | silver | 75% | 67% | 83% | 56% | 121 | 95 | 0 |
| 1v1 | gold | 33% | 50% | 50% | 8% | 104 | 78 | 0 |
| 1v1 | gladiator | 17% | 8% | 17% | 0% | 77 | 52 | 0 |
| 2v2 | bronze | 100% | 83% | 100% | 97% | 192 | 165 | 0 |
| 2v2 | silver | 100% | 83% | 67% | 74% | 217 | 189 | 0 |
| 2v2 | gold | 33% | 25% | 50% | 4% | 128 | 102 | 0 |
| 2v2 | gladiator | 8% | 0% | 17% | 0% | 104 | 79 | 0 |
| 3v3 | bronze | 92% | 100% | 92% | 91% | 182 | 156 | 0 |
| 3v3 | silver | 83% | 100% | 67% | 74% | 147 | 122 | 0 |
| 3v3 | gold | 42% | 33% | 50% | 7% | 125 | 97 | 0 |
| 3v3 | gladiator | 0% | 17% | 0% | 0% | 103 | 76 | 0 |

Con el ajuste las finales de Oro quedan en 50% en las tres modalidades (antes 0%, 0% y 50%/30%), parejas con las rondas previas (25-50%).

### Lo que no sale de estas medidas

- Las victorias por partida que supone el plan (90/70/60/40%) son de personas: aquí un bot fuerte (skill 0,85) saca entre 38% y 99% de copa estimada en Bronce y entre 0% y 9% en Oro, y no hay forma de saber cuánto
  se parece a un jugador real hasta la prueba con personas del plan.
- Duración: las partidas simuladas duran 70-257 s de pelea y pausas (sin los 7 s finales), contra los 216 s (3,6 min) que supone el plan para las estimaciones de las 2 horas.
  Un humano que kitea o se frustra puede tardar más; los 1v1 contra Bronce y Plata salieron de 121 a 162 s y los 2v2 de 192 a 257 s.
- Tampoco se midió el efecto de la baja de `skill` por derrotas seguidas (0,05 hasta el piso), porque el simulador no juega rachas.

## 2026-11-02: el bot sacerdote en duelo (sin aliados vivos) y el desempate por % de vida

Estado del código: `balance/priest-bot`. No cambia ningún número de clase (`data/classes.json` y `data/powers.json` intactos), solo `core/bot_brain.gd`.

### Por qué perdía el sacerdote (medido, no supuesto)

Mediciones con scripts descartables sobre duelos del sacerdote (bots normales) contra cada clase:

| Hecho | Dato |
|---|---|
| Todo lo que lanza (Castigo, escudo, renovar, sanación) comparte el enfriamiento global de 1,5 s (`GCD_MS`); Castigo tiene 0,8 s de enfriamiento propio, así que el tope real es un Castigo cada 1,5 s | Castigo hace 22 de daño: como mucho unos 14,7 de daño por segundo |
| El bot curaba antes de pegar: con un solo sacerdote, su único "aliado" es él mismo, y escudo (<60%), renovar (<85%) y sanación (<70%) tomaban el turno antes que Castigo | Contra el guerrero, en 6 peleas de 60 s: 88 Castigos, 41 renovar, 20 escudos, 10 sanaciones, 14 alaridos y 4 himnos (casi la mitad del enfriamiento global fue a curarse) |
| Castigo además tenía una tirada al azar por pensamiento (`0.35 + skill*0.65`) incluso con el turno libre | Con el enfriamiento global libre, un 24% del tiempo no lanzaba nada |
| Sólo una parte del daño llega | Contra el guerrero, 8,3 de daño por Castigo en vez de 22 (el guerrero tiene bloqueo frontal y los bots normales apuntan con ruido; no se separó cuánto es cada cosa); el rival termina con 62-75% de vida cuando muere el sacerdote |
| Aun con todas las defensas apagadas (umbrales en 0; 12 peleas por rival, primera ronda) el sacerdote no gana ni una al guerrero, al cazador, al brujo ni al asesino (5 de 12 al Escarcha) | Con ~14,7 de daño por segundo tope y ~38% de aciertos, no le alcanza: es un problema de números de la clase, no del bot |

Así que el bot se puede mejorar un poco (más Castigos, curarse más tarde), pero no arreglar: con los números actuales el sacerdote no puede ganar a casi nadie en 1v1.

### Cambio

Con aliados vivos nada cambia (mismos umbrales y mismas tiradas). Si el sacerdote no tiene aliados vivos: lanza Castigo cada vez que el enfriamiento global lo deja (sin tirada al azar) y los umbrales para curarse bajan: escudo 60% a 45%, renovar 85% a 55%, sanación 70% a 50% (45% a 30% con un cuerpo a cuerpo encima). El druida no cambia. Pruebas en `tests/test_priest_bot.gd`; el equipo queda cubierto por `test_team_priest_still_shields_the_hurt_ally_like_before` y el druida solo por `test_lone_druid_keeps_its_healer_thresholds`.

### Comandos y resultados

```
tools/duel_run.sh 20 priest_after              # normal, N=20 (mismo N que la línea base): 9 min 25 s
tools/duel_run.sh 10 priest_after_hard hard    # difícil, N=10 (mismo que la línea base): 3 min 3 s
tools/duel_run.sh 10 pct_normal                # normal, N=10, repetición con los contadores de % de vida: 4 min 15 s
```

"Antes" son las cifras de la sección de línea base de arriba (mismo comando, código anterior). Los bots usan números al azar sin semilla, así que dos corridas del mismo comando no dan lo mismo: entre la corrida N=20 y la repetición N=10 el espejo pasó de 46% a 61% al límite.

| Sacerdote (fila, win rate) | contra Escarcha | contra Fuego | contra cazador, asesino, brujo y guerrero | espejo | global sin espejo |
|---|---|---|---|---|---|
| Normal N=20, antes | 5% | 0% | 0% | 51% | 1,1% |
| Normal N=20, después | 14% | 0% | 0% | 50% | 2,6% |
| Normal N=10, repetición | 2% | 0% | 0% | 51% | 1,5% |
| Difícil N=10, antes | 0% | 0% | 0% | 42% | 0,0% |
| Difícil N=10, después | 0% | 0% | 0% | 56% | 0,0% |

Espejo del sacerdote (sacerdote vs sacerdote), la pareja que llegaba al límite casi siempre:

| corrida | rondas al límite | largo medio (s) |
|---|---|---|
| Normal N=20, antes | 84% (209/250) | 433 |
| Normal N=20, después | 46% (118/256) | 410 |
| Normal N=10, repetición | 61% (71/117), 1 duelo sin terminar | 378 |
| Difícil N=10, antes | 42% (53/127) | 392 |
| Difícil N=10, después | 12% (15/128) | 331 |

Conclusión: el sacerdote sigue en 0% contra todo salvo el espejo y, con suerte, Escarcha; en normal pasó de 1,1% a 2,6% y de 1,5% en la repetición (dentro del ruido: celdas de 100 duelos, unos +/-10 puntos), y en difícil sigue en 0,0%. Lo que sí se movió fue el espejo, que termina antes (menos rondas al límite en ambas dificultades), aunque sigue largo. Con N=20 los demás win rates globales variaron 2-4 puntos (hunter 69,0% a 71,7%, guerrero 74,1% a 72,9%): ruido de corrida más que efecto. Para que el sacerdote sea competitivo en 1v1 hay que tocar los números de la clase, no el bot.

### Rondas al límite: ¿y un desempate por % de vida?

No se cambió la regla (`core/arena_match.gd`: gana quien tenga más vida absoluta restante). Se agregaron contadores de telemetría (`limit_pct_decided`, `limit_pct_differs`, `limit_pct_ties`): entre las rondas al límite con ganador por vida absoluta, cuántas decidiría distinto una regla de "vida restante de los vivos / vida máxima del equipo". Los simuladores de equipos y de duelos los imprimen.

```
tools/balance_run.sh 100 pct_team100    # 2v2 y 3v3, 1000 partidas (500 por modo), 4 min 29 s
```

| modo | rondas | al límite | con ganador por vida absoluta | el % de vida daría otro ganador | empate por % |
|---|---|---|---|---|---|
| 2v2 | 1189 | 2,0% (24) | 24 | 0 | 0 |
| 3v3 | 1173 | 1,6% (19) | 19 | 0 | 0 |
| 1v1 normal N=10 (2450 duelos) | 5515 | 1,9% | 103 | 3 | 0 |
| 1v1 difícil N=10 (2450 duelos, corrida después) | 5371 | 0,9% | 47 | 4 | 0 |

En total 193 rondas al límite con ganador, 7 distintas (3,6%): 0 de 43 en equipos y 7 de 150 en 1v1 (4,7%). Las rondas al límite son raras (menos de 2%) salvo el espejo del sacerdote, donde ambos tienen la misma vida máxima y el % de vida y la vida absoluta coinciden.

Recomendación: no cambiar la regla. Casi nunca decide distinto (0 en equipos, 5% en 1v1 sobre un evento que ya es del 1-2% de las rondas), no arregla el espejo del sacerdote (misma vida máxima) y agregaría una regla más. Si se quisiera premiar a las clases de poca vida, lo que cuenta es el sacerdote mismo, y eso sale por la vía de los números de la clase.

## Medición tras los kits de 4 poderes (2026-11-03)

Las tablas anteriores de este documento son de antes de pasar a kits de 4 poderes y ya no describen el juego. Medido con bots: sirve para detectar extremos, no para decidir números finales sin una prueba con personas.

**Duelos 1v1 (dificultad normal, 4.900 duelos):** 0,9% de rondas al límite y 1 empate.

| Variante | Victorias |
|---|---|
| Guerrero | 92,6% |
| Pícaro | 82,7% |
| Brujo | 68,6% |
| Mago de fuego | 43,1% |
| Sacerdote | 23,0% |
| Mago de escarcha | 21,4% |
| Cazador | 18,7% |

**Torneo (`tools/tournament_run.sh 20 0.55 1`, margen de hasta ±22 puntos por celda):** Gladiador queda en 0% en todas las modalidades, y Oro entre 0% y 5% de copa estimada para este jugador simulado.

**Cambio de datos:** dos jefes de Bronce eran casi imposibles porque el guerrero domina con estos kits (final de 1v1 en 20%, final de 3v3 en 30%). Brasa Joven pasa de guerrero a mago, y en la Cofradía Roja de 3v3 el guerrero pasa a cazador.

| Bronce (N=40, semilla 5) | Cuartos | Semifinal | Final |
|---|---|---|---|
| 1v1 | 28/40 | 25/40 | 36/40 |
| 3v3 | 39/40 | 36/40 | 39/40 |

Plata, Oro y Gladiador no se tocaron.
