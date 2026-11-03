class_name AtomicFile
extends RefCounted
## Writes a file so a crash never leaves it half written: the text goes to `path + ".tmp"` first and is then renamed over `path`.


static func write_text(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	var from := ProjectSettings.globalize_path(tmp)
	var to := ProjectSettings.globalize_path(path)
	if DirAccess.rename_absolute(from, to) == OK:
		return true
	DirAccess.remove_absolute(to)  # some platforms refuse to replace an existing file
	return DirAccess.rename_absolute(from, to) == OK
