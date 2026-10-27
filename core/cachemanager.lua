local config = require "prosody.core.configmanager";
local metric = require "prosody.core.statsmanager".metric;

local cache = require "prosody.util.cache";

local mf_evictions = metric("counter", "prosody_cache_evictions", "", "Number of cache evictions (cache full)", { "cache_name", "host" });

local mf_slots_used = metric("gauge", "prosody_cache_slots_used", "","Cache slots in use", { "cache_name", "host" });
local mf_slots_total = metric("gauge", "prosody_cache_slots_total", "", "Cache slots total", { "cache_name", "host" });

local function new_managed_cache(host, name, default_size, on_evict)
	if host and not prosody.hosts[host] then
		error("Cannot create "..name.." cache for unknown host: "..host);
	end
	host = host or "*";
	local config_size = tonumber(config.get(host or "*", name.."_cache_size") or default_size or 128);
	if not config_size then
		error("Invalid cache size for "..name.." on "..host);
	end
	local size = math.max(config_size, 1);

	local measure_eviction = mf_evictions:with_labels(name, host);

	local caches;
	if host and host ~= "*" then
		caches = host and prosody.hosts[host].caches;
		if not caches then
			caches = {};
			prosody.hosts[host].caches = caches;
		end
	else
		caches = prosody.caches;
		if not caches then
			caches = {};
			prosody.caches = caches; -- luacheck: ignore 122/prosody
		end
	end

	if caches[name] then
		error(
			("Duplicate cache name: %s (%s)"):format(
				name,
				host == "*" and "global" or ("on host "..host)
			)
		);
	end

	local c = cache.new(size, function (key, val, self)
		if (on_evict and on_evict(key, val, self)) ~= false then
			measure_eviction:add(1);
			return true;
		end
		return false;
	end);
	caches[c] = {
		name = name;
		measure_slots_used = mf_slots_used:with_labels(name, host);
		measure_slots_total = mf_slots_total:with_labels(name, host);
	};
	return c;
end

local function delete_managed_cache(host, name)
	host = host or "*";

	local caches;
	if host and host ~= "*" then
		caches = host and prosody.hosts[host].caches;
	else
		caches = prosody.caches;
	end

	if caches and caches[name] then
		caches[name] = nil;
		return true;
	end

	return nil, "cache not found";
end

if prosody then
	prosody.events.add_handler("stats-update", function ()
		if prosody.caches then
			for c, info in pairs(prosody.caches) do
				info.measure_slots_used:set(c:count());
				info.measure_slots_total:set(c.size);
			end
		end
		for _, host_session in pairs(prosody.hosts) do
			if host_session.caches then
				for c, info in pairs(host_session.caches) do
					info.measure_slots_used:set(c:count());
					info.measure_slots_total:set(c.size);
				end
			end
		end
	end);
end

return {
	new_managed_cache = new_managed_cache;
	delete_managed_cache = delete_managed_cache;
};
