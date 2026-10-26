local muc_util;

local st = require "util.stanza";

do
	-- XXX Hack for lack of a mock moduleapi
	local env = setmetatable({
		module = {
			_shared = {};
			-- Close enough to the real module:shared() for our purposes here
			shared = function (self, name)
				local t = self._shared[name];
				if t == nil then
					t = {};
					self._shared[name] = t;
				end
				return t;
			end;
		}
	}, { __index = _ENV or _G });
	muc_util = require "util.envload".envloadfile("plugins/muc/util.lib.lua", env)();
	end

describe("muc/util", function ()
	describe("filter_muc_x()", function ()
		it("correctly filters muc#user", function ()
			local stanza = st.message({ to = "to", from = "from", id = "foo" })
				:tag("x", { xmlns = "http://jabber.org/protocol/muc#user" })
					:tag("invite", { to = "user@example.com" });

			assert.equal(true, stanza:has_single_child_tag());
			assert.equal(stanza, muc_util.filter_muc_x(stanza));
			assert.equal(false, stanza:has_child_tags());
		end);

		it("correctly filters muc#user on a cloned stanza", function ()
			local stanza = st.message({ to = "to", from = "from", id = "foo" })
				:tag("x", { xmlns = "http://jabber.org/protocol/muc#user" })
					:tag("invite", { to = "user@example.com" });

			assert.equal(true, stanza:has_single_child_tag());
			local filtered = muc_util.filter_muc_x(st.clone(stanza));
			assert.equal(true, stanza:has_single_child_tag());
			assert.equal(false, filtered:has_child_tags());
		end);
	end);
end);
