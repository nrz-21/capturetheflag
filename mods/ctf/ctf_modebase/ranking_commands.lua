local S = core.get_translator(core.get_current_modname())

local function get_gamemode(param)
	local opt_param, mode_param = ctf_modebase.match_mode(param)

	if mode_param then
		local mode = ctf_modebase.modes[mode_param]
		if mode_param == "all" then
			return "all", nil, opt_param
		elseif not mode then
			return false, S("No such game mode").. ": " .. mode_param
		end

		return mode_param, mode, opt_param
	else
		local current_mode = ctf_modebase:get_current_mode()
		if not current_mode then
			return false, S("The game isn't running")
		end

		return ctf_modebase.current_mode, current_mode, opt_param
	end
end

local function rank(name, mode_name, mode_data, pname)
	if not mode_name then
		return false, mode_data
	end

	if not pname then
		pname = name
	end
	local prank = mode_data.rankings:get(pname) -- [p]layer [rank]

	if not prank then
		return false, S("Player @1 has no rankings in mode @2".."\n", pname, mode_name)
	end

	local return_str = string.format(
		"\tRankings for player %s in mode %s:\n\t", core.colorize("#ffea00", pname), mode_name
	)

	for _, irank in ipairs(mode_data.summary_ranks) do
		return_str = string.format("%s%s: %s,\n\t",
			return_str,
			core.colorize("#63d437", HumanReadable(irank)),
			core.colorize("#ffea00", math.round(prank[irank] or 0))
		)
	end

	for _, pair in pairs({{"kills", "deaths"}, {"score", "kills"}}) do
		return_str = string.format("%s%s: %s,\n\t",
			return_str,
			core.colorize("#63d437", HumanReadable(pair[1].."/"..pair[2])),
			core.colorize("#ffea00", 0.1 * math.round(10 * (
						(prank[pair[1]] or 0   ) /
				math.max(prank[pair[2]] or 0, 1)
			)))
		)
	end

	return_str = string.format("%s%s: %s\n",
		return_str,
		core.colorize("#63d437", "Place"),
		core.colorize("#ffea00", mode_data.rankings:get_place(pname, "score"))
	)

	return true, return_str
end

ctf_core.register_chatcommand_alias("rank", "r", {
	description = S("Get the rank of yourself or a player"),
	params = S("[mode:all | mode:technical modename] <playername>"),
	func = function(name, param)
		local mode_name, mode_data, pname = get_gamemode(param)
		if mode_name == "all" then
			local return_str = string.format(
				"Rankings for player %s in all modes:\n",
				core.colorize("#ffea00", pname or name),
				mode_name
			)

			for _, mode in ipairs(ctf_modebase.modelist) do
				mode_data = ctf_modebase.modes[mode]
				return_str = return_str .. select(2, rank(name, mode, mode_data, pname))
			end
			return true, return_str
		else
			return rank(name, mode_name, mode_data, pname)
		end
	end
})

local donate_timer = {}

ctf_api.register_on_match_end(function()
	donate_timer = {}
end)

