# Imba Arena Tournament (Godot 4.7)

Arenas PvP 2v2 / 3v3 con controles estilo World of Warcraft, cuatro arenas estratégicas de diseño propio, bots que
llenan los lugares libres y juego online por IP (ENet) o por Steam. Port del prototipo web (`../magma-arena`) a Godot 4
en GDScript.

## Estado

| Etapa | Qué | Estado |
|-------|-----|--------|
| 1a | Núcleo: datos, reglas, partida autoritativa, bots, tests | listo |
| 1b | Menú, escenario 3D, HUD, efectos, sonido, red ENet, servidor dedicado | listo |
| 2 | Rediseño: 4 arenas (salas con puerta, pilares vivos, puente), controles WoW, auto-ataque sólo melee/cazador, selección muy visible | listo |
| 3 | Arte: 5 personajes y kit de escenario generados con Blender (`tools/blender/`), calidad gráfica alta/media/baja/auto | listo (ver "Límites del arte") |
| 4 | Distribución (zips Windows/macOS/Linux), versión en el handshake, UX de hosting | listo |
| 4b | Menú nuevo (cristal oscuro, tipografías Rajdhani + Inter, íconos SVG, navegación con teclado/gamepad, selección de campeón con tooltips), VFX por escuela, personajes CC0 (KayKit), ícono de la app | listo |
| 4c | v0.3.0: lava de placas, tomas cinematográficas en el menú, ultrawide, Sacerdote propio, playtest con entrada real, balance con simulaciones | listo |
| 4d | Feedback de playtest: amortiguación, cursor propio, personajes más chicos, tooltips de uso, audio CC0 sin pasos, piernas independientes del ataque, vida enemiga roja, sin minimapa, modo espíritu y espectador, resolución adaptativa | implementado en el proyecto fuente |
| 4d | v0.3.1: sin círculo de magma (amortiguación), cursores propios, personajes más chicos, tooltips, modo espíritu, audio Foley CC0, rendimiento Retina, feeling de combate, barra de lanzamiento | listo |
| 4e | v0.4.0: especializaciones (Mago: Fuego/Escarcha), sacerdote bot que acompaña al equipo | listo |
| 4f | v0.5.0: sexta clase, Brujo (Aflicción): maldiciones independientes, miedo real, drenar vida, pacto oscuro | listo |
| 4g | v0.6.0: tutorial interactivo, página Cómo jugar, Arena de práctica con medidor de daño y identidades de clase asimétricas | listo |
| 5 | Steam (GodotSteam GDExtension): salas de amigos/públicas, invitaciones, nombres de Steam | **implementado, sin probar contra Steam real** |

## Cómo jugar

Requiere Godot 4.7.2 (`godot` en el PATH). La primera vez (o al agregar `class_name`): `godot --headless --path . --import`.

**En Windows**: bajá `Godot_v4.7.2-stable_win64.exe.zip` del release oficial y poné en la PATH un `godot` que apunte a
`Godot_v4.7.2-stable_win64_console.exe` (el de consola: sin él los scripts no ven la salida). Los `.sh` (tests, smoke, exportación,
plantillas, rcedit) corren en Git Bash; rcedit funciona nativo, así que el `.exe` exportado lleva ícono y versión. El repo fija fin de
línea LF (`.gitattributes`) porque Godot reescribe los recursos con LF.

| Modo | Comando |
|------|---------|
| Menú | `godot --path .` (título -> menú principal -> Jugar / Campeones / Configuración) |
| Sin conexión (bots) | menú → **Jugar → Práctica**, o `godot --path . -- --offline --cls=warrior --map=bridge` |
| Anfitrión por IP | menú → **Jugar → Crear partida** (UDP 7777 por defecto; el puerto se cambia en el menú). La sala muestra puerto, IP local y pública con botones **Copiar** |
| Unirse por IP | menú → **Jugar → Unirse** → IP + puerto (se recuerda la última dirección; acepta `IP:PUERTO`) |
| Steam | menú → **Jugar → Steam** → **Crear sala** (sólo amigos / pública) o **Buscar salas**; también por invitación desde la superposición |
| Servidor dedicado | `godot --headless --path . -- --server --port=7777 --mode=2 --map=random --wait=10` |

