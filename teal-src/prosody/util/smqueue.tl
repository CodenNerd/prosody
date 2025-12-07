local queue = require "prosody.util.queue";

local record lib
	-- T would typically be util.stanza
	record smqueue<T>
		_queue : queue.queue<T>
		_head : integer
		_tail : integer
		_next_checkpoint : integer
		type checkpoint = { integer, function(any), any }
		_checkpoints : { checkpoint }

		enum ack_errors
			"tail"
			"head"
			"pop"
		end
		push : function (smqueue<T>, T)
		ack : function (smqueue<T>, integer) : { T }, ack_errors
		resumable : function (smqueue<T>) : boolean
		resume : function (smqueue<T>)  : queue.queue.iterator, any, integer
		consume : function (smqueue<T>) : function() : T
		_call_checkpoints : function(smqueue<T>, integer)

		table : function (smqueue<T>) : { T }
	end
	new : function <T>(integer) : smqueue<T>
end

local type smqueue = lib.smqueue;

function smqueue:push(v : T)
	self._head = self._head + 1;
	-- Wraps instead of errors
	assert(self._queue:push(v));
end

-- Call when receiver has acknowledged some stanzas
-- `h` (sent by the receiver) is the running count of
-- successfully received stanzas
function smqueue:ack(h : integer) : { T }, smqueue.ack_errors
	if h < self._tail then
		-- h is less than a previous h
		return nil, "tail"
	elseif h > self._head then
		-- h is greater than the number of stanzas we sent
		return nil, "head"
	end
	-- TODO optimize? cache table fields
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

function smqueue:count_unacked() : integer
	return self._head - self._tail
end

function smqueue:count_acked() : integer
	return self._tail
end

function smqueue:resumable() : boolean
	return self._queue:count() >= (self._head - self._tail)
end

function smqueue:resume() : queue.queue.iterator, any, integer
	return self._queue:items()
end

function smqueue:consume() : (function() : T)
	return self._queue:consume() as (function() : T)
end

-- Compatibility layer, plain ol' table
function smqueue:table() : { T }
	local t : { T } = {};
	for i, v in self:resume() do
		t[i] = v;
	end
	return t
end

-- Add a 'checkpoint' which will call a function when all the stanzas
-- currently in the queue have been successfully delivered and acknowledged
function smqueue:add_checkpoint(cb : function (any), ud : any)
	table.insert(self._checkpoints, { self._head, cb, ud });
	if not self._next_checkpoint then
		self._next_checkpoint = self._head;
	end
end

function smqueue:_call_checkpoints(h : integer)
	local checkpoints = self._checkpoints;

	-- Pop the checkpoint info and update the next checkpoint info
	local c = table.remove(checkpoints, 1);
	self._next_checkpoint = checkpoints[1] and checkpoints[1][1] or nil;

	-- Call the callback
	local cb, ud = c[2], c[3];
	cb(ud);

	-- In case we passed over multiple checkpoints, call them also
	if h >= self._next_checkpoint then
		return self:_call_checkpoints(h)
	end
end

local function freeze(q : smqueue<any>) : { string:integer }
	return { head = q._head, tail = q._tail }
end

local smqueue_mt = {
	--
	__name = "smqueue";
	__index = smqueue;
	__len = smqueue.count_unacked;
	-- Return a simple object for serialization
	-- This is forbidden by Teal. Thanks Teal!
	__freeze = freeze;
}

function lib.new<T>(size : integer) : smqueue<T>
	assert(size>0);
	return setmetatable({
		_head = 0;
		_tail = 0;
		_queue = queue.new(size, true);
		_checkpoints = {};
	}, smqueue_mt)
end

return lib
