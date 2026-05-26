-- This file is generated from teal-src/prosody/util/smqueue.tl
local queue = require("prosody.util.queue");

local lib = { smqueue = {} }

local smqueue = lib.smqueue;

function smqueue:push(v)
	self._head = self._head + 1;

	assert(self._queue:push(v));
end

function smqueue:ack(h)
	if h < self._tail then

		return nil, "tail"
	elseif h > self._head then

		return nil, "head"
	end

	local acked = {};
	self._tail = h;
	local expect = self._head - self._tail;
	while expect < self._queue:count() do
		local v = self._queue:pop();
		if not v then
			return nil, "pop"
		end
		table.insert(acked, v);
	end

	self:_call_checkpoints(h);

	return acked
end

function smqueue:count_unacked()
	return self._head - self._tail
end

function smqueue:count_acked()
	return self._tail
end

function smqueue:resumable()
	return self._queue:count() >= (self._head - self._tail)
end

function smqueue:resume()
	return self._queue:items()
end

function smqueue:consume()
	return self._queue:consume()
end

function smqueue:table()
	local t = {};
	for i, v in self:resume() do
		t[i] = v;
	end
	return t
end

function smqueue:add_checkpoint(cb, ud)
	table.insert(self._checkpoints, { self._head; cb; ud });
end

function smqueue:_call_checkpoints(h)
	local checkpoints = self._checkpoints;
	local c = checkpoints[1];

	while c and h >= c[1] do
		table.remove(checkpoints, 1);
		local cb, ud = c[2], c[3];
		cb(ud);
		c = checkpoints[1];
	end
end

local function freeze(q)
	return { head = q._head; tail = q._tail }
end

local smqueue_mt = { __name = "smqueue"; __index = smqueue; __len = smqueue.count_unacked; __freeze = freeze }

function lib.new(size)
	assert(size > 0);
	return setmetatable({ _head = 0; _tail = 0; _queue = queue.new(size, true); _checkpoints = {} }, smqueue_mt)
end

return lib