Opciones de línea de comandos (tras `--`): `--map=random|bridge|pillars|tomb|living`, `--cls=`, `--mode=2|3`, `--diff=`, `--gfx=auto|alta|media|baja`,
`--name=`, `--team=`, `--host`, `--join=IP[:PUERTO]`, `--autopilot`, `--drive` (jugador scripteado), `--target` (mantiene un enemigo seleccionado),
`--log`, `--shot=PREFIJO --shot-times=3,10` (capturas), `--time-scale=N`, `--rounds=N`, `--no-capture`.
Para capturas de menús: `--menu=hub|play|setup:practice|join|champions:rogue|settings:audio` (+ `--menu-tip=N` abre el tooltip de la habilidad N), `--lobby-demo`, `--end-demo`, `--menu-script=1:key,2:go:play,3:press:ui_down` (acciones temporizadas).

## Arenas

Cuatro arenas simétricas (rotación de 180°), chicas y limpias: 3–5 objetos que bloquean la visión y nada de decoración dentro del campo.
Cada equipo empieza en una **sala cerrada con puerta**: **20 s** de preparación la primera ronda (10 s entre rondas), podés moverte y
usar escudos/refuerzos adentro; las puertas bloquean paso y visión hasta que empieza la pelea. El mapa se elige **al azar por partida**
(el anfitrión sortea con semilla y lo informa a todos) o a mano.

| Arena | Idea |
|-------|------|
| **Puente de Magma** | Dos mesetas unidas por un puente angosto sobre un abismo de lava (daño). Desde el abismo no se ve la altura; rampas para salir |
| **Cuatro Pilares** | Sala redonda con cuatro pilares grandes: el clásico de esquivar la línea de visión |
| **Tumba del Titán** | Estatua colosal central, dos lápidas junto a las salas y columnas rotas |
| **Pilares Vivos** | Pilares que suben y se hunden en ciclos (aviso de 2 s con temblor y brillo); al subir te empujan hacia afuera, nunca te atrapan |

Todo es determinista y autoritativo del servidor (`core/game_map.gd`); el cliente sólo recibe `gates` y `ft` en cada snapshot.

No hay círculo que cierre ni daño por estar lejos del centro. **Amortiguación** reduce la sanación desde los 40 s de pelea,
sube 2 puntos porcentuales por segundo y tiene un tope de 95%; aparece como debuff. La lava propia del Puente sigue haciendo daño.

## Controles (estilo WoW)

El cursor está libre; no hay mira. Los hechizos van al **objetivo seleccionado**.

| Acción | Control |
|--------|---------|
| Mirar con personaje | mantener **clic derecho** + arrastrar (el cursor se oculta y vuelve a su lugar al soltar) |
| Sólo cámara | mantener **clic izquierdo** + arrastrar · rueda: zoom (la cámara choca con paredes y pilares) |
| Correr adelante | ambos botones |
| Mover | **W/S** adelante/atrás según hacia dónde mira el personaje · **A/D** giran (con clic derecho apretado: paso lateral) |
| Seleccionar | clic (sin arrastrar) sobre una unidad · `Tab` enemigos de enfrente · `F1`–`F3` aliados · `Esc` limpia |
| Atacar | clic derecho sobre un enemigo: lo selecciona, te gira hacia él y enciende el auto-ataque |
| Habilidades | `1` `2` `Q` `E` `Shift` `F` `R` (ultimate) |
| Hechizos al suelo (meteoros, trampa) | aparece un círculo bajo el cursor: clic izquierdo coloca, clic derecho / `Esc` cancela |
| Saltar · silenciar | `Espacio` · `M` |
| Ver qué hace una habilidad y cómo usarla | pasar el cursor sobre su ícono en la barra |
| Al morir | pantalla azul desaturada; `Tab` cambia entre aliados vivos, clic en su marco elige a quién mirar; se restablece al revivir |

