--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/App.lua
	Montagem final: cria a janela, registra as abas, liga os modulos e
	mantem a barra de status viva.

	Abas: Painel · Remotes · Explorer · Inventario · Logs · Scanner ·
	      Console · Ambiente · Ajustes
═══════════════════════════════════════════════════════════════════════════]]

local UNI     = ...
local Env     = UNI.require("src/core/Env")
local Util    = UNI.require("src/core/Util")
local Signal  = UNI.require("src/core/Signal")
local Config  = UNI.require("src/core/Config")
local Theme   = UNI.require("src/ui/Theme")
local Create  = UNI.require("src/ui/Create")
local Library = UNI.require("src/ui/Library")

local T, C = Theme, Theme.c

local App = {}
App.started = false

--══════════════════════════════════════════════════════════════════════════
-- PAINEL (visao geral)
--══════════════════════════════════════════════════════════════════════════
local function buildOverview(page, window, mods)
	Library.pageHeader(page, "Painel",
		"Estado da sessao, do lugar e do que o seu executor consegue fazer.")

	local body = Create.frame({
		Parent = page,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
	})

	local left = Create.frame({ Parent = body, Size = UDim2.new(0.5, -1, 1, 0) })
	local right = Create.frame({
		Parent = body,
		Position = UDim2.new(0.5, 1, 0, 0),
		Size = UDim2.new(0.5, -1, 1, 0),
	})
	Create.frame({
		Parent = body,
		BackgroundColor3 = C.strokeSoft,
		BackgroundTransparency = 0,
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, -12),
	})

	local kvLeft = Library.keyValue(left, {})
	local kvRight = Library.keyValue(right, {})

	--── esquerda: sessao + lugar + metricas ──────────────────────────────
	local function refreshLeft()
		kvLeft:Clear()

		kvLeft:Section("sessao")
		kvLeft:Row("versao", ("UNICLUDE %s (%s)"):format(UNI.Version, UNI.Codename), { color = C.accent })
		kvLeft:Row("modulos", #UNI.Order .. " carregados")
		kvLeft:Row("boot", ("%.2f s"):format(UNI.BootTime or 0))
		kvLeft:Row("tempo ativo", Util.duration(os.time() - UNI.StartedAt))
		kvLeft:Row("origem", UNI.Dev and "disco (modo dev)" or ("branch " .. UNI.Branch))
		kvLeft:Row("config", Config.LoadedFromDisk and Config.Path or "em memoria (sem filesystem)")

		kvLeft:Gap()
		kvLeft:Section("lugar")
		kvLeft:Row("PlaceId", tostring(game.PlaceId))
		kvLeft:Row("JobId", tostring(game.JobId))
		local placeName = "?"
		pcall(function()
			placeName = Env.Services.MarketplaceService:GetProductInfo(game.PlaceId).Name
		end)
		kvLeft:Row("nome", placeName, { tall = true })
		kvLeft:Row("jogadores", ("%d / %d"):format(#Env.Services.Players:GetPlayers(), Env.Services.Players.MaxPlayers))
		kvLeft:Row("voce", Env.LocalPlayer and Env.LocalPlayer.Name or "?")
		kvLeft:Row("UserId", Env.LocalPlayer and tostring(Env.LocalPlayer.UserId) or "?")

		kvLeft:Gap()
		kvLeft:Section("desempenho")
		local ping = "?"
		pcall(function()
			ping = ("%d ms"):format(Env.Services.Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
		end)
		kvLeft:Row("ping", ping, { color = C.info })
		local mem = "?"
		pcall(function()
			mem = Util.bytes(Env.Services.Stats:GetTotalMemoryUsageMb() * 1024 * 1024)
		end)
		kvLeft:Row("memoria", mem)
		kvLeft:Row("fps", tostring(math.floor(1 / math.max(Env.Services.RunService.Heartbeat:Wait(), 1 / 240))))
	end

	--── direita: capacidades + remotes mais chamados ─────────────────────
	local function refreshRight()
		kvRight:Clear()

		kvRight:Section("executor")
		kvRight:Row("nome", Env.ExecutorName, { color = C.accent })
		if Env.ExecutorVersion ~= "" then kvRight:Row("versao", Env.ExecutorVersion) end

		local missing = Env.missingCritical()
		kvRight:Row("estado", #missing == 0 and "todas as funcoes criticas presentes"
			or ("faltam: " .. table.concat(missing, ", ")),
			{ tall = true, color = #missing == 0 and C.success or C.danger })

		kvRight:Gap()
		kvRight:Section("capacidades")
		for _, cap in ipairs(Env.Caps) do
			kvRight:Row(cap.label, cap.ok and "disponivel" or "ausente",
				{ color = cap.ok and C.success or (cap.critical and C.danger or C.textFaint) })
		end

		kvRight:Gap()
		kvRight:Section("remotes mais chamados")
		local ranked = {}
		for path, bucket in pairs(mods.RemoteSpy.byRemote) do
			table.insert(ranked, { path = path, count = bucket.count, name = bucket.name, kind = bucket.kind })
		end
		table.sort(ranked, function(a, b) return a.count > b.count end)
		if #ranked == 0 then
			kvRight:Row("—", "nenhuma chamada capturada ainda", { color = C.textFaint })
		else
			for i, r in ipairs(ranked) do
				if i > 12 then break end
				kvRight:Row(r.name, ("%d chamadas"):format(r.count), { color = Theme.kindColor(r.kind) })
			end
		end
	end

	--── acoes rapidas na base ────────────────────────────────────────────
	local actions = Create.frame({
		Parent = page,
		Position = UDim2.new(0, 12, 1, -36),
		Size = UDim2.new(1, -24, 0, 28),
	})
	Create.list(actions, "h", 6)

	Library.Controls.button(actions, {
		text = "Atualizar painel", variant = "ghost", order = 1,
		onClick = function() refreshLeft(); refreshRight() end,
	})
	Library.Controls.button(actions, {
		text = "Mapear remotes do jogo", variant = "solid", order = 2,
		tooltip = "Lista todos os remotes existentes, mesmo os que nunca foram chamados",
		onClick = function()
			task.spawn(function()
				local found = mods.RemoteSpy.discover()
				local lines = { ("-- UNICLUDE · %d remotes encontrados"):format(#found), "" }
				for _, r in ipairs(found) do
					table.insert(lines, ("%-14s %s"):format(r.kind, r.path))
				end
				local ok, where = Config.export("mapa_remotes", table.concat(lines, "\n"), "txt")
				Library.notify(("%d remotes · %s"):format(#found, ok and where or "clipboard"), "ok", 4)
				if not ok then Env.copy(table.concat(lines, "\n")) end
			end)
		end,
	})
	Library.Controls.button(actions, {
		text = "Copiar diagnostico", variant = "ghost", order = 3,
		onClick = function()
			local lines = {
				"UNICLUDE " .. UNI.Version,
				"executor: " .. Env.ExecutorName .. " " .. Env.ExecutorVersion,
				"place: " .. game.PlaceId .. " job: " .. tostring(game.JobId),
				"modulos: " .. table.concat(UNI.Order, ", "),
				"capacidades ausentes: " .. (table.concat(Env.missingCritical(), ", ")),
				"chamadas capturadas: " .. mods.RemoteSpy.stats.total,
			}
			Env.copy(table.concat(lines, "\n"))
			Library.notify("Diagnostico copiado", "ok", 2)
		end,
	})

	task.spawn(function()
		refreshLeft()
		refreshRight()
		while page.Parent do
			task.wait(4)
			if page.Visible then
				refreshLeft()
				refreshRight()
			end
		end
	end)
end

--══════════════════════════════════════════════════════════════════════════
-- AJUSTES
--══════════════════════════════════════════════════════════════════════════
local function buildSettings(page, window, mods)
	Library.pageHeader(page, "Ajustes",
		"Tudo aqui e salvo em " .. Config.Path .. " e volta no proximo boot.")

	local scroll = Create.scroll({
		Parent = page,
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.new(1, -24, 1, -64),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	Create.list(scroll, "v", 6)

	local function group(title)
		local head = Create.text({
			Parent = scroll,
			Text = string.upper(title),
			Font = T.faces.bold,
			TextSize = T.font.micro,
			TextColor3 = C.textFaint,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = #scroll:GetChildren(),
		})
		local row = Create.frame({
			Parent = scroll,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = #scroll:GetChildren() + 1,
		})
		local layout = Create.list(row, "h", 6)
		layout.Wraps = true
		layout.FillDirection = Enum.FillDirection.Horizontal
		return row
	end

	local function toggle(parent, key, text, tooltip)
		return Library.Controls.toggle(parent, {
			text = text,
			value = Config.get(key),
			tooltip = tooltip,
			order = #parent:GetChildren(),
			onChange = function(v) Config.set(key, v) end,
		})
	end

	local g1 = group("captura de remotes")
	toggle(g1, "spyEnabled", "spy ligado", "Desliga a captura sem remover os hooks")
	toggle(g1, "logRemoteEvents", "RemoteEvent")
	toggle(g1, "logRemoteFunctions", "RemoteFunction")
	toggle(g1, "logUnreliable", "Unreliable")
	toggle(g1, "logBindables", "Bindables", "Ruidoso na maioria dos jogos")
	toggle(g1, "logReturns", "capturar retorno", "Guarda o que o servidor devolve em InvokeServer")
	toggle(g1, "groupIdentical", "agrupar identicas", "Chamadas repetidas viram uma linha com contador")
	toggle(g1, "captureCaller", "script chamador")
	toggle(g1, "captureTraceback", "traceback", "Custa performance em jogos que spammam remote")

	local g2 = group("console")
	toggle(g2, "captureOutput", "output")
	toggle(g2, "captureWarnings", "warnings")
	toggle(g2, "captureErrors", "errors")
	toggle(g2, "captureInfo", "info")
	toggle(g2, "logAutoScroll", "auto-scroll")

	local g3 = group("explorer e inventario")
	toggle(g3, "explorerShowNil", "instancias nil")
	toggle(g3, "inventoryAutoRefresh", "auto-scan do inventario")
	toggle(g3, "inventoryDeepScan", "varredura de memoria", "Usa getgc, mais lento")
	toggle(g3, "scannerIncludeCClosures", "incluir closures C no scanner")

	local g4 = group("interface")
	toggle(g4, "notifications", "notificacoes")

	Library.Controls.dropdown(g4, {
		prefix = "tecla: ",
		options = { "RightControl", "RightShift", "Insert", "Home", "F4", "LeftAlt" },
		value = Config.get("toggleKey"),
		order = 99,
		onChange = function(v)
			Config.set("toggleKey", v)
			Library.notify("Atalho agora e " .. v, "ok", 2)
		end,
	})

	local g5 = group("dados")
	Library.Controls.button(g5, {
		text = "Limpar bloqueados", variant = "ghost", order = 1,
		onClick = function()
			Config.clearList("blockedRemotes")
			Library.notify("Lista de bloqueio limpa", "info")
		end,
	})
	Library.Controls.button(g5, {
		text = "Limpar ignorados", variant = "ghost", order = 2,
		onClick = function()
			Config.clearList("ignoredRemotes")
			Library.notify("Lista de ignorados limpa", "info")
		end,
	})
	Library.Controls.button(g5, {
		text = "Restaurar padroes", variant = "danger", order = 3,
		onClick = function()
			Config.reset()
			Library.notify("Configuracao restaurada. Recarregue o script.", "warn", 5)
		end,
	})
	Library.Controls.button(g5, {
		text = "Salvar agora", variant = "solid", order = 4,
		onClick = function()
			local ok = Config.save()
			Library.notify(ok and "Configuracao salva" or "Sem filesystem", ok and "ok" or "warn")
		end,
	})

	-- listas ativas
	local listsTitle = Create.text({
		Parent = scroll,
		Text = "REMOTES BLOQUEADOS",
		Font = T.faces.bold,
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 900,
	})

	local blockedBox = Create.mono({
		Parent = scroll,
		Text = "",
		TextSize = T.font.small,
		TextColor3 = C.danger,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 901,
	})

	local function refreshLists()
		local blocked = {}
		for path in pairs(Config.all().blockedRemotes or {}) do
			table.insert(blocked, "⊘ " .. path)
		end
		table.sort(blocked)
		blockedBox.Text = #blocked > 0 and table.concat(blocked, "\n") or "nenhum remote bloqueado"
		blockedBox.TextColor3 = #blocked > 0 and C.danger or C.textFaint
	end

	Config.Changed:Connect(function(key)
		if key == "blockedRemotes" then refreshLists() end
	end)
	refreshLists()
end

--══════════════════════════════════════════════════════════════════════════
-- AMBIENTE
--══════════════════════════════════════════════════════════════════════════
local function buildEnvironment(page, window, mods)
	Library.pageHeader(page, "Ambiente",
		"O que o seu executor entrega e o que cada modulo do UNICLUDE carregou.")

	local split = Library.splitPane(page, {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		leftWidth = 420,
	})

	local kvCaps = Library.keyValue(split.left, {})
	local kvMods = Library.keyValue(split.right, {})

	kvCaps:Section("funcoes do executor")
	for _, cap in ipairs(Env.Caps) do
		kvCaps:Row(cap.label, cap.ok and "ok" or (cap.critical and "CRITICO: ausente" or "ausente"),
			{ color = cap.ok and C.success or (cap.critical and C.danger or C.textFaint) })
		if cap.note and not cap.ok then
			kvCaps:Row("  ↳", cap.note, { color = C.textFaint, tall = true })
		end
	end

	kvMods:Section("modulos carregados")
	for _, path in ipairs(UNI.Order) do
		kvMods:Row(path, UNI.Origin[path] or "?", {
			color = UNI.Origin[path] == "disco" and C.warn or C.textDim,
			onClick = function()
				Env.copy(UNI.Sources[path] or "")
				Library.notify("Fonte de " .. path .. " copiada", "ok", 2)
			end,
		})
	end

	kvMods:Gap()
	kvMods:Section("repositorio")
	kvMods:Row("base", UNI.Base, { tall = true })
	kvMods:Row("branch", UNI.Branch)
	kvMods:Row("loadstring",
		('loadstring(game:HttpGet("%sinit.lua"))()'):format(UNI.Base), { tall = true, color = C.accent })
end

--══════════════════════════════════════════════════════════════════════════
-- START
--══════════════════════════════════════════════════════════════════════════
function App:Start()
	if App.started then return end
	App.started = true

	if Config.get("theme") and Theme.palettes[Config.get("theme")] then
		Theme.use(Config.get("theme"))
	end

	-- modulos de feature
	local mods = {
		RemoteSpy = UNI.require("src/modules/RemoteSpy"),
		Explorer  = UNI.require("src/modules/Explorer"),
		Logs      = UNI.require("src/modules/Logs"),
		Inventory = UNI.require("src/modules/Inventory"),
		Scanner   = UNI.require("src/modules/Scanner"),
		Console   = UNI.require("src/modules/Console"),
		Config    = Config,
		Env       = Env,
		Util      = Util,
	}
	App.mods = mods
	for k, v in pairs(mods) do UNI.Modules[k] = v end

	-- janela
	local window = Library.window({
		title = "UNICLUDE",
		version = UNI.Version,
		subtitle = "monitor de remotes, workspace, logs e inventario",
	})
	App.window = window
	UNI.onCleanup(function() window:Destroy() end)

	-- abas
	window:SectionLabel("visao")
	local tabOverview = window:AddTab({ id = "Painel", label = "Painel", icon = "◈" })

	window:SectionLabel("captura")
	local tabRemotes = window:AddTab({ id = "Remotes", label = "Remotes", icon = "⇄",
		tooltip = "Toda chamada de RemoteEvent e RemoteFunction" })
	local tabLogs = window:AddTab({ id = "Logs", label = "Logs", icon = "≡",
		tooltip = "Output, warnings e erros com stack" })
	local tabScanner = window:AddTab({ id = "Scanner", label = "Scanner", icon = "◎",
		tooltip = "Memoria viva: gc, upvalues, constantes" })

	window:SectionLabel("mundo")
	local tabExplorer = window:AddTab({ id = "Explorer", label = "Explorer", icon = "▸" })
	local tabInventory = window:AddTab({ id = "Inventario", label = "Inventario", icon = "▤" })

	window:SectionLabel("ferramentas")
	local tabConsole = window:AddTab({ id = "Console", label = "Console", icon = "›" })
	local tabEnv = window:AddTab({ id = "Ambiente", label = "Ambiente", icon = "⚙" })
	local tabSettings = window:AddTab({ id = "Ajustes", label = "Ajustes", icon = "⚒" })

	-- conteudo
	buildOverview(tabOverview.page, window, mods)
	mods.RemoteSpy.buildPage(tabRemotes.page, window)
	mods.Logs.buildPage(tabLogs.page, window)
	mods.Scanner.buildPage(tabScanner.page, window)
	mods.Explorer.buildPage(tabExplorer.page, window)
	mods.Inventory.buildPage(tabInventory.page, window)
	mods.Console.buildPage(tabConsole.page, window)
	buildEnvironment(tabEnv.page, window, mods)
	buildSettings(tabSettings.page, window, mods)

	-- instalacao dos hooks
	mods.Logs.install()

	if Config.get("spyOnStart") then
		local ok = mods.RemoteSpy.install()
		window:SetStatus(ok and "capturando remotes" or "spy indisponivel neste executor",
			ok and C.accent or C.danger)
		if not ok then
			Library.notify("Remote Spy nao pode iniciar: executor sem hookmetamethod", "erro", 8)
		end
	else
		window:SetStatus("spy desligado", C.textFaint)
	end

	-- badges vivos nas abas
	task.spawn(function()
		while App.started do
			task.wait(1)
			local spyTotal = mods.RemoteSpy.stats.total
			tabRemotes:SetBadge(spyTotal > 0 and Util.compactNumber(spyTotal) or nil,
				mods.RemoteSpy.paused and C.warn or C.accentSoft)

			local errors = mods.Logs.counts.Error or 0
			tabLogs:SetBadge(errors > 0 and tostring(errors) or nil, C.danger)

			local invCount = #mods.Inventory.items
			tabInventory:SetBadge(invCount > 0 and Util.compactNumber(invCount) or nil, C.textFaint)
		end
	end)

	-- restaura a aba anterior
	local saved = Config.get("activeTab")
	if saved and window.tabs[saved] then window:SelectTab(saved) end

	Library.notify(("UNICLUDE %s pronto · %s para esconder")
		:format(UNI.Version, Config.get("toggleKey")), "accent", 5)
	mods.Logs.internal(("UNICLUDE %s iniciado em %.2fs"):format(UNI.Version, UNI.BootTime or 0))

	return App
end

function App:Focus()
	if App.window then App.window:Focus() end
end

return App
