ctf_core = {
	settings = {
		-- server_mode = core.settings:get("ctf_server_mode") or "play",
		server_mode = core.settings:get_bool("creative_mode", false) and "mapedit" or "play",
		low_ram_mode = core.settings:get("ctf_low_ram_mode") == "true" or false,
	}
}

---@param files table
-- Returns dofile() return values in order that files are given
--
-- Example: local f1, f2 = ctf_core.include_files("file1", "file2")
function ctf_core.include_files(...)
	local PATH = core.get_modpath(core.get_current_modname()) .. "/"
	local returns = {}

	for _, file in pairs({...}) do
		for _, value in pairs{dofile(PATH .. file)} do
			table.insert(returns, value)
		end
	end

	return unpack(returns)
end

ctf_core.include_files(
	"helpers.lua",
	"privileges.lua",
	"cooldowns.lua"
)
