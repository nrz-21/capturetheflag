ctf_gui.old_init()

local context = {}

local S = core.get_translator(core.get_current_modname())

local function greet_player(player)
	core.chat_send_player(
		player:get_player_name(),
		core.colorize(ctf_map.CHAT_COLOR, S("Welcome! This server is in mapedit mode.").."\n")
	)
	if not core.check_player_privs(player, "ctf_map_editor") then
		core.chat_send_player(
			player:get_player_name(),
			core.colorize(ctf_map.CHAT_COLOR,
					S("To start, grant yourself \"ctf_map_editor\" "..
					"using \"/grantme ctf_map_editor\". Then run \"/ctf_map editor\""))
		)
	else
		core.chat_send_player(
			player:get_player_name(),
			core.colorize(ctf_map.CHAT_COLOR, S("To start, run \"/ctf_map editor\""))
		)
	end
end

if ctf_core.settings.server_mode == "mapedit" then
	core.register_on_joinplayer(greet_player)
end

local function edit_map(pname, map)
	local p = core.get_player_by_name(pname)

	core.close_formspec(pname, "ctf_map:loading")

	ctf_map.announce_map(map)

	p:set_pos(vector.add(map.pos1, vector.divide(map.size, 2)))

	skybox.set(p, table.indexof(ctf_map.skyboxes, map.skybox)-1)

	physics.set(pname, "ctf_map_editor_speed", {
		speed = map.phys_speed,
		jump = map.phys_jump,
		gravity = map.phys_gravity,
	})

	core.settings:set("time_speed", map.time_speed * 72)
	core.registered_chatcommands["time"].func(pname, tostring(map.start_time))

	core.after(8, core.fix_light, map.pos1, map.pos2)

	context[pname] = map
end

function ctf_map.set_flag_location(pname, teamname, pos)
	if context[pname] == nil then
		return
	end

	if context[pname].teams[teamname] == nil then
		context[pname].teams[teamname] = {}
	end

	context[pname].teams[teamname].flag_pos = pos
end

local function dothenext(time, dir, func)
	core.after(time, function()
		local next = function(dir2)
			dothenext(time, dir2, func)
		end

		func(next, dir)
	end)
end

ctf_map.register_map_command("resave_all", function(name, params)
	local maplist = table.copy(ctf_map.registered_maps)

	dothenext(1, 1, function(next, dir)
		if not maplist[dir] then
			core.chat_send_player(
				name,
				"\n"..core.colorize("green", S("Map resaving done.")).."\n"
			)
			return
		end

		local map = ctf_map.load_map_meta(dir, maplist[dir])


		if map.enabled then
			ctf_map.place_map(map, function()
				edit_map(name, map)

				if context[name].initial_stuff[1] == "none" then
					table.remove(context[name].initial_stuff, 1)
				end

				if context[name].treasures == "none" then
					context[name].treasures = nil
				end

				ctf_map.save_map(context[name])
				context[name] = nil

				next(dir + 1)
			end)
		else
			next(dir + 1)
		end
	end)
end)