Auto-ataque: **sólo guerrero, asesino y cazador** (tecla `1` o clic derecho). Necesita objetivo hostil a tiro, visible y **de frente**; se apaga si el
objetivo muere, elegís un aliado o limpiás la selección. Mago, brujo y sacerdote **nunca** atacan solos (su `1` es un hechizo común). Errores:
"No tenés objetivo", "Fuera de alcance", "No está a la vista", "Objetivo inválido: es un aliado".

Selección: anillo grande animado bajo el objetivo (rojo hostil / verde aliado), contorno de luz en el modelo, flecha sobre la cabeza, nameplate
agrandada y al frente, marco de objetivo grande, flecha en el borde de la pantalla si está fuera de vista y resalte + cursor (espada/mano) al pasar el mouse.

## Brujo — Aflicción

Sexta clase jugable: seleccioná **Brujo** en Campeones o usá `--offline --cls=warlock`.
Presión sostenida, sin mascota ni escape instantáneo; modelo KayKit CC0 con corona ósea y foco verde.

| Tecla | Habilidad | Uso |
|-------|-----------|-----|
| 1 | Descarga de las sombras | 34 de daño, lanzamiento de 1,2 s |
| 2 | Corrupción | 9 de daño/s durante 8 s |
| Q | Agonía | 7 de daño/s durante 10 s |
| E | Miedo | Lanzamiento de 1,2 s; huye 3 s, se rompe tras más de 40 de daño |
| Shift | Pacto oscuro | Cuesta 15% de vida actual (no letal); absorbe 80 durante 6 s |
| F | Drenar vida | Lanzamiento de 1,5 s; roba hasta 42 de vida al completar, no es canalización |
| R | Putrefacción del alma | Definitiva: 25 de daño + 16/s durante 6 s |

Las maldiciones son independientes por brujo y hechizo: refrescar prolonga, no acumula ni retrasa el siguiente pulso.
Disipar las elimina; siguen activas si muere su autor. El daño periódico también rompe Miedo.
El drenaje cura sólo vida realmente quitada (sin escudos ni exceso al matar), reducido por herida mortal y amortiguación.
Moverte o perder alcance/visión cancela el resultado del drenaje y del miedo. Bots usan el kit y evitan maldecir al objetivo controlado.
Protocolo de red **3**: todos los participantes necesitan esta versión del proyecto (cambió la tabla de habilidades).

## Calidad gráfica

Menú → **Gráficos**: Auto / Alta / Media / Baja (se guarda). Auto ajusta primero la resolución 3D (piso 0,5), buscando 60 FPS
o 90 en pantallas de alta frecuencia. Si en el piso sigue debajo de 54 FPS durante 4 muestras, reduce efectos un nivel.
Arranca en *media* con GPU integrada y en *baja* sin GPU/Vulkan. Las ventanas Retina tienen un presupuesto de píxeles y
usan MetalFX espacial en macOS al escalar; la interfaz mantiene su resolución. Alta: SSAO, SSR sobre lava, niebla volumétrica,
sombras 4096; SDFGI desactivado. Baja: sin sombras ni bloom, escala máxima 0,75. `F3` muestra estadísticas de rendimiento.
Si Vulkan/D3D12 fallan el motor cae solo al renderer OpenGL (Compatibility) y el juego fuerza *baja*.

## Distribución y Jugar con amigos

```sh
tools/install_templates.sh      # una vez: descarga las plantillas de exportación de Godot 4.7.2
tools/export_all.sh windows macos linux   # genera build/ImbaArenaTournament-{windows,macos,linux}.zip
```

