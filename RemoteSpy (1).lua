--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/modules/RemoteSpy.lua
	Captura de RemoteEvent / UnreliableRemoteEvent / RemoteFunction /
	BindableEvent / BindableFunction.

	Estrategia de hook (em camadas, cada uma protegida por pcall):
	  1. __namecall  → pega remote:FireServer(...) (99% dos casos)
	  2. hookfunction nos metodos reais → pega remote.FireServer(remote, ...)
	  3. __index     → detecta acesso ao metodo, usado para inferir origem

	Recursos: log em anel, agrupamento de chamadas identicas, bloqueio,
	lista de ignorados, captura de retorno, script chamador, traceback,
	geracao de script de replay, spam controlado e exportacao.
═══════════════════════════════════════════════════════════════════════════]]

local UNI        = ...
local Env        = UNI.require("src/core/Env")
local Util       = UNI.require("src/core/Util")
local Signal     = UNI.require("src/core/Signal")
local Config     = UNI.require("src/core/Config")
local Serializer = UNI.require("src/core/Serializer")
local Theme      = UNI.require("src/ui/Theme")
local Create     = UNI.require("src/ui/Create")
local Library    = UNI.require("src/ui/Library")
local VirtualList= UNI.require("src/ui/VirtualList")

local T, C = Theme, Theme.c

local Spy = {}
Spy.Name = "RemoteSpy"

--══════════════════════════════════════════════════════════════════════════
-- ESTADO
--══════════════════════════════════════════════════════════════════════════
Spy.log       = Util.Ring.new(Config.get("maxRemoteLogs"))
Spy.byRemote  = {}        -- path -> { count, remote, lastClock, kind }
Spy.stats     = { total = 0, blocked = 0, perSecond = 0, sessionStart = os.clock() }
Spy.paused    = false
Spy.installed = false
Spy.Added     = Signal.new("Spy.Added")
Spy.Cleared   = Signal.new("Spy.Cleared")

local hooks = {}          -- funcoes de desinstalacao
local seq = 0
local recentWindow = {}

local METHODS = {
	FireServer     = { kind = "event",      remote = true },
	fireServer     = { kind = "event",      remote = true },
	InvokeServer   = { kind = "function",   remote = true, returns = true },
	invokeServer   = { kind = "function",   remote = true, returns = true },
	Fire           = { kind = "bindable",   remote = false },
	fire           = { kind = "bindable",   remote = false },
	Invoke         = { kind = "bindfunc",   remote = false, returns = true },
	invoke         = { kind = "bindfunc",   remote = false, returns = true },
}

--══════════════════════════════════════════════════════════════════════════
-- FILTRAGEM
--══════════════════════════════════════════════════════════════════════════
local function shouldLogClass(className)
	if className == "RemoteEvent" then return Config.get("logRemoteEvents") end
	if className == "UnreliableRemoteEvent" then return Config.get("logUnreliable") end
	if className == "RemoteFunction" then return Config.get("logRemoteFunctions") end
	if className == "BindableEvent" or className == "BindableFunction" then
		return Config.get("logBindables")
	end
	return false
end

