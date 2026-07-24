--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/core/Env.lua
	Camada de compatibilidade entre executores.

	Nenhum outro modulo do UNICLUDE deve chamar hookmetamethod/getgc/etc direto.
	Tudo passa por aqui, com fallback seguro e flag de capacidade.
═══════════════════════════════════════════════════════════════════════════]]

local UNI = ...

local Env = {}

--══════════════════════════════════════════════════════════════════════════
-- servicos (com cloneref quando disponivel, evita deteccao por referencia)
--══════════════════════════════════════════════════════════════════════════
local rawCloneref = clonereference or cloneref
local function ref(obj)
	if rawCloneref then
		local ok, c = pcall(rawCloneref, obj)
		if ok and c then return c end
	end
	return obj
end
Env.cloneref = ref

local function svc(name)
	local ok, s = pcall(game.GetService, game, name)
	if ok and s then return ref(s) end
	return nil
end

Env.Services = {
	Players            = svc("Players"),
	RunService         = svc("RunService"),
	UserInputService   = svc("UserInputService"),
	TweenService       = svc("TweenService"),
	HttpService        = svc("HttpService"),
	ReplicatedStorage  = svc("ReplicatedStorage"),
	StarterGui         = svc("StarterGui"),
	StarterPack        = svc("StarterPack"),
	Lighting           = svc("Lighting"),
	Workspace          = svc("Workspace"),
	LogService         = svc("LogService"),
	CoreGui            = svc("CoreGui"),
	TextService        = svc("TextService"),
	GuiService         = svc("GuiService"),
	MarketplaceService = svc("MarketplaceService"),
	Stats              = svc("Stats"),
	Debris             = svc("Debris"),
	ContentProvider    = svc("ContentProvider"),
	ProximityPromptService = svc("ProximityPromptService"),
	SoundService       = svc("SoundService"),
	Teams              = svc("Teams"),
}

Env.LocalPlayer = Env.Services.Players and Env.Services.Players.LocalPlayer

--══════════════════════════════════════════════════════════════════════════
-- identidade do executor
--══════════════════════════════════════════════════════════════════════════
local function firstFn(...)
	for _, f in ipairs({ ... }) do
		if typeof(f) == "function" then return f end
	end
	return nil
end

Env.identify = firstFn(identifyexecutor, getexecutorname, function()
	if syn then return "Synapse" end
	if KRNL_LOADED then return "KRNL" end
	if fluxus then return "Fluxus" end
	if is_sirhurt_closure then return "SirHurt" end
	return "Desconhecido"
end)

local okName, execName, execVer = pcall(function() return Env.identify() end)
Env.ExecutorName    = okName and tostring(execName) or "Desconhecido"
Env.ExecutorVersion = okName and execVer and tostring(execVer) or ""

--══════════════════════════════════════════════════════════════════════════
-- funcoes de hook / reflexao
--══════════════════════════════════════════════════════════════════════════
Env.getrawmetatable   = firstFn(getrawmetatable, debug and debug.getmetatable)
Env.setreadonly       = firstFn(setreadonly, make_writeable)
Env.isreadonly        = firstFn(isreadonly)
Env.hookmetamethod    = firstFn(hookmetamethod)
Env.hookfunction      = firstFn(hookfunction, replaceclosure, detour_function)
Env.newcclosure       = firstFn(newcclosure) or function(f) return f end
Env.checkcaller       = firstFn(checkcaller) or function() return false end
Env.getcallingscript  = firstFn(getcallingscript) or function() return nil end
Env.getnamecallmethod = firstFn(getnamecallmethod) or function()
	local ok, m = pcall(function() return debug.getinfo(2).name end)
	return ok and m or ""
end
Env.setnamecallmethod = firstFn(setnamecallmethod)
Env.islclosure        = firstFn(islclosure) or function() return false end
Env.iscclosure        = firstFn(iscclosure) or function() return false end
Env.getgc             = firstFn(getgc, get_gc_objects)
Env.getreg            = firstFn(getreg, debug and debug.getregistry)
Env.getloadedmodules  = firstFn(getloadedmodules)
Env.getconnections    = firstFn(getconnections, get_signal_cons)
Env.getinstances      = firstFn(getinstances)
Env.getnilinstances   = firstFn(getnilinstances, get_nil_instances)
Env.getscriptclosure  = firstFn(getscriptclosure, getscriptfunction)
Env.getsenv           = firstFn(getsenv)
Env.decompile         = firstFn(decompile)
Env.getscripthash     = firstFn(getscripthash)
Env.firesignal        = firstFn(firesignal)
Env.fireclickdetector = firstFn(fireclickdetector)
Env.fireproximityprompt = firstFn(fireproximityprompt)
Env.setclipboard      = firstFn(setclipboard, toclipboard, (syn and syn.write_clipboard))
Env.setfpscap         = firstFn(setfpscap)
Env.getcustomasset    = firstFn(getcustomasset, getsynasset)
Env.protectgui        = firstFn(protectgui, (syn and syn.protect_gui))
Env.gethui            = firstFn(gethui, get_hidden_gui)
Env.request           = firstFn((syn and syn.request), (http and http.request), http_request, request)

-- debug.*
Env.debug = {
	getupvalues  = (debug and (debug.getupvalues or debug.getupvals)),
	setupvalue   = (debug and debug.setupvalue),
	getconstants = (debug and (debug.getconstants or debug.getconsts)),
	setconstant  = (debug and debug.setconstant),
	getproto     = (debug and debug.getproto),
	getprotos    = (debug and debug.getprotos),
	getinfo      = (debug and debug.getinfo),
	getstack     = (debug and debug.getstack),
	traceback    = (debug and debug.traceback) or function() return "" end,
}

