--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/core/Util.lua
	Funcoes utilitarias compartilhadas: caminhos de instancia, formatacao,
	busca fuzzy, throttle/debounce, hashing e helpers de tabela.
═══════════════════════════════════════════════════════════════════════════]]

local UNI = ...
local Env = UNI.require("src/core/Env")

local Util = {}

--══════════════════════════════════════════════════════════════════════════
-- INSTANCIAS
--══════════════════════════════════════════════════════════════════════════

local SERVICE_ROOTS = {
	ReplicatedStorage = "ReplicatedStorage",
	Workspace = "Workspace",
	Players = "Players",
	Lighting = "Lighting",
	StarterGui = "StarterGui",
	StarterPack = "StarterPack",
	StarterPlayer = "StarterPlayer",
	SoundService = "SoundService",
	Teams = "Teams",
	ReplicatedFirst = "ReplicatedFirst",
	TextChatService = "TextChatService",
	MaterialService = "MaterialService",
	Chat = "Chat",
}

--- Nome completo tolerante a erro (instancias em nil retornam "[nil]/Nome")
function Util.fullName(inst)
	if typeof(inst) ~= "Instance" then return tostring(inst) end
	local ok, name = pcall(function() return inst:GetFullName() end)
	if ok and name and name ~= "" then return name end
	-- fallback manual
	local parts, node, depth = {}, inst, 0
	while node and depth < 64 do
		table.insert(parts, 1, Env.safeIndex(node, "Name", "?"))
		local okp, parent = pcall(function() return node.Parent end)
		if not okp then break end
		node = parent
		depth += 1
	end
	if node == nil then table.insert(parts, 1, "[nil]") end
	return table.concat(parts, ".")
end

--- Gera codigo Luau que resolve a instancia (usado no gerador de scripts)
function Util.instancePath(inst)
	if typeof(inst) ~= "Instance" then return "nil" end

	local segments = {}
	local node = inst
	local guard = 0

	while node and node ~= game and guard < 128 do
		guard += 1
		local name = Env.safeIndex(node, "Name", "?")
		local parent = Env.safeIndex(node, "Parent", nil)

		if parent == game then
			local className = Env.safeIndex(node, "ClassName", name)
			local serviceName = SERVICE_ROOTS[className] or SERVICE_ROOTS[name] or className
			table.insert(segments, 1, ('game:GetService("%s")'):format(serviceName))
			return table.concat(segments)
		end

		-- jogador local vira referencia curta
		if node == Env.LocalPlayer then
			table.insert(segments, 1, 'game:GetService("Players").LocalPlayer')
			return table.concat(segments)
		end

		if name:match("^[%a_][%w_]*$") then
			table.insert(segments, 1, "." .. name)
		else
			table.insert(segments, 1, ('[%q]'):format(name))
		end

		node = parent
	end

	if node == game then
		return "game" .. table.concat(segments)
	end

	-- instancia orfa: melhor esforco
	return ('--[[ instancia fora da DataModel ]] nil %s'):format(Util.fullName(inst))
end

