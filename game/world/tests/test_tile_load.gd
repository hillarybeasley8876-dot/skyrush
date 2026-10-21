extends Node
## Probe: the tiles of the roads, the blocks and the Bund have to be instantiated from the
## imported gltf / glb files (the loader used to skip every imported tile).
## Run: tools/godot.sh test res://world/tests/test_tile_load.gd

const AssetLibrary := preload("res://world/loader/asset_library.gd")

var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	var lib := AssetLibrary.new()
	for spec in [["roads", AssetLibrary.ROADS_DIR, "roads_"],
			["blocks", AssetLibrary.BLOCKS_DIR, "blocks_"],
			["bund", AssetLibrary.BUND_DIR, ""]]:
		var label := String(spec[0])
		var dir_path := String(spec[1])
		var prefix := String(spec[2])
		var files := lib.find_glbs(dir_path, prefix)
		var loaded := 0
		for path in files:
			var node := lib.instantiate_glb(path)
			if node == null:
				continue
			loaded += 1
			var meshes := node.find_children("*", "MeshInstance3D", true, false)
			print("[probe] %s %s -> %d meshes" % [label, path.get_file(), meshes.size()])
			node.free()
		print("[probe] %s: %d of %d tiles instantiated" % [label, loaded, files.size()])
		if loaded == 0 and not files.is_empty():
			_failed += 1
	print("[probe] RESULT %s" % ("FAIL" if _failed > 0 else "PASS"))
	get_tree().quit(1 if _failed > 0 else 0)
