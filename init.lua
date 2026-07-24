--!nocheck
--!nolint
--[[═══════════════════════════════════════════════════════════════════════════
	UNICLUDE  ·  bootstrap loader
	repo: https://github.com/yahmeh5-cmyk/UNICLUDE

	uso:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/yahmeh5-cmyk/UNICLUDE/main/init.lua"))()

	opcoes (defina ANTES do loadstring):
		getgenv().UNICLUDE_BRANCH = "main"     -- branch alternativa
		getgenv().UNICLUDE_DEV    = true       -- le de workspace/UNICLUDE/... via readfile
		getgenv().UNICLUDE_NOCACHE= true       -- ignora cache de sessao (recarrega tudo)
		getgenv().UNICLUDE_BUNDLE = { ["src/App"] = "...source..." } -- modo offline

	este arquivo NAO contem logica de UI nem de hook. ele so:
		1. resolve o ambiente de HTTP do executor
		2. baixa cada modulo do repo
		3. compila com um require() proprio (cache + deteccao de ciclo)
		4. inicia src/App
═══════════════════════════════════════════════════════════════════════════]]

local VERSION   = "1.0.0"
local CODENAME  = "citron"
local USER      = "yahmeh5-cmyk"
local REPO      = "UNICLUDE"

--══════════════════════════════════════════════════════════════════════════
-- 0. ambiente global
--══════════════════════════════════════════════════════════════════════════
local G = (typeof(getgenv) == "function" and getgenv()) or _G

if G.UNICLUDE and G.UNICLUDE.Running then
	local prev = G.UNICLUDE
	if prev.App and prev.App.Focus then
		pcall(function() prev.App:Focus() end)
		warn("[UNICLUDE] ja esta rodando — janela focada.")
		return prev
	end
	-- instancia zumbi: derruba antes de subir outra
	pcall(function() prev:Destroy() end)
end

local BRANCH  = tostring(G.UNICLUDE_BRANCH or "main")
local DEV     = G.UNICLUDE_DEV == true
local NOCACHE = G.UNICLUDE_NOCACHE == true
local BUNDLE  = type(G.UNICLUDE_BUNDLE) == "table" and G.UNICLUDE_BUNDLE or nil
local BASE    = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(USER, REPO, BRANCH)
local DEVDIR  = "UNICLUDE/"

--══════════════════════════════════════════════════════════════════════════
-- 1. camada HTTP
--══════════════════════════════════════════════════════════════════════════
local requestFn =
	(syn and syn.request)
	or (http and http.request)
	or (fluxus and fluxus.request)
	or http_request
	or request

local function rawGet(url)
	if requestFn then
		local ok, res = pcall(requestFn, { Url = url, Method = "GET", Headers = { ["Cache-Control"] = "no-cache" } })
		if ok and type(res) == "table" then
			local code = res.StatusCode or res.Status or 0
			if code >= 200 and code < 300 and res.Body and #res.Body > 0 then
				return res.Body
			end
			if code == 404 then return nil, "404 nao encontrado" end
		end
	end
	local ok, body = pcall(function() return game:HttpGet(url, true) end)
	if ok and type(body) == "string" and #body > 0 then
		if body:sub(1, 15) == "404: Not Found" then return nil, "404 nao encontrado" end
		return body
	end
	return nil, tostring(body)
end

local function fetch(url, attempts)
	attempts = attempts or 3
	local lastErr
	for i = 1, attempts do
		local body, err = rawGet(url)
		if body then return body end
		lastErr = err
		if err == "404 nao encontrado" then break end
		task.wait(0.35 * i)
	end
	return nil, lastErr
end

--══════════════════════════════════════════════════════════════════════════
-- 2. resolucao de fonte por modulo
--══════════════════════════════════════════════════════════════════════════
local function sourceFor(path)
	-- path exemplo: "src/core/Util"
	if BUNDLE and BUNDLE[path] then
		return BUNDLE[path], "bundle"
	end

	local file = path .. ".lua"

	if DEV and isfile and readfile then
		local local_ = DEVDIR .. file
		local ok, exists = pcall(isfile, local_)
		if ok and exists then
			local ok2, src = pcall(readfile, local_)
			if ok2 and src and #src > 0 then return src, "disco" end
		end
	end

	local url = BASE .. file
	if NOCACHE or DEV then
		url = url .. "?nc=" .. tostring(math.floor(os.clock() * 1000)) .. tostring(math.random(1e4))
	end
	local src, err = fetch(url)
	if not src then
		return nil, nil, ("nao consegui baixar %s (%s)"):format(file, tostring(err))
	end
	return src, "rede"
