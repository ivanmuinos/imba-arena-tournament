# Imba Arena: progresión, talentos y sinergias

Propuesta de diseño · 3 de noviembre de 2026 · Estado: en revisión

> **Talentos apagados (9 de noviembre de 2026).** Están desactivados en todas las clases hasta revisarlos: no cambian ningún kit, los bots no los eligen y el menú no los muestra. Los datos, el código y lo que cada jugador ya eligió se conservan; se vuelven a prender con `Talents.enabled` en `core/talents.gd`.

Propuesta para sumar a las 6 clases (kits de 4 poderes) una progresión permanente de cuenta, ramas de talentos y sinergias entre clases, sin romper el ranked. Es un diseño para revisar con Ivan antes de programar.

## Progresión de cuenta

Cada campeón tiene su propio nivel, del 1 al 20. Subir de nivel desbloquea talentos y rangos de habilidad. Las habilidades se hacen más fuertes, pero con un techo de +10% para que un veterano no aplaste a un jugador nuevo.

| Concepto | Propuesta |
| --- | --- |
| XP por partida | Ganar 100 · perder 40 · +1 por cada 10 de daño o curación (máximo +60) · primera victoria del día ×2 |
| Nivel del campeón | 1 a 20, por clase (maestría). La curva sube: unas 4 partidas por nivel al principio y 12 hacia el final |
| Rangos de habilidad | Cada uno de los 4 poderes tiene rangos 1 a 5. Un rango se gana cada 2 niveles y se elige qué poder subir |
| Efecto de un rango | +2% al número principal del poder: daño, curación, absorción o duración del control |
| Techo | 5 rangos × 2% = +10% por poder, el máximo |
| Talentos | Fila 1 en nivel 5, fila 2 en nivel 10, fila 3 en nivel 15 y fila 4 en nivel 20 |

La definitiva y el ataque básico no suben de rango: así el techo de poder queda acotado y más fácil de balancear.

Pregunta abierta: ¿la XP se gana también en práctica y contra bots? La propuesta es que sí, pero a la mitad.

## Ramas de talentos

Cada clase tiene 4 filas de talentos. En cada fila se elige 1 de 3 opciones, y se puede cambiar fuera de partida. Usamos filas con elección y no un árbol de puntos porque son más fáciles de balancear y de entender.

Cada fila toca una parte del kit:

1. Fila 1 (nivel 5): el ataque básico.
2. Fila 2 (nivel 10): el poder de daño.
3. Fila 3 (nivel 15): el poder de control.
4. Fila 4 (nivel 20): la definitiva o una sinergia.

Algunas opciones cambian un poder por uno de la reserva (las habilidades que salieron del kit). Así vuelven a ser jugables sin sumar botones.

