--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/core/Config.lua
	Configuracao persistente (workspace/UNICLUDE/config.json) com
	valores padrao, validacao, sinal de mudanca e auto-save debounced.
═══════════════════════════════════════════════════════════════════════════]]

local UNI    = ...
local Env    = UNI.require("src/core/Env")
local Signal = UNI.require("src/core/Signal")
local Util   = UNI.require("src/core/Util")

local HttpService = Env.Services.HttpService
local FOLDER = "UNICLUDE"
local PATH   = FOLDER .. "/config.json"

local Config = {}
Config.Changed = Signal.new("Config.Changed")

--══════════════════════════════════════════════════════════════════════════
-- PADROES
--══════════════════════════════════════════════════════════════════════════
Config.Defaults = {
	-- janela
	windowPosition   = { 60, 60 },
	windowSize       = { 980, 620 },
	activeTab        = "Remotes",
	toggleKey        = "RightControl",
	uiScale          = 1,
	minimized        = false,

	-- remote spy
	spyEnabled       = true,
	spyOnStart       = true,
	logRemoteEvents  = true,
	logRemoteFunctions = true,
	logBindables     = false,
	logUnreliable    = true,
	logReturns       = true,
	captureCaller    = true,
	captureTraceback = true,
	ignoreSelfCalls  = true,
	groupIdentical   = true,
	maxRemoteLogs    = 800,
	maxArgDepth      = 8,
	pauseOnFocus     = false,
	blockedRemotes   = {},   -- [fullName] = true
	ignoredRemotes   = {},   -- [fullName] = true
	pinnedRemotes    = {},   -- [fullName] = true

	-- logs
	captureOutput    = true,
	captureWarnings  = true,
	captureErrors    = true,
	captureInfo      = false,
	maxConsoleLogs   = 1200,
	logAutoScroll    = true,

	-- explorer
	explorerAutoExpand = false,
	explorerShowNil    = true,
	explorerRoots      = { "Workspace", "ReplicatedStorage", "Players", "Lighting", "StarterGui", "StarterPack" },

	-- inventario
	inventoryAutoRefresh = true,
	inventoryInterval    = 3,
	inventoryDeepScan    = true,
	inventoryMaxDepth    = 6,

	-- scanner
	scannerIncludeCClosures = false,
	scannerMaxResults       = 400,

	-- geral
	notifications    = true,
	notifyDuration   = 3.5,
	exportFolder     = "UNICLUDE/exports",
	theme            = "citron",
}

--══════════════════════════════════════════════════════════════════════════
-- ESTADO
--══════════════════════════════════════════════════════════════════════════
local state = Util.deepCopy(Config.Defaults)
local dirty = false
local loadedFromDisk = false

--══════════════════════════════════════════════════════════════════════════
-- IO
--══════════════════════════════════════════════════════════════════════════
function Config.load()
	if not Env.hasFS then return false, "sem filesystem" end
	local raw = Env.readFile(PATH)
	if not raw then return false, "arquivo inexistente" end

	local ok, parsed = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(parsed) ~= "table" then
		return false, "json invalido"
	end

	for k, v in pairs(parsed) do
		if Config.Defaults[k] ~= nil then
			local defType = type(Config.Defaults[k])
			if type(v) == defType then
				state[k] = v
			end
		end
	end
	loadedFromDisk = true
	return true
end

function Config.save()
	if not Env.hasFS then return false, "sem filesystem" end
	local ok, encoded = pcall(function() return HttpService:JSONEncode(state) end)
	if not ok then return false, "falha ao serializar" end
	Env.ensureFolder(FOLDER)
	local wrote, err = Env.writeFile(PATH, encoded)
	if wrote then dirty = false end
	return wrote, err
end

local scheduleSave = Util.debounce(function()
	if dirty then Config.save() end
end, 1.5)

--══════════════════════════════════════════════════════════════════════════
-- API
--══════════════════════════════════════════════════════════════════════════
function Config.get(key)
	local v = state[key]
	if v == nil then return Config.Defaults[key] end
	return v
end

function Config.set(key, value, silent)
	local old = state[key]
	if old == value then return value end
	state[key] = value
	dirty = true
	scheduleSave()
	if not silent then
		Config.Changed:Fire(key, value, old)
	end
	return value
end

function Config.toggle(key)
	return Config.set(key, not Config.get(key))
end

function Config.all()
	return Util.deepCopy(state)
end

function Config.reset(key)
	if key then
		Config.set(key, Util.deepCopy(Config.Defaults[key]))
	else
		state = Util.deepCopy(Config.Defaults)
		dirty = true
		Config.save()
		Config.Changed:Fire("*", nil, nil)
	end
end

--══════════════════════════════════════════════════════════════════════════
-- SUBTABELAS (listas de bloqueio/ignore/pin)
--══════════════════════════════════════════════════════════════════════════
local function setFlag(tableKey, id, value)
	local t = state[tableKey]
	if type(t) ~= "table" then t = {}; state[tableKey] = t end
	if value then t[id] = true else t[id] = nil end
	dirty = true
	scheduleSave()
	Config.Changed:Fire(tableKey, t, nil)
	return value
end

function Config.isBlocked(id) return state.blockedRemotes[id] == true end
function Config.setBlocked(id, v) return setFlag("blockedRemotes", id, v) end
function Config.toggleBlocked(id) return setFlag("blockedRemotes", id, not Config.isBlocked(id)) end

function Config.isIgnored(id) return state.ignoredRemotes[id] == true end
function Config.setIgnored(id, v) return setFlag("ignoredRemotes", id, v) end
function Config.toggleIgnored(id) return setFlag("ignoredRemotes", id, not Config.isIgnored(id)) end

function Config.isPinned(id) return state.pinnedRemotes[id] == true end
function Config.togglePinned(id) return setFlag("pinnedRemotes", id, not Config.isPinned(id)) end

function Config.clearList(tableKey)
	state[tableKey] = {}
	dirty = true
	scheduleSave()
	Config.Changed:Fire(tableKey, state[tableKey], nil)
end

--══════════════════════════════════════════════════════════════════════════
-- EXPORTACAO
--══════════════════════════════════════════════════════════════════════════
function Config.exportPath(name, extension)
	local folder = Config.get("exportFolder")
	Env.ensureFolder("UNICLUDE")
	Env.ensureFolder(folder)
	return ("%s/%s_%s.%s"):format(folder, name, Util.dateStamp(), extension or "txt")
end

function Config.export(name, content, extension)
	if not Env.hasFS then
		local copied = Env.copy(content)
		return false, copied and "copiado para a area de transferencia" or "sem filesystem nem clipboard"
	end
	local path = Config.exportPath(name, extension)
	local ok, err = Env.writeFile(path, content)
	if ok then return true, path end
	return false, tostring(err)
end

--══════════════════════════════════════════════════════════════════════════
Config.load()
Config.LoadedFromDisk = loadedFromDisk
Config.Path = PATH

UNI.onCleanup(function()
	if dirty then Config.save() end
end)

return Config
