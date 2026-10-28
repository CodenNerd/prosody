-- Prosody IM
-- Copyright (C) 2008-2009 Matthew Wild
-- Copyright (C) 2008-2009 Waqas Hussain
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local datetime = require "prosody.util.datetime";
local jid_split = require "prosody.util.jid".split;
local datestamp = require "prosody.util.datetime".date;

local cleanup_after = module:get_option_period("offline_expires_after", "never");

local offline_messages = module:open_store("offline", "archive");

module:add_feature("msgoffline");

function schedule_cleanup(_username, _date) -- luacheck: ignore 212
	-- Called to make a note of which users have messages on which days, which in
	-- turn is used to optimize the message expiry routine.
	--
	-- This noop is conditionally replaced later depending on retention settings
	-- and storage backend capabilities.
end

module:hook("message/offline/handle", function(event)
	local origin, stanza = event.origin, event.stanza;
	local to = stanza.attr.to;
	local node;
	if to then
		node = jid_split(to)
	else
		node = origin.username;
	end

	local ok = offline_messages:append(node, nil, stanza, os.time(), "");
	if ok then
		schedule_cleanup(node);
		module:log("debug", "Saved to offline storage: %v", stanza);
	end
	return ok;
end, -1);

module:hook("message/offline/broadcast", function(event)
	local origin = event.origin;
	origin.log("debug", "Broadcasting offline messages");

	local node, host = origin.username, origin.host;

	local data = offline_messages:find(node);
	if not data then return true; end
	for _, stanza, when in data do
		stanza:tag("delay", {xmlns = "urn:xmpp:delay", from = host, stamp = datetime.datetime(when)}):up(); -- XEP-0203
		origin.send(stanza);
	end
	local ok = offline_messages:delete(node);
	if type(ok) == "number" and ok > 0 then
		origin.log("debug", "%d offline messages consumed");
	end
	return true;
end, -1);

if cleanup_after ~= math.huge then
	local cleanup_storage = module:open_store("offline_cleanup");
	local cleanup_map = module:open_store("offline_cleanup", "map");

	module:log("debug", "offline_expires_after = %d -- in seconds", cleanup_after);

	if not offline_messages.delete then
		module:log("error", "offline_expires_after set but mod_%s does not support deleting", offline_messages._provided_by);
		return false;
	end

	-- For each day, store a set of users that have new messages. To expire
	-- messages, we collect the union of sets of users from dates that fall
	-- outside the cleanup range.

	if not (offline_messages.caps and offline_messages.caps.wildcard_delete) then
		local last_date = module:new_cache("archive_cleanup_date", 1000);
		function schedule_cleanup(username, date)
			date = date or datestamp();
			if last_date:get(username) == date then return end
			local ok = cleanup_map:set(date, username, true);
			if ok then
				last_date:set(username, date);
			end
		end
	end

	local cleanup_time = module:measure("cleanup", "times");

	local async = require "prosody.util.async";
	module:daily("Remove expired offline messages", function ()
		local cleanup_done = cleanup_time();

		if offline_messages.caps and offline_messages.caps.wildcard_delete then
			local ok, err = offline_messages:delete(true, { ["end"] = os.time() - cleanup_after })
			if ok then
				local sum = tonumber(ok);
				if sum then
					module:log("info", "Deleted %d expired messages", sum);
				else
					-- driver did not tell
					module:log("info", "Deleted all expired messages");
				end
			else
				module:log("error", "Could not delete messages: %s", err);
			end
			cleanup_done();
			return;
		end

		local users = {};
		local cut_off = datestamp(os.time() - cleanup_after);
		for date in cleanup_storage:users() do
			if date <= cut_off then
				module:log("debug", "Messages from %q should be expired", date);
				local messages_this_day = cleanup_storage:get(date);
				if messages_this_day then
					for user in pairs(messages_this_day) do
						users[user] = true;
					end
					if date < cut_off then
						-- Messages from the same day as the cut-off might not have expired yet,
						-- but all earlier will have, so clear storage for those days.
						cleanup_storage:set(date, nil);
					end
				end
			end
		end
		local sum, num_users = 0, 0;
		for user in pairs(users) do
			local ok, err = offline_messages:delete(user, { ["end"] = os.time() - cleanup_after; })
			if ok then
				num_users = num_users + 1;
				sum = sum + (tonumber(ok) or 0);
			else
				cleanup_map:set(cut_off, user, true);
				module:log("error", "Could not delete messages for user '%s': %s", user, err);
			end
			local wait, done = async.waiter();
			module:add_timer(0.01, done);
			wait();
		end
		module:log("info", "Deleted %d expired messages for %d users", sum, num_users);
		cleanup_done();
	end);

else
	module:log("debug", "Offline message expiry disabled");
end
