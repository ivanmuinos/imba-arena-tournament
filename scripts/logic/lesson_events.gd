class_name LessonEvents
extends RefCounted
## Turns one entry of the server's journal into the event strings steps wait for, from the point of view of the player `me`.


static func keys(ev: Dictionary, me: int) -> Array:
	match str(ev.get("e", "")):
		"plate":
			return ["plate", "plate:%d" % int(ev.get("i", -1))]
		"door":
			return ["door:%d" % int(ev.get("i", -1))]
		"cast":
			return ["cast", "cast:%s" % str(ev.get("ability", ""))] if int(ev.get("u", -1)) == me else []
		"dmg":
			if int(ev.get("t", -1)) == me:  # nobody behind it: the floor (lava) did it
				return ["hurt", "burned"] if int(ev.get("by", -1)) < 0 else ["hurt"]
			return ["dmg"] if int(ev.get("by", -1)) == me else []
		"heal":
			return ["heal"] if int(ev.get("by", -1)) == me else []
		"note":
			return ["note:%s" % str(ev.get("k", ""))]
		"cc":
			var cat := str(ev.get("cat", ""))
			if int(ev.get("t", -1)) == me:
				return ["cc_me", "cc_me:%s" % cat]
			var out := ["cc", "cc:%s" % cat]
			if str(ev.get("kind", "")) != "":
				out.append("cc:%s:%s" % [cat, str(ev.kind)])
			return out
		"cc_immune":
			return ["cc_immune", "cc_immune:%s" % str(ev.get("why", ""))]
		"cc_break":
			return ["self_break"] if int(ev.get("by", -1)) == me else []
		"interrupt":
			return ["interrupted"] if int(ev.get("t", -1)) == me else ["interrupt"]
		"cast_cancel":
			return ["cast_cancel", "cast_cancel:%s" % str(ev.get("why", ""))] if int(ev.get("u", -1)) == me else []
		"trinket":
			return ["trinket"] if int(ev.get("u", -1)) == me else []
		"gem":
			return ["gem", "gem:%s" % str(ev.get("kind", ""))] if int(ev.get("u", -1)) == me else []
		"down":
			return ["down"] if int(ev.get("t", -1)) == me else []
		"death":
			return ["death"]
	return []
