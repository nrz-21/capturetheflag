local hud = mhud.init()

local SKIP_DELAY = 50 * 60
local SKIP_INTERVAL = 15 * 60
local VOTING_TIME = 60

local timer = nil
local votes = nil
local voters_count = nil

local voted_skip = false
local flags_hold = 0

ctf_modebase.skip_vote = {}

local S = core.get_translator(core.get_current_modname())

local function add_vote_hud(player)
	hud:add(player, "skip_vote:background", {
		hud_elem_type = "image",
        position = {x = 1, y = 0.5},
        offset = {x = -100, y = 0},
        text = "gui_formbg.png",
        scale = {x = 0.4, y = 0.2}
	})
	hud:add(player, "skip_vote:vote", {
		hud_elem_type = "text",
		position = {x = 1, y = 0.5},
		offset = {x = -100, y = 0},
		text = S("Skip to next match?") .."\n"
			..S("/yes /no or /abstain"),
		color = 0xF235FF
	})
end

function ctf_modebase.skip_vote.start_vote()
	if timer then
		timer:cancel()
		timer = nil
	end

	votes = {}
	voters_count = 0

	for _, player in ipairs(core.get_connected_players()) do
		add_vote_hud(player)
		core.sound_play("ctf_modebase_notification", {
			gain = 0.8,
			pitch = 1.0,
		}, true)
		voters_count = voters_count + 1
	end

	timer = core.after(VOTING_TIME, ctf_modebase.skip_vote.end_vote)
end

function ctf_modebase.skip_vote.end_vote()
	if timer then
		timer:cancel()
		timer = nil
	end

	hud:remove_all()

	local yes = 0
	local no = 0

	for _, vote in pairs(votes) do
		if vote == "yes" then
			yes = yes + 1
		elseif vote == "no" then
			no = no + 1
		end
	end

	votes = nil

	if yes > no then
		core.chat_send_all(S("Vote to skip match passed, @1 to @2", yes, no))

		voted_skip = true
		if flags_hold <= 0 then
			ctf_modebase.summary.set_winner("NO WINNER")

			local match_rankings, special_rankings, rank_values, formdef = ctf_modebase.summary.get()
			formdef.title = S("Match Skipped")

			for _, p in ipairs(core.get_connected_players()) do
				ctf_modebase.summary.show_gui(p:get_player_name(), match_rankings, special_rankings, rank_values, formdef)
			end

			ctf_modebase.start_new_match(5)
		end
	else
		core.chat_send_all(S("Vote to skip match failed, @1 to @2", yes, no))
		timer = core.after(SKIP_INTERVAL, ctf_modebase.skip_vote.start_vote)
	end
end

-- Automatically start a skip vote after 50m, and subsequent votes every 15m
ctf_api.register_on_match_start(function()
	if timer then return end -- There was /vote_skip

	timer = core.after(SKIP_DELAY, ctf_modebase.skip_vote.start_vote)
end)

ctf_api.register_on_match_end(function()
	if timer then
		timer:cancel()
		timer = nil
	end

	hud:remove_all()

	votes = nil

	voted_skip = false
	flags_hold = 0
end)

function ctf_modebase.skip_vote.on_flag_take()
	flags_hold = flags_hold + 1
end

function ctf_modebase.skip_vote.on_flag_drop(count)
	flags_hold = flags_hold - count
	if flags_hold <= 0 and voted_skip then
		ctf_modebase.start_new_match(5)
	end
end

function ctf_modebase.skip_vote.on_flag_capture(count)
	flags_hold = flags_hold - count
	if flags_hold <= 0 and voted_skip then
		voted_skip = false
		timer = core.after(30, ctf_modebase.skip_vote.start_vote)
	end
end

core.register_on_joinplayer(function(player)
	if votes and not votes[player:get_player_name()] then
		add_vote_hud(player)
		voters_count = voters_count + 1
	end
end)

core.register_on_leaveplayer(function(player)
	if votes and not votes[player:get_player_name()] then
		voters_count = voters_count - 1

		if voters_count == 0 then
			ctf_modebase.skip_vote.end_vote()
		end
	end
end)

core.register_chatcommand("vote_skip", {
	description = S("Start a match skip vote"),
	privs = {ctf_admin = true},
	func = function(name, param)
		core.log("action", string.format("[ctf_admin] %s ran /vote_skip", name))

		if not ctf_modebase.in_game then
			return false, S("Map switching is in progress")
		end

		if votes then
			return false, S("Vote is already in progress")
		end

		ctf_modebase.skip_vote.start_vote()

		return true, S("Vote is started")
	end,
})

local function player_vote(name, vote)
	if not votes then
		return false, S("There is no vote in progress")
	end

	if not votes[name] then
		voters_count = voters_count - 1
	end

	votes[name] = vote

	local player = core.get_player_by_name(name)
	if hud:exists(player, "skip_vote:vote") then
		hud:remove(player, "skip_vote:vote")
		hud:remove(player, "skip_vote:background")
	end

	if voters_count == 0 then
		ctf_modebase.skip_vote.end_vote()
	end

	return true
end

ctf_core.register_chatcommand_alias("yes", "y", {
	description = S("Vote yes"),
	privs = {interact = true},
	func = function(name, params)
		return player_vote(name, "yes")
	end
})

ctf_core.register_chatcommand_alias("no", "n", {
	description = S("Vote no"),
	privs = {interact = true},
	func = function(name, params)
		return player_vote(name, "no")
	end
})

ctf_core.register_chatcommand_alias("abstain", "abs", {
	description = S("Vote third party"),
	privs = {interact = true},
	func = function(name, params)
		return player_vote(name, "abstain")
	end
})
