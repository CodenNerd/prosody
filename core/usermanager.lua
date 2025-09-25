-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local modulemanager = require "prosody.core.modulemanager";
local log = require "prosody.util.logger".init("usermanager");
local type = type;
local jid_split = require "prosody.util.jid".split;
local config = require "prosody.core.configmanager";
local sasl_new = require "prosody.util.sasl".new;
local storagemanager = require "prosody.core.storagemanager";

local prosody = _G.prosody;
local hosts = prosody.hosts;

local setmetatable = setmetatable;

local default_provider = "internal_hashed";

local debug = debug;

local _ENV = nil;
-- luacheck: std none

local function new_null_provider()
	local function dummy() return nil, "method not implemented"; end;
	local function dummy_get_sasl_handler() return sasl_new(nil, {}); end
	return setmetatable({name = "null", get_sasl_handler = dummy_get_sasl_handler}, {
		__index = function(self, method) return dummy; end --luacheck: ignore 212
	});
end

local fallback_authz_provider = {
	-- luacheck: ignore 212
	get_jids_with_role = function (role) end;

	get_user_role = function (user) end;
	set_user_role = function (user, role_name) end;

	get_user_secondary_roles = function (user) end;
	add_user_secondary_role = function (user, host, role_name) end;
	remove_user_secondary_role = function (user, host, role_name) end;

	user_can_assume_role = function(user, role_name) end;

	get_jid_role = function (jid) end;
	set_jid_role = function (jid, role) end;

	get_users_with_role = function (role_name) end;
	add_default_permission = function (role_name, action, policy) end;
	get_role_by_name = function (role_name) end;
	get_all_roles = function () end;
};

local provider_mt = { __index = new_null_provider() };

local function initialize_host(host)
	local host_session = hosts[host];

	local authz_provider_name = config.get(host, "authorization") or "internal";

	local authz_mod = modulemanager.load(host, "authz_"..authz_provider_name);
	host_session.authz = authz_mod or fallback_authz_provider;

	if host_session.type ~= "local" then return; end

	host_session.events.add_handler("item-added/auth-provider", function (event)
		local provider = event.item;
		local auth_provider = config.get(host, "authentication") or default_provider;
		if config.get(host, "anonymous_login") then
			log("error", "Deprecated config option 'anonymous_login'. Use authentication = 'anonymous' instead.");
			auth_provider = "anonymous";
		end -- COMPAT 0.7
		if provider.name == auth_provider then
			host_session.users = setmetatable(provider, provider_mt);
		end
		if host_session.users ~= nil and host_session.users.name ~= nil then
			log("debug", "Host '%s' now set to use user provider '%s'", host, host_session.users.name);
		end
	end);
	host_session.events.add_handler("item-removed/auth-provider", function (event)
		local provider = event.item;
		if host_session.users == provider then
			host_session.users = new_null_provider();
		end
	end);
	host_session.users = new_null_provider(); -- Start with the default usermanager provider
	local auth_provider = config.get(host, "authentication") or default_provider;
	if config.get(host, "anonymous_login") then auth_provider = "anonymous"; end -- COMPAT 0.7
	if auth_provider ~= "null" then
		modulemanager.load(host, "auth_"..auth_provider);
	end

end;
prosody.events.add_handler("host-activated", initialize_host, 100);

local function provider_helpers(provider_type)
	local function get_provider(host)
		local host_session = hosts[host];
		if not host_session then
			return nil, "unknown host";
		end
		local provider = host_session[provider_type];
		if not provider then
			return nil, "no "..provider_type.." provider";
		end
		return provider;
	end

	local function get_provider_method(host, method_name)
		local provider, err = get_provider(host);
		if not provider then
			return nil, err;
		end
		local method = provider[method_name];
		if not method then
			return nil, "method not implemented";
		end
		return method;
	end

	local function call_method(host, method_name, log_message, pre_event, post_event, event, ...)
		local method, method_err = get_provider_method(host, method_name);
		if not method then return nil, method_err; end
		if pre_event and prosody.events.fire_event(pre_event, event) ~= nil then
			return nil, event.reason or "prevented by module";
		end
		local ok, err = method(...);
		if not ok then
			return ok, err;
		end
		if log_message then
			log("info", "%s: %s@%s", log_message, event.username, event.host);
		end
		if post_event then
			prosody.events.fire_event(post_event, event);
		end
		return ok, err;
	end

	local function call_quiet_method(host, method_name, ...)
		return call_method(host, method_name, nil, nil, nil, nil, ...);
	end

	return get_provider, get_provider_method, call_method, call_quiet_method;
