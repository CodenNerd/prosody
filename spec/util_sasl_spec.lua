local sasl = require "util.sasl";
local base64 = require "util.encodings".base64

-- profile * mechanism
-- callbacks could use spies instead

local function test_scram(profile, name, H, HMAC, Hi)
	local sxor = require"util.strbitop".sxor;
	local Normalize = require"util.encodings".stringprep.saslprep;

	local plain = sasl.new("sasl.test", profile);
	assert.truthy(plain:select("SCRAM-"..name));
	local gs2_cbind_flag = "n";
	local gs2_header = gs2_cbind_flag .. ",,"; -- no authzid
	local saslname = "user";
	local username = "n=" .. saslname;
	local c_nonce = "fyko+d2lbbFgONRv9qkxdawL";
	local nonce = "r=" .. c_nonce
	local client_first_message_bare = username .. "," .. nonce;
	local client_first_message = gs2_header .. client_first_message_bare
	local first_status, server_first_message, err = plain:process(client_first_message);
	assert.equals("challenge", first_status, err or server_first_message)
	assert.matches("r=[^,]+,s=[^,]+,i=%d+", server_first_message);
	nonce = server_first_message:match("r=[^,]+")
	local salt = server_first_message:match("s=[^,]+")
	local iteration_count = server_first_message:match("i=[^,]+")
	assert.matches("r=", nonce)
	assert.equal(c_nonce, nonce:sub(3, #c_nonce + 2))
	assert.matches("s=", salt)
	assert.matches("i=", iteration_count)

	local cbind_input = gs2_header;
	local channel_binding = "c=" .. base64.encode(cbind_input)
	local client_final_message_without_proof = channel_binding .. "," .. nonce;

	local i = tonumber(iteration_count:sub(3))
	local SaltedPassword, err = Hi(Normalize("pencil"), base64.decode(salt:sub(3)), i)
	assert.truthy(SaltedPassword, err)

	local ClientKey = HMAC(SaltedPassword, "Client Key")
	local StoredKey = H(ClientKey)
	local AuthMessage = client_first_message_bare .. "," .. server_first_message .. "," .. client_final_message_without_proof
	local ClientSignature = HMAC(StoredKey, AuthMessage)
	local ClientProof = sxor(ClientKey, ClientSignature)
	local ServerKey = HMAC(SaltedPassword, "Server Key")
	local ServerSignature = HMAC(ServerKey, AuthMessage)

	local proof = "p=" .. base64.encode(ClientProof)
	local client_final_message = client_final_message_without_proof .. "," .. proof;
	local final_status, server_final_message, err = plain:process(client_final_message);

	assert.equals("success", final_status, err or server_final_message)
	assert.matches("v=[^,]+",server_final_message)
	local verifier = server_final_message:match("v=[^,]+")
	assert.equal(verifier, "v="..base64.encode(ServerSignature))
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

	describe("oauthbearer profile", function()
		local profile = {
			oauthbearer = function(_, token, _realm, _authzid)
				if token == "example-bearer-token" then
					return "user", true, {};
				else
					return nil, nil, {}
				end
			end;
		}

		it("works with OAUTHBEARER", function()
			local bearer = sasl.new("sasl.test", profile);

			assert.truthy(bearer:select("OAUTHBEARER"));
			assert.equals("success", bearer:process("n,,\1auth=Bearer example-bearer-token\1\1"));
			assert.equals("user", bearer.username);
		end)


		it("returns extras with OAUTHBEARER", function()
			local bearer = sasl.new("sasl.test", profile);

			assert.truthy(bearer:select("OAUTHBEARER"));
			local status, extra = bearer:process("n,,\1auth=Bearer unknown\1\1");
			assert.equals("challenge", status);
			assert.equals("{\"status\":\"invalid_token\"}", extra);
			assert.equals("failure", bearer:process("\1"));
		end)

	end)
end);

