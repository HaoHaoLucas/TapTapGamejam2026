class_name MetaResourceProvider
extends RefCounted
## Read-only door for resources that outlive a run.
## A future archive can override this without touching the card grid.
## Each connected entry is:
## { "id": String, "name": String, "icon": Texture2D, "count": int, "description": String }

const DISCONNECTED_TEXT := "局外资源尚未接入"


func is_available() -> bool:
	return false


func list_resources() -> Array:
	return []
