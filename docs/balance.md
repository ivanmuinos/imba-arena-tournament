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