end

--══════════════════════════════════════════════════════════════════════════
-- 3. objeto UNICLUDE + require proprio
--══════════════════════════════════════════════════════════════════════════
local UNI
UNI = {
	Version   = VERSION,
	Codename  = CODENAME,
	Base      = BASE,
	Branch    = BRANCH,
	Dev       = DEV,
	Running   = false,
	StartedAt = os.time(),
	Cache     = {},   -- path -> retorno do modulo
	Sources   = {},   -- path -> source string
	Origin    = {},   -- path -> "rede"|"disco"|"bundle"
	Loading   = {},   -- deteccao de ciclo
	Order     = {},   -- ordem de carga (debug)
	Modules   = {},   -- alias amigavel -> retorno
	Cleanup   = {},   -- funcoes de desligamento
}

local function fail(msg, detail)
	local text = "[UNICLUDE] " .. tostring(msg)
	if detail then text = text .. "\n    ↳ " .. tostring(detail) end
	warn(text)
	error(text, 0)
end

function UNI.require(path)
	path = path:gsub("%.lua$", ""):gsub("^%./", "")

	local cached = UNI.Cache[path]
	if cached ~= nil then return cached end

	if UNI.Loading[path] then
		fail("dependencia circular detectada", path)
	end
	UNI.Loading[path] = true

	local src, origin, err = sourceFor(path)
	if not src then
		UNI.Loading[path] = nil
		fail("modulo ausente: " .. path, err)
	end

	local chunk, compileErr = loadstring(src, "@UNICLUDE/" .. path .. ".lua")
	if not chunk then
		UNI.Loading[path] = nil
		fail("erro de compilacao em " .. path, compileErr)
	end

	local ok, ret = pcall(chunk, UNI, path)
	UNI.Loading[path] = nil
	if not ok then
		fail("erro ao executar " .. path, ret)
	end
	if ret == nil then
		fail("modulo " .. path .. " nao retornou nada")
	end

	UNI.Cache[path]   = ret
	UNI.Sources[path] = src
	UNI.Origin[path]  = origin
	table.insert(UNI.Order, path)

	local alias = path:match("([^/]+)$")
	if alias and UNI.Modules[alias] == nil then UNI.Modules[alias] = ret end

	return ret
end

--- registra uma funcao para rodar no shutdown
function UNI.onCleanup(fn)
	if type(fn) == "function" then table.insert(UNI.Cleanup, fn) end
	return fn
end

--- desliga tudo (unhooks, GUI, conexoes)
function UNI:Destroy()
	for i = #UNI.Cleanup, 1, -1 do
		pcall(UNI.Cleanup[i])
		UNI.Cleanup[i] = nil
	end
	UNI.Running = false
	if G.UNICLUDE == UNI then G.UNICLUDE = nil end
end

--- recarrega um modulo em runtime (util no modo DEV)
function UNI.reload(path)
	UNI.Cache[path] = nil
	return UNI.require(path)
end

G.UNICLUDE = UNI

--══════════════════════════════════════════════════════════════════════════
-- 4. boot
--══════════════════════════════════════════════════════════════════════════
local t0 = os.clock()

local bootOk, bootErr = pcall(function()
	-- ordem explicita: garante mensagens de erro uteis se faltar arquivo
	UNI.require("src/core/Env")
	UNI.require("src/core/Signal")
	UNI.require("src/core/Util")
	UNI.require("src/core/Serializer")
	UNI.require("src/core/Config")

	UNI.require("src/ui/Theme")
	UNI.require("src/ui/Create")
	UNI.require("src/ui/Highlighter")
	UNI.require("src/ui/VirtualList")
	UNI.require("src/ui/Library")

	local App = UNI.require("src/App")
	UNI.App = App
	App:Start()
end)

if not bootOk then
	warn("[UNICLUDE] falha no boot:\n" .. tostring(bootErr))
	pcall(function() UNI:Destroy() end)
	return UNI
end

UNI.Running  = true
UNI.BootTime = os.clock() - t0

print(("[UNICLUDE] v%s (%s) · %d modulos · %.2fs · %s")
	:format(VERSION, CODENAME, #UNI.Order, UNI.BootTime, DEV and "modo dev" or BRANCH))

return UNI
