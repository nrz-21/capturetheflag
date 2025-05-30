local CURRENT_MAP_VERSION = "3"

local modname = core.get_current_modname()

local IS_RUNTIME = true
core.after(0, function()
	IS_RUNTIME = false
end)

function ctf_map.skybox_exists(subdir)
	local list = core.get_dir_list(subdir, true)

	return table.indexof(list, "skybox") ~= -1
end

-- calc_flag_center() calculates the center of a map from the positions of the flags.
local function calc_flag_center(map)
	local flag_center = vector.zero()
	local flag_count = 0

	for _, team in pairs(map.teams) do
		flag_center = flag_center + team.flag_pos
		flag_count = flag_count + 1
	end

	flag_center = flag_center:apply(function(value)
		return value / flag_count
	end)

	return flag_center
end

function ctf_map.load_map_meta(idx, dirname)
	assert(ctf_map.map_path[dirname], "Map "..dirname.." not found")

	local meta = Settings(ctf_map.map_path[dirname] .. "/map.conf")

	if not meta then error("Map '"..dump(dirname).."' not found") end

	core.log("info", "load_map_meta: Loading map meta from '" .. dirname .. "/map.conf'")

	local map
	local offset = vector.new(608 * idx, 0, 0) -- 608 is a multiple of 16, the size of a mapblock

	if not meta:get("map_version") then
		if not meta:get("r") then
			error("Map was not properly configured: " .. ctf_map.map_path[dirname] .. "/map.conf")
		end

		local mapr = meta:get("r")
		local maph = meta:get("h")
		local start_time = meta:get("start_time")
		local time_speed = meta:get("time_speed")
		local initial_stuff = meta:get("initial_stuff")

		offset.y = -maph / 2

		local offset_to_new = vector.new(mapr, maph/2, mapr)

		local pos1 = offset
		local pos2 = vector.add(offset, vector.new(mapr * 2,  maph, mapr * 2))

		map = {
			pos1          = pos1,
			pos2          = pos2,
			rotation      = meta:get("rotation"),
			offset        = offset,
			size          = vector.subtract(pos2, pos1),
			enabled       = not meta:get("disabled", false),
			dirname       = dirname,
			name          = meta:get("name"),
			author        = meta:get("author"),
			hint          = meta:get("hint"),
			license       = meta:get("license"),
			others        = meta:get("others"),
			base_node     = meta:get("base_node"),
			initial_stuff = initial_stuff and initial_stuff:split(","),
			treasures     = meta:get("treasures"),
			skybox        = "none",
			start_time    = start_time and tonumber(start_time) or ctf_map.DEFAULT_START_TIME,
			time_speed    = time_speed and tonumber(time_speed) or 1,
			phys_speed    = tonumber(meta:get("phys_speed")),
			phys_jump     = tonumber(meta:get("phys_jump")),
			phys_gravity  = tonumber(meta:get("phys_gravity")),
			chests        = {},
			teams         = {},
			barrier_area  = {pos1 = pos1, pos2 = pos2},
		}

		-- Read teams from config
		local i = 1
		while meta:get("team." .. i) do
			local tname  = meta:get("team." .. i)
			local tpos   = core.string_to_pos(meta:get("team." .. i .. ".pos"))

			map.teams[tname] = {
				enabled = true,
				flag_pos = vector.add(offset, vector.add( tpos, offset_to_new )),
				pos1 = vector.new(),
				pos2 = vector.new()
			}

			i = i + 1
		end

		-- Read custom chest zones from config
		i = 1
		core.log("verbose", "Parsing chest zones of " .. map.name .. "...")
		while meta:get("chests." .. i .. ".from") do
			local from  = core.string_to_pos(meta:get("chests." .. i .. ".from"))
			local to    = core.string_to_pos(meta:get("chests." .. i .. ".to"))
			assert(from and to, "Positions needed for chest zone " ..
					i .. " in map " .. map.name)

			from, to = vector.sort(from, to)

			map.chests[i] = {
				pos1   = vector.add(offset, vector.add(from, offset_to_new)),
				pos2   = vector.add(offset, vector.add(to,   offset_to_new)),
				amount = tonumber(meta:get("chests." .. i .. ".n") or "20"),
			}

			i = i + 1
		end

		-- Add default chest zone if none given
		if i == 1 then
			map.chests[i] = {
				pos1 = map.pos1,
				pos2 = map.pos2,
				amount = ctf_map.DEFAULT_CHEST_AMOUNT,
			}
		end
	else
		-- If new items are added also remember to change the table in mapedit_gui.lua
		-- The version number should be updated if you change an item
		local size = core.deserialize(meta:get("size"))

		offset.y = -size.y/2

		map = {
			map_version    = tonumber(meta:get("map_version") or "0"),
			pos1           = offset,
			pos2           = vector.add(offset, size),
			offset         = offset,
			size           = size,
			dirname        = dirname,
			enabled        = meta:get("enabled") == "true",
			name           = meta:get("name"),
			author         = meta:get("author"),
			hint           = meta:get("hint"),
			license        = meta:get("license"),
			others         = meta:get("others"),
			initial_stuff  = core.deserialize(meta:get("initial_stuff")),
			treasures      = meta:get("treasures"),
			skybox         = meta:get("skybox"),
			start_time     = tonumber(meta:get("start_time")),
			time_speed     = tonumber(meta:get("time_speed")),
			phys_speed     = tonumber(meta:get("phys_speed")),
			phys_jump      = tonumber(meta:get("phys_jump")),
			phys_gravity   = tonumber(meta:get("phys_gravity")),
			chests         = core.deserialize(meta:get("chests")),
			teams          = core.deserialize(meta:get("teams")),
			barrier_area   = core.deserialize(meta:get("barrier_area")),
			game_modes     = core.deserialize(meta:get("game_modes")),
			enable_shadows = tonumber(meta:get("enable_shadows") or "0.26"),
		}

		for id, def in pairs(map.chests) do
			map.chests[id].pos1 = vector.add(offset, def.pos1)
			map.chests[id].pos2 = vector.add(offset, def.pos2)
		end

		for id, def in pairs(map.teams) do
			map.teams[id].flag_pos = vector.add(offset, def.flag_pos)

			map.teams[id].pos1 = vector.add(offset, def.pos1)
			map.teams[id].pos2 = vector.add(offset, def.pos2)
		end

		if map.barrier_area then
			map.barrier_area.pos1 = vector.add(offset, map.barrier_area.pos1)
			map.barrier_area.pos2 = vector.add(offset, map.barrier_area.pos2)
		else
			map.barrier_area = {pos1 = map.pos1, pos2 = map.pos2}
		end
	end

	map.flag_center = calc_flag_center(map)

	for _, e in pairs(core.get_dir_list(ctf_map.map_path[dirname], false)) do
		if e:match("%.png") then
			if core.features.dynamic_add_media_startup then
				core.dynamic_add_media({
					filename = dirname .. "_" .. e,
					filepath = ctf_map.map_path[dirname] .. "/" .. e
				}, not IS_RUNTIME and function() end or nil)
			end
		end
	end

	if ctf_map.skybox_exists(ctf_map.map_path[dirname]) then
		skybox.add({dirname, "#ffffff", [5] = "png"})

		for _, e in pairs(core.get_dir_list(ctf_map.map_path[dirname] .. "/skybox/", false)) do
			if e:match("%.png") then
				if core.features.dynamic_add_media_startup then
					core.dynamic_add_media({
						filename = dirname .. e,
						filepath = ctf_map.map_path[dirname] .. "/skybox/" .. e
					}, not IS_RUNTIME and function() end or nil)
				end
			end
		end

		map.skybox = dirname
		map.skybox_forced = true
	end

	return map