function ctf_map.show_map_editor(player)
	if context[player] then
		ctf_map.show_map_save_form(player)
		return
	end

	local maplist = table.copy(ctf_map.registered_maps)
	local maplist_sorted = maplist
	table.sort(maplist_sorted)

	local selected_map = 1
	ctf_gui.old_show_formspec(player, "ctf_map:start", {
		size = {x = 8, y = 10.2},
		title = S("Capture The Flag Map Editor"),
		description = S("Would you like to edit an existing map or create a new one?"),
		privs = {ctf_map_editor = true},
		elements = {
			newmap = {
				type = "button", exit = true, label = S("Create New Map"),
				pos = {"center", 0},
				func = function(pname)
					core.chat_send_player(pname,
							core.colorize(ctf_map.CHAT_COLOR,
									S("Please decide what the size of your map will be ")..
									S("and punch nodes on two opposite corners of it")))
					ctf_map.get_pos_from_player(pname, 2, function(p, positions)
						local pos1, pos2 = vector.sort(positions[1], positions[2])

						context[p] = {
							pos1          = pos1,
							pos2          = pos2,
							enabled       = false,
							dirname       = "new_map",
							name          = "My New Map",
							author        = player,
							hint          = "hint",
							license       = "CC-BY",
							others        = "Other info",
							base_node     = "ctf_map:cobble",
							initial_stuff = {},
							treasures     = "none",
							skybox        = "none",
							-- Also see the save form for defaults
							start_time    = ctf_map.DEFAULT_START_TIME,
							time_speed    = 1,
							phys_speed    = 1,
							phys_jump     = 1,
							phys_gravity  = 1,
							--
							chests        = {},
							teams         = {},
							--
							game_modes    = {},
						}

						core.chat_send_player(pname, core.colorize(ctf_map.CHAT_COLOR,
								S("Build away! When you are done, run \"/ctf_map editor\"")))
					end)
				end,
			},
			currentmaps = {
				type = "textlist",
				pos = {"center", 1.7},
				size = {6, 6},
				items = maplist_sorted,
				func = function(pname, fields)
					local event = core.explode_textlist_event(fields.currentmaps)

					if event.type ~= "INV" then
						selected_map = event.index
					end
				end,
			},
			editexisting = {
				type = "button", exit = true, label = S("Start Editing"),
				pos = {0.1, 7.8},
				func = function(pname, fields)
					core.after(0.1, function()
						ctf_gui.old_show_formspec(pname, "ctf_map:loading", {
							size = {x = 6, y = 4},
							title = S("Capture The Flag Map Editor"),
							description = S("Placing map") .. " '" ..
								maplist_sorted[selected_map].. "'. " .. S("This will take a few seconds...")
						})
					end)

					core.after(0.5, function()
						local idx = table.indexof(maplist, maplist_sorted[selected_map])
						local map = ctf_map.load_map_meta(idx, maplist_sorted[selected_map])

						ctf_map.place_map(map, function()
								core.after(2, edit_map, pname, map)
						end)
					end)
				end,
			},
			resume_edit = {
				type = "button", exit = true, label = S("Resume Editing"),
				pos = {(8-ctf_gui.ELEM_SIZE.x) - 0.3, 7.8},
				func = function(pname, fields)
					core.after(0.1, function()
						ctf_gui.old_show_formspec(pname, "ctf_map:loading", {
							size = {x = 6, y = 4},
							title = S("Capture The Flag Map Editor"),
							description = S("Resuming map") .. " '" ..maplist_sorted[selected_map].."'.\n"..
									S("(Remember that this doesn't recall setting changes)")
						})
					end)

					core.after(0.5, function()
						local idx = table.indexof(maplist, maplist_sorted[selected_map])
						local map = ctf_map.load_map_meta(idx, maplist_sorted[selected_map])

						core.after(2, edit_map, pname, map)
					end)
				end,
			},
		}
	})
end

