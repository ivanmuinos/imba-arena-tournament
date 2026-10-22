class_name SpellSchools
extends RefCounted
## Magic schools used to colour and shape spell effects: every ability maps to one school, each school has
## a three-tone palette (hot core / body / rim) and a particle profile that scales with the quality level.

const SCHOOLS := ["fire", "frost", "arcane", "physical", "holy", "shadow", "nature"]

const OF := {
	"shadowbolt": "shadow", "corruption": "shadow", "agony": "shadow", "fear": "shadow", "darkpact": "shadow", "drainlife": "nature", "soulrot": "shadow",
	"fireball": "fire", "pyro": "fire", "meteor": "fire", "volley": "fire", "dragonbreath": "fire",
	"nova": "frost", "trap": "frost", "conc": "frost", "frostbolt": "frost", "icelance": "frost", "blizzard": "frost",
	"poly": "arcane", "blink": "arcane", "counter": "arcane",
	"shot": "physical", "aimed": "physical", "disengage": "physical",
	"strike": "physical", "mortal": "physical", "charge": "physical", "hamstring": "physical", "shieldwall": "physical", "pummel": "physical", "bladestorm": "physical",
	"stab": "physical", "eviscerate": "physical", "cheapshot": "physical", "kick": "physical",
	"smite": "holy", "heal": "holy", "pwshield": "holy", "dispel": "holy", "hymn": "holy",
	"scream": "shadow", "silence": "shadow", "blind": "shadow", "vanish": "shadow", "deathmark": "shadow",
	"renew": "nature",
	"rifle": "physical", "headshot": "physical", "flashbang": "holy", "kevlar": "physical", "knife": "physical", "bash": "physical", "awp": "physical",
	"slash": "physical", "tempest": "physical", "windwall": "frost", "sweep": "physical", "flow": "frost", "upcut": "physical", "lastbreath": "physical", "tornado": "frost",
	"wrath": "nature", "regrowth": "nature", "ironbark": "nature", "cyclone": "nature", "rejuv": "nature", "naturescure": "nature", "tranquility": "nature",
}

const PALETTE := {
	"fire": {"core": Color("#fff1b0"), "mid": Color("#ff6a10"), "edge": Color("#b81c00")},
	"frost": {"core": Color("#e8fbff"), "mid": Color("#5fc8ff"), "edge": Color("#1c5fd0")},
	"arcane": {"core": Color("#f6e0ff"), "mid": Color("#b45cff"), "edge": Color("#4a1a9a")},
	"physical": {"core": Color("#ffffff"), "mid": Color("#ffd9a0"), "edge": Color("#8a6a48")},
	"holy": {"core": Color("#ffffff"), "mid": Color("#ffe27a"), "edge": Color("#d89a1a")},
	"shadow": {"core": Color("#d9b8ff"), "mid": Color("#6a2fb0"), "edge": Color("#1a0a2e")},
	"nature": {"core": Color("#e6ffd0"), "mid": Color("#5fd964"), "edge": Color("#1a6a2a")},
}

## n particles, speed, gravity (positive = falls), life, size
const BURST := {
	"fire": {"n": 36, "speed": 7.0, "gravity": -2.0, "life": 0.7, "size": 0.5},
	"frost": {"n": 34, "speed": 6.0, "gravity": 5.0, "life": 0.6, "size": 0.38},
	"arcane": {"n": 32, "speed": 4.5, "gravity": 0.0, "life": 0.7, "size": 0.4},
	"physical": {"n": 18, "speed": 5.0, "gravity": 7.0, "life": 0.35, "size": 0.32},
	"holy": {"n": 34, "speed": 3.5, "gravity": -3.0, "life": 0.9, "size": 0.42},
	"shadow": {"n": 30, "speed": 3.0, "gravity": -0.5, "life": 0.9, "size": 0.55},
	"nature": {"n": 28, "speed": 3.5, "gravity": 2.0, "life": 0.8, "size": 0.4},
}


static func explicit(ability_id: String) -> bool:
	return OF.has(ability_id)


static func school_of(ability_id: String) -> String:
	return OF.get(ability_id, "physical")


static func palette(school: String) -> Dictionary:
	return PALETTE.get(school, PALETTE.physical)


## Particle profile scaled by the quality multiplier (Quality.TABLE "particles", 0.3-1.0).
static func burst(school: String, quality: float) -> Dictionary:
	var b: Dictionary = (BURST.get(school, BURST.physical) as Dictionary).duplicate()
	b.n = maxi(3, int(round(float(b.n) * quality)))
	return b
