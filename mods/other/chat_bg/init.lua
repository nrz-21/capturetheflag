local hud = mhud.init()

local S = core.get_translator(core.get_current_modname())

local function get_val(val, default)
	if not val or val == "" then
		return default
	else
		return val
	end
end

local function lim(val, min, max)
	return math.max(math.min(val, max), min)
end

local function update_hud(player)
	local meta = player:get_meta()

	if get_val(meta:get_string("chat_bg:enabled"), false) then
		local opacity = get_val(meta:get_string("chat_bg:opacity"), 110)
		local width   = get_val(meta:get_string("chat_bg:width"  ), 35 )
		local height  = get_val(meta:get_string("chat_bg:height" ), 50 )

		if not hud:get(player, "chat_bg") then
			hud:add(player, "chat_bg", {
				hud_elem_type = "image",
				z_index = -400,
				position = {x = 0, y = 0},
				alignment = {x = "right", y = "down"},
				scale = {x = -lim(width, 1, 100), y = -lim(height, 1, 100)},
				text = "gui_hb_bg.png^[noalpha^[opacity:"..lim(opacity, 1, 255),
			})
		else
			hud:change(player, "chat_bg", {
				scale = {x = -lim(width, 1, 100), y = -lim(height, 1, 100)},
				text = "gui_hb_bg.png^[noalpha^[opacity:"..lim(opacity, 1, 255),
			})
		end
	end
end

core.register_on_joinplayer(function(player)
	update_hud(player)
end)

local cmd = chatcmdbuilder.register("chat_bg", {
	description = S("Manage the chat background"),
	params = S("toggle | set <opacity | width | height> <1-255 | 1-100 | 1-100>")
})

cmd:sub("toggle", function(name)
	local player = core.get_player_by_name(name)
	if player then
		local meta = player:get_meta()
		local current = get_val(meta:get_string("chat_bg:enabled"), false)

		if current then
			meta:set_string("chat_bg:enabled", "")
			hud:remove(player, "chat_bg")
		else
			meta:set_string("chat_bg:enabled", "yes")
			update_hud(player)
		end


		return true, S("Hud Toggled to") .. " " .. (current and "off state" or "on state")
	else
		return false, S("Unable to find your player object")
	end
end)

cmd:sub("set :setting :value:int", function(name, setting, value)
	local player = core.get_player_by_name(name)

	if player then
		local meta = player:get_meta()

		if setting == "opacity" or setting == "width" or setting == "height" then
			meta:set_string("chat_bg:"..setting, value == 0 and "" or value)

			update_hud(player)

			return true, S("Set @1 to @2", setting, value == 0 and "default" or lim(value, 1, 255))
		else
			return false, S("Invalid setting '@1'. Avaliable settings: opacity, width, height", setting)
		end
	else
		return false, S("Unable to find your player object")
	end
end)