| Clase | Fila 1 · básico | Fila 2 · daño | Fila 3 · control | Fila 4 · definitiva o sinergia |
| --- | --- | --- | --- | --- |
| Mago Fuego | Bola de fuego quema 50% más · rebota al 50% en un 2.º enemigo · cada 3.ª es crítica | Piroexplosión instantánea tras 2 críticos · ignora la 1.ª interrupción por daño · cambiar por **Contrahechizo** | Polimorfia instantánea cada 30 s · Aliento de dragón empuja 4 m · cambiar Aliento por **Traslación** | Meteoros deja el suelo ardiendo 4 s · la definitiva carga 25% más rápido · *sinergia con sacerdote* |
| Mago Escarcha | Descarga ralentiza 60% · se lanza 0,3 s más rápido · congela 1 s al 3.er golpe seguido | Lanza de hielo con 2 cargas · astillado ×3 en vez de ×2,5 · rebota en un 2.º enemigo | Nova recarga 4 s antes · cambiar Polimorfia por **Traslación** · cambiar Nova por **Contrahechizo** | Ventisca 30% más grande · congela 1 s al terminar · *sinergia con guerrero, asesino o cazador* |
| Brujo | Descarga instantánea si el objetivo tiene 2 maldiciones · cura 20% de su daño · deja una marca de +10% de daño de maldiciones | Corrupción salta a un enemigo cercano al terminar · Drenar vida cura 30% más · cambiar Drenar vida por **Agonía** | Miedo instantáneo con 25 s de recarga · Miedo dura 1 s más · cambiar Miedo por **Pacto oscuro** | Putrefacción dura 3 s más · se contagia a los maldecidos cercanos · *sinergia con cazador* |
| Cazador | Disparo ralentiza 10% (se acumula hasta 3) · 15% más rápido estando quieto · cada 5.º atraviesa | Disparo apuntado se lanza moviéndote · crítico contra ralentizados · cambiar por **Disparo silenciador** | 2 trampas a la vez · Conmoción ralentiza 70% · cambiar Conmoción por **Retirada** | Andanada de 13 flechas · las flechas queman 3 s · *sinergia con guerrero* |
| Guerrero | Golpe +20% contra ralentizados · Golpe carga 50% más la definitiva · bloquea 10% más | Golpe mortal reduce la curación 70% · se reinicia al matar · cambiar por **Zurrar** | Carga con 2 usos · Seccionar enraíza 1 s · cambiar Seccionar por **Muro de escudo** | Filotormenta dura 2 s más · cura 20% de su daño · *sinergia con sacerdote* |
| Asesino | Puñalada envenena 3 por segundo · 20% más rápida por la espalda · +5% de crítico | Eviscerar +30% por la espalda · reinicia Golpe bajo al matar · cambiar por **Patada** | Ceguera dura 1 s más · Golpe bajo dura 0,5 s más · cambiar Ceguera por **Desvanecer** | Marca de muerte +50% de daño recibido · se reinicia al matar · *sinergia con mago* |
| Sacerdote | Castigo cura al aliado más herido el 50% de su daño · Castigo +20% · Castigo baja 1 s la recarga del Escudo | Sanación 0,5 s más rápida · deja una curación de 6 s · cambiar Escudo divino por **Renovar** | Alarido llega 2 m más lejos · Alarido recarga 5 s antes · cambiar Alarido por **Disipar** | Himno también escuda 30 · Himno cura 30% más · *sinergia con mago o guerrero* |

Las opciones en cursiva son talentos de sinergia; están detallados en la sección siguiente. Los números son de partida: los fija la simulación de balance.

## Sinergias

Hay tres capas. Los bonus de equipo se activan solos al armar el equipo. Los combos premian coordinarse en la pelea. Los talentos de sinergia los elige cada jugador en la fila 4.

### Bonus pasivo de equipo

Se activa cuando las dos clases están en el mismo equipo, y se muestra en la selección de campeones. No todas las parejas tienen bonus: así la elección de equipo importa. Cada bonus vale entre 5% y 10%.

| Pareja | Bonus de equipo |
| --- | --- |
| Sacerdote + Mago | El Escudo divino sobre el mago evita que le interrumpan el lanzamiento mientras dure |
| Sacerdote + Guerrero | Las curas del sacerdote sobre el guerrero curan 10% más |
| Sacerdote + Asesino | El asesino recibe 5% de vida al usar Golpe bajo cerca del sacerdote |
| Mago + Asesino | Los objetivos congelados o en Polimorfia reciben 10% más de daño físico |
| Mago + Guerrero | La Carga sobre un objetivo ralentizado por el mago aturde 0,5 s más |
| Brujo + Cazador | Los enemigos aterrorizados que pisan una trampa quedan congelados 50% más |
| Brujo + Sacerdote | Las maldiciones curan al sacerdote un 10% de su daño |
| Cazador + Guerrero | El Disparo de conmoción también deja al objetivo con −10% de armadura |

### Combos entre habilidades

Funcionan siempre, estén o no las dos clases en el bonus de equipo. Se enseñan en el tutorial y en la descripción de cada poder.

