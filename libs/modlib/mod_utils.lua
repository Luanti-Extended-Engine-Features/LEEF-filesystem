
function mtul.utils.get_resource(modname, resource, ...)
	if not resource then
		resource = modname
		modname = minetest.get_current_modname()
	end
	return table.concat({minetest.get_modpath(modname), resource, ...}, "/")
end
local function trim_spacing(text)
	return text:match"^%s*(.-)%s*$"
end
--I will add a file reading lib eventually...
local read_file = mtul.file.read or function(mod, filename)
    local filepath = mtul.utils.get_resource(mod, filename)
    local file, err = io.open(filename, "r")
    if file == nil then return nil, err end
    local content = file:read"*a"
    file:close()
end

local mod_info
function mtul.utils.get_mod_info()
	if mod_info then return mod_info end
	mod_info = {}
	-- TODO validate modnames
	local modnames = minetest.get_modnames()
	for _, mod in pairs(modnames) do
		local info
		local mod_conf = Settings(mtul.utils.get_resource(mod, "mod.conf"))
		if mod_conf then
			info = {}
			mod_conf = mod_conf:to_table()
			local function read_depends(field)
				local depends = {}
				for depend in (mod_conf[field] or ""):gmatch"[^,]+" do
					depends[trim_spacing(depend)] = true
				end
				info[field] = depends
			end
			read_depends"depends"
			read_depends"optional_depends"
		else
			info = {
				description = read_file(mod, "description.txt"),
				depends = {},
				optional_depends = {}
			}
			local depends_txt = read_file(mod, "depends.txt")
			if depends_txt then
                local trimmed = {}
                for key, value in pairs(string.split(depends_txt or "", "\n")) do
                    trimmed[key] = trim_spacing(value)
                end
				for _, dependency in ipairs(trimmed) do
					local modname, is_optional = dependency:match"(.+)(%??)"
					table.insert(is_optional == "" and info.depends or info.optional_depends, modname)
				end
			end
		end
		if info.name == nil then
			info.name = mod
		end
		mod_info[mod] = info
	end
	return mod_info
end
local mod_load_order
function mtul.utils.get_mod_load_order()
	if mod_load_order then return mod_load_order end
	mod_load_order = {}
	local mod_info = mtul.utils.get_mod_info()
	-- If there are circular soft dependencies, it is possible that a mod is loaded, but not in the right order
	-- TODO somehow maximize the number of soft dependencies fulfilled in case of circular soft dependencies
	local function load(mod)
		if mod.status == "loaded" then
			return true
		end
		if mod.status == "loading" then
			return false
		end
		-- TODO soft/vs hard loading status, reset?
		mod.status = "loading"
		-- Try hard dependencies first. These must be fulfilled.
		for depend in pairs(mod.depends) do
			if not load(mod_info[depend]) then
				return false
			end
		end
		-- Now, try soft dependencies.
		for depend in pairs(mod.optional_depends) do
			-- Mod may not exist
			if mod_info[depend] then
				load(mod_info[depend])
			end
		end
		mod.status = "loaded"
		table.insert(mod_load_order, mod)
		return true
	end
	for _, mod in pairs(mod_info) do
		assert(load(mod))
	end
	return mod_load_order
end