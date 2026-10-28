-- Test vectors from XEP-0115 section 5
local caps = require "util.caps";
local st = require "util.stanza";

-- Parsers (util.xmppstream, util.xml) set attr.xmlns on every element,
-- while stanzas built in memory (e.g. by mod_disco) leave it unset on children
local function as_parsed(stanza, xmlns)
	xmlns = stanza.attr.xmlns or xmlns;
	stanza.attr.xmlns = xmlns;
	for _, child in ipairs(stanza.tags) do
		as_parsed(child, xmlns);
	end
	return stanza;
end

-- 5.2 Simple Generation Example
local function simple_example()
	return st.stanza("query", { xmlns = "http://jabber.org/protocol/disco#info";
			node = "http://code.google.com/p/exodus#QgayPKawpkPSDYmwT/WM94uAlu0=" })
		:tag("identity", { category = "client"; name = "Exodus 0.9.1"; type = "pc" }):up()
		:tag("feature", { var = "http://jabber.org/protocol/caps" }):up()
		:tag("feature", { var = "http://jabber.org/protocol/disco#info" }):up()
		:tag("feature", { var = "http://jabber.org/protocol/disco#items" }):up()
		:tag("feature", { var = "http://jabber.org/protocol/muc" }):up();
end
local simple_S = "client/pc//Exodus 0.9.1<http://jabber.org/protocol/caps<"
	.."http://jabber.org/protocol/disco#info<http://jabber.org/protocol/disco#items<"
	.."http://jabber.org/protocol/muc<";
local simple_ver = "QgayPKawpkPSDYmwT/WM94uAlu0=";

-- 5.3 Complex Generation Example
local function complex_example()
	return st.stanza("query", { xmlns = "http://jabber.org/protocol/disco#info";
			node = "http://psi-im.org#q07IKJEyjvHSyhy//CH0CxmKi8w=" })
		:tag("identity", { ["xml:lang"] = "en"; category = "client"; name = "Psi 0.11"; type = "pc" }):up()
		:tag("identity", { ["xml:lang"] = "el"; category = "client"; name = "Ψ 0.11"; type = "pc" }):up()
		:tag("feature", { var = "http://jabber.org/protocol/caps" }):up()
		:tag("feature", { var = "http://jabber.org/protocol/disco#info" }):up()
		:tag("feature", { var = "http://jabber.org/protocol/disco#items" }):up()
		:tag("feature", { var = "http://jabber.org/protocol/muc" }):up()
		:tag("x", { xmlns = "jabber:x:data"; type = "result" })
			:tag("field", { var = "FORM_TYPE"; type = "hidden" })
				:text_tag("value", "urn:xmpp:dataforms:softwareinfo")
			:up()
			:tag("field", { var = "ip_version"; type = "text-multi" })
				:text_tag("value", "ipv4")
				:text_tag("value", "ipv6")
			:up()
			:tag("field", { var = "os" }):text_tag("value", "Mac"):up()
			:tag("field", { var = "os_version" }):text_tag("value", "10.5.1"):up()
			:tag("field", { var = "software" }):text_tag("value", "Psi"):up()
			:tag("field", { var = "software_version" }):text_tag("value", "0.11"):up()
		:up();
end
local complex_S = "client/pc/el/Ψ 0.11<client/pc/en/Psi 0.11<http://jabber.org/protocol/caps<"
	.."http://jabber.org/protocol/disco#info<http://jabber.org/protocol/disco#items<"
	.."http://jabber.org/protocol/muc<urn:xmpp:dataforms:softwareinfo<ip_version<ipv4<ipv6<"
	.."os<Mac<os_version<10.5.1<software<Psi<software_version<0.11<";
local complex_ver = "q07IKJEyjvHSyhy//CH0CxmKi8w=";

describe("util.caps", function ()
	describe("#calculate_hash()", function ()
		for shape, prepare in pairs({ built = function (s) return s; end; parsed = as_parsed }) do
			describe("with a "..shape.." stanza", function ()
				it("works for the simple example (5.2)", function ()
					local ver, S = caps.calculate_hash(prepare(simple_example()));
					assert.equal(simple_S, S);
					assert.equal(simple_ver, ver);
				end);

				it("works for the complex example (5.3)", function ()
					local ver, S = caps.calculate_hash(prepare(complex_example()));
					assert.equal(complex_S, S);
					assert.equal(complex_ver, ver);
				end);
			end);
		end
	end);
end);