Cada zip trae `LEEME.txt` (cómo abrirlo: en Mac clic derecho → Abrir o `xattr -dr com.apple.quarantine`; en Windows SmartScreen →
*Más información → Ejecutar de todas formas*). El macOS es universal (Intel + Apple Silicon), con firma ad-hoc. Pasá el zip por donde quieras.
**Todos tienen que tener la misma versión** (`config/version` en `project.godot`): si no, el servidor lo rechaza con un mensaje claro.

Para jugar online por IP (todo es **UDP**, puerto 7777 por defecto):

- **A. VPN virtual (lo más simple, sin tocar el router):** Tailscale, ZeroTier o Radmin VPN. Todos se unen a la misma red y usan la IP virtual del anfitrión.
- **B. Abrir el puerto:** en el router, redirigí **UDP 7777** a la PC del anfitrión; los demás usan su IP pública (la sala la muestra con botón *Copiar*).
- **C. Túnel UDP con playit.gg:** creá un túnel UDP al puerto 7777 y compartí la dirección que te da.
- **D. Servidor dedicado en un VPS barato:** copiá el juego, abrí UDP 7777 y corré `--server`. Ejemplo de servicio systemd:

```ini
# /etc/systemd/system/imba.service
[Unit]
Description=Imba Arena Tournament server
After=network.target
[Service]
User=imba
WorkingDirectory=/opt/imba
ExecStart=/opt/imba/ImbaArenaTournament.x86_64 --headless -- --server --port=7777 --mode=2 --map=random --wait=15
Restart=always
[Install]
WantedBy=multi-user.target
```

> **ngrok y cloudflared no sirven**: el juego usa UDP y esos túneles gratuitos sólo exponen TCP/HTTP.

## Steam

GodotSteam **GDExtension 4.23.1** (Steamworks 1.65), fuente: https://codeberg.org/godotsteam/godotsteam/releases/tag/v4.23.1
(`godotsteam-4.23.1-gdextension-plugin-4.4.zip.tar.xz`, funciona en Godot 4.4+; sha256 `37d53ede5eda11d2247d70c1af91f95a4777ad2a419fc8a24de1cc816d21cc0a`),
instalada en `addons/godotsteam/` (sólo win64, macOS universal y linux64). App id de desarrollo **480** (Spacewar, `steam_appid.txt`).

- Es **opcional**: sin la extensión o sin el cliente de Steam el menú deshabilita la fila de Steam (con el motivo) y todo sigue igual por ENet. Verificado: la extensión carga en 4.7.2 y en un build macOS exportado, y el juego arranca sin Steam.
- Salas: *Crear sala Steam* (sólo amigos / pública), lista **Salas de Steam** (sólo muestra las de la misma versión y con lugar), invitaciones y "unirse a partida" desde la superposición. Los jugadores se llaman como su nombre de Steam y el servidor los identifica por **SteamID**.
- Red: `SteamTransport` usa mensajes P2P de Steam (con relay, sin abrir puertos) detrás de la misma interfaz `Transport` que ENet; `GameServer`/`GameClient` no cambian.
- **Sin probar contra Steam real** (no había cliente de Steam en esta máquina): la lógica de lobbies, el transporte y el flujo completo (lobby → partida) se prueban con un Steam falso en `tests/test_steam.gd`, y los nombres de métodos/señales de `SteamBackendReal` se comprobaron contra la extensión cargada, pero la integración final hay que probarla con dos cuentas de Steam.

## Playtest con entrada real y balance

