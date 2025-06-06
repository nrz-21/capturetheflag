throwable_snow = {}
local S = core.get_translator(core.get_current_modname())

function throwable_snow.on_hit_player(thrower, player)
	core.get_player_by_name(player):punch(
		core.get_player_by_name(thrower),
		2,
		{ damage_groups = {snowball = 1, fleshy = 1} },
		vector.new()
	)

	hud_events.new(player, {
		text = S("@1 hit you with a snowball!", thrower),
		quick = true,
	})
end

local snowball_def = {
	description = S("Snowball"),
	image = "default_snowball.png",
	range = 4,
	collide_with_objects = true,
	stack_max = 99,
	throw_cooldown = 0.9,
	on_explode = function(def, obj, pos, name)
		core.add_particlespawner({
			amount = 9,
			time = 0.01,
			minpos = pos,
			maxpos = pos,
			minvel = {x = -2, y = -1, z = -2},
			maxvel = {x = 2, y = 2, z = 2},
			minacc = {x = 0, y = -9, z = 0},
			maxacc = {x = 0, y = -9, z = 0},
			minexptime = 0.5,
			maxexptime = 1,
			minsize = 0.9,
			maxsize = 1.6,
			collisiondetection = true,
			collision_removal = false,
			vertical = false,
			texture = "default_snow.png",
		})

		core.sound_play("default_snow_footstep", {
			pos = pos,
			gain = 0.8,
			pitch = 3.0,
			max_hear_distance = 16,
		})
	end,
	on_collide = function(def, obj, name, moveresult)
		for _, collision in ipairs(moveresult.collisions) do
			if collision.type == "object" and collision.object:is_player() and core.get_player_by_name(name) then
				throwable_snow.on_hit_player(name, collision.object:get_player_name())
			end
		end
		return true
	end,
	particle = {
		image = "default_snow.png",
		life = 1,
		size = 1,
		glow = 1,
		interval = 0.5,
	}
}

grenades.register_grenade("throwable_snow:snowball", table.copy(snowball_def))

snowball_def.stack_max = -1
grenades.register_grenade("throwable_snow:infinite_snowball", snowball_def)

core.override_item("default:snow", {drop = "throwable_snow:snowball 2"})
