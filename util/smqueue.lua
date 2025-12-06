-- Represents an outgoing reliable stanza queue

local queue = require("prosody.util.queue");

-- SM queue methods
local smqueue = {};

function smqueue:push(v)
	self._head = self._head + 1;

	assert(self._queue:push(v));
end

-- Call when receiver has acknowledged some stanzas
-- `h` (sent by the receiver) is the running count of
-- successfully received stanzas
function smqueue:ack(h)
	if h < self._tail then
		-- h is less than a previous h
		return nil, "tail"
	elseif h > self._head then
		-- h is greater than the number of stanzas we sent
		return nil, "head"
	end

	local acked = {};
	self._tail = h;
	local expect = self._head - self._tail;
	while expect < self._queue:count() do
		local v = self._queue:pop();
		if not v then return nil, "pop" end
		table.insert(acked, v);
	end

	local c = self._next_checkpoint;
	if c and h >= c then
		self:_call_checkpoints(h);
	end

	return acked
end

function smqueue:count_unacked() return self._head - self._tail end

function smqueue:count_acked() return self._tail end

function smqueue:resumable() return self._queue:count() >= (self._head - self._tail) end

function smqueue:resume() return self._queue:items() end

function smqueue:consume() return self._queue:consume() end

function smqueue:table()
	local t = {};
	for i, v in self:resume() do t[i] = v; end
	return t
end

-- Add a 'checkpoint' which will call a function when all the stanzas
-- currently in the queue have been successfully delivered and acknowledged
function smqueue:add_checkpoint(cb, ud)
	table.insert(self._checkpoints, { self._head, cb, ud });
	if not self._next_checkpoint then
		self._next_checkpoint = self._head;
	end
end
};

function smqueue:_call_checkpoints(h)
	local checkpoints = self._checkpoints;

	-- Pop the checkpoint info and update the next checkpoint info
	local c = table.remove(checkpoints, 1);
	self._next_checkpoint = checkpoints[1] and checkpoints[1][1] or nil;

	-- Call the callback
	local cb, ud = c[2], c[3];
	cb(ud);

	-- In case we passed over multiple checkpoints, call them also
	if h >= self._next_checkpoint then
		return self:_call_checkpoints(h);
	end
end

local smqueue_mt = {
	__name = "smqueue";
	__index = smqueue;
	__len = smqueue.count_unacked;
	-- Return a simple object for serialization
	__freeze = function (q) return { head = q._head; tail = q._tail } end;
};

local lib = {};

function lib.new(size)
	assert(size > 0);
	return setmetatable({
		_head = 0;
		_tail = 0;
		_queue = queue.new(size, true);
		_checkpoints = {};
	}, smqueue_mt)
end

return lib
