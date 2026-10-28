local config = require "prosody.core.configmanager";
local metric = require "prosody.core.statsmanager".metric;

local cache = require "prosody.util.cache";

local mf_evictions = metric("counter", "prosody_cache_evictions", "", "Number of cache evictions (cache full)", { "cache_name", "host" });

local mf_slots_used = metric("gauge", "prosody_cache_slots_used", "","Cache slots in use", { "cache_name", "host" });
local mf_slots_total = metric("gauge", "prosody_cache_slots_total", "", "Cache slots total", { "cache_name", "host" });

-- Caches created by module:new_cache() are removed when their module is unloaded
local function track_module_caches(events, caches)
	events.add_handler("item-removed/cache", function (event)
		local info = caches[event.item.name];
		if info and info.cache == event.item.cache then
			caches[event.item.name] = nil;
		end
	end);
end

local function new_managed_cache(host, name, default_size, on_evict)
	host = host or "*";
	if host ~= "*" and not prosody.hosts[host] then
		error("Cannot create "..name.." cache for unknown host: "..host);
	end
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
			track_module_caches(prosody.hosts[host].events, caches);
		end
	else
		caches = prosody.caches;
		if not caches then
			caches = {};
			prosody.caches = caches; -- luacheck: ignore 122/prosody
			track_module_caches(prosody.events, caches);
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
	caches[name] = {
		cache = c;
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
			for _, info in pairs(prosody.caches) do
				info.measure_slots_used:set(info.cache:count());
				info.measure_slots_total:set(info.cache.size);
			end
		end
		for _, host_session in pairs(prosody.hosts) do
			if host_session.caches then
				for _, info in pairs(host_session.caches) do
					info.measure_slots_used:set(info.cache:count());
					info.measure_slots_total:set(info.cache.size);
				end
			end
		end
	end);
end

return {
	new_managed_cache = new_managed_cache;
	delete_managed_cache = delete_managed_cache;
};
