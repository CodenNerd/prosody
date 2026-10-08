
local encodings = require "util.encodings";
local utf8 = assert(encodings.utf8, "no encodings.utf8 module");

describe("util.encodings", function ()
	describe("#encode()", function()
		it("should work", function ()
			assert.is.equal(encodings.base64.encode(""), "");
			assert.is.equal(encodings.base64.encode('coucou'), "Y291Y291");
			assert.is.equal(encodings.base64.encode("\0\0\0"), "AAAA");
			assert.is.equal(encodings.base64.encode("\255\255\255"), "////");
		end);
	end);
	describe("#decode()", function()
		it("should work", function ()
			assert.is.equal(encodings.base64.decode(""), "");
			assert.is.equal(encodings.base64.decode("="), "");
			assert.is.equal(encodings.base64.decode('Y291Y291'), "coucou");
			assert.is.equal(encodings.base64.decode("AAAA"), "\0\0\0");
			assert.is.equal(encodings.base64.decode("////"), "\255\255\255");
		end);
	end);
end);
describe("util.encodings.utf8", function()
	describe("#valid()", function()
		it("rejects oversized sequences before shifting", function()
			assert.is_false(utf8.valid("\255\143\143\143\143\143\143\143"));
			assert.is_false(utf8.valid("\254\128\128\128\128\128\128"));
		end);

		it("keeps strict Unicode validation", function()
			assert.is_false(utf8.valid("\237\160\128")); -- U+D800
			assert.is_false(utf8.valid("\244\144\128\128")); -- U+110000
			assert.is_false(utf8.valid("\248\136\128\128\128")); -- U+200000
			assert.is_false(utf8.valid("\252\132\128\128\128\128")); -- U+4000000
			assert.is_true(utf8.valid("\244\143\191\191")); -- U+10FFFF
			assert.is_true(utf8.valid("a\0b"));
		end);

		it("should work", function()

			for line in io.lines("spec/utf8_sequences.txt") do
				local data = line:match(":%s*([^#]+)"):gsub("%s+", ""):gsub("..", function (c) return string.char(tonumber(c, 16)); end)
				local expect = line:match("(%S+):");

				assert(expect == "pass" or expect == "fail", "unknown expectation: "..line:match("^[^:]+"));

				local valid = utf8.valid(data);
				assert.is.equal(valid, utf8.valid(data.." "));
				assert.is.equal(valid, expect == "pass", line);
			end

		end);
	end);
end);
