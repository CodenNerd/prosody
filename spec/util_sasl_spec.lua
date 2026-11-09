local sasl = require "util.sasl";
local json = require "util.json"
local base64 = require "util.encodings".base64
local sxor = require"util.strbitop".sxor;
local Normalize = require"util.encodings".stringprep.saslprep;

-- profile * mechanism
-- callbacks could use spies instead

local function test_scram(profile, name, H, HMAC, Hi, extensions, bad_proof, expected_error)
	local plain = sasl.new("sasl.test", profile);
	assert.truthy(plain:select("SCRAM-"..name));
	local gs2_cbind_flag = "n";
	local gs2_header = gs2_cbind_flag .. ",,"; -- no authzid
	local saslname = "user";
	local username = "n=" .. saslname;
	local c_nonce = "fyko+d2lbbFgONRv9qkxdawL";
	local nonce = "r=" .. c_nonce
	local client_first_message_bare = username .. "," .. nonce .. (extensions and "," .. extensions or "");
	local client_first_message = gs2_header .. client_first_message_bare
	local first_status, server_first_message, err = plain:process(client_first_message);
	assert.equals("challenge", first_status, err or server_first_message)
	assert.string(server_first_message);
	local f = server_first_message:match("f=[^,]+")
	if not f then
		assert.matches("r=[^,]+,s=[^,]+,i=%d+", server_first_message);
	else
		assert.matches("r=[^,]+,f=[^,]+", server_first_message);
	end
	nonce = server_first_message:match("r=[^,]+")
	local salt = server_first_message:match("s=[^,]+") or ""
	local iteration_count = server_first_message:match("i=[^,]+") or ""
	assert.matches("r=", nonce)
	assert.equal(c_nonce, nonce:sub(3, #c_nonce + 2))
	if f then
		assert.matches("f=", f)
	else
		assert.matches("s=", salt)
		assert.matches("i=", iteration_count)
	end

	local cbind_input = gs2_header;
	local channel_binding = "c=" .. base64.encode(cbind_input)
	local client_final_message_without_proof = channel_binding .. "," .. nonce;

	local i = tonumber(iteration_count:sub(3))
	local SaltedPassword, err = Hi(Normalize("pencil"), base64.decode(salt:sub(3)), i)
	assert.truthy(SaltedPassword, err)
	if f then
		local mcf_salt =base64.decode(f:sub(3))
		assert.equals(mcf_salt, SaltedPassword:sub(1,#mcf_salt))
	end

	local ClientKey = HMAC(SaltedPassword, "Client Key")
	local StoredKey = H(ClientKey)
	local AuthMessage = client_first_message_bare .. "," .. server_first_message .. "," .. client_final_message_without_proof
	local ClientSignature = HMAC(StoredKey, AuthMessage)
	local ClientProof = sxor(ClientKey, ClientSignature)
	local ServerKey = HMAC(SaltedPassword, "Server Key")
	local ServerSignature = HMAC(ServerKey, AuthMessage)

	local proof = "p=" .. (bad_proof and bad_proof(ClientProof) or base64.encode(ClientProof))
	local client_final_message = client_final_message_without_proof .. "," .. proof;
	local final_status, server_final_message, err = plain:process(client_final_message);

	if bad_proof then
		assert.equals("failure", final_status)
		assert.equals(expected_error, server_final_message)
		return
	end

	assert.equals("success", final_status, err or server_final_message)
	assert.matches("v=[^,]+",server_final_message)
	local verifier = server_final_message:match("v=[^,]+")
	assert.equal(verifier, "v="..base64.encode(ServerSignature), "server signature matched")
end

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

		it("works with SCRAM-SHA-1", function ()
			local Hi = require"prosody.util.hashes".pbkdf2_hmac_sha1;
			local H = require"prosody.util.hashes".sha1;
			local HMAC = require"prosody.util.hashes".hmac_sha1;

			test_scram(profile, "SHA-1", H, HMAC, Hi);
		end)

		it("works with SCRAM-SHA-256", function ()
			local Hi = require"prosody.util.hashes".pbkdf2_hmac_sha256;
			local H = require"prosody.util.hashes".sha256;
			local HMAC = require"prosody.util.hashes".hmac_sha256;

			test_scram(profile, "SHA-256", H, HMAC, Hi);
		end)

		for name, algo in pairs({ ["SHA-1"] = "sha1"; ["SHA-256"] = "sha256" }) do
			local Hi = require"prosody.util.hashes"["pbkdf2_hmac_" .. algo];
			local H = require"prosody.util.hashes"[algo];
			local HMAC = require"prosody.util.hashes"["hmac_" .. algo];

			for description, bad_proof in pairs({
				["invalid base64"] = function () return "!" end;
				["an empty"] = function () return "" end;
				["a too short"] = function (proof) return base64.encode(proof:sub(2)) end;
				["a too long"] = function (proof) return base64.encode(proof .. "\0") end;
			}) do
				it("rejects " .. description .. " proof with SCRAM-" .. name, function ()
					test_scram(profile, name, H, HMAC, Hi, nil, bad_proof, "malformed-request");
				end)
			end

			it("rejects an incorrect proof with SCRAM-" .. name, function ()
				test_scram(profile, name, H, HMAC, Hi, nil, function (proof)
					return base64.encode(("\0"):rep(#proof));
				end, "not-authorized");
			end)
		end
	end);

	describe("scram_sha_1 profile", function()
		local Hi = require"prosody.util.hashes".pbkdf2_hmac_sha1;
		local H = require"prosody.util.hashes".sha1;
		local HMAC = require"prosody.util.hashes".hmac_sha1;

		local profile = {
			scram_sha_1 = function (_, username, realm)
				assert.equals("user", username)
				assert.equals("sasl.test", realm)

				local password = "pencil"
				local iteration_count = 4096;
				local salt = base64.decode("QSXCR+Q6sek8bf92")

				local SaltedPassword = Hi(password, salt, iteration_count)
				local ClientKey = HMAC(SaltedPassword, "Client Key")
				local StoredKey = H(ClientKey)
				local ServerKey = HMAC(SaltedPassword, "Server Key")
				return StoredKey, ServerKey, iteration_count, salt, true;
			end;
		};

		it("works with SCRAM-SHA-1", function ()
			test_scram(profile, "SHA-1", H, HMAC, Hi);
		end)

	end)

	describe("crypt profile", function ()
		local H = require"prosody.util.hashes".sha256;
		local HMAC = require"prosody.util.hashes".hmac_sha256;
		local Hi = function() return "$y$j75$00vQs9624O0VmZoU0ESJq.$tUzH7vku1hX8ejQOpggbysE18gt60o6p4.rMJD1CjN."; end

		local profile = {
			crypt = function (_, username, realm)
				assert.equals("user", username)
				assert.equals("sasl.test", realm)
				return Hi(), true;
			end
		}
		it("works with SCRAM-SHA-256", function ()
			local crypt = sasl.new("sasl.test", profile);
			assert.truthy(crypt:select("SCRAM-SHA-256"))
			local status, server_first_message, err = crypt:process("n,,n=user,r=fyko+d2lbbFgONRv9qkxdawL,f=y")
			assert.equals("challenge", status, err or server_first_message);
			assert.string(server_first_message);
			local f = server_first_message:match("^r=[^,]+,f=([^,]+)")
			assert.equals("$y$j75$00vQs9624O0VmZoU0ESJq.$", base64.decode(f))

			test_scram(profile, "SHA-256", H, HMAC, Hi, "f=y")
		end)
	end)

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