function ctf_map.show_map_save_form(player, scroll_pos)
	if not context[player] then
		core.log("error", "Cannot show save form because "..player.." is not editing a map!")
		return
	end

	if not context[player].teams then
		context[player].teams = {}
	end

	for name in pairs(ctf_teams.team) do
		if not context[player].teams[name] then
			context[player].teams[name] = {
				enabled = false,
				flag_pos = vector.new(),
				pos1 = vector.new(),
				pos2 = vector.new(),
			}
		end
	end

	local elements = {}

	-- MAP CORNERS
	elements.positions = {
		type = "button", exit = true,
		label = S("Corners") .." - ".. core.pos_to_string(context[player].pos1, 0) ..
				" - " .. core.pos_to_string(context[player].pos2, 0),
		pos = {0, 0.5},
		size = {10 - (ctf_gui.SCROLLBAR_WIDTH + 0.1), ctf_gui.ELEM_SIZE.y},
		func = function(pname)
			ctf_map.get_pos_from_player(pname, 2, function(p, positions)
				context[p].pos1 = positions[1]
				context[p].pos2 = positions[2]
			end)
		end,
	}

	-- MAP ENABLED
	elements.enabled = {
		type = "checkbox", label = S("Map Enabled"), pos = {0, 2}, default = context[player].enabled,
		func = function(pname, fields) context[pname].enabled = fields.enabled == "true" or false end,
	}

	-- FOLDER NAME, MAP NAME, MAP AUTHOR(S), MAP HINT, MAP LICENSE, OTHER INFO
	local ypos = 3
	for name, label in pairs({
			dirname = S("Folder Name"), name = S("Map Name")   , author = S("Map Author(s)"),
			hint    = S("Map Hint")   , license = S("Map License"), others = S("Other Info")
		}) do
		elements[name] = {
			type = "field", label = label,
			pos = {0, ypos}, size = {6, 0.7},
			default = context[player][name],
			func = function(pname, fields)
				context[pname][name] = fields[name]
			end,
		}

		ypos = ypos + 1.4
	end

	-- MAP INITIAL STUFF
	elements.initial_stuff = {
		type = "field", label = S("Map Initial Stuff"), pos = {0, ypos}, size = {6, 0.7},
		default = table.concat(context[player].initial_stuff or {"none"}, ","),
		func = function(pname, fields)
			context[pname].initial_stuff = string.split(fields.initial_stuff:gsub("%s?,%s?", ","), ",")
		end,
	}
	ypos = ypos + 1.4

	-- MAP TREASURES
	elements.treasures = {
		type = "textarea", label = S("Map Treasures"), pos = {0, ypos}, size = {ctf_gui.FORM_SIZE.x-3.6, 2.1},
		default = context[player].treasures,
		func = function(pname, fields)
			context[pname].treasures = fields.treasures
		end,
	}
	ypos = ypos + 3.1

	-- SKYBOX SELECTOR
	elements.skybox_label = {
		type = "label",
		pos = {0, ypos},
		label = (context[player].skybox_forced and S("Skybox: Using the one provided in map folder")) or "Skybox:",
	}

	if not context[player].skybox_forced then
		elements.skybox = {
			type = "dropdown",
			pos = {1.1, ypos-(ctf_gui.ELEM_SIZE.y/2)},
			size = {6, ctf_gui.ELEM_SIZE.y},
			items = ctf_map.skyboxes,
			default_idx = table.indexof(ctf_map.skyboxes, context[player].skybox),
			func = function(pname, fields)
				local oldval = context[pname].skybox
				context[pname].skybox = fields.skybox

				if context[pname].skybox ~= oldval then
					skybox.set(PlayerObj(pname), table.indexof(ctf_map.skyboxes, fields.skybox)-1)
				end
			end,
		}
	end
	ypos = ypos + 1.2

	-- MAP shadows
	elements.enable_shadows = {
		type = "field", label = S("Map Shadow intensity (0.0-1.0)"), pos = {0, ypos},
		size = {4, 0.7}, default = context[player].enable_shadows or "0.26",
		func = function(pname, fields)
			local oldval = context[pname].enable_shadows
			context[pname].enable_shadows = math.max(0, math.min(1, tonumber(fields.enable_shadows or "0.26")))

			if context[pname].enable_shadows ~= oldval then
				PlayerObj(pname):set_lighting({shadows = {intensity = context[pname].enable_shadows}})
			end
		end,
	}
	ypos = ypos + 1.5

	-- MODE SELECTOR
	context[player].game_modes = context[player].game_modes or {}
	local available_game_modes = table.copy(ctf_modebase.modelist)

	for _, v in pairs(context[player].game_modes) do
		table.remove(available_game_modes, table.indexof(available_game_modes, v))
	end

	elements.game_modeslabel = {
		type = "label",
		pos = {0, ypos},
		label = S("Map Modes")
	}
	elements.available_game_modeslabel = {
		type = "label",
		pos = {ctf_gui.FORM_SIZE.x/2 - 0.2, ypos},
		label = S("Available Modes")
	}
	ypos = ypos + 0.3
	elements["game_modes"] = {
		type = "textlist",
		pos = {0, ypos},
		size = {ctf_gui.FORM_SIZE.x/2 - 0.4, 2},
		items = context[player].game_modes,
		func = function(pname, fields)
			local event = core.explode_textlist_event(fields.game_modes)

			if event.type == "DCL" then
				table.remove(context[pname].game_modes, event.index)

				ctf_map.show_map_save_form(pname, core.explode_scrollbar_event(fields.formcontent).value)
			end
		end
	}
	elements.available_game_modes = {
		type = "textlist",
		pos = {ctf_gui.FORM_SIZE.x/2 - 0.2, ypos},
		size = {ctf_gui.FORM_SIZE.x/2 - 0.4, 2},
		items = available_game_modes,
		func = function(pname, fields)
			local event = core.explode_textlist_event(fields.available_game_modes)

			if event.type == "DCL" then
				table.insert(context[pname].game_modes, available_game_modes[event.index])

				ctf_map.show_map_save_form(pname, core.explode_scrollbar_event(fields.formcontent).value)
			end
		end
	}
	ypos = ypos + 3

	-- MAP PHYSICS
	for name, label in pairs({speed = S("Map Movement Speed"), jump = S("Map Jump Height"), gravity = S("Map Gravity")}) do
		elements[name] = {
			type = "field", label = label,
			pos = {0, ypos}, size = {4, 0.7},
			default = context[player]["phys_"..name] or 1,
			func = function(pname, fields)
				local oldval = context[pname]["phys_"..name]
				context[pname]["phys_"..name] = tonumber(fields[name]) or 1

				if context[pname]["phys_"..name] ~= oldval then
					physics.set(pname, "ctf_map_editor_"..name, {[name] = tonumber(fields[name] or 1)})
				end
			end,
		}

		ypos = ypos + 1.4
	end

	-- MAP START TIME
	elements.start_time = {
		type = "field", label = S("Map start_time"), pos = {0, ypos}, size = {4, 0.7},
		default = context[player].start_time or ctf_map.DEFAULT_START_TIME,
		func = function(pname, fields)
			local oldval = context[pname].start_time
			context[pname].start_time = tonumber(fields.start_time or ctf_map.DEFAULT_START_TIME)

			if context[pname].start_time ~= oldval then
				core.registered_chatcommands["time"].func(pname, tostring(context[pname].start_time))
			end
		end,
	}
	ypos = ypos + 1.4

	-- MAP time_speed
	elements.time_speed = {
		type = "field", label = S("Map time_speed (Multiplier)"), pos = {0, ypos},
		size = {4, 0.7}, default = context[player].time_speed or "1",
		func = function(pname, fields)
			local oldval = context[pname].time_speed
			context[pname].time_speed = tonumber(fields.time_speed or "1")

			if context[pname].time_speed ~= oldval then
				core.settings:set("time_speed", context[pname].time_speed * 72)
			end
		end,
	}
	ypos = ypos + 1.4

	-- TEAMS
	local idx = ypos
	for teamname, def in pairs(context[player].teams) do
		elements[teamname.."_checkbox"] = {
			type = "checkbox",
			label = HumanReadable(teamname) .. " " .. S("Team"),
			pos = {0, idx},
			default = def.enabled,
			func = function(pname, fields)
				context[pname].teams[teamname].enabled = fields[teamname.."_checkbox"] == "true" or false
			end,
		}
		idx = idx + 1

		elements[teamname.."_button"] = {
			type = "button",
			exit = true,
			label = S("Set Flag Pos") .. ": " .. core.pos_to_string(def.flag_pos),
			pos = {0.2, idx-(ctf_gui.ELEM_SIZE.y/2)},
			size = {5, ctf_gui.ELEM_SIZE.y},
			func = function(pname, fields)
					ctf_map.get_pos_from_player(pname, 1, function(name, positions)
						local pos = positions[1]
						local node = core.get_node(pos).name

						if string.match(node, "^ctf_modebase:flag_top_.*$") then
							pos = vector.offset(pos, 0, -1, 0)
						elseif node ~= "air" and node ~= "ctf_modebase:flag" then
							pos = vector.offset(pos, 0, 1, 0)
						end

						ctf_map.set_flag_location(pname, teamname, pos)

						local facedir = core.dir_to_facedir(core.get_player_by_name(pname):get_look_dir())
						core.set_node(pos, {name="ctf_modebase:flag", param2=facedir})
						core.set_node(vector.offset(pos, 0, 1, 0), {name="ctf_modebase:flag_top_"..teamname, param2 = facedir})

						core.after(0.1, ctf_map.show_map_save_form, pname,
								core.explode_scrollbar_event(fields.formcontent).value)
					end)
			end,
		}

		elements[teamname.."_teleport"] = {
			type = "button",
			exit = true,
			label = S("Go to pos"),
			pos = {0.2 + 5 + 0.1, idx-(ctf_gui.ELEM_SIZE.y/2)},
			size = {2, ctf_gui.ELEM_SIZE.y},
			func = function(pname)
				PlayerObj(pname):set_pos(context[pname].teams[teamname].flag_pos)
			end,
		}

		idx = idx + 1

		elements[teamname.."_positions"] = {
			type = "button", exit = true,
			label = S("Zone Bounds") .. " - " .. core.pos_to_string(context[player].teams[teamname].pos1, 0) ..
					" - " .. core.pos_to_string(context[player].teams[teamname].pos2, 0),
			pos = {0.2, idx-(ctf_gui.ELEM_SIZE.y/2)},
			size = {9 - (ctf_gui.SCROLLBAR_WIDTH + 0.1), ctf_gui.ELEM_SIZE.y},
			func = function(pname, fields)
				ctf_map.get_pos_from_player(pname, 2, function(p, positions)
					context[pname].teams[teamname].pos1 = positions[1]
					context[pname].teams[teamname].pos2 = positions[2]

					core.after(0.1, ctf_map.show_map_save_form, pname,
							core.explode_scrollbar_event(fields.formcontent).value)
				end)
			end,
		}
		idx = idx + (0.7 / 2) + 0.3 + (0.3 / 2)

		local look_pos = context[player].teams[teamname].look_pos

		elements[teamname .. "_look_pos"] = {
			type = "label",
			label = S("Look position") .. ": " .. (look_pos and vector.to_string(look_pos) or "auto"),
			pos = {0.2, idx},
			-- "The first line of text is now positioned centered exactly at the position specified."
			-- https://github.com/minetest/minetest/blob/480d5f2d51ca8f7c4400b0918bb53b776e4ff440/doc/lua_api.txt#L2929
		}
		idx = idx + (0.3 / 2) + 0.1 + (0.7 / 2)

		local btn_width = (9 - (ctf_gui.SCROLLBAR_WIDTH + 0.1) - 0.1) / 2

		elements[teamname.."_look_pos_auto"] = {
			type = "button",
			label = S("Auto"),
			pos = {0.2, idx - (ctf_gui.ELEM_SIZE.y / 2)},
			size = {btn_width, ctf_gui.ELEM_SIZE.y},

			func = function(pname, fields)
				context[pname].teams[teamname].look_pos = nil

				core.after(0.1, ctf_map.show_map_save_form, pname,
						core.explode_scrollbar_event(fields.formcontent).value)
			end,
		}

		elements[teamname.."_look_pos_choose"] = {
			type = "button",
			label = S("Choose"),
			pos = {0.2 + btn_width + 0.1, idx - (ctf_gui.ELEM_SIZE.y / 2)},
			size = {btn_width, ctf_gui.ELEM_SIZE.y},

			func = function(pname, fields)
				ctf_map.get_pos_from_player(pname, 1, function(_, positions)
					context[pname].teams[teamname].look_pos = positions[1]

					core.after(0.1, ctf_map.show_map_save_form, pname,
							core.explode_scrollbar_event(fields.formcontent).value)
				end)
			end,
			exit = true,
		}

		idx = idx + (0.7 / 2) + 0.3 + (0.7 / 2) + 0.5
	end

	-- CHEST ZONES
	elements.addchestzone = {
		type = "button",
		exit = true,
		label = S("Add Chest Zone"),
		pos = {(5 - 0.2) - (ctf_gui.ELEM_SIZE.x / 2), idx},
		func = function(pname, fields)
			table.insert(context[pname].chests, {
				pos1 = vector.new(),
				pos2 = vector.new(),
				amount = ctf_map.DEFAULT_CHEST_AMOUNT,
			})
			core.after(0.1, ctf_map.show_map_save_form, pname,
					core.explode_scrollbar_event(fields.formcontent).value)
		end,
	}
	idx = idx + 1

	if #context[player].chests > 0 then
		for id, def in pairs(context[player].chests) do
			elements["chestzone_"..id] = {
				type = "button",
				exit = true,
				label = S("Chest Zone").." "..id.." - "..core.pos_to_string(def.pos1, 0) ..
						" - "..core.pos_to_string(def.pos2, 0),
				pos = {0, idx},
				size = {7, ctf_gui.ELEM_SIZE.y},
				func = function(pname, fields)
					if not context[pname].chests[id] then return end

					ctf_map.get_pos_from_player(pname, 2, function(name, new_positions)
						context[pname].chests[id].pos1 = new_positions[1]
						context[pname].chests[id].pos2 = new_positions[2]

						core.after(0.1, ctf_map.show_map_save_form, pname,
								core.explode_scrollbar_event(fields.formcontent).value)
					end)
				end,
			}
			elements["chestzone_chests_"..id] = {
				type = "field",
				label = S("Amount"),
				pos = {7.2, idx},
				size = {1, ctf_gui.ELEM_SIZE.y},
				default = context[player].chests[id].amount,
				func = function(pname, fields)
					if not context[pname].chests[id] then return end

					local newnum = tonumber(fields["chestzone_chests_"..id])
					if newnum then
						context[pname].chests[id].amount = newnum
					end
				end,
			}
			elements["chestzone_remove_"..id] = {
				type = "button",
				exit = true,
				label = "X",
				pos = {8.4, idx},
				size = {ctf_gui.ELEM_SIZE.y, ctf_gui.ELEM_SIZE.y},
				func = function(pname, fields)
					table.remove(context[pname].chests, id)
					core.after(0.1, ctf_map.show_map_save_form, pname,
							core.explode_scrollbar_event(fields.formcontent).value)
				end,
			}
			idx = idx + 1
		end
	end
	idx = idx + 1.5

	-- FINISH EDITING
	elements.finishediting = {
		type = "button",
		exit = true,
		pos = {(5 - 0.2) - (ctf_gui.ELEM_SIZE.x / 2), idx},
		label = S("Finish Editing"),
		func = function(pname)
			core.after(0.1, function()
				if context[pname].initial_stuff[1] == "none" then
					table.remove(context[player].initial_stuff, 1)
				end

				if context[pname].treasures == "none" then
					context[pname].treasures = nil
				end

				ctf_map.save_map(context[pname])
				context[pname] = nil
			end)
		end,
	}

	-- CANCEL EDITING
	elements.cancelediting = {
		type = "button",
		exit = true,
		pos = {ctf_gui.FORM_SIZE.x - ctf_gui.SCROLLBAR_WIDTH - ctf_gui.ELEM_SIZE.x - 1, idx},
		label = S("Cancel Editing"),
		func = function(pname)
			core.after(0.1, function()
				context[pname] = nil
				ctf_map.show_map_editor(player)
			end)
		end,
	}

	-- Show formspec
	ctf_gui.old_show_formspec(player, "ctf_map:save", {
		title = S("Capture The Flag Map Editor"),
		description = S("Save your map or edit the config.").."\n"..S("Remember to press ENTER after writing to a field"),
		privs = {ctf_map_editor = true},
		elements = elements,
		scroll_pos = {y = scroll_pos or 0},
	})
end
