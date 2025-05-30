extends DialogicSubsystem

## Subsystem that manages loading layouts with specific styles applied.

signal style_changed(info:Dictionary)


#region STATE
####################################################################################################

func clear_game_state(_clear_flag := DialogicGameHandler.ClearFlags.FULL_CLEAR) -> void:
	pass


func load_game_state(load_flag := LoadFlags.FULL_LOAD) -> void:
	if load_flag == LoadFlags.ONLY_DNODES:
		return
	load_style(dialogic.current_state_info.get('style', ''))

#endregion


#region MAIN METHODS
####################################################################################################

## This helper method calls load_style, but with the [parameter state_reload] as true,
## which is commonly wanted if you expect a game to already be in progress.
func change_style(style_name := "", is_base_style := true) -> Node:
	return load_style(style_name, null, is_base_style, true)


## Loads a style. Consider using the simpler [method change_style] if you want to change the style while another style is already in use.
## [br] If [param state_reload] is true, the current state will be loaded into a new layout scenes nodes.
## That should not be done before calling start() or load() as it would be unnecessary or cause double-loading.
func load_style(style_name := "", parent: Node = null, is_base_style := true, state_reload := false) -> Node:
	var style := DialogicUtil.get_style_by_name(style_name)

	var signal_info := {'style':style_name}
	dialogic.current_state_info['style'] = style_name

	# is_base_style should only be wrong on temporary changes like character styles
	if is_base_style:
		dialogic.current_state_info['base_style'] = style_name

	var previous_layout := get_layout_node()
	if is_instance_valid(previous_layout) and previous_layout.has_meta('style'):
		signal_info['previous'] = previous_layout.get_meta('style').name

		# If this is the same style and scene, do nothing
		if previous_layout.get_meta('style') == style:
			return previous_layout

		# If this has the same scene setup, just apply the new overrides
		elif previous_layout.get_meta('style') == style.get_inheritance_root() or previous_layout.get_meta('style').get_inheritance_root() == style.get_inheritance_root():
			DialogicUtil.apply_scene_export_overrides(previous_layout, style.get_layer_inherited_info("").overrides)
			var index := 0
			for layer in previous_layout.get_layers():
				DialogicUtil.apply_scene_export_overrides(
					layer,
					style.get_layer_inherited_info(style.get_layer_id_at_index(index)).overrides)
				index += 1

			previous_layout.set_meta('style', style)
			style_changed.emit(signal_info)
			return

		else:
			parent = previous_layout.get_parent()

			previous_layout.get_parent().remove_child(previous_layout)
			previous_layout.queue_free()

	# if this is another style:
	var new_layout := create_layout(style, parent)
	if state_reload:
		# Preserve process_mode on style changes
		if previous_layout:
			new_layout.process_mode = previous_layout.process_mode

		new_layout.ready.connect(reload_current_info_into_new_style)

	style_changed.emit(signal_info)

	return new_layout


## Method that adds a layout scene with all the necessary layers.
## The layout scene will be added to the tree root and returned.
func create_layout(style: DialogicStyle, parent: Node = null) -> DialogicLayoutBase:

	# Load base scene
	var base_scene: DialogicLayoutBase
	var base_layer_info := style.get_layer_inherited_info("")
	if base_layer_info.path.is_empty():
		base_scene = DialogicUtil.get_default_layout_base().instantiate()
	else:
		base_scene = load(base_layer_info.path).instantiate()

	base_scene.name = "DialogicLayout_"+style.name.to_pascal_case()

	# Apply base scene overrides
	DialogicUtil.apply_scene_export_overrides(base_scene, base_layer_info.overrides)

	# Load layers
	for layer_id in style.get_layer_inherited_list():
		var layer := style.get_layer_inherited_info(layer_id)

		if not ResourceLoader.exists(layer.path):
			continue

		var layer_scene: DialogicLayoutLayer = null

		if ResourceLoader.load_threaded_get_status(layer.path) == ResourceLoader.THREAD_LOAD_LOADED:
			layer_scene = ResourceLoader.load_threaded_get(layer.path).instantiate()
		else:
			layer_scene = load(layer.path).instantiate()

		base_scene.add_layer(layer_scene)

		# Apply layer overrides
		DialogicUtil.apply_scene_export_overrides(layer_scene, layer.overrides)

	base_scene.set_meta('style', style)

	if parent == null:
		parent = dialogic.get_parent()
	parent.call_deferred("add_child", base_scene)

	dialogic.get_tree().set_meta('dialogic_layout_node', base_scene)

	return base_scene


## When changing to a different layout scene,
## we have to load all the info from the current_state_info (basically
func reload_current_info_into_new_style() -> void:
	for subsystem in dialogic.get_children():
		subsystem.load_game_state(LoadFlags.ONLY_DNODES)


## Returns the style currently in use
func get_current_style() -> String:
	if has_active_layout_node():
		var style: DialogicStyle = get_layout_node().get_meta('style', null)
		if style:
			return style.name
	return ''


func has_active_layout_node() -> bool:
	return (
		get_tree().has_meta('dialogic_layout_node')
		and is_instance_valid(get_tree().get_meta('dialogic_layout_node'))
		and not get_tree().get_meta('dialogic_layout_node').is_queued_for_deletion()
	)


func get_layout_node() -> DialogicLayoutBase:
	if has_active_layout_node():
		return get_tree().get_meta('dialogic_layout_node')
	return null


## Similar to get_tree().get_first_node_in_group('group_name') but filtered to the active layout node subtree
func get_first_node_in_layout(group_name: String) -> Node:
	var layout_node := get_layout_node()
	if null == layout_node:
		return null
	var nodes := get_tree().get_nodes_in_group(group_name)
	for node in nodes:
		if layout_node.is_ancestor_of(node):
			return node
	return null

#endregion