end

local get_provider, _, call_method, call_quiet_method = provider_helpers("users");

local function test_password(username, host, password)
	return call_quiet_method(host, "test_password", username, password);
end

local function get_password(username, host)
	return call_quiet_method(host, "get_password", username);
end

local function set_password(username, password, host, resource)
	return call_method(host, "set_password", "Account password changed", "pre-user-password-change", "user-password-changed", {
		username = username, host = host, resource = resource
	}, username, password);
end

local function get_account_info(username, host)
	return call_quiet_method(host, "get_account_info", username);
end

local function user_exists(username, host)
	if hosts[host].sessions[username] then
		-- Shortcut for online users, we know they exist :)
		return true;
	end
	return call_quiet_method(host, "user_exists", username);
end

local function create_user(username, password, host)
	return call_method(host, "create_user", "User account created", "pre-create-user", "user-created", {
		username = username, host = host
	}, username, password);
end

local function delete_user(username, host)
	local ok, err = call_method(host, "delete_user", "User account deleted", "pre-delete-user", "user-deleted", {
		username = username, host = host
	}, username);
	if not ok then return nil, err; end
	return storagemanager.purge(username, host);
end

local function user_is_enabled(username, host)
	local ret, err = call_quiet_method(host, "is_enabled", username);
	if ret ~= nil then
		return ret;
	elseif err ~= "method not implemented" then
		return nil, err;
	end

	-- Fallback
	local info, err = get_account_info(username, host);
	if info and info.enabled ~= nil then
		return info.enabled;
	elseif err ~= "method not implemented" then
		-- Storage issues etetc
		return info, err;
	end

	-- API unsupported implies users are always enabled
	return true;
end

local function enable_user(username, host)
	return call_method(host, "enable", "User account enabled", "pre-enable-user", "user-enabled", {
		username = username, host = host
	}, username);
end

local function disable_user(username, host, meta)
	return call_method(host, "disable", "User account disabled", "pre-disable-user", "user-disabled", {
		username = username, host = host, meta = meta
	}, username, meta);
end


local function users(host)
	return call_quiet_method(host, "users");
end

local function get_sasl_handler(host, session)
	return call_quiet_method(host, "get_sasl_handler", session);
end

local _, _, call_authz_method, call_quiet_authz_method = provider_helpers("authz");


local function get_user_role(user, host)
	if type(user) ~= "string" then return false; end
	return call_quiet_authz_method(host, "get_user_role", user);
end

local function set_user_role(user, host, role_name)
	if type(user) ~= "string" then return false; end

	local event = { username = user, host = host, role_name = role_name, role = nil };
	local role, err = call_authz_method(
		host,
		"set_user_role",
		"Account role changed to <"..role_name..">",
		"pre-user-role-change",
		nil,
		event,
		user,
		role_name
	);
	if not role then
		return nil, err;
	end
	event.role = role;
	prosody.events.fire_event("user-role-changed", event);
	return role;
end

local function create_user_with_role(username, password, host, role)
	local ok, err = create_user(username, nil, host);
	if not ok then return ok, err; end

	local role_ok, role_err = set_user_role(username, host, role);
	if not role_ok then
		delete_user(username, host);
		return nil, "Failed to assign role: "..role_err;
	end

	if password then
		local pw_ok, pw_err = set_password(username, password, host);
		if not pw_ok then
			return nil, "Failed to set password: "..pw_err;
		end

		local enable_ok, enable_err = enable_user(username, host);
		if not enable_ok and enable_err ~= "method not implemented" then
			return enable_ok, "Failed to enable account: "..enable_err;
		end
	end

	return true;
end

local function user_can_assume_role(user, host, role_name)
	if type(user) ~= "string" then return false; end
	return call_quiet_authz_method(host, "user_can_assume_role", user, role_name);