- `tools/playtest.sh [clase ...]` abre una ventana real y maneja el juego con `Input.parse_input_event` (botones, arrastres, movimiento del mouse y teclas): mouselook con RMB, órbita con LMB, ambos botones, selección por clic, Tab, auto-ataque con clic derecho, retículo de zona (colocar y cancelar) y Esc; verifica objetivo, rumbo, daño, cursor y estados pegados. Código en `scripts/dev/playtest.gd`.
- `tools/balance_run.sh [N] [etiqueta]` simula partidas bot contra bot en paralelo y escribe tablas de tasa de victoria; resultados y salvedades en `docs/balance.md`.
- `tools/install_rcedit.sh` descarga rcedit v2.0.0 (verificado por SHA-256). rcedit es un programa de Windows: para embeber ícono y versión en el `.exe` hace falta Windows o wine; sin wine `export_all.sh` exporta el `.exe` sin esos recursos y lo avisa.

## Estructura

```
data/        clases, habilidades, power-ups, mapas, constantes
core/        simulación autoritativa sin dibujo ni red: game_map (4 arenas), rules (formas, LdV, colisión), arena_match, bot_brain
scripts/logic/  lógica del cliente testeada: PlayerController, SpellKinds, InputLogic, ClickPicker, OffscreenIndicator, Quality, NetChoice, Wire, SnapshotBuffer, Predictor...
scripts/net/    Transport · LoopbackTransport · PeerTransport (ENet) · steam/ (backend, transporte y lobbies de Steam) · GameServer · GameClient · SnapshotCodec · FxFilter
scripts/view/   ArenaWorld (arenas), UnitView/CharacterRig (modelos .glb + animaciones), FxManager, CameraRig, MatchView, AudioBank
scripts/ui/     MenuScreen + menu/ (splash, hub, jugar, configurar, unirse, campeones, configuración), kit/ (MButton, Card, Segmented, tooltip, sonidos), lobby, fin de partida, HUD, navegador de salas Steam
tools/blender/  generadores reproducibles (Blender 5.2 headless): build_characters.py, build_env.py -> assets/models/ (personajes procedurales, de respaldo)
tools/icons/    build_icons.py (set de íconos SVG -> assets/icons), build_app_icon.py (ícono .ico/.icns de la app)
tools/render_menu_art.gd  retratos de clase y miniaturas de mapas (assets/ui) renderizados con el juego (`godot --path . --script res://tools/render_menu_art.gd`, ventana real)
tools/          export_all.sh, install_templates.sh, LEEME.txt
assets/         modelos .glb generados, third_party/kaykit (personajes CC0), fonts (OFL), icons (SVG), ui (retratos/mapas), shaders (terreno, cristal, hechizos, superficies del kit...)
tests/          tests headless + smoke.sh + FakeSteam
docs/screens/   capturas
```

Regenerar arte: `blender -b --python tools/blender/build_characters.py` y `build_env.py`, luego `godot --headless --path . --import`.

## Tests

```sh
./run_tests.sh              # todos (263); falla ante cualquier test o error de script
./run_tests.sh net steam    # sólo las suites cuyo archivo contiene esas palabras; -v imprime cada test
./tests/smoke.sh            # humo headless: menú, partida offline, jugador scripteado en 2 mapas, servidor dedicado + cliente ENet
```

Los `ERROR: ... decode_variant` de `test_logic` son esperados (prueban que bytes basura y objetos serializados se rechazan).

Validación visual del feedback (ventana real, guarda `docs/screens/feedback_*.png`):
`godot --path . --resolution 1600x900 --script res://tools/check_playtest_feedback.gd -- --offline --mode=3 --map=tomb --cls=mage --no-capture --gfx=media`.
Comprueba hover, límites del tooltip, muerte autoritativa, cambio de aliado con Tab y vuelta al revivir.

## Arte y créditos

