local S = core.get_translator(core.get_current_modname())

local cmd = chatcmdbuilder.register("ctf_teams", {
	description = S("Team management commands"),
	params = S("set <player> <team> | rset <match pattern> <team>"),
	privs = {
		ctf_team_admin = true,
	}
})

cmd:sub("set :player:username :team", function(name, player, team)
	if core.get_player_by_name(player) then
		if table.indexof(ctf_teams.current_team_list, team) == -1 then
			return false, S("No such team") .. ": " .. team
		end

		ctf_teams.set(player, team)

		return true, S("Allocated @1 to team @2", player, team)
	else
		return false, S("No such player") .. ": " .. player
	end
end)

cmd:sub("rset :pattern :team", function(name, pattern, team)
	if table.indexof(ctf_teams.current_team_list, team) == -1 then
		return false, S("No such team") .. ": " .. team
	end

	local added = {}

	for _, player in pairs(core.get_connected_players()) do
		local pname = player:get_player_name()

		if pname:match(pattern) then
			ctf_teams.set(player, team)
			table.insert(added, pname)
		end
	end

	if #added >= 1 then
		return true, S("Added the following players to team") .. " " .. team .. ": " .. table.concat(added, ", ")
	else
		return false, S("No player names matched the given regex, or all players that matched were locked to a team")
	end
end)

local function get_team_players(team)
	local tcolor = ctf_teams.team[team].color
	local count = 0
	local str = ""

	for player in pairs(ctf_teams.online_players[team].players) do
		count = count + 1
		str = str .. player .. ", "
	end

	return S("Team @1 has @2 players: @3", core.colorize(tcolor, team), count, str:sub(1, -3))
end

core.register_chatcommand("team", {
	description = S("Get team members for 'team' or on which team is 'player' in"),
	params = S("<team> | player <player>"),
	func = function(name, param)
		local _, pos = param:find("^player +")
		if pos then
			local player = param:sub(pos + 1)
			local pteam = ctf_teams.get(player)

			if not pteam then
				return false, S("No such player") .. ": " .. player
			end

			local tcolor = ctf_teams.team[pteam].color
			return true, S("Player @1 is in team @2", player, core.colorize(tcolor, pteam))
		elseif param == "" then
			local str = ""
			for _, team in ipairs(ctf_teams.current_team_list) do
				str = str .. get_team_players(team) .. "\n"
			end
			return true, str:sub(1, -2)
		else
			if table.indexof(ctf_teams.current_team_list, param) == -1 then
				return false, S("No such team") .. ": " .. param
			end

			return true, get_team_players(param)
		end
	end,
})
