describe("util.poll", function()
	local poll;
	setup(function()
		poll = require "util.poll";
	end);
	it("loads", function()
		assert.is_table(poll);
		assert.is_function(poll.new);
		assert.is_string(poll.api);
	end);
	describe("new", function()
		local p;
		setup(function()
			p = poll.new();
		end)
		it("times out", function ()
			local fd, err = p:wait(0);
			assert.falsy(fd);
			assert.equal("timeout", err);
		end);
		it("works", function()
			-- stdout should be writable, right?
			assert.truthy(p:add(1, false, true));
			local fd, r, w = p:wait(1);
			assert.is_number(fd);
			assert.is_boolean(r);
			assert.is_boolean(w);
			assert.equal(1, fd);
			assert.falsy(r);
			assert.truthy(w);
			assert.truthy(p:del(1));
		end);
	end)
	describe("cached events", function()
		local socket = require "socket";
		local p, sender, sockets;

		before_each(function()
			p = assert(poll.new());
			sender = assert(socket.udp());
			sockets = {};
		end);

		after_each(function()
			for _, conn in ipairs(sockets) do
				p:del(conn:getfd());
				conn:close();
			end
			sender:close();
			p = nil;
		end);

		local function ready_batch()
			for i = 1, 3 do
				local conn = assert(socket.udp());
				sockets[i] = conn;
				assert(conn:setsockname("127.0.0.1", 0));
				assert(conn:settimeout(1));
				assert(p:add(conn:getfd(), true, false));
				assert(sender:sendto("ready", conn:getsockname()));
			end
			local first, readable, writable = p:wait(1);
			assert.is_true(readable);
			assert.is_false(writable);
			local pending = {};
			for _, conn in ipairs(sockets) do
				if conn:getfd() == first then
					assert.equal("ready", conn:receive());
				else
					pending[#pending + 1] = conn;
				end
			end
			assert.equal(2, #pending);
			return pending;
		end

		it("discards deleted cached events and preserves other events", function()
			local pending = ready_batch();
			assert(p:del(pending[1]:getfd()));
			local fd, readable, writable = p:wait(0);
			assert.equal(pending[2]:getfd(), fd);
			assert.is_true(readable);
			assert.is_false(writable);
			assert.equal("ready", pending[2]:receive());
			local next_fd, err = p:wait(0);
			assert.is_nil(next_fd);
			assert.equal("timeout", err);
		end);

		it("discards old cached events when a descriptor is re-added", function()
			local pending = ready_batch();
			for _, conn in ipairs(pending) do
				assert(p:del(conn:getfd()));
				assert.equal("ready", conn:receive());
			end
			local conn = pending[1];
			assert(p:add(conn:getfd(), true, false));
			local fd, err = p:wait(0);
			assert.is_nil(fd);
			assert.equal("timeout", err);
			assert(sender:sendto("fresh", conn:getsockname()));
			assert.equal(conn:getfd(), p:wait(1));
			assert.equal("fresh", conn:receive());
		end);
	end);
end);