- **Personajes**: Mago, Guerrero (Caballero), Asesino y Cazador (Pícaro con capucha) son de **KayKit : Adventurers Character Pack 1.0** de Kay Lousberg, licencia **CC0** (archivo `assets/third_party/kaykit/LICENSE.txt`, fuente en `SOURCE.txt`: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0). El Sacerdote es el modelo del Mago recoloreado y sin sombrero (el paquete gratuito no trae sacerdote ni cazador). Las capas toman el color del equipo. Con `CharacterRig.use_kaykit = false` se vuelve a los modelos procedurales de Blender (`assets/models/`).
- **Tipografías**: Rajdhani (títulos) e Inter (texto), SIL Open Font License (`assets/fonts/OFL-*.txt`).
- **Audio de combate**: 19 muestras Foley de Kenney RPG Audio e Impact Sounds, **CC0**, en `assets/third_party/kenney_audio/` con licencias y hashes de origen. Armas/metales, vidrio, telas y campanas interpretan las escuelas con variación suave de tono. Los pasos son silenciosos; los avisos de interfaz siguen sintetizados. La preferencia subjetiva del sonido requiere una escucha de playtest.
- **Íconos**: dibujados por script (`tools/icons/build_icons.py`), sin emoji en ningún lado (los emoji se rompen en Windows).
- **Escenario**: kit generado con Blender; superficies con un shader de piedra/madera/metal triplanar con normal map, polvo y desgaste de bordes (`assets/shaders/kit_surface.gdshader`), piso calmo de baja frecuencia en la Tumba, VFX por escuela (fuego, escarcha, arcano, físico, sagrado, sombra, naturaleza) con proyectiles de malla con fresnel/disolución, decals de suelo animados, auras y marcas de quemadura, que escalan con la calidad gráfica.

Límites: el escenario sigue siendo procedural (sin texturas horneadas ni esculpido a mano), las estatuas y las lápidas son geometría simple con textura de superficie, y los VFX son shaders y partículas sin flipbooks pintados. Si querés más personajes (Druida, Ingeniero, Bárbaro, Pícaro/Cazador propios), el paquete EXTRA de KayKit o los packs CC0 de Quaternius sirven: bajá los `.glb` a `assets/third_party/<pack>/`, agregá su licencia y registralos en `CharacterRig.KAYKIT`.

## Otras diferencias con la web

Sin cola pública ni códigos de sala (se juega por IP, Steam o servidor dedicado); 
Se probaron en ejecución los builds de macOS y Windows (Windows 11, Vulkan); el de Linux se exporta pero no se probó.


## Créditos de audio y notas de 0.3.1

- Interfaz: Kenney Interface Sounds (CC0) en `assets/third_party/kenney_ui/` (licencia, fuente y hash del archivo original incluidos). Combate: Kenney RPG Audio e Impact Sounds (CC0) en `assets/third_party/kenney_audio/`.
- Los personajes llevan un contorno de tinta (`assets/shaders/outline.gdshader`) para unificar el estilo pintado a mano.
- Cursores: dibujados en vectores (`CursorKit`), se rasterizan al tamaño de la ventana (nítidos en Retina).
- Rendimiento: `tools/perf.sh` mide en ventana real; `F3` muestra estadísticas; en "Auto" la escala 3D se adapta a los píxeles y a los fps.

## Especializaciones (0.4.0)

Los kits viven en `data/classes.json` (`specs` de cada clase: nombre, ícono, color, descripción, estadísticas y las 7 habilidades). Para sumar una a otra clase alcanza con agregar `specs` y `default_spec`; la elección se hace en Campeones (dos tarjetas bajo la clase), se guarda por clase y viaja en el saludo, la sala, la partida y los snapshots. El protocolo subió a la versión 2 y el juego a 0.4.0, así que no se mezclan versiones. No se hizo la pasiva opcional "Combustión".

## Brujo (0.5.0)

Sexta clase, sin mascota: Descarga de sombras, Corrupción y Agonía (maldiciones independientes que se refrescan sin acumular y se pueden disipar), Aterrorizar (huida real, comparte rendimientos decrecientes con el grito del sacerdote y se rompe con más de 40 de daño), Pacto oscuro (sacrifica 15% de vida actual por un escudo propio), Drenar vida (canalizado, cura sólo el daño realmente hecho) y Putrefacción del alma (definitiva). Modelo: KayKit Mage con capucha cornuda, ojos y báculo con calavera en llama vil, capa de sombra y grimorio (piezas propias, sin assets nuevos). Los efectos tienen ícono y descripción en los marcos de objetivo. El protocolo y el juego subieron a 0.5.0.