end

function ctf_map.save_map(mapmeta)
	local path = core.get_worldpath() .. "/schems/" .. mapmeta.dirname .. "/"
	core.mkdir(path)

	core.chat_send_all(core.colorize(ctf_map.CHAT_COLOR, "Saving Map..."))

	-- Write to .conf
	local meta = Settings(path .. "map.conf")

	mapmeta.pos1, mapmeta.pos2 = vector.sort(mapmeta.pos1, mapmeta.pos2)

	if not mapmeta.offset then
		mapmeta.offset = mapmeta.pos1
	end

	for id, def in pairs(mapmeta.chests) do
		def.pos1, def.pos2 = vector.sort(def.pos1, def.pos2)

		mapmeta.chests[id].pos1 = vector.subtract(def.pos1, mapmeta.offset)
		mapmeta.chests[id].pos2 = vector.subtract(def.pos2, mapmeta.offset)
	end

	for id, def in pairs(mapmeta.teams) do
		-- Remove team from the list if not enabled
		if not def.enabled then
			mapmeta.teams[id] = nil
		else
			core.load_area(def.flag_pos)
			local flagpos = core.find_node_near(def.flag_pos, 3, {"group:flag_bottom"}, true)

			if not flagpos then
				flagpos = def.flag_pos
				core.chat_send_all(core.colorize((core.get_node(flagpos).name == "ignore") and "orange" or "red",
					"Failed to find flag for team " .. id ..
					". Node at given position: " .. dump(core.get_node(flagpos).name)
				))
			end

			mapmeta.teams[id].flag_pos = vector.subtract(
				flagpos,
				mapmeta.offset
			)

			mapmeta.teams[id].pos1 = vector.subtract(def.pos1, mapmeta.offset)
			mapmeta.teams[id].pos2 = vector.subtract(def.pos2, mapmeta.offset)
		end
	end

	local pos1, pos2 = mapmeta.pos1:copy(), mapmeta.pos2:copy()
	local barrier_area = {pos1 = pos1:subtract(mapmeta.offset), pos2 = pos2:subtract(mapmeta.offset)}

	meta:set("map_version"   , CURRENT_MAP_VERSION)
	meta:set("size"          , core.serialize(vector.subtract(mapmeta.pos2, mapmeta.pos1)))
	meta:set("enabled"       , mapmeta.enabled and "true" or "false")
	meta:set("name"          , mapmeta.name)
	meta:set("author"        , mapmeta.author)
	meta:set("hint"          , mapmeta.hint)
	meta:set("license"       , mapmeta.license)
	meta:set("others"        , mapmeta.others)
	meta:set("initial_stuff" , core.serialize(mapmeta.initial_stuff))
	meta:set("treasures"     , mapmeta.treasures or "")
	meta:set("skybox"        , mapmeta.skybox)
	meta:set("start_time"    , mapmeta.start_time)
	meta:set("time_speed"    , mapmeta.time_speed)
	meta:set("phys_speed"    , mapmeta.phys_speed)
	meta:set("phys_jump"     , mapmeta.phys_jump)
	meta:set("phys_gravity"  , mapmeta.phys_gravity)
	meta:set("chests"        , core.serialize(mapmeta.chests))
	meta:set("teams"         , core.serialize(mapmeta.teams))
	meta:set("barrier_area"  , core.serialize(barrier_area))
	meta:set("game_modes"    , core.serialize(mapmeta.game_modes))
	meta:set("enable_shadows", mapmeta.enable_shadows)

	meta:write()

	local filepath = path .. "map.mts"
	if core.create_schematic(mapmeta.pos1, mapmeta.pos2, nil, filepath) then
		core.chat_send_all(core.colorize(ctf_map.CHAT_COLOR, "Saved Map '" .. mapmeta.name .. "' to " .. path))
		core.chat_send_all(core.colorize(ctf_map.CHAT_COLOR,
								"To play, move it to \""..core.get_modpath(modname).."/maps/"..mapmeta.dirname..", "..
								"start a normal ctf game, and run \"/ctf_next -f "..mapmeta.dirname.."\""));
	else
		core.chat_send_all(core.colorize(ctf_map.CHAT_COLOR, "Map Saving Failed!"))
	end
end