- **Nova de escarcha → golpe físico de un aliado:** el congelado se rompe y recibe 30% más (astillado de equipo).
- **Miedo → Trampa congelante:** el enemigo que huye aterrorizado y pisa la trampa queda congelado sin que el daño lo libere 1 s.
- **Escudo divino → Piroexplosión o Descarga de escarcha:** con el escudo puesto, el lanzamiento no se interrumpe por daño.
- **Golpe bajo o Carga → Piroexplosión:** un objetivo aturdido recibe la Piroexplosión como crítico.
- **Marca de muerte → cualquier aliado:** el +40% de daño recibido vale para todo el equipo, no solo para el asesino (ya pasa hoy; se va a mostrar mejor).

### Talentos de sinergia (fila 4)

| Clase | Talento | Rinde con |
| --- | --- | --- |
| Mago Fuego | Tu próxima Piroexplosión es instantánea si un sacerdote te puso Escudo divino | Sacerdote |
| Mago Escarcha | Los enemigos que congelás reciben 20% más del daño físico de tus aliados | Guerrero, asesino, cazador |
| Brujo | Tu Miedo dirige al enemigo hacia la trampa más cercana de un cazador aliado | Cazador |
| Cazador | Si un guerrero carga contra un objetivo atrapado en tu trampa, queda aturdido 1 s más | Guerrero |
| Guerrero | El Escudo divino sobre vos dura el doble y te da +10% de daño | Sacerdote |
| Asesino | Tu Eviscerar es crítico contra objetivos congelados o en Polimorfia | Mago |
| Sacerdote | Tus curas sobre un mago o un guerrero le bajan 1 s la recarga de su poder de daño | Mago, guerrero |

## Balance y matchmaking

El ranked queda justo porque en ranked todos juegan con los rangos al máximo: solo cuentan la habilidad del jugador y los talentos que eligió. Las partidas normales sí usan el nivel real, y el matchmaking empareja por nivel.

| Modo | Rangos de habilidad | Talentos | Cómo se arma la partida |
| --- | --- | --- | --- |
| Ranked | Normalizados: todos al rango 5 | Los elegidos (filas desbloqueadas por nivel) | Elo como hoy, sin cambios |
| Normal | Los reales del jugador | Los elegidos | Banda de nivel promedio del equipo: ±3 al principio y más ancha cuanto más se espera (igual que `Ranked.window`) |
| Práctica y bots | Los reales | Los elegidos | Sin emparejamiento |

En ranked hace falta un nivel mínimo del campeón (por ejemplo 10) para entrar con él. Así nadie llega con talentos sin desbloquear.

Para el balance, la simulación con bots que usamos en el último ajuste se extiende en tres pasos:

1. Cada talento contra el kit base, en duelos y 3v3. Meta: ningún talento cambia más de 5 puntos el % de victorias.
2. Las combinaciones de talentos más jugadas, con las clases entre 45% y 55% de victorias.
3. Las parejas con bonus de equipo contra parejas sin bonus. Meta: el bonus suma entre 2 y 5 puntos, no más.

Los bots eligen talentos al azar entre los desbloqueados para su nivel, así la simulación cubre todo.

## Riesgos y decisiones para Ivan

La decisión más importante es dónde se guarda la progresión: hoy todo vive en la PC de cada jugador y es fácil de editar.

| Tema | Riesgo | Propuesta | Decisión |
| --- | --- | --- | --- |
| Trampas | Nivel, rangos y talentos en `user://` se editan a mano | Guardarlos en Steam (estadísticas o Steam Cloud) y que el servidor del host valide nivel contra talentos | A definir |
| Red | El lobby y las entradas de la partida no llevan talentos ni rangos | Sumar `talents` y `ranks` a la entrada del jugador; el servidor rechaza lo que no corresponde al nivel | A definir |
| UI | No hay dónde elegir talentos ni ver la XP | Pestaña de talentos en Campeones, XP y nivel en la pantalla de fin de partida, sinergias en la selección | A definir |
| Alcance | 7 kits × 12 talentos = 84 talentos más 8 bonus y 5 combos | Primera versión con 2 filas por clase (niveles 5 y 10) y 3 bonus de equipo; el resto en una segunda etapa | A definir |
| Clases desactivadas | Antiterrorista, ronin y el resto no tienen talentos (el Druida y el Paladín ya tienen) | Quedan sin talentos hasta que se reactiven | A definir |

