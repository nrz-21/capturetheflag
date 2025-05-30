--
--- Team set/get
--

---@param player string | ObjectRef
function ctf_teams.remove_online_player(player)
	player = PlayerName(player)

	local team = ctf_teams.player_team[player]
	if team then
		if ctf_teams.online_players[team].players[player] then
			ctf_teams.online_players[team].players[player] = nil
			ctf_teams.online_players[team].count = ctf_teams.online_players[team].count - 1
		end
	end
end

---@param player string | ObjectRef
---@param new_team string | nil
---@param force boolean
function ctf_teams.set(player, new_team, force)
	player = PlayerName(player)

	if not new_team then
		ctf_teams.player_team[player] = nil
		return
	end

	assert(type(new_team) == "string", "ctf_teams.set(): new_team must be a string! value: "..dump(new_team))

	local old_team = ctf_teams.player_team[player]
	if not force and old_team == new_team then
		return
	end

	ctf_teams.remove_online_player(player)

	ctf_teams.player_team[player] = new_team
	ctf_teams.online_players[new_team].players[player] = true
	ctf_teams.online_players[new_team].count = ctf_teams.online_players[new_team].count + 1

	RunCallbacks(ctf_teams.registered_on_allocplayer, PlayerObj(player), new_team, old_team)
end

---@param player string | ObjectRef
---@return nil | string
function ctf_teams.get(player)
	player = PlayerName(player)

	return ctf_teams.player_team[player]
end

--
--- Allocation
--

local tpos = 1
function ctf_teams.default_team_allocator(player)
	if #ctf_teams.current_team_list <= 0 then return end -- No teams initialized yet
	player = PlayerName(player)

	if ctf_teams.player_team[player] then
		return ctf_teams.player_team[player]
	end

	local team = ctf_teams.current_team_list[tpos]

	if tpos >= #ctf_teams.current_team_list then
		tpos = 1
	else
		tpos = tpos + 1
	end

	return team
end
ctf_teams.team_allocator = ctf_teams.default_team_allocator

---@param player string | ObjectRef
---@param force boolean [optional]
---@return nil | string
function ctf_teams.allocate_player(player, force)
	player = PlayerName(player)
	local team = ctf_teams.team_allocator(player)

	ctf_teams.set(player, team, force)

	return team
end

---@param teams table
-- Should be called at match start
function ctf_teams.allocate_teams(teams)
	ctf_teams.player_team = {}
	ctf_teams.online_players = {}
	ctf_teams.current_team_list = {}
	tpos = 1

	for teamname, def in pairs(teams) do
		ctf_teams.online_players[teamname] = {count = 0, players = {}}
		table.insert(ctf_teams.current_team_list, teamname)
	end

	local unallocatedPlayers = core.get_connected_players()
	if #ctf_teams.parties ~= 0 then
		-- Remove any parties that are too big
		ctf_teams.deleteOversizedParties()
		-- This function will allocate party players into teams
		-- and also remove players in parties who have been allocated from the table
		unallocatedPlayers = ctf_teams.allocate_parties(unallocatedPlayers)
	end
	table.shuffle(unallocatedPlayers)

	for _, player in ipairs(unallocatedPlayers) do
		ctf_teams.allocate_player(player)
	end
end

--
--- Other
--

---@param teamname string Name of team
---@return boolean | table,table
--- Returns 'false' if there is no current map.
---
--- Example usage: `pos1, pos2 = ctf_teams.get_team_territory("red")`
function ctf_teams.get_team_territory(teamname)
	local current_map = ctf_map.current_map
	if not current_map or not current_map.teams[teamname] then return false end

	return current_map.teams[teamname].pos1, current_map.teams[teamname].pos2
end

---@param teamname string Name of team
---@param message string message to send
--- Like `core.chat_send_player()` but sends to all members of the given team
function ctf_teams.chat_send_team(teamname, message)
	assert(teamname and message, "Incorrect usage of chat_send_team()")

	for player in pairs(ctf_teams.online_players[teamname].players) do
		core.chat_send_player(player, message)
	end
end

--- Like `core.get_connected_players()` but leaves out players that aren't in a team
function ctf_teams.get_connected_players()
	local out = core.get_connected_players()

	for k, v in ipairs(table.copy(out)) do
		if not ctf_teams.get(v) then
			table.remove(out, table.indexof(out, v))
		end
	end

	return out
end