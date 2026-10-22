class_name SpellKinds
extends RefCounted
## How each ability picks its target (WoW-style: no crosshair, spells use your selected target):
##   auto       slot-0 auto-attack of melee classes and the hunter (toggle, needs a hostile target)
##   hostile    single target, the selected enemy
##   friendly   the selected ally, or yourself
##   self       centred on you / a self buff
##   ground     placed with a ground reticle under the cursor
##   direction  fired/moved along your facing (or toward your target)

const TABLE := {
	"shadowbolt": "hostile", "corruption": "hostile", "agony": "hostile", "fear": "hostile", "darkpact": "self", "drainlife": "hostile", "soulrot": "hostile",
	"fireball": "hostile", "dragonbreath": "direction", "frostbolt": "hostile", "icelance": "hostile", "blizzard": "ground", "pyro": "hostile", "nova": "self", "poly": "hostile", "blink": "direction", "counter": "hostile", "meteor": "ground",
	"shot": "auto", "aimed": "hostile", "trap": "ground", "conc": "hostile", "disengage": "direction", "silence": "hostile", "volley": "direction",
	"strike": "auto", "mortal": "hostile", "charge": "hostile", "hamstring": "hostile", "shieldwall": "self", "pummel": "hostile", "bladestorm": "self",
	"smite": "hostile", "heal": "friendly", "pwshield": "friendly", "scream": "self", "renew": "friendly", "dispel": "friendly", "hymn": "self",
	"wrath": "hostile", "regrowth": "friendly", "ironbark": "friendly", "cyclone": "hostile", "rejuv": "friendly", "naturescure": "friendly", "tranquility": "self",
	"rifle": "auto", "headshot": "hostile", "flashbang": "ground", "kevlar": "self", "knife": "self", "bash": "hostile", "awp": "hostile",
	"slash": "auto", "tempest": "hostile", "windwall": "direction", "sweep": "hostile", "flow": "self", "upcut": "hostile", "lastbreath": "hostile",
	"stab": "auto", "eviscerate": "hostile", "cheapshot": "hostile", "blind": "hostile", "vanish": "self", "kick": "hostile", "deathmark": "hostile",
}


static func kind(spec: Dictionary) -> String:
	return TABLE.get(spec.id, "self")