## Fases de implementación

Se programa en cuatro etapas, cada una con su PR y sus tests. No se empieza hasta que este documento esté aprobado.

1. **Progresión:** `ProgressStore` (XP, nivel y rangos por campeón, en `user://progress.json` o en Steam según lo que decida Ivan) y XP en la pantalla de fin de partida.
2. **Talentos:** `data/talents.json`, que se aplica al armar el kit (`GameData.kit` más modificadores, y `equip()` para los cambios por habilidades de la reserva). La red lleva los talentos, el servidor los valida y los bots los eligen. También la pestaña de talentos en Campeones.
   - **Versión 1 (hecha):** 2 filas por kit (nivel 5: ataque básico; nivel 10: poder de daño). Cada talento es solo un dato: multiplica o suma un número de una habilidad (o la probabilidad de crítico del kit), o cambia un poder por uno de la reserva (`core/talents.gd`).
   - **Versión 2 (hecha):** casi todos los talentos de las dos filas cambian la forma de jugar, porque los de números se sentían aburridos. Siguen siendo datos: la operación `set` le da a una habilidad un campo de mecánica que lee `ArenaMatch`, por ejemplo `bounce`, `nth` con `nthEffect` (crítico, congelar o atravesar), `leech`, `allyHeal`, `vsSlowed`, `behind`, `critVsSlowed`, `killReset`, `poison`, `slowStack`, `curseMark`, `spread`, `castMove`, `stillCd`, `noPushback`, `instantAfterCrits`, `curseHaste`, `hotHps`, `healCut`, `cdOf` y `charges`. Quedan un cambio de poder por fila y algún número suelto. Los contadores ("cada N" y la racha de críticos) se ven en la barra de acciones.
   - **Cambios respecto de la tabla de arriba:** la Descarga de sombras se lanza 40% más rápido contra un objetivo con tu maldición, en vez de ser instantánea con 2 maldiciones, porque el kit base tiene una sola. La Corrupción contagia a un enemigo cercano al lanzarla, en vez de saltar al terminar, porque se renueva antes de terminar. Con el Golpe, el guerrero bloquea 10% más.
   - El servidor valida que los talentos existan y que haya uno por fila, pero **no puede comprobar el nivel**, porque la progresión sigue en `user://progress.json`. Esto depende de la decisión pendiente sobre Steam.
3. **Sinergias:** bonus de equipo y combos en `ArenaMatch`, y su indicador en la selección de campeones.
   - **Versión 1:** 3 bonus de equipo en `data/synergies.json` (`core/synergies.gd`), con una pestaña Sinergias en Campeones y el aviso en la cuenta regresiva de la partida. Son parejas de daño porque los equipos de dos de daño son los que van más atrás en 2v2. Combos activos para cualquier equipo: Golpe bajo o Carga → Piroexplosión crítica, Miedo → Trampa congelante (el daño no libera durante 1 s) y Escudo divino → lanzamiento sin retroceso, que ya funcionaba porque un golpe absorbido no empuja el lanzamiento. Los talentos de sinergia, las parejas con sanadores y el combo de Nova (hoy en la reserva) quedan para otra etapa.
   - **Cambios respecto de la tabla de bonus:** Mago + Asesino también cuenta a los enraizados, porque el Mago de Escarcha controla sobre todo con raíces. Mago + Guerrero también cuenta al objetivo ardiendo, porque el Mago de Fuego no ralentiza; el ralentizado tiene que ser de la Descarga de escarcha, no del Seccionar propio. Cazador + Guerrero es +5% de daño físico recibido en vez de −10% de armadura, porque solo el Guerrero y el Paladín tienen armadura.
4. **Balance y matchmaking:** simulación extendida, ajuste de números y búsqueda por banda de nivel en partidas normales.
