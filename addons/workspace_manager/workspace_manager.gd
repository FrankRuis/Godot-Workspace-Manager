@tool
extends EditorPlugin

const layout_file: String = "res://.godot/editor/editor_layout.cfg"
const plugin_root: String = "res://addons/workspace_manager/"
const sections: Array[StringName] = [&"EditorNode", &"ScriptEditor"]
const keys: Array[String] = ["open_scenes", "open_scripts", "open_help"]

@onready var editor_interface: EditorInterface
@onready var script_editor: ScriptEditor

var dock: MarginContainer
var workspaces_interface: ItemList
var new_name: LineEdit
var current_workspace: StringName = &""

var switch_requested = false
var scene_queue: Array[String]


func _enter_tree():
	editor_interface = get_editor_interface()
	script_editor = get_editor_interface().get_script_editor()
	
	# Build the dock.
	dock = preload(plugin_root + "workspace_manager.tscn").instantiate()
	new_name = dock.get_node('%NewName')
	
	workspaces_interface = dock.get_node_or_null("%Workspaces")
	for file in get_workspace_files():
		workspaces_interface.add_item(file_to_name(file))
	
	# Buttons.
	var save_button: Button = dock.get_node_or_null("%Save")
	if save_button:
		save_button.pressed.connect(save_current_workspace)
	else:
		push_error("Could not find the Save Workspace button.")
	
	var load_button: Button = dock.get_node_or_null("%Load")
	if load_button:
		load_button.pressed.connect(load_workspace)
	else:
		push_error("Could not find the Create Workspace button.")
	
	var delete_button: Button = dock.get_node_or_null("%Delete")
	if delete_button:
		delete_button.pressed.connect(delete_workspace)
	else:
		push_error("Could not find the Delete Workspace button.")
	
	var create_button: Button = dock.get_node_or_null("%Create")
	if create_button:
		create_button.pressed.connect(create_new_workspace)
	else:
		push_error("Could not find the Create Workspace button.")
	
	# Open the next scene in the scene queue after the previous scene has been opened.
	scene_changed.connect(_open_next_scene.unbind(1))
	
	# Add the dock to the editor.
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)


func create_new_workspace():
	if not new_name:
		push_error("Error while creating new workspace, could not find workspace name input.")
		return
	
	var workspace_name = new_name.text
	if workspace_name:
		workspace_name = workspace_name.to_snake_case()
	else:
		push_error("Error while creating new workspace, no name entered.")
		return
	
	save_workspace(workspace_name)
	workspaces_interface.add_item(workspace_name.capitalize())


func save_current_workspace():
	var selected = workspaces_interface.get_selected_items()
	if selected:
		var workspace_name = workspaces_interface.get_item_text(selected[0])
		save_workspace(workspace_name)
	else:
		push_error("Error while saving current workspace, no workspace selected.")


func save_workspace(workspace_name: String):
	var config = _read_config()
	if not config:
		push_error("Error while saving workspace, could not read current config file.")
		return
	
	var saved_workspace = ConfigFile.new()
	for section in sections.filter(func (e): return e in sections):
		for key in Array(config.get_section_keys(section)).filter(func (e): return e in keys):
			saved_workspace.set_value(section, key, config.get_value(section, key))
	saved_workspace.save(plugin_root + "workspaces/{0}".format([name_to_file(workspace_name)]))
	print("Saved workspace " + workspace_name)


func load_workspace():
	var selected = workspaces_interface.get_selected_items()
	if selected:
		var workspace_name = workspaces_interface.get_item_text(selected[0])
		
		var workspace_config = ConfigFile.new()
		var err = workspace_config.load(plugin_root + "workspaces/" + name_to_file(workspace_name))
		if err != OK:
			push_error("Error while loading " + name_to_file(workspace_name))
			return
		
		var config = _read_config()
		if not config:
			push_error("Error while loading workspace, could not read current config file.")
			return
		
		var open_scenes = editor_interface.get_open_scenes()
		var scenes_to_open = workspace_config.get_value("EditorNode", "open_scenes")
		var scene_titles = []
		for scene_path in scenes_to_open:
			scene_titles.append(scene_path.get_basename().get_file())
		var open_scripts = script_editor.get_open_scripts()
		
		# Save changes.
		var save_err = editor_interface.save_scene()
		if save_err != OK:
			push_error("Error while loading " + name_to_file(workspace_name) + ", could not save changes.")
			return
		
		# Set the config layout.
		for section in sections.filter(func (e): return e in sections):
			for key in Array(config.get_section_keys(section)).filter(func (e): return e in keys):
				config.set_value(section, key, workspace_config.get_value(section, key))
		config.save(layout_file)
		
		# Close all scene tabs.
		if open_scenes:
			# Need to switch to first open scene to prevent crash.
			editor_interface.open_scene_from_path(open_scenes[0])
			
			# Find the scene tab bar and close scenes that are not part of the workspace to load.
			var scene_name = open_scenes[0].get_basename().get_file()
			for child in editor_interface.get_base_control().find_children("*", "TabBar", true, false):
				if child.tab_count and child.get_tab_title(0) == scene_name:
					for i in range(child.tab_count - 1, -1, -1):
						if not child.get_tab_title(i) in scene_titles:
							child.emit_signal('tab_close_pressed', i)
					break
		
		# Open the scenes in the loaded workspace (doesn't work in a loop, so I use the scene_changed signal).
		scene_queue = []
		for scene in scenes_to_open:
			if not scene in open_scenes:
				scene_queue.append(scene)
		switch_requested = true
		call_deferred("_open_next_scene")
		
		# Close all script tabs, then open the scripts in the loaded workspace.
		script_editor._close_all_tabs()
		for script in workspace_config.get_value("ScriptEditor", "open_scripts"):
			editor_interface.edit_resource(load(script))
		
		print("Loaded workspace " + workspace_name)
	else:
		push_error("Error while loading workspace, no workspace selected.")


func _open_next_scene():
	if not switch_requested:
		return
	
	if switch_requested and scene_queue.size() == 0:
		switch_requested = false
		return

	var next_scene = scene_queue.pop_front()
	if next_scene:
		editor_interface.open_scene_from_path(next_scene)


func delete_workspace():
	var selected = workspaces_interface.get_selected_items()
	if selected:
		var workspace_name = workspaces_interface.get_item_text(selected[0])
		DirAccess.remove_absolute(plugin_root + "workspaces/" + name_to_file(workspace_name))
		workspaces_interface.remove_item(selected[0])
		print("Removed workspace " + workspace_name)
	else:
		push_error("Error while deleting workspace, no workspace selected.")


func get_workspace_files():
	var workspace_files = []
	var dir = DirAccess.open(plugin_root + "workspaces")
	dir.list_dir_begin()

	while true:
		var file = dir.get_next()
		if file == "":
			break
		elif not file.begins_with(".") and file.ends_with(".cfg"):
			workspace_files.append(file)

	dir.list_dir_end()
	
	return workspace_files


func file_to_name(file: String):
	return file.substr(10).split(".")[0].capitalize()


func name_to_file(name: String):
	return "workspace_{0}.cfg".format([name.to_snake_case()])


func _read_config():
	var config = ConfigFile.new()
	var err = config.load(layout_file)
	if err != OK:
		push_error("Error while loading res://.godot/editor/editor_layout.cfg")
		return
	
	return config


func _exit_tree():
	remove_control_from_docks(dock)
	dock.free()
