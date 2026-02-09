-- Allow for both require"util.foo" and require"prosody.util.foo" for a
-- transition period while we update all require calls.

if (...) == "prosody.loader" then
	local function is_relative(path)
		local path_sep = package.config:sub(1,1);
		return ((path_sep == "/" and path:sub(1,1) ~= "/")
			or (path_sep == "\\" and (path:sub(1,1) ~= "/" and path:sub(2,3) ~= ":\\")))
	end
	local function filter_relative_paths(path)
		if is_relative(path) then return ""; end
	end
	local function sanitise_paths(paths)
		return (paths:gsub("[^;]+;?", filter_relative_paths):gsub(";;+", ";"));
	end

	-- For require"util.foo" also look in paths equivalent to "prosody.util.foo"
	package.path = sanitise_paths(CFG_SOURCEDIR.."/?.lua;"..package.path:gsub("([^;]*)(?[^;]*)", "%1prosody/%2;%1%2"));
	package.cpath = sanitise_paths(CFG_SOURCEDIR.."/?.so;"..package.cpath:gsub("([^;]*)(?[^;]*)", "%1prosody/%2;%1%2"));
else
	-- When requiring "prosody.x", also look for "x"
	for i = #package.searchers, 1, -1 do
		local search = package.searchers[i];
		table.insert(package.searchers, i, function(module_name)
			local lib = module_name:match("^prosody%.(.*)$");
			if lib then
				return search(lib);
			end
		end)
	end
end

-- Look for already loaded module with or without prefix
setmetatable(package.loaded, {
	__index = function(loaded, module_name)
		local suffix = module_name:match("^prosody%.(.*)$");
		if suffix then
			return rawget(loaded, suffix);
		end
		local prefixed = rawget(loaded, "prosody." .. module_name);
		if prefixed ~= nil then
			return prefixed;
		end
	end;
})