end

local function add_user_secondary_role(user, host, role_name)
	if type(user) ~= "string" then return false; end

	local event = { username = user, host = host, role_name = role_name, role = nil };
	local role, err = call_authz_method(
		host,
		"add_user_secondary_role",
		"Account gained role <"..role_name..">",
		"pre-add-user-role",
		"user-role-added",
		event,
		user,
		role_name
	);
	if not role then
		return nil, err;
	end
	event.role = role;
	prosody.events.fire_event("user-role-added", event);
	return role;
end

local function remove_user_secondary_role(user, host, role_name)
	if type(user) ~= "string" then return false; end

	return call_authz_method(
		host,
		"remove_user_secondary_role",
		"Account lost role <"..role_name..">",
		"pre-remove-user-role",
		"user-role-removed",
		{ username = user, host = host, role_name = role_name },
		user,
		role_name
	);
end

local function get_user_secondary_roles(user, host)
	if type(user) ~= "string" then return false; end
	return call_quiet_authz_method(host, "get_user_secondary_roles", user);
end

local function get_jid_role(jid, host)
	local jid_node, jid_host = jid_split(jid);
	if host == jid_host and jid_node then
		return call_quiet_authz_method(host, "get_user_role", jid_node);
	end
	return call_quiet_authz_method(host, "get_jid_role", jid);
end

local function set_jid_role(jid, host, role_name)
	local _, jid_host = jid_split(jid);
	if host == jid_host then
		return nil, "unexpected-local-jid";
	end
	return call_quiet_authz_method(host, "set_jid_role", jid, role_name);
end

local strict_deprecate_is_admin;
local legacy_admin_roles = { ["prosody:admin"] = true, ["prosody:operator"] = true };
local function is_admin(jid, host)
	if strict_deprecate_is_admin == nil then
		strict_deprecate_is_admin = (config.get("*", "strict_deprecate_is_admin") == true);
	end
	if strict_deprecate_is_admin then
		log("error", "Attempt to use deprecated is_admin() API: %s", debug.traceback());
		return false;
	end
	log("warn", "Usage of legacy is_admin() API, which will be disabled in a future build: %s", debug.traceback());
	log("warn", "See https://prosody.im/doc/developers/permissions about the new permissions API");
	local role = get_jid_role(jid, host);
	return role and legacy_admin_roles[role.name] or false;
end

local function get_users_with_role(role, host)
	if type(role) ~= "string" then return false; end
	return call_quiet_authz_method(host, "get_users_with_role", role);
end

local function get_jids_with_role(role, host)
	if type(role) ~= "string" then return false; end
	return call_quiet_authz_method(host, "get_jids_with_role", role);
end

local function get_role_by_name(role_name, host)
	if type(role_name) ~= "string" then return false; end
	return call_quiet_authz_method(host, "get_role_by_name", role_name);
end

local function get_all_roles(host)
	if host and not hosts[host] then return false; end
	return call_quiet_authz_method(host, "get_all_roles");
end

return {
	new_null_provider = new_null_provider;
	initialize_host = initialize_host;
	test_password = test_password;
	get_password = get_password;
	set_password = set_password;
	get_account_info = get_account_info;
	user_exists = user_exists;
	create_user = create_user;
	create_user_with_role = create_user_with_role;
	delete_user = delete_user;
	user_is_enabled = user_is_enabled;
	enable_user = enable_user;
	disable_user = disable_user;
	users = users;
	get_sasl_handler = get_sasl_handler;
	get_provider = get_provider;
	get_user_role = get_user_role;
	set_user_role = set_user_role;
	user_can_assume_role = user_can_assume_role;
	add_user_secondary_role = add_user_secondary_role;
	remove_user_secondary_role = remove_user_secondary_role;
	get_user_secondary_roles = get_user_secondary_roles;
	get_users_with_role = get_users_with_role;
	get_jid_role = get_jid_role;
	set_jid_role = set_jid_role;
	get_jids_with_role = get_jids_with_role;
	get_role_by_name = get_role_by_name;
	get_all_roles = get_all_roles;

	-- Deprecated
	is_admin = is_admin;
};