local function argSignature(remotePath, method, args)
	local parts = { remotePath, method }
	for i = 1, (args.n or #args) do
		local v = args[i]
		local t = typeof(v)
		if t == "string" then
			parts[#parts + 1] = "s:" .. (#v > 48 and v:sub(1, 48) or v)
		elseif t == "number" or t == "boolean" then
			parts[#parts + 1] = t:sub(1, 1) .. ":" .. tostring(v)
		elseif t == "Instance" then
			parts[#parts + 1] = "i:" .. Env.safeIndex(v, "Name", "?")
		else
			parts[#parts + 1] = t
		end
	end
	return Util.shortHash(table.concat(parts, "|"))
end

--══════════════════════════════════════════════════════════════════════════
-- REGISTRO
--══════════════════════════════════════════════════════════════════════════
local function record(remote, method, args, meta)
	seq += 1

	local class = Env.safeIndex(remote, "ClassName", "?")
	local path  = Util.fullName(remote)
	local kind  = Util.remoteKind(remote)

	local signature = Config.get("groupIdentical")
		and argSignature(path, method, args) or nil

	-- agrupa com a ultima entrada se for identica
	if signature then
		local list = Spy.log:list()
		local last = list[#list]
		if last and last.signature == signature and (os.clock() - last.clock) < 12 then
			last.count += 1
			last.clock = os.clock()
			last.time = Util.timestampMs()
			Spy.stats.total += 1
			Spy.Added:Fire(last, true)
			return last
		end
	end

	local entry = {
		id        = seq,
		remote    = remote,
		name      = Env.safeIndex(remote, "Name", "?"),
		path      = path,
		class     = class,
		kind      = kind,
		method    = method,
		args      = args,
		argCount  = args.n or #args,
		returns   = nil,
		count     = 1,
		signature = signature,
		time      = Util.timestampMs(),
		clock     = os.clock(),
		caller    = meta and meta.caller,
		callerName= meta and meta.callerName,
		traceback = meta and meta.traceback,
		blocked   = meta and meta.blocked or false,
		via       = meta and meta.via or "namecall",
	}

	Spy.log:push(entry)
	Spy.stats.total += 1
	if entry.blocked then Spy.stats.blocked += 1 end

	local bucket = Spy.byRemote[path]
	if not bucket then
		bucket = { count = 0, remote = remote, kind = kind, class = class, name = entry.name, firstSeen = os.clock() }
		Spy.byRemote[path] = bucket
	end
	bucket.count += 1
	bucket.lastClock = os.clock()

	table.insert(recentWindow, os.clock())

	Spy.Added:Fire(entry, false)
	return entry
end

--══════════════════════════════════════════════════════════════════════════
-- HOOKS
--══════════════════════════════════════════════════════════════════════════
local function callerInfo()
	local info = {}
	if Config.get("captureCaller") then
		local ok, script = pcall(Env.getcallingscript)
		if ok and script then
			info.caller = script
			info.callerName = Util.fullName(script)
		end
	end
	if Config.get("captureTraceback") then
		local ok, tb = pcall(Env.traceback, 3)
		if ok then info.traceback = tb end
	end
	return info
end

local function handleCall(remote, method, args, via)
	if Spy.paused then return false end
	if not Config.get("spyEnabled") then return false end

	local class = Env.safeIndex(remote, "ClassName", "")
	if not shouldLogClass(class) then return false end

	local path = Util.fullName(remote)
	if Config.isIgnored(path) then return false end

	local blocked = Config.isBlocked(path)
	local meta = callerInfo()
	meta.blocked = blocked
	meta.via = via

	local entry = record(remote, method, args, meta)
	return blocked, entry
end

function Spy.install()
	if Spy.installed then return true end

	local mt = Env.getrawmetatable and Env.getrawmetatable(game)
	if not mt then
		Library.notify("Executor sem getrawmetatable: Remote Spy indisponivel", "erro", 6)
		return false
	end

	--── camada 1: __namecall ─────────────────────────────────────────────
	local okNamecall = pcall(function()
		local oldNamecall
		local replacement = Env.newcclosure(function(self, ...)
			local method = Env.getnamecallmethod()
			local spec = METHODS[method]

			if spec and not Env.checkcaller() and typeof(self) == "Instance" then
				if Util.isRemote(self) then
					local args = table.pack(...)
					local blocked, entry = handleCall(self, method, args, "namecall")
					if blocked then
						if spec.returns then return nil end
						return
					end
					if spec.returns and Config.get("logReturns") then
						local results = table.pack(oldNamecall(self, ...))
						if entry then entry.returns = results end
						return table.unpack(results, 1, results.n)
					end
				end
			end

			return oldNamecall(self, ...)
		end)

		if Env.hookmetamethod then
			oldNamecall = Env.hookmetamethod(game, "__namecall", replacement)
		else
			oldNamecall = mt.__namecall
			Env.setreadonly(mt, false)
			mt.__namecall = replacement
			Env.setreadonly(mt, true)
		end

		table.insert(hooks, function()
			pcall(function()
				if Env.hookmetamethod then
					Env.hookmetamethod(game, "__namecall", oldNamecall)
				else
					Env.setreadonly(mt, false)
					mt.__namecall = oldNamecall
					Env.setreadonly(mt, true)
				end
			end)
		end)
	end)

	--── camada 2: hookfunction nos metodos reais ─────────────────────────
	if Env.hookfunction then
		local samples = {
			{ class = "RemoteEvent",   method = "FireServer" },
			{ class = "RemoteFunction",method = "InvokeServer" },
			{ class = "BindableEvent", method = "Fire" },
			{ class = "BindableFunction", method = "Invoke" },
		}
		for _, sample in ipairs(samples) do
			pcall(function()
				local dummy = Instance.new(sample.class)
				local original = dummy[sample.method]
				local spec = METHODS[sample.method]
				local old
				old = Env.hookfunction(original, Env.newcclosure(function(self, ...)
					if not Env.checkcaller() and typeof(self) == "Instance" and Util.isRemote(self) then
						local args = table.pack(...)
						local blocked, entry = handleCall(self, sample.method, args, "direto")
						if blocked then
							if spec.returns then return nil end
							return
						end
						if spec.returns and Config.get("logReturns") then
							local results = table.pack(old(self, ...))
							if entry then entry.returns = results end
							return table.unpack(results, 1, results.n)
						end
					end
					return old(self, ...)
				end))
				dummy:Destroy()
				table.insert(hooks, function()
					pcall(Env.hookfunction, original, old)
				end)
			end)
		end
	end

	Spy.installed = okNamecall
	UNI.onCleanup(Spy.uninstall)

	-- amostragem de chamadas por segundo
	task.spawn(function()
		while Spy.installed do
			task.wait(1)
			local cutoff = os.clock() - 1
			for i = #recentWindow, 1, -1 do
				if recentWindow[i] < cutoff then table.remove(recentWindow, i) end
			end
			Spy.stats.perSecond = #recentWindow
		end
	end)

	return okNamecall
end

function Spy.uninstall()
	if not Spy.installed then return end
	for i = #hooks, 1, -1 do
		pcall(hooks[i])
		hooks[i] = nil
	end
	Spy.installed = false
end

function Spy.clear()
	Spy.log:clear()
	table.clear(Spy.byRemote)
	Spy.stats.total = 0
	Spy.stats.blocked = 0
	Spy.Cleared:Fire()
end

function Spy.setPaused(v)
	Spy.paused = v
end

--══════════════════════════════════════════════════════════════════════════
-- ACOES
--══════════════════════════════════════════════════════════════════════════
function Spy.scriptFor(entry)
	return Serializer.buildCallScript(entry, { maxDepth = Config.get("maxArgDepth") })
end

function Spy.replay(entry)
	local ok, err = pcall(function()
		local remote = entry.remote
		local args = entry.args
		if entry.method == "InvokeServer" or entry.method == "Invoke" then
			return remote[entry.method](remote, table.unpack(args, 1, args.n))
		end
		remote[entry.method](remote, table.unpack(args, 1, args.n))
	end)
	return ok, err
end

local spamThreads = {}

function Spy.spam(entry, interval)
	local key = entry.path .. entry.method
	if spamThreads[key] then
		task.cancel(spamThreads[key])
		spamThreads[key] = nil
		return false
	end
	spamThreads[key] = task.spawn(function()
		while true do
			pcall(Spy.replay, entry)
			task.wait(interval or 0.5)
		end
	end)
	return true
end

function Spy.stopAllSpam()
	for k, thread in pairs(spamThreads) do
		pcall(task.cancel, thread)
		spamThreads[k] = nil
	end
end
UNI.onCleanup(Spy.stopAllSpam)

function Spy.exportAll()
	local lines = {
		"-- UNICLUDE · dump de remotes",
		("-- %s · %d chamadas · jogo %d"):format(os.date("%Y-%m-%d %H:%M:%S"), Spy.stats.total, game.PlaceId),
		"",
	}
	for _, entry in ipairs(Spy.log:list()) do
		table.insert(lines, ("--[[ #%d · %s · x%d · %s ]]"):format(entry.id, entry.time, entry.count, entry.path))
		table.insert(lines, Serializer.buildCallScript(entry))
		table.insert(lines, ("-"):rep(72))
	end
	return table.concat(lines, "\n")
end

--══════════════════════════════════════════════════════════════════════════
-- VARREDURA DE REMOTES EXISTENTES
--══════════════════════════════════════════════════════════════════════════
function Spy.discover()
	local found = {}
	local roots = {
		Env.Services.ReplicatedStorage, Env.Services.Workspace,
		Env.Services.Lighting, Env.Services.StarterGui,
		Env.Services.StarterPack, Env.Services.SoundService,
	}
	local rf = Env.Services.ReplicatedStorage
	for _, root in ipairs(roots) do
		if root then
			pcall(function()
				for _, d in ipairs(root:GetDescendants()) do
					if Util.isRemote(d) then
						table.insert(found, {
							remote = d,
							path = Util.fullName(d),
							name = d.Name,
							class = d.ClassName,
							kind = Util.remoteKind(d),
						})
					end
				end
			end)
		end
	end
	if Env.getnilinstances then
		pcall(function()
			for _, inst in ipairs(Env.getnilinstances()) do
				if Util.isRemote(inst) then
					table.insert(found, {
						remote = inst, path = "[nil]." .. inst.Name, name = inst.Name,
						class = inst.ClassName, kind = Util.remoteKind(inst), orphan = true,
					})
				end
			end
		end)
	end
	table.sort(found, function(a, b) return a.path < b.path end)
	return found
end

--══════════════════════════════════════════════════════════════════════════
-- PAINEL
--══════════════════════════════════════════════════════════════════════════
function Spy.buildPage(page, window)
	local filter = { query = "", kind = "todos", onlyBlocked = false }
	local selected = nil

	--── toolbar ──────────────────────────────────────────────────────────
	local bar = Library.toolbar(page)

	local pauseBtn, pauseLabel = bar:Button({
		text = "Pausar", variant = "ghost",
		tooltip = "Congela a captura sem remover os hooks",
		onClick = function()
			Spy.setPaused(not Spy.paused)
			pauseLabel.Text = Spy.paused and "Retomar" or "Pausar"
			pauseLabel.TextColor3 = Spy.paused and C.warn or C.textDim
			window:SetStatus(Spy.paused and "captura pausada" or "capturando", Spy.paused and C.warn or C.accent)
		end,
	})

	bar:Button({
		text = "Limpar", variant = "ghost",
		tooltip = "Apaga o historico de chamadas",
		onClick = function()
			Spy.clear()
			Library.notify("Historico limpo", "info", 1.5)
		end,
	})

	bar:Separator()

	local search = bar:Input({
		placeholder = "Filtrar por nome, caminho ou argumento",
		icon = "⌕",
		Size = UDim2.new(0, 260, 0, T.metrics.inputHeight),
		debounce = 0.18,
		onChange = function(text) filter.query = text; Spy.refreshList() end,
	})

	bar:Dropdown({
		prefix = "tipo: ",
		options = {
			{ text = "todos", value = "todos" },
			{ text = "eventos", value = "event" },
			{ text = "funcoes", value = "function" },
			{ text = "unreliable", value = "unreliable" },
			{ text = "bindables", value = "bindable" },
		},
		value = "todos",
		onChange = function(v) filter.kind = v; Spy.refreshList() end,
	})

	bar:Separator()

	bar:Button({
		text = "Exportar", variant = "ghost",
		tooltip = "Salva todas as chamadas como script Luau",
		onClick = function()
			local content = Spy.exportAll()
			local ok, where = Config.export("remotes", content, "lua")
			Library.notify(ok and ("Salvo em " .. where) or ("Nao salvei: " .. where), ok and "ok" or "warn", 4)
		end,
	})

	local counter = bar:Counter({ label = "chamadas", color = C.accent })
	local rate = bar:Counter({ label = "por seg", color = C.info })

	--── split ────────────────────────────────────────────────────────────
	local split = Library.splitPane(page, {
		Position = UDim2.fromOffset(0, T.metrics.toolbarHeight),
		Size = UDim2.new(1, 0, 1, -T.metrics.toolbarHeight),
		leftWidth = 400, minLeft = 300, minRight = 320,
	})

	--── lista ────────────────────────────────────────────────────────────
	local listHolder = Create.frame({ Parent = split.left, Size = UDim2.fromScale(1, 1) })
	Create.padding(listHolder, 6, 4, 6, 6)

	local list
	list = VirtualList.new({
		Parent = listHolder,
		RowHeight = 38,
		StickToBottom = true,
		EmptyTitle = "Nenhuma chamada capturada",
		EmptyHint = "Interaja com o jogo. Toda chamada de remote aparece aqui em tempo real.",
		CreateRow = function()
			local row = Create.button({
				Text = "",
				BackgroundColor3 = C.panelAlt,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
			})
			Create.corner(row, T.radius.sm)
			Create.padding(row, 0, 8, 0, 8)

			local marker = Create.frame({
				Parent = row,
				BackgroundColor3 = C.accent,
				BackgroundTransparency = 0,
				Size = UDim2.fromOffset(3, 3),
				Position = UDim2.new(0, 0, 0, 8),
			})
			Create.corner(marker, T.radius.pill)

			local name = Create.text({
				Parent = row,
				Text = "",
				Font = T.faces.medium,
				TextSize = T.font.body,
				TextColor3 = C.text,
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -110, 0, 14),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})

			local sub = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.micro,
				TextColor3 = C.textFaint,
				Position = UDim2.fromOffset(10, 19),
				Size = UDim2.new(1, -110, 0, 12),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})

			local time = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.micro,
				TextColor3 = C.textFaint,
				Position = UDim2.new(1, -96, 0, 4),
				Size = UDim2.fromOffset(90, 14),
				TextXAlignment = Enum.TextXAlignment.Right,
			})

			local tag = Create.text({
				Parent = row,
				Text = "",
				Font = T.faces.bold,
				TextSize = T.font.micro,
				TextColor3 = C.accent,
				Position = UDim2.new(1, -96, 0, 19),
				Size = UDim2.fromOffset(90, 12),
				TextXAlignment = Enum.TextXAlignment.Right,
			})

			return row, { marker = marker, name = name, sub = sub, time = time, tag = tag }
		end,
		BindRow = function(api, entry, index, isSelected, frame)
			local color = Theme.kindColor(entry.kind)
			api.marker.BackgroundColor3 = entry.blocked and C.danger or color
			api.name.Text = entry.name
			api.name.TextColor3 = entry.blocked and C.textFaint or C.text

			local argPreview = {}
			for i = 1, math.min(entry.argCount, 4) do
				table.insert(argPreview, Serializer.preview(entry.args[i], 18))
			end
			if entry.argCount > 4 then table.insert(argPreview, "…") end
			api.sub.Text = ("%s(%s)"):format(entry.method, table.concat(argPreview, ", "))

			api.time.Text = entry.time
			api.tag.Text = entry.count > 1 and ("×" .. entry.count) or entry.kind
			api.tag.TextColor3 = entry.count > 1 and C.warn or color

			frame.BackgroundTransparency = isSelected and 0 or 1
			frame.BackgroundColor3 = isSelected and C.selected or C.panelAlt
		end,
		OnActivate = function(entry)
			selected = entry
			Spy.showDetail(entry)
		end,
		OnContext = function(entry, index, frame)
			local mouse = Env.Services.UserInputService:GetMouseLocation()
			Library.contextMenu({
				{ text = "Copiar script de replay", icon = "⧉", action = function()
					Env.copy(Spy.scriptFor(entry))
					Library.notify("Script copiado", "ok", 1.6)
				end },
				{ text = "Copiar caminho", icon = "⌁", action = function()
					Env.copy(entry.path)
					Library.notify("Caminho copiado", "ok", 1.6)
				end },
				{ text = "Executar de novo", icon = "▷", action = function()
					local ok, err = Spy.replay(entry)
					Library.notify(ok and "Chamada reenviada" or ("Falhou: " .. tostring(err)), ok and "ok" or "erro")
				end },
				{ text = "Spam a cada 0.5s", icon = "⟳", action = function()
					local started = Spy.spam(entry, 0.5)
					Library.notify(started and "Spam ligado" or "Spam desligado", "warn")
				end },
				{ separator = true },
				{ text = Config.isBlocked(entry.path) and "Desbloquear remote" or "Bloquear remote",
				  icon = "⊘", color = C.danger, action = function()
					Config.toggleBlocked(entry.path)
					Spy.refreshList()
					Library.notify(Config.isBlocked(entry.path) and "Remote bloqueado" or "Remote liberado", "warn")
				end },
				{ text = Config.isIgnored(entry.path) and "Parar de ignorar" or "Ignorar remote",
				  icon = "◌", action = function()
					Config.toggleIgnored(entry.path)
					Spy.refreshList()
				end },
			}, mouse.X, mouse.Y - 36)
		end,
	})

	--── detalhe ──────────────────────────────────────────────────────────
	local detail = Create.frame({ Parent = split.right, Size = UDim2.fromScale(1, 1) })

	local detailHeader = Create.frame({
		Parent = detail,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0,
	})
	Create.padding(detailHeader, 8, 10, 0, 12)

	local detailTitle = Create.text({
		Parent = detailHeader,
		Text = "Nenhuma chamada selecionada",
		Font = T.faces.bold,
		TextSize = T.font.heading,
		TextColor3 = C.textDim,
		Size = UDim2.new(1, -80, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local detailPath = Create.mono({
		Parent = detailHeader,
		Text = "clique numa linha da esquerda",
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, -80, 0, 14),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local seg = Library.segmented(detail, {
		options = {
			{ text = "Argumentos", value = "args" },
			{ text = "Script", value = "script" },
			{ text = "Origem", value = "origin" },
			{ text = "Retorno", value = "ret" },
		},
		value = "args",
		onChange = function(v) Spy.showDetail(selected, v) end,
	})
	seg.instance.Position = UDim2.fromOffset(10, 52)

	local detailBody = Create.frame({
		Parent = detail,
		Position = UDim2.fromOffset(8, 80),
		Size = UDim2.new(1, -16, 1, -122),
	})

	local codeView = Library.codeView(detailBody, {
		placeholder = "Selecione uma chamada para inspecionar os argumentos",
	})

	local kv = Library.keyValue(detailBody, {})
	kv.instance.Visible = false

	--── acoes do detalhe ─────────────────────────────────────────────────
	local actions = Create.frame({
		Parent = detail,
		Position = UDim2.new(0, 8, 1, -38),
		Size = UDim2.new(1, -16, 0, 30),
	})
	Create.list(actions, "h", 6)

	Library.Controls.button(actions, {
		text = "Copiar script", variant = "solid", order = 1,
		onClick = function()
			if not selected then return end
			Env.copy(Spy.scriptFor(selected))
			Library.notify("Script copiado pro clipboard", "ok", 1.8)
		end,
	})
	Library.Controls.button(actions, {
		text = "Executar", variant = "ghost", order = 2,
		onClick = function()
			if not selected then return end
			local ok, err = Spy.replay(selected)
			Library.notify(ok and "Enviado" or ("Erro: " .. tostring(err)), ok and "ok" or "erro")
		end,
	})
	Library.Controls.button(actions, {
		text = "Bloquear", variant = "danger", order = 3,
		onClick = function()
			if not selected then return end
			Config.toggleBlocked(selected.path)
			Library.notify(Config.isBlocked(selected.path) and "Bloqueado" or "Liberado", "warn")
			Spy.refreshList()
		end,
	})
	Library.Controls.button(actions, {
		text = "Salvar .lua", variant = "ghost", order = 4,
		onClick = function()
			if not selected then return end
			local ok, where = Config.export("remote_" .. selected.name, Spy.scriptFor(selected), "lua")
			Library.notify(ok and ("Salvo em " .. where) or where, ok and "ok" or "warn", 4)
		end,
	})

	--══════════════════════════════════════════════════════════════════════
	function Spy.showDetail(entry, mode)
		selected = entry
		mode = mode or seg:Get()

		if not entry then
			detailTitle.Text = "Nenhuma chamada selecionada"
			detailTitle.TextColor3 = C.textDim
			detailPath.Text = "clique numa linha da esquerda"
			codeView:Clear()
			return
		end

		detailTitle.Text = ("%s · %s"):format(entry.name, entry.method)
		detailTitle.TextColor3 = Theme.kindColor(entry.kind)
		detailPath.Text = entry.path

		codeView.instance.Visible = mode ~= "origin"
		kv.instance.Visible = mode == "origin"

		if mode == "args" then
			if entry.argCount == 0 then
				codeView:Set("-- chamada sem argumentos\n" .. entry.method .. "()")
			else
				local body = Serializer.argList(entry.args, { maxDepth = Config.get("maxArgDepth") })
				codeView:Set(("local args = {\n\t%s\n}"):format(body))
			end

		elseif mode == "script" then
			codeView:Set(Spy.scriptFor(entry))

		elseif mode == "ret" then
			if entry.returns and entry.returns.n > 0 then
				codeView:Set("local retorno = {\n\t" .. Serializer.argList(entry.returns) .. "\n}")
			elseif entry.method == "InvokeServer" or entry.method == "Invoke" then
				codeView:Set("-- retorno nao capturado\n-- ative 'Capturar retorno' nas configuracoes")
			else
				codeView:Set("-- " .. entry.method .. " nao retorna valor")
			end

		elseif mode == "origin" then
			kv:Clear()
			kv:Section("chamada")
			kv:Row("id", "#" .. entry.id)
			kv:Row("horario", entry.time)
			kv:Row("repeticoes", entry.count, { color = entry.count > 1 and C.warn or C.text })
			kv:Row("via", entry.via)
			kv:Row("classe", entry.class, { color = Theme.kindColor(entry.kind) })
			kv:Row("bloqueado", tostring(entry.blocked), { color = entry.blocked and C.danger or C.textDim })
			kv:Gap()
			kv:Section("origem")
			kv:Row("script", entry.callerName or "nao identificado",
				{ color = entry.callerName and C.text or C.textFaint })
			if entry.caller then
				kv:Row("classe do script", Env.safeIndex(entry.caller, "ClassName", "?"))
			end
			kv:Gap()
			kv:Section("traceback")
			kv:Row("pilha", entry.traceback or "captura desativada", { tall = true })
			kv:Gap()
			kv:Section("assinatura de tipos")
			kv:Row("tipos", Serializer.typeSignature(entry.args), { tall = true })
		end
	end

	--══════════════════════════════════════════════════════════════════════
	local function passesFilter(entry)
		if filter.kind ~= "todos" and entry.kind ~= filter.kind then return false end
		if filter.query ~= "" then
			local haystack = entry.name .. " " .. entry.path .. " " .. entry.method
			for i = 1, math.min(entry.argCount, 6) do
				haystack = haystack .. " " .. Serializer.preview(entry.args[i], 30)
			end
			if not Util.fuzzy(haystack, filter.query) then return false end
		end
		return true
	end

	local refresh = Util.throttle(function()
		local items = {}
		local pinned = {}
		for _, entry in ipairs(Spy.log:list()) do
			if passesFilter(entry) then
				if Config.isPinned(entry.path) then
					table.insert(pinned, entry)
				else
					table.insert(items, entry)
				end
			end
		end
		for i = #pinned, 1, -1 do table.insert(items, 1, pinned[i]) end
		list:SetItems(items)
		counter:Set(Util.compactNumber(Spy.stats.total))
		rate:Set(Spy.stats.perSecond)
		rate:SetColor(Spy.stats.perSecond > 30 and C.warn or C.info)
	end, 0.12)

	Spy.refreshList = refresh

	Spy.Added:Connect(function() refresh() end)
	Spy.Cleared:Connect(function()
		selected = nil
		Spy.showDetail(nil)
		refresh()
	end)

	task.spawn(function()
		while page.Parent do
			task.wait(1)
			rate:Set(Spy.stats.perSecond)
		end
	end)

	refresh()
	return { list = list, refresh = refresh }
end

return Spy
