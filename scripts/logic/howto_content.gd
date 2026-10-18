class_name HowToContent
extends RefCounted
## Text of the static "Cómo jugar" reference page (BBCode, Spanish). Pure functions so the content can be tested and kept in
## sync with the data: the class overview is generated from data/classes.json (HP, speed, armor, identity).

static func controls() -> String:
	var rows := [
		["W A S D / flechas", "Moverte (relativo a la cámara). [b]Espacio[/b] salta."],
		["Clic derecho + arrastrar", "Mirar alrededor: el personaje gira con la cámara."],
		["Clic izquierdo + arrastrar", "Orbitar la cámara sin girar al personaje."],
		["Rueda del mouse", "Acercar / alejar la cámara."],
		["Clic izquierdo en una unidad", "Elegir objetivo. Los enemigos tienen la barra roja."],
		["Tab", "Cambiar al siguiente enemigo. [b]Esc[/b] suelta el objetivo o cancela un lanzamiento."],
		["Clic derecho en un enemigo", "Elegirlo y, si tu clase tiene ataque automático, empezar a pegarle."],
		["1  2  Q  E  Shift  F  R", "Las siete habilidades de tu campeón (R es la definitiva)."],
		["F1  F2  F3", "Elegir a un aliado (o clic en su cuadro) para curas y escudos."],
		["Hechizos de zona", "Apretá la tecla, apuntá con el retículo y [b]clic izquierdo[/b] para colocar; clic derecho o Esc cancelan."],
		["M", "Silenciar el sonido. [b]F3[/b] muestra los cuadros por segundo."],
	]
	var out := "[b]Controles[/b]\n\n"
	for r in rows:
		out += "[color=#ffc15a][b]%s[/b][/color]  %s\n" % [r[0], r[1]]
	return out


static func rules() -> String:
	return "[b]Reglas de la partida[/b]\n\n" \
		+ "[color=#ffc15a][b]Equipos[/b][/color]  2 contra 2 o 3 contra 3. Los lugares vacíos los ocupan bots.\n" \
		+ "[color=#ffc15a][b]Sala de inicio[/b][/color]  Cada equipo espera con las puertas cerradas (20 s la primera ronda, 10 s las demás). Ahí podés usar escudos y curas.\n" \
		+ "[color=#ffc15a][b]Ronda[/b]  [/color]Se abren las puertas y se pelea. Gana la ronda el equipo que elimina a todos los rivales.\n" \
		+ "[color=#ffc15a][b]Partida[/b][/color]  Al mejor de 3: gana quien primero consigue 2 rondas.\n" \
		+ "[color=#ffc15a][b]Amortiguación[/b][/color]  Pasados 40 s de pelea, toda curación recibida baja un 2% por segundo (hasta casi nada): los duelos de sanadores no se estiran para siempre.\n" \
		+ "[color=#ffc15a][b]Línea de visión[/b][/color]  Casi todos los hechizos necesitan ver al objetivo: los pilares y paredes tapan. Los arbustos esconden a quien está adentro.\n" \
		+ "[color=#ffc15a][b]Control de masas[/b][/color]  Aturdir, enraizar, silenciar, miedo, incapacitar. Repetir el mismo tipo rinde 100%, 50%, 25% y después es inmune por un rato. Algunos efectos se rompen con el daño.\n" \
		+ "[color=#ffc15a][b]Interrupciones[/b][/color]  Mientras lanzás una barra de lanzamiento no podés moverte; si te movés, saltás o te interrumpen se cancela y esa habilidad queda bloqueada unos segundos.\n" \
		+ "[color=#ffc15a][b]Mejoras[/b][/color]  Aparecen gemas en el mapa: crítico asegurado, sigilo, escudo y velocidad.\n"


static func _pct(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


## One block per class: role, HP, speed, damage reduction and what it is good (and bad) at, straight from the data.
static func classes() -> String:
	GameData.ensure_loaded()
	var out := "[b]Los campeones[/b]\n\n"
	for id in GameData.classes:
		var c: Dictionary = GameData.classes[id]
		out += "[color=#ffc15a][b]%s[/b][/color]  [i]%s[/i]\n" % [str(c.name).to_upper(), ", ".join(c.tags)]
		var armor := float(c.get("armor", 0.0))
		out += "Vida %d   Velocidad %s%s\n" % [int(c.hp), str(c.speed), ("   Armadura %s del daño físico" % _pct(armor)) if armor > 0.0 else ""]
		out += "%s\n" % str(c.get("identity", c.get("tagline", "")))
		for sid in GameData.spec_ids(id):
			var sp: Dictionary = c.specs[sid]
			out += "  [color=#9edcfa]%s[/color]: %s\n" % [str(sp.name), str(sp.desc)]
		out += "\n"
	return out


## Tooltip of a champion-select stat bar, with the real numbers behind it (kit = GameData.kit(cls, spec)).
static func stat_tip(kit: Dictionary, key: String) -> String:
	var abs: Array = kit.abilities
	match key:
		"hp":
			var armor := float(kit.get("armor", 0.0))
			return "Vida %d%s" % [int(kit.hp), (", armadura %s contra daño físico" % _pct(armor)) if armor > 0.0 else ", sin armadura"]
		"mobility":
			return "Velocidad %s m/s" % str(kit.speed)
		"damage":
			var b: Dictionary = abs[0]
			var biggest := 0.0
			for i in range(0, 6):
				biggest = maxf(biggest, float(abs[i].get("dmg", 0.0)))
			var line := "Mayor golpe %d" % int(biggest)
			if b.has("dmg") and float(b.cd) > 0.0:
				line = "Ataque básico %d cada %.1f s (%d por segundo); %s" % [int(b.dmg), float(b.cd) / 1000.0, roundi(float(b.dmg) / (float(b.cd) / 1000.0)), line.to_lower()]
			var crit := float(kit.get("crit", 0.0))
			return line + (", crítico +%s" % _pct(crit) if crit > 0.0 else "")
		"control":
			var n := 0
			for i in range(0, 6):
				if abs[i].has("ccMs") or abs[i].has("slowPct"):
					n += 1
			return "%d habilidades que controlan (aturden, ralentizan, aterrorizan o interrumpen)" % n
		"difficulty":
			return "Qué tan exigente es de jugar bien: más alto, más para aprender."
	return ""
