describe("util.smqueue", function()

	local smqueue
	setup(function() smqueue = require "util.smqueue"; end)

	describe("#new()", function()
		it("should work", function()
			assert.has_error(function () smqueue.new(-1) end);
			assert.has_error(function () smqueue.new(0) end);
			assert.not_has_error(function () smqueue.new(1) end);
			local q = smqueue.new(10);
			assert.truthy(q);
		end)
	end)

	describe("#push()", function()
		it("should allow pushing many items", function()
			local q = smqueue.new(10);
			for i = 1, 20 do q:push(i); end
			assert.equal(20, q:count_unacked());
		end)
	end)

	describe("#resumable()", function()
		it("returns true while the queue is small", function()
			local q = smqueue.new(10);
			for i = 1, 10 do q:push(i); end
			assert.truthy(q:resumable());
			q:push(11);
			assert.falsy(q:resumable());
		end)
	end)

	describe("#ack", function()
		it("allows removing items", function()
			local q = smqueue.new(10);
			for i = 1, 10 do q:push(i); end
			assert.same({ 1; 2; 3 }, q:ack(3));
			assert.same({ 4; 5; 6 }, q:ack(6));
			assert.falsy(q:ack(3), "can't go backwards")
			assert.falsy(q:ack(100), "can't ack too many")
			for i = 11, 20 do q:push(i); end
			assert.same({ 11; 12 }, q:ack(12), "items are dropped");
		end)
	end)

	describe("#resume", function()
		it("iterates over current items", function()
			local q = smqueue.new(10);
			for i = 1, 12 do q:push(i); end
			assert.same({ 3; 4; 5; 6 }, q:ack(6));
			assert.truthy(q:resumable());
			local resume = {}
			for _, i in q:resume() do resume[i] = true end
			assert.same({ [7] = true; [8] = true; [9] = true; [10] = true; [11] = true; [12] = true }, resume);
		end)
	end)

	describe("#table", function ()
		it("produces a compat layer", function ()
			local q = smqueue.new(10);
			for i = 1,10 do q:push(i); end
			do
				local t = q:table();
				assert.same({ 1; 2; 3; 4; 5; 6; 7; 8; 9; 10 }, t);
			end
			do
				for i = 11,20 do q:push(i); end
				local t = q:table();
				assert.same({ 11; 12; 13; 14; 15; 16; 17; 18; 19; 20 }, t);
			end
			do
				q:ack(15);
				local t = q:table();
				assert.same({ 16; 17; 18; 19; 20 }, t);
			end
			do
				q:ack(20);
				local t = q:table();
				assert.same({}, t);
			end
		end)
	end)

	describe("#add_checkpoint", function()
		it("fires the callback when ack reaches the checkpoint", function()
			local q = smqueue.new(10);
			for i = 1, 4 do q:push(i); end
			local called = false;
			q:add_checkpoint(function() called = true; end);
			assert.falsy(called, "should not fire before ack");
			q:ack(4);
			assert.truthy(called, "should fire when ack reaches checkpoint");
		end)

		it("fires when ack exceeds the checkpoint", function()
			local q = smqueue.new(10);
			for i = 1, 4 do q:push(i); end
			local called = false;
			q:add_checkpoint(function() called = true; end);
			for i = 5, 8 do q:push(i); end
			q:ack(7); -- acks past the checkpoint at 4
			assert.truthy(called);
		end)

		it("does not fire for acks below the checkpoint threshold", function()
			local q = smqueue.new(10);
			for i = 1, 5 do q:push(i); end
			local called = false;
			q:add_checkpoint(function() called = true; end);
			q:ack(4);
			assert.falsy(called, "should not fire when ack is below checkpoint");
		end)

		it("fires the callback with optional data argument", function()
			local q = smqueue.new(10);
			for i = 1, 4 do q:push(i); end
			local received_data;
			q:add_checkpoint(function(d) received_data = d; end, "hello");
			q:ack(4);
			assert.equal("hello", received_data);
		end)

		it("fires multiple checkpoints in a single ack call", function()
			local q = smqueue.new(10);
			for i = 1, 3 do q:push(i); end
			local fired = {};
			q:add_checkpoint(function() fired[#fired+1] = "first"; end);
			q:push(4);
			q:add_checkpoint(function() fired[#fired+1] = "second-1"; end);
			q:add_checkpoint(function() fired[#fired+1] = "second-2"; end);
			q:push(5);
			q:add_checkpoint(function() fired[#fired+1] = "third"; end);
			q:ack(5); -- should call all checkpoints, in order
			assert.same({ "first", "second-1", "second-2", "third" }, fired);
		end)

		it("fires checkpoints in order across multiple acks", function()
			local q = smqueue.new(10);
			for i = 1, 3 do q:push(i); end
			local order = {};
			q:add_checkpoint(function() order[#order+1] = 1; end);
			q:push(4);
			q:add_checkpoint(function() order[#order+1] = 2; end);
			q:push(5);
			q:add_checkpoint(function() order[#order+1] = 3; end);
			q:ack(3); -- fires only first
			assert.same({ 1 }, order);
			q:ack(5); -- fires second and third
			assert.same({ 1, 2, 3 }, order);
		end)

		it("fires each checkpoint exactly once", function()
			local q = smqueue.new(10);
			for i = 1, 4 do q:push(i); end
			local count = 0;
			q:add_checkpoint(function() count = count + 1; end);
			q:ack(4);
			q:ack(4); -- duplicate ack
			for i = 5, 8 do q:push(i); end
			q:ack(8);
			assert.equal(1, count);
		end)
	end)
end);