ctf_core.register_chatcommand_alias("donate", "d", {
	description = S("Donate your match score to your teammate")..
			"\n"..S("Can be used only once in 2.5 minutes")..
			"\n"..S("Replace <score> with :max or any negative number to donate the maximum amount"),
	params = S("<name [name2 name3 ...]> <score> [message]"),
	func = function(name, param)
		local current_mode = ctf_modebase:get_current_mode()
		if not current_mode or not ctf_modebase.match_started then
			return false, S("The match hasn't started yet!")
		end

		local pnames, score, dmessage = {}, 0, ""
		local pcount, ismessage = 0, false

		for p in string.gmatch(param, "%S+") do
			if ismessage then
				dmessage = dmessage .. " " .. p
			elseif ctf_core.to_number(p) and score == 0 then
				score = p
			elseif p == ":max" and score == 0 then
				score = -1
			else
				local team = ctf_teams.get(p)
				if not team and pcount > 0 then
					dmessage = dmessage .. p
					ismessage = true
				else
					if pnames[p] then
						return false, S("You cannot donate more than once to the same person.")
					end

					if p == name then
						return false, S('You cannot donate to yourself!')
					end

					if not core.get_player_by_name(p) then
						return false, S("Player @1 is not online!", p)
					end

					if team ~= ctf_teams.get(name) then
						return false, S("Player @1 is not on your team!", p)
					end

					pnames[p] = team
					pcount = pcount + 1
				end
			end
		end

		if pcount == 0 then
			return false, S("You should provide the player name!")
		end

		score = ctf_core.to_number(score)
		if not score then
			return false, S("You should provide score amount!")
		end
		score = math.floor(score)

		local cur_score = math.min(
			current_mode.recent_rankings.get(name).score or 0,
			(current_mode.rankings:get(name) or {}).score or 0
		)

		if score < 0 then
			score = math.floor(cur_score / 2 / pcount)
		end

		if score < 5 then
			return false, S("You should donate at least 5 score!")
		end

		local scoretotal = score * pcount

		if scoretotal > cur_score / 2 then
			return false, S("You can donate only half of your match score!")
		end

		if donate_timer[name] and donate_timer[name] + 150 > os.time() then
			local time_diff = donate_timer[name] + 150 - os.time()
			return false, S(
				"You can donate only once in 2.5 minutes! You can donate again in @1m @2s.",
				math.floor(time_diff / 60),
				time_diff % 60)
		end

		dmessage = (dmessage and dmessage ~= "") and (": " .. dmessage) or ""

		if #dmessage > 50 then
			return false, S("The donation message is") .. " " .. (#dmessage - 50) .." ".. S("chars too long!")
		end

		current_mode.recent_rankings.add(name, {score=-scoretotal}, true)
		local names = ""
		for pname, team in pairs(pnames) do
			current_mode.recent_rankings.add(pname, {score=score}, true)
			core.log("action", S(
				"Player '@1' donated @2 score to player '@3'", name, score, pname
			))
			names = names .. pname .. ", "
		end
		names = names:sub(1, -3)
		if pcount > 2 then
			names = string.gsub(names, ", (%S+)$", ", and %1")
		elseif pcount > 1 then
			names = string.gsub(names, ", (%S+)$", " and %1")
		end

		donate_timer[name] = os.time()
		local donate_text = S("@1 donated @2 score to @3@4", name, score, names, dmessage)

		core.chat_send_all(core.colorize("#00EEFF", donate_text))
		ctf_modebase.announce(core.get_translated_string("en", donate_text))
		return true
	end
})



local allow_reset = {}
core.register_chatcommand("reset_rankings", {
	description = core.colorize("red", S("Resets rankings of you or another player to nothing")),
	params = S("[mode:technical modename] <playername>"),
	func = function(name, param)
		local mode_name, mode_data, pname = get_gamemode(param)
		if not mode_name or not mode_data then
			return false, mode_data
		end

		if pname then
			if core.check_player_privs(name, {ctf_admin = true}) then
				mode_data.rankings:del(pname)

				core.log("action", string.format(
					"[ctf_admin] %s reset rankings for player '%s' in mode %s", name, pname, mode_name
				))
				return true, S("Rankings reset for player '@1' in mode @2", pname, mode_name)
			else
				return false, S("The ctf_admin priv is required to reset the rankings of other players!")
			end
		else
			local key = string.format("%s:%s", mode_name, name)
			if not allow_reset[key] then
				allow_reset[key] = true

				core.after(30, function()
					allow_reset[key] = nil
				end)

				return true, core.colorize("red", S("This will reset your").." (") ..
					core.colorize("cyan", name) ..
					core.colorize("red", ") "..S("stats and rankings for")) .." "..
					core.colorize("cyan", mode_name) ..
					core.colorize("red", " " ..S("mode completely.").."\n") ..
					S("You will lose access to any special privileges such as the") .." "..
					S("team chest or userlimit skip. This is irreversable. If you're") .." "..
					S("sure, re-type /reset_rankings within 30 seconds to reset.")
			end
			mode_data.rankings:del(name)
			allow_reset[key] = nil

			core.log("action", string.format(
				"Player '%s' reset their rankings in mode %s", name, mode_name
			))
			return true, S("Your rankings have been reset")
		end
	end
})

core.register_chatcommand("top50", {
	description = S("Show the top 50 players"),
	params = "[mode:technical modename]",
	func = function(name, param)
		local mode_name, mode_data = get_gamemode(param)
		if not mode_name or not mode_data then
			return false, mode_data
		end

		local top50 = {}

		for i, info in ipairs(mode_data.rankings:get_top(50, "score")) do
			local t = mode_data.rankings:get(info[1]) or {}
			t.pname = info[1]
			t.number = i
			table.insert(top50, t)
		end

		local own_pos = mode_data.rankings:get_place(name, "score")
		if own_pos and own_pos > 50 then
			local t = table.copy(mode_data.rankings:get(name) or {})
			t.pname = name
			t.number = own_pos
			table.insert(top50, t)
		end

		mode_data.summary_ranks._sort = "score"
		ctf_modebase.summary.show_gui_sorted(name, top50, {}, mode_data.summary_ranks, {
			title = S("Top 50 Players"),
			gamemode = mode_name,
			-- disable_nonuser_colors = true,
		})
	end,
})

core.register_chatcommand("make_pro", {
	description = S("Make yourself or another player a pro (Will break target player's ranks)"),
	params = S("[mode:technical modename] <playername>"),
	privs = {ctf_admin = true},
	func = function(name, param)
		local mode_name, mode_data, pname = get_gamemode(param)
		if not mode_name or not mode_data then
			return false, mode_data
		end

		if not pname then
			return false, S("You should provide the player name!")
		end

		local old_ranks = mode_data.rankings:get(pname)
		local note = ""
		if not old_ranks then
			note = " "..S("Note: Player '@1' had no rankings before that.", pname)
		end

		mode_data.rankings:set(pname, {score = 8000, kills = 7, deaths = 5, flag_captures = 5})

		core.log("action", string.format(
			"[ctf_admin] %s made player '%s' a pro in mode %s: %s", name, pname, mode_name, dump(old_ranks)
		))
		return true, S("Player '@1' is now a pro.@2", pname, note)
	end
})

core.register_chatcommand("add_score", {
	description = S("Add score to player"),
	params = S("[mode:technical modename] <playername> <score>"),
	privs = {ctf_admin = true},
	func = function(name, param)
		local mode_name, mode_data, opt_param = get_gamemode(param)
		if not mode_name then
			return false, mode_data
		end

		local pname, score = string.match(opt_param or "", "^(.*) (.*)$")

		if not pname then
			return false, S("You should provide the player name!")
		end

		score = ctf_core.to_number(score)
		if not score then
			return false, S("You should provide score amount!")
		end

		local old_ranks = mode_data.rankings:get(pname)
		local note = ""
		if not old_ranks then
			note = " "..S("Note: Player '@1' had no rankings before that.", pname)
		end

		mode_data.rankings:add(pname, {score = score})

		core.log("action", string.format(
			"[ctf_admin] %s added %s score to player '%s' in mode %s", name, score, pname, mode_name
		))
		return true, S("Added @1 score to player '@2'.@3", score, pname, note)
	end
})

core.register_chatcommand("transfer_rankings", {
	description = S("Transfer rankings of one player to another."),
	params = "<src> <dest>",
	privs = {ctf_admin = true},
	func = function(name, param)
		local src, dst = param:trim():match("^(.*) (.*)$")

		if not src then
			return false, S("You should provide source player name!")
		end
		if not dst then
			return false, S("You should provide destination player name!")
		end

		local src_rankings = {}
		local dst_rankings = {}
		local src_exists = false
		local dst_exists = false

		for mode_name, mode in pairs(ctf_modebase.modes) do
			local src_rank = mode.rankings:get(src)
			src_rankings[mode_name] = src_rank or {}
			if src_rank then
				src_exists = true
			end

			local dst_rank = mode.rankings:get(dst)
			dst_rankings[mode_name] = dst_rank or {}
			if dst_rank then
				dst_exists = true
			end
		end

		local note = ""
		if not src_exists then
			return false, S("Source player '@1' has no rankings!", src)
		end
		if not dst_exists then
			note = " "..S("Note: Destination player '@1' had no rankings.", dst)
		end

		if src == dst then
			return false, S("Source name and destination name cannot be the same!")
		end

		for mode_name, mode in pairs(ctf_modebase.modes) do
			mode.rankings:set(dst, src_rankings[mode_name], true)
		end

		for _, mode in pairs(ctf_modebase.modes) do
			mode.rankings:del(src)
		end

		core.log("action", string.format(
			"[ctf_admin] %s transferred rankings from '%s' to '%s': %s -> %s | %s",
			name, src, dst, dump(src_rankings), dump(dst_rankings), note
		))
		return true, S("Rankings of '@1' have been transferred to '@2'.@3", src, dst, note)
	end
})