## Cómo jugar y tutorial (0.6.0)

- **Menú principal > Cómo jugar**: referencia estática (Controles, Reglas, Campeones con vida, velocidad, armadura e identidad de cada clase, generada desde `data/classes.json` por `HowToContent`) y el botón **Empezar el tutorial**.
- **Tutorial interactivo**: corre dentro de la Arena de práctica con tu campeón y su especialización. Cada paso (`TutorialFlow`, lógica pura con tests) sólo avanza cuando hacés la acción: moverte y saltar, cámara (clic derecho, clic izquierdo, rueda), elegir objetivo (clic y Tab), ataque básico y auto-ataque, tus habilidades con sus teclas y descripciones reales, barra de lanzamiento (quedarte quieto y cancelar moviéndote), hechizos de zona, línea de visión (esconderte del muñeco hechicero), interrumpir o controlar, debuffs y tooltips, la definitiva, y cómo es una partida (sala de inicio, puertas, al mejor de 3, amortiguación). Resalta las teclas, marca con una flecha el elemento del HUD o el muñeco, deja saltear un paso o salir, y al final ofrece Arena de práctica, Contra bots o Menú. Se ofrece una sola vez en el primer arranque (`tutorial_seen` en la configuración) y siempre se puede repetir.
- Prueba con entradas reales: `tools/playtest.sh tutorial`.

## Arena de práctica (0.6.0)

- **Jugar > Arena de práctica**: mapa propio (`yard`, sólo sin conexión), sin rondas, temporizador ni amortiguación; si morís reaparecés al instante. Corre en el mismo servidor autoritativo que el resto del juego (anfitrión local).
- **Muñecos** (`core/practice_yard.gd`): tres fijos a cuerpo a cuerpo, 15 m y 25 m, uno móvil que patrulla una línea (skillshots y kiteo), un hechicero que lanza un hechizo largo cada pocos segundos (para practicar interrupciones; nunca hace daño), uno tras un pilar (línea de visión) y un aliado herido que pierde vida solo (para sanadores). Tienen 50 000 de vida, nunca mueren, se pueden aturdir, aterrorizar o ralentizar y muestran debuffs y números de daño.
- **Panel**: medidor de daño (total, DPS de los últimos 10 s y desde el primer golpe, curación hecha, tabla por habilidad con daño, porcentaje, lanzamientos y críticos; `PracticeMeter`, calculado en el servidor), Reiniciar (medidor, muñecos, cooldowns y proyectiles en vuelo), Sin cooldowns, Definitiva lista, cambio de campeón y especialización sin salir, y Volver al menú.
- Prueba con entradas reales: `tools/playtest.sh practice`.

## Identidades de clase (0.6.0)

Cada clase tiene números muy distintos (vida, daño, crítico y armadura, todo en `data/classes.json`): Asesino cañón de cristal (380 de vida, crítico +10%, mayor golpe), Guerrero tanque (640 y 18% de armadura contra daño físico), Mago Fuego frágil y explosivo, Mago Escarcha de control, Cazador de daño sostenido, Sacerdote de curación, Brujo de desgaste. Detalle y matriz de enfrentamientos en `docs/balance.md`. Herramientas: `tools/balance_run.sh` y `tools/duel_run.sh`.

## Créditos de audio de 0.5.0

Los sonidos de habilidades son capas de grabaciones reales CC0 de OpenGameArt en `assets/third_party/oga_sfx/` (licencia y fuentes en `LICENSE.txt` y `SOURCE.txt` de esa carpeta; `tools/audio/build_sfx.py` las recorta y normaliza).
