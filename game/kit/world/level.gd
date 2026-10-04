class_name Level
extends Node3D
## The root of every level scene. A level needs: ground to stand on, light, and at least one spawn point (a
## Marker3D in the "spawn" group). Everything else (collectibles, NPCs, props, portals) is optional.
## `make new-level ID=x` copies the template level for you.

@export var level_id := ""
