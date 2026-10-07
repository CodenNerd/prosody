local json = require "prosody.util.json";
local _ENV = nil;

local function parse_initial_client_response(message) --> success, string...
	-- kvsep
	if message == "\001" then
		return true;
	end

	local gs2_header, kvpairs = message:match("^(n,[^,]*,)\001(.*)\001$");

	if not gs2_header then
		return false;
	end

	-- gs2-header kvsep *kvpair kvsep
	local gs2_authzid = gs2_header:match("^[^,]*,a=([^,]*),$");

	-- key "=" value kvsep
	local auth_header, consumed = nil, 0;
	for k, v, epos in kvpairs:gmatch("([a-zA-Z]+)=([\033-\126 \009\r\n]*)\001()") do
		consumed = epos - 1;
		if k == "auth" then
			auth_header = v;
		end
	end

	if consumed ~= #kvpairs then
		return false;
	end

	local token;
	if auth_header and auth_header ~= "" then
		token = auth_header:match("^Bearer (.+)$");
		if not token then
			return false;
		end
	end

	return true, token, gs2_authzid;
end

local function oauthbearer(self, message)
	if not message then
		return "failure", "malformed-request";
	end

	if message == "\001" and self.state then
		return "failure", "not-authorized";
	end

	local parsed, token, gs2_authzid = parse_initial_client_response(message);
	if not parsed then
		return "failure", "malformed-request";
	end

	local username, state, token_info = self.profile.oauthbearer(self, token, self.realm, gs2_authzid);

	if state == false then
		return "failure", "account-disabled";
	elseif state == nil or not username then
		-- For token-level errors, RFC 7628 demands use of a JSON-encoded
		-- challenge response upon failure. We relay additional info from
		-- the auth backend if available.
		self.state = true;
		return "challenge", json.encode({
			status = token_info and token_info.status or "invalid_token";
			scope = token_info and token_info.scope or nil;
			["openid-configuration"] = token_info and token_info.oidc_discovery_url or nil;
		});
	end
	self.username = username;
	self.token_info = token_info;

	return "success";
end

local function init(registerMechanism)
	registerMechanism("OAUTHBEARER", {"oauthbearer"}, oauthbearer);
end

return {
	init = init;
}
