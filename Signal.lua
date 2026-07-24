--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/core/Signal.lua
	Signal leve em Lua puro + Maid (gerenciador de limpeza).

	Nao usa BindableEvent, entao os argumentos passam por referencia
	(tabelas, funcoes e userdata sobrevivem intactos — essencial pro Remote Spy).
═══════════════════════════════════════════════════════════════════════════]]

local UNI = ...

--══════════════════════════════════════════════════════════════════════════
-- Connection
--══════════════════════════════════════════════════════════════════════════
local Connection = {}
Connection.__index = Connection

function Connection.new(signal, fn)
	return setmetatable({
		_signal    = signal,
		_fn        = fn,
		Connected  = true,
	}, Connection)
end

function Connection:Disconnect()
	if not self.Connected then return end
	self.Connected = false
	local sig = self._signal
	if not sig then return end
	local idx = table.find(sig._handlers, self)
	if idx then table.remove(sig._handlers, idx) end
	self._signal = nil
	self._fn = nil
end
Connection.disconnect = Connection.Disconnect
Connection.Destroy = Connection.Disconnect

--══════════════════════════════════════════════════════════════════════════
-- Signal
--══════════════════════════════════════════════════════════════════════════
local Signal = {}
Signal.__index = Signal

function Signal.new(name)
	return setmetatable({
		_name     = name or "Signal",
		_handlers = {},
		_waiting  = {},
	}, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect espera uma funcao")
	local c = Connection.new(self, fn)
	table.insert(self._handlers, c)
	return c
end

function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end

function Signal:Fire(...)
	-- copia defensiva: handlers podem se desconectar durante o disparo
	local snapshot = table.clone(self._handlers)
	for _, c in ipairs(snapshot) do
		if c.Connected and c._fn then
			local ok, err = pcall(c._fn, ...)
			if not ok then
				warn(("[UNICLUDE/%s] erro em handler: %s"):format(self._name, tostring(err)))
			end
		end
	end
	if #self._waiting > 0 then
		local waiters = self._waiting
		self._waiting = {}
		for _, thread in ipairs(waiters) do
			task.spawn(thread, ...)
		end
	end
end

--- Dispara sem pcall (mais rapido, use em hot path)
function Signal:FireFast(...)
	for _, c in ipairs(self._handlers) do
		if c.Connected then c._fn(...) end
	end
end

function Signal:Wait()
	table.insert(self._waiting, coroutine.running())
	return coroutine.yield()
end

function Signal:HandlerCount()
	return #self._handlers
end

function Signal:DisconnectAll()
	for _, c in ipairs(table.clone(self._handlers)) do
		c.Connected = false
		c._signal = nil
		c._fn = nil
	end
	table.clear(self._handlers)
end
Signal.Destroy = Signal.DisconnectAll

--══════════════════════════════════════════════════════════════════════════
-- Maid: junta conexoes, instancias, threads e funcoes para limpeza em bloco
--══════════════════════════════════════════════════════════════════════════
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Add(item)
	if item == nil then return nil end
	table.insert(self._tasks, item)
	return item
end
Maid.give = Maid.Add
Maid.__call = function(self, item) return self:Add(item) end

function Maid:AddAll(list)
	for _, v in ipairs(list) do self:Add(v) end
end

local function cleanupOne(item)
	local t = typeof(item)
	if t == "function" then
		pcall(item)
	elseif t == "RBXScriptConnection" then
		pcall(function() item:Disconnect() end)
	elseif t == "Instance" then
		pcall(function() item:Destroy() end)
	elseif t == "thread" then
		pcall(task.cancel, item)
	elseif t == "table" then
		if type(item.Disconnect) == "function" then
			pcall(function() item:Disconnect() end)
		elseif type(item.Destroy) == "function" then
			pcall(function() item:Destroy() end)
		elseif type(item.destroy) == "function" then
			pcall(function() item:destroy() end)
		end
	end
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for i = #tasks, 1, -1 do
		cleanupOne(tasks[i])
	end
end
Maid.Destroy = Maid.Clean
Maid.DoCleaning = Maid.Clean

--══════════════════════════════════════════════════════════════════════════
return {
	new        = Signal.new,
	Signal     = Signal,
	Connection = Connection,
	Maid       = Maid,
	newMaid    = Maid.new,
}