-- filesystem
Env.fs = {
	writefile   = firstFn(writefile),
	readfile    = firstFn(readfile),
	appendfile  = firstFn(appendfile),
	isfile      = firstFn(isfile),
	isfolder    = firstFn(isfolder),
	makefolder  = firstFn(makefolder),
	listfiles   = firstFn(listfiles),
	delfile     = firstFn(delfile),
}
Env.hasFS = Env.fs.writefile ~= nil and Env.fs.readfile ~= nil and Env.fs.isfile ~= nil

--══════════════════════════════════════════════════════════════════════════
-- mapa de capacidades (mostrado na aba Ambiente da UI)
--══════════════════════════════════════════════════════════════════════════
Env.Caps = {
	{ key = "hookmetamethod",  label = "Hook de metamethod",   ok = Env.hookmetamethod ~= nil, critical = true,
	  note = "necessario para o Remote Spy" },
	{ key = "getrawmetatable", label = "Metatable bruta",      ok = Env.getrawmetatable ~= nil, critical = true },
	{ key = "newcclosure",     label = "C-closure",            ok = newcclosure ~= nil },
	{ key = "checkcaller",     label = "checkcaller",          ok = checkcaller ~= nil, critical = true,
	  note = "sem isso o spy loga as proprias chamadas" },
	{ key = "getcallingscript",label = "Script chamador",      ok = getcallingscript ~= nil },
	{ key = "hookfunction",    label = "Hook de funcao",       ok = Env.hookfunction ~= nil },
	{ key = "getgc",           label = "Garbage collector",    ok = Env.getgc ~= nil,
	  note = "usado pelo Scanner" },
	{ key = "getloadedmodules",label = "Modulos carregados",   ok = Env.getloadedmodules ~= nil },
	{ key = "getconnections",  label = "Conexoes de signal",   ok = Env.getconnections ~= nil },
	{ key = "getnilinstances", label = "Instancias nil",       ok = Env.getnilinstances ~= nil },
	{ key = "decompile",       label = "Decompilador",         ok = Env.decompile ~= nil },
	{ key = "upvalues",        label = "Upvalues (debug)",     ok = Env.debug.getupvalues ~= nil },
	{ key = "constants",       label = "Constantes (debug)",   ok = Env.debug.getconstants ~= nil },
	{ key = "filesystem",      label = "Sistema de arquivos",  ok = Env.hasFS,
	  note = "usado para salvar config e exportar logs" },
	{ key = "clipboard",       label = "Area de transferencia",ok = Env.setclipboard ~= nil },
	{ key = "gethui",          label = "GUI oculta",           ok = Env.gethui ~= nil },
	{ key = "http",            label = "HTTP request",         ok = Env.request ~= nil },
}

function Env.missingCritical()
	local out = {}
	for _, c in ipairs(Env.Caps) do
		if c.critical and not c.ok then table.insert(out, c.label) end
	end
	return out
end

function Env.supports(key)
	for _, c in ipairs(Env.Caps) do
		if c.key == key then return c.ok end
	end
	return false
end

--══════════════════════════════════════════════════════════════════════════
-- helpers
--══════════════════════════════════════════════════════════════════════════

--- Parenteia uma ScreenGui no lugar mais seguro disponivel.
function Env.mountGui(gui)
	if Env.protectgui then pcall(Env.protectgui, gui) end
	if Env.gethui then
		local ok, hui = pcall(Env.gethui)
		if ok and hui then
			gui.Parent = hui
			return gui
		end
	end
	local okCore = pcall(function() gui.Parent = Env.Services.CoreGui end)
	if okCore and gui.Parent then return gui end
	local plr = Env.LocalPlayer
	if plr then
		local pg = plr:FindFirstChildOfClass("PlayerGui")
		if pg then gui.Parent = pg end
	end
	return gui
end

--- Copia texto pra area de transferencia; retorna sucesso.
function Env.copy(text)
	if not Env.setclipboard then return false end
	local ok = pcall(Env.setclipboard, tostring(text))
	return ok
end

--- Garante que a pasta exista antes de escrever.
function Env.ensureFolder(path)
	if not Env.fs.isfolder or not Env.fs.makefolder then return false end
	local ok, exists = pcall(Env.fs.isfolder, path)
	if ok and exists then return true end
	return (pcall(Env.fs.makefolder, path))
end

--- Escrita segura de arquivo (cria pastas do caminho).
function Env.writeFile(path, content)
	if not Env.fs.writefile then return false, "sem filesystem" end
	local dir = ""
	for part in path:gmatch("([^/]+)/") do
		dir = dir .. part
		Env.ensureFolder(dir)
		dir = dir .. "/"
	end
	local ok, err = pcall(Env.fs.writefile, path, content)
	return ok, err
end

function Env.readFile(path)
	if not Env.fs.readfile or not Env.fs.isfile then return nil end
	local ok, exists = pcall(Env.fs.isfile, path)
	if not ok or not exists then return nil end
	local ok2, data = pcall(Env.fs.readfile, path)
	return ok2 and data or nil
end

--- Chamada segura de metodo em Instance (nao dispara __index custom do jogo).
function Env.safeIndex(obj, prop, default)
	local ok, v = pcall(function() return obj[prop] end)
	if ok then return v end
	return default
end

--- traceback limpo, sem as linhas internas do UNICLUDE
function Env.traceback(level)
	local raw = Env.debug.traceback("", level or 2)
	local lines = {}
	for line in tostring(raw):gmatch("[^\r\n]+") do
		if not line:find("UNICLUDE/", 1, true) then
			table.insert(lines, (line:gsub("^%s+", "")))
		end
	end
	return table.concat(lines, "\n")
end

return Env
