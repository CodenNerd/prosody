local sasl = require "util.sasl";
local json = require "util.json"

-- profile * mechanism
-- callbacks could use spies instead

describe("util.sasl", function ()
	describe("plain_test profile", function ()
		local profile = {
			plain_test = function (_, username, password, realm)
				assert.equals("user", username)
				assert.equals("pencil", password)
				assert.equals("sasl.test", realm)
				return true, true;
			end;
		};
		it("works with PLAIN", function ()
			local plain = sasl.new("sasl.test", profile);
			assert.truthy(plain:select("PLAIN"));
			assert.truthy(plain:process("\000user\000pencil"));
			assert.equals("user", plain.username);
		end);
	end);

	describe("plain profile", function ()
		local profile = {
			plain = function (_, username, realm)
				assert.equals("user", username)
				assert.equals("sasl.test", realm)
				return "pencil", true;
			end;
		};

		it("works with PLAIN", function ()
			local plain = sasl.new("sasl.test", profile);
			assert.truthy(plain:select("PLAIN"));
			assert.truthy(plain:process("\000user\000pencil"));
			assert.equals("user", plain.username);
		end);

		-- TODO SCRAM
	end);

	describe("oauthbearer profile", function()
		local profile = {
			oauthbearer = function(_, token, _realm, _authzid)
				if token == "example-bearer-token" then
					return "user", true, {};
				else
					return nil, nil, { oidc_discovery_url = "https://auth.example.com/.well-known/oauth-authorization-server" }
				end
			end;
		}

		it("works with OAUTHBEARER", function()
			local bearer = sasl.new("sasl.test", profile);

			assert.truthy(bearer:select("OAUTHBEARER"));
			assert.equals("success", bearer:process("n,,\1auth=Bearer example-bearer-token\1\1"));
			assert.equals("user", bearer.username);
		end)


		it("returns extras with OAUTHBEARER on invalid token", function()
			local bearer = sasl.new("sasl.test", profile);

			assert.truthy(bearer:select("OAUTHBEARER"));
			local status, extra = bearer:process("n,,\1auth=Bearer unknown\1\1");
			assert.equals("challenge", status, tostring(extra));
			assert.same({
				status = "invalid_token";
				["openid-configuration"] = "https://auth.example.com/.well-known/oauth-authorization-server";
			}, json.decode(extra));
			assert.equals("failure", bearer:process("\1"));
		end)

		it("returns extras with OAUTHBEARER with empty auth header", function()
			local bearer = sasl.new("sasl.test", profile);

			assert.truthy(bearer:select("OAUTHBEARER"));
			local status, extra = bearer:process("n,,\1auth=\1\1");
			assert.equals("challenge", status, tostring(extra));
			assert.same({
				status = "invalid_token";
				["openid-configuration"] = "https://auth.example.com/.well-known/oauth-authorization-server";
			}, json.decode(extra));
			assert.equals("failure", bearer:process("\1"));
		end)

		it("returns extras with OAUTHBEARER without auth header", function()
			local bearer = sasl.new("sasl.test", profile);

			assert.truthy(bearer:select("OAUTHBEARER"));
			local status, extra = bearer:process("n,,\1\1");
			assert.equals("challenge", status, tostring(extra));
			assert.same({
				status = "invalid_token";
				["openid-configuration"] = "https://auth.example.com/.well-known/oauth-authorization-server";
			}, json.decode(extra));
			assert.equals("failure", bearer:process("\1"));
		end)

		it("allows a minimal initial response", function ()
			local bearer = sasl.new("sasl.test", profile);

			assert.truthy(bearer:select("OAUTHBEARER"));
			local status, extra = bearer:process("\1");
			assert.equals("challenge", status, tostring(extra));
			assert.same({
				status = "invalid_token";
				["openid-configuration"] = "https://auth.example.com/.well-known/oauth-authorization-server";
			}, json.decode(extra));
			assert.equals("failure", bearer:process("\1"));

		end);

		it("rejects responses with malformed framing or stray data", function ()
			-- Anything in the kvpair region that is not key "=" value kvsep is invalid.
			local cases = {
				-- No GS2 header at all
				"\1something\1foo=bar\1";
				-- Stray token before a valid kvpair
				"n,,\1something\1foo=bar\1";
				-- Valid token followed by stray data; must not authenticate
				"n,,\1auth=Bearer example-bearer-token\1something\1";
				-- Missing final kvsep
				"n,,\1auth=Bearer example-bearer-token\1"
			};

			for _, message in ipairs(cases) do
				local bearer = sasl.new("sasl.test", profile);
				assert.truthy(bearer:select("OAUTHBEARER"));
				local status, err = bearer:process(message);
				assert.equals("failure", status, ("%q -> %s"):format(message, tostring(err)));
				assert.equals("malformed-request", err, ("%q"):format(message));
				assert.is_nil(bearer.username, ("%q"):format(message));
			end
		end);
	end)
end);

