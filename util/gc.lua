local set = require "prosody.util.set";

local known_options = {
	incremental = set.new { "mode", "threshold", "speed", "step_size" };
	generational = set.new { "mode", "minor_threshold", "major_threshold" };
};

if _VERSION == "Lua 5.5" then
	known_options.generational = set.new { "mode", "minor_multiplier", "minor_major_threshold", "major_minor_threshold"  };
elseif _VERSION ~= "Lua 5.4" then
	known_options.generational = nil;
	known_options.incremental:remove("step_size");
end

local function configure(user, defaults)
	local mode = user.mode or defaults.mode or "incremental";
	if not known_options[mode] then
		return nil, "GC mode not supported on ".._VERSION..": "..mode;
	end

	for k, v in pairs(user) do
		if not known_options[mode]:contains(k) then
			return nil, "Unknown GC parameter: "..k;
		elseif k ~= "mode" and type(v) ~= "number" then
			return nil, "parameter '"..k.."' should be a number";
		end
	end

	if mode == "incremental" then
		if _VERSION == "Lua 5.4" then
			collectgarbage(mode,
				user.threshold or defaults.threshold,
				user.speed or defaults.speed,
				user.step_size or defaults.step_size
			);
		elseif _VERSION == "Lua 5.5" then
			collectgarbage(mode);
			collectgarbage("param", "pause", user.threshold or defaults.threshold);
			collectgarbage("param", "stepmul", user.speed or defaults.speed);
			collectgarbage("param", "stepsize", user.step_size or defaults.step_size);
		else
			collectgarbage("setpause", user.threshold or defaults.threshold);
			collectgarbage("setstepmul", user.speed or defaults.speed);
		end
	elseif mode == "generational" then
		if _VERSION == "Lua 5.4" then
			collectgarbage(mode,
				user.minor_threshold or defaults.minor_threshold,
				user.major_threshold or defaults.major_threshold
			);
		elseif _VERSION == "Lua 5.5" then
			collectgarbage(mode);
			collectgarbage("param", "minormul", user.minor_multiplier or defaults.minor_multiplier);
			collectgarbage("param", "majorminor", user.major_minor_threshold or defaults.major_minor_threshold);
			collectgarbage("param", "minormajor", user.minor_major_threshold or defaults.minor_major_threshold);
		end
	end
	return true;
end

return {
	configure = configure;
};