--- Caminho relativo a um ancestral (para exibicao compacta)
function Util.relativePath(inst, ancestor)
	local full = Util.fullName(inst)
	if ancestor then
		local base = Util.fullName(ancestor)
		if full:sub(1, #base) == base then
			return full:sub(#base + 2)
		end
	end
	return full
end

--- Conta descendentes com limite (evita travar em mundos gigantes)
function Util.countDescendants(inst, cap)
	cap = cap or 25000
	local n = 0
	local ok = pcall(function()
		for _ in ipairs(inst:GetDescendants()) do
			n += 1
			if n >= cap then break end
		end
	end)
	if not ok then return -1 end
	return n
end

--══════════════════════════════════════════════════════════════════════════
-- CLASSIFICACAO
--══════════════════════════════════════════════════════════════════════════

local REMOTE_CLASSES = {
	RemoteEvent = "event",
	UnreliableRemoteEvent = "unreliable",
	RemoteFunction = "function",
	BindableEvent = "bindable",
	BindableFunction = "bindfunc",
}
Util.RemoteClasses = REMOTE_CLASSES

function Util.isRemote(inst)
	if typeof(inst) ~= "Instance" then return false end
	local class = Env.safeIndex(inst, "ClassName", "")
	return REMOTE_CLASSES[class] ~= nil
end

function Util.remoteKind(inst)
	return REMOTE_CLASSES[Env.safeIndex(inst, "ClassName", "")] or "desconhecido"
end

local CLASS_ICONS = {
	RemoteEvent = "⇄", UnreliableRemoteEvent = "⇢", RemoteFunction = "⇌",
	BindableEvent = "◇", BindableFunction = "◈",
	Folder = "▸", Model = "▣", Part = "▪", MeshPart = "▪", UnionOperation = "▪",
	Script = "≡", LocalScript = "≡", ModuleScript = "≣",
	Player = "☺", Humanoid = "☻", Tool = "⚒", Backpack = "▤",
	ScreenGui = "▢", Frame = "▭", TextLabel = "T", TextButton = "T",
	ImageLabel = "▩", Sound = "♪", Animation = "↻", Camera = "◉",
	IntValue = "#", NumberValue = "#", StringValue = "\"", BoolValue = "±",
	ObjectValue = "@", Configuration = "⚙", Attachment = "•",
}

function Util.classIcon(className)
	return CLASS_ICONS[className] or "◦"
end

--══════════════════════════════════════════════════════════════════════════
-- FORMATACAO
--══════════════════════════════════════════════════════════════════════════

function Util.timestamp(t)
	return os.date("%H:%M:%S", t or os.time())
end

function Util.timestampMs(clockValue)
	local ms = math.floor(((clockValue or os.clock()) % 1) * 1000)
	return ("%s.%03d"):format(os.date("%H:%M:%S"), ms)
end

function Util.dateStamp()
	return os.date("%Y-%m-%d_%H-%M-%S")
end

function Util.duration(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	if m > 0 then return ("%dm %02ds"):format(m, s) end
	return ("%ds"):format(s)
end

function Util.compactNumber(n)
	n = tonumber(n) or 0
	local abs = math.abs(n)
	if abs >= 1e9 then return ("%.2fB"):format(n / 1e9) end
	if abs >= 1e6 then return ("%.2fM"):format(n / 1e6) end
	if abs >= 1e3 then return ("%.1fk"):format(n / 1e3) end
	if n % 1 == 0 then return tostring(math.floor(n)) end
	return ("%.2f"):format(n)
end

function Util.bytes(n)
	n = tonumber(n) or 0
	local units = { "B", "KB", "MB", "GB" }
	local i = 1
	while n >= 1024 and i < #units do n = n / 1024; i += 1 end
	return ("%.1f %s"):format(n, units[i])
end

function Util.truncate(str, max, tail)
	str = tostring(str)
	max = max or 80
	if #str <= max then return str end
	if tail then
		return "…" .. str:sub(#str - max + 2)
	end
	return str:sub(1, max - 1) .. "…"
end

--- Colapsa quebras de linha para exibir numa unica linha de lista
function Util.oneLine(str, max)
	str = tostring(str):gsub("[\r\n]+", " ⏎ "):gsub("%s+", " ")
	return Util.truncate(str, max or 120)
end

function Util.pluralize(n, singular, plural)
	if n == 1 then return ("1 %s"):format(singular) end
	return ("%d %s"):format(n, plural or (singular .. "s"))
end

--══════════════════════════════════════════════════════════════════════════
-- BUSCA
--══════════════════════════════════════════════════════════════════════════

--- Busca por subsequencia (fuzzy). Retorna score ou nil.
function Util.fuzzy(haystack, needle)
	if needle == nil or needle == "" then return 0 end
	haystack = tostring(haystack):lower()
	needle = tostring(needle):lower()

	local exact = haystack:find(needle, 1, true)
	if exact then
		return 1000 - exact -- match literal ganha sempre
	end

	local hi, score, streak = 1, 0, 0
	for i = 1, #needle do
		local ch = needle:sub(i, i)
		local found = haystack:find(ch, hi, true)
		if not found then return nil end
		if found == hi then streak += 1 else streak = 0 end
		score += 10 - math.min(9, found - hi) + streak * 2
		hi = found + 1
	end
	return score
end

--- Filtra e ordena uma lista por relevancia
function Util.filterSort(items, query, textOf)
	if query == nil or query == "" then return items end
	local scored = {}
	for _, item in ipairs(items) do
		local s = Util.fuzzy(textOf(item), query)
		if s then table.insert(scored, { item = item, score = s }) end
	end
	table.sort(scored, function(a, b) return a.score > b.score end)
	local out = table.create(#scored)
	for i, e in ipairs(scored) do out[i] = e.item end
	return out
end

--══════════════════════════════════════════════════════════════════════════
-- TABELAS
--══════════════════════════════════════════════════════════════════════════

function Util.deepCopy(t, seen)
	if type(t) ~= "table" then return t end
	seen = seen or {}
	if seen[t] then return seen[t] end
	local copy = {}
	seen[t] = copy
	for k, v in pairs(t) do
		copy[Util.deepCopy(k, seen)] = Util.deepCopy(v, seen)
	end
	return copy
end

function Util.merge(base, override)
	local out = Util.deepCopy(base)
	for k, v in pairs(override or {}) do
		if type(v) == "table" and type(out[k]) == "table" then
			out[k] = Util.merge(out[k], v)
		else
			out[k] = v
		end
	end
	return out
end

function Util.keys(t)
	local out = {}
	for k in pairs(t) do table.insert(out, k) end
	return out
end

function Util.count(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

function Util.slice(t, from, to)
	local out = {}
	for i = from, math.min(to, #t) do table.insert(out, t[i]) end
	return out
end

function Util.reverse(t)
	local out = {}
	for i = #t, 1, -1 do table.insert(out, t[i]) end
	return out
end

--- Buffer circular: mantem os N itens mais recentes sem realocar
local Ring = {}
Ring.__index = Ring
function Ring.new(capacity)
	return setmetatable({ cap = capacity, items = {}, total = 0 }, Ring)
end
function Ring:push(v)
	table.insert(self.items, v)
	self.total += 1
	if #self.items > self.cap then
		table.remove(self.items, 1)
	end
	return v
end
function Ring:clear()
	table.clear(self.items)
	self.total = 0
end
function Ring:list() return self.items end
function Ring:size() return #self.items end
Util.Ring = Ring

--══════════════════════════════════════════════════════════════════════════
-- CONTROLE DE FLUXO
--══════════════════════════════════════════════════════════════════════════

function Util.debounce(fn, delaySeconds)
	local pending
	return function(...)
		local args = table.pack(...)
		if pending then task.cancel(pending) end
		pending = task.delay(delaySeconds, function()
			pending = nil
			fn(table.unpack(args, 1, args.n))
		end)
	end
end

function Util.throttle(fn, interval)
	local last = 0
	local queued
	return function(...)
		local now = os.clock()
		local args = table.pack(...)
		if now - last >= interval then
			last = now
			fn(table.unpack(args, 1, args.n))
		elseif not queued then
			queued = task.delay(interval - (now - last), function()
				queued = nil
				last = os.clock()
				fn(table.unpack(args, 1, args.n))
			end)
		end
	end
end

function Util.retry(fn, attempts, waitTime)
	for i = 1, attempts or 3 do
		local ok, res = pcall(fn)
		if ok then return true, res end
		if i < (attempts or 3) then task.wait(waitTime or 0.25) end
	end
	return false
end

--══════════════════════════════════════════════════════════════════════════
-- HASH / ID
--══════════════════════════════════════════════════════════════════════════

--- FNV-1a 32 bits. Usado para agrupar chamadas identicas de remote.
function Util.hash(str)
	local h = 2166136261
	for i = 1, #str do
		h = bit32.bxor(h, string.byte(str, i))
		h = (h * 16777619) % 4294967296
	end
	return h
end

function Util.shortHash(str)
	return ("%08x"):format(Util.hash(tostring(str)))
end

local idCounter = 0
function Util.nextId(prefix)
	idCounter += 1
	return ("%s%d"):format(prefix or "id", idCounter)
end

--══════════════════════════════════════════════════════════════════════════
-- STRINGS
--══════════════════════════════════════════════════════════════════════════

function Util.escapeRich(s)
	return (tostring(s)
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub('"', "&quot;")
		:gsub("'", "&apos;"))
end

function Util.trim(s)
	return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.lines(s)
	local out = {}
	for line in tostring(s):gmatch("([^\n]*)\n?") do table.insert(out, line) end
	if out[#out] == "" then table.remove(out) end
	return out
end

function Util.startsWith(s, prefix)
	return tostring(s):sub(1, #prefix) == prefix
end

return Util
