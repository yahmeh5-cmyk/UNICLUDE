--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/modules/Scanner.lua
	Varredura de memoria: garbage collector, upvalues, constantes, modulos
	carregados e conexoes de signal.

	Serve para achar o que o Remote Spy nao mostra: a funcao que monta os
	argumentos, a tabela de configuracao do jogo, o modulo que guarda o
	inventario, o handler que valida seu input.

	Tudo roda em pedacos com task.wait para nao congelar o cliente.
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

local Scanner = {}
Scanner.Name = "Scanner"
Scanner.results = {}
Scanner.Updated = Signal.new("Scanner.Updated")
Scanner.busy = false

--══════════════════════════════════════════════════════════════════════════
-- HELPERS
--══════════════════════════════════════════════════════════════════════════
local function funcLabel(fn)
	if not Env.debug.getinfo then return "function" end
	local ok, info = pcall(Env.debug.getinfo, fn)
	if not ok or not info then return "function" end
	local name = info.name
	if name == nil or name == "" then name = "anonima" end
	local src = tostring(info.short_src or info.source or "?")
	return ("%s @ %s:%s"):format(name, src, tostring(info.linedefined or "?"))
end

local function safeCount(t)
	local n = 0
	local ok = pcall(function()
		for _ in pairs(t) do
			n += 1
			if n > 5000 then return end
		end
	end)
	return n
end

local function push(kind, label, detail, ref, extra)
	table.insert(Scanner.results, {
		kind = kind,
		label = label,
		detail = detail,
		ref = ref,
		extra = extra,
	})
end

--══════════════════════════════════════════════════════════════════════════
-- MODOS DE VARREDURA
--══════════════════════════════════════════════════════════════════════════

--- Tabelas vivas cujo conteudo casa com a busca
function Scanner.scanTables(query, limit)
	if not Env.getgc then return "executor sem getgc" end
	local scanned, matched = 0, 0

	for _, obj in ipairs(Env.getgc(true)) do
		if matched >= limit then break end
		scanned += 1
		if scanned % 4000 == 0 then task.wait() end

		if type(obj) == "table" then
			local ok = pcall(function()
				for k, v in pairs(obj) do
					if matched >= limit then break end
					local keyStr = tostring(k)
					local valStr = type(v) == "table" and "table" or tostring(v)
					if Util.fuzzy(keyStr, query) or (#valStr < 200 and Util.fuzzy(valStr, query)) then
						matched += 1
						push("tabela", keyStr,
							("%s = %s  ·  %d chaves"):format(keyStr, Serializer.preview(v, 44), safeCount(obj)),
							obj, { key = k, value = v })
						break
					end
				end
			end)
		end
	end

	return ("%d tabelas varridas · %d resultados"):format(scanned, matched)
end

--- Funcoes Lua cujo nome, fonte ou constantes casam com a busca
function Scanner.scanFunctions(query, limit)
	if not Env.getgc then return "executor sem getgc" end
	local scanned, matched = 0, 0
	local includeC = Config.get("scannerIncludeCClosures")

	for _, obj in ipairs(Env.getgc(false)) do
		if matched >= limit then break end
		scanned += 1
		if scanned % 3000 == 0 then task.wait() end

		if type(obj) == "function" then
			local isL = Env.islclosure(obj)
			if isL or includeC then
				local label = funcLabel(obj)
				local hit = Util.fuzzy(label, query)

				if not hit and isL and Env.debug.getconstants then
					local ok, consts = pcall(Env.debug.getconstants, obj)
					if ok and consts then
						for _, const in ipairs(consts) do
							if type(const) == "string" and Util.fuzzy(const, query) then
								hit = true
								break
							end
						end
					end
				end

				if hit then
					matched += 1
					push("funcao", label, isL and "closure Lua" or "closure C", obj)
				end
			end
		end
	end

	return ("%d objetos varridos · %d funcoes"):format(scanned, matched)
end

--- Upvalues de todas as funcoes vivas
function Scanner.scanUpvalues(query, limit)
	if not Env.getgc or not Env.debug.getupvalues then
		return "executor sem getgc/debug.getupvalues"
	end
	local matched, scanned = 0, 0

	for _, obj in ipairs(Env.getgc(false)) do
		if matched >= limit then break end
		if type(obj) == "function" and Env.islclosure(obj) then
			scanned += 1
			if scanned % 800 == 0 then task.wait() end
			local ok, ups = pcall(Env.debug.getupvalues, obj)
			if ok and ups then
				for index, value in pairs(ups) do
					if matched >= limit then break end
					local preview = Serializer.preview(value, 48)
					if Util.fuzzy(preview, query) or Util.fuzzy(funcLabel(obj), query) then
						matched += 1
						push("upvalue", ("[%s] %s"):format(tostring(index), preview),
							funcLabel(obj), obj, { index = index, value = value })
					end
				end
			end
		end
	end

	return ("%d closures varridas · %d upvalues"):format(scanned, matched)
end

--- Strings constantes dentro das funcoes (otimo pra achar nomes de remote)
function Scanner.scanConstants(query, limit)
	if not Env.getgc or not Env.debug.getconstants then
		return "executor sem debug.getconstants"
	end
	local matched, scanned = 0, 0

	for _, obj in ipairs(Env.getgc(false)) do
		if matched >= limit then break end
		if type(obj) == "function" and Env.islclosure(obj) then
			scanned += 1
			if scanned % 800 == 0 then task.wait() end
			local ok, consts = pcall(Env.debug.getconstants, obj)
			if ok and consts then
				for i, const in ipairs(consts) do
					if matched >= limit then break end
					if type(const) == "string" and #const < 200 and Util.fuzzy(const, query) then
						matched += 1
						push("constante", const, funcLabel(obj), obj, { index = i, value = const })
					end
				end
			end
		end
	end

	return ("%d closures varridas · %d constantes"):format(scanned, matched)
end

--- ModuleScripts ja carregados
function Scanner.scanModules(query, limit)
	if not Env.getloadedmodules then return "executor sem getloadedmodules" end
	local matched = 0
	local ok, modules = pcall(Env.getloadedmodules)
	if not ok then return "getloadedmodules falhou" end

	for _, mod in ipairs(modules) do
		if matched >= limit then break end
		local path = Util.fullName(mod)
		if query == "" or Util.fuzzy(path, query) then
			matched += 1
			push("modulo", Env.safeIndex(mod, "Name", "?"), path, mod)
		end
	end

	return ("%d modulos carregados · %d resultados"):format(#modules, matched)
end

--- Conexoes ativas de signals comuns
function Scanner.scanConnections(query, limit)
	if not Env.getconnections then return "executor sem getconnections" end
	local matched = 0

	local targets = {
		{ name = "RunService.Heartbeat", signal = Env.Services.RunService.Heartbeat },
		{ name = "RunService.RenderStepped", signal = Env.Services.RunService.RenderStepped },
		{ name = "RunService.Stepped", signal = Env.Services.RunService.Stepped },
		{ name = "UIS.InputBegan", signal = Env.Services.UserInputService.InputBegan },
		{ name = "UIS.InputEnded", signal = Env.Services.UserInputService.InputEnded },
		{ name = "Players.PlayerAdded", signal = Env.Services.Players.PlayerAdded },
	}

	for _, target in ipairs(targets) do
		if matched >= limit then break end
		local ok, conns = pcall(Env.getconnections, target.signal)
		if ok and conns then
			for i, conn in ipairs(conns) do
				if matched >= limit then break end
				local fnLabel = conn.Function and funcLabel(conn.Function) or "handler C"
				if query == "" or Util.fuzzy(target.name .. " " .. fnLabel, query) then
					matched += 1
					push("conexao", target.name, fnLabel, conn, { index = i })
				end
			end
		end
	end

	return ("%d conexoes listadas"):format(matched)
end

--══════════════════════════════════════════════════════════════════════════
-- EXECUCAO
--══════════════════════════════════════════════════════════════════════════
local MODES = {
	tabelas    = Scanner.scanTables,
	funcoes    = Scanner.scanFunctions,
	upvalues   = Scanner.scanUpvalues,
	constantes = Scanner.scanConstants,
	modulos    = Scanner.scanModules,
	conexoes   = Scanner.scanConnections,
}

function Scanner.run(mode, query, onDone)
	if Scanner.busy then return end
	Scanner.busy = true
	table.clear(Scanner.results)

	task.spawn(function()
		local fn = MODES[mode]
		local summary = "modo desconhecido"
		if fn then
			local ok, result = pcall(fn, query, Config.get("scannerMaxResults"))
			summary = ok and tostring(result) or ("erro: " .. tostring(result))
		end
		Scanner.busy = false
		Scanner.Updated:Fire(Scanner.results, summary)
		if onDone then onDone(summary) end
	end)
end

--══════════════════════════════════════════════════════════════════════════
-- PAINEL
--══════════════════════════════════════════════════════════════════════════
function Scanner.buildPage(page, window)
	local mode = "constantes"
	local query = ""
	local selected = nil

	local bar = Library.toolbar(page)

	bar:Dropdown({
		prefix = "modo: ",
		options = { "constantes", "funcoes", "upvalues", "tabelas", "modulos", "conexoes" },
		value = mode,
		Size = UDim2.new(0, 160, 0, T.metrics.inputHeight),
		onChange = function(v) mode = v end,
	})

	local input = bar:Input({
		placeholder = "Termo de busca (nome, string, remote…)",
		icon = "⌕",
		Size = UDim2.new(0, 280, 0, T.metrics.inputHeight),
		onChange = function(text) query = text end,
		onSubmit = function() Scanner.trigger() end,
	})

	local runBtn, runLabel = bar:Button({
		text = "Varrer", variant = "solid",
		onClick = function() Scanner.trigger() end,
	})

	bar:Separator()

	bar:Button({
		text = "Exportar", variant = "ghost",
		onClick = function()
			local lines = { ("-- UNICLUDE · varredura (%s) · %s"):format(mode, os.date("%H:%M:%S")), "" }
			for _, r in ipairs(Scanner.results) do
				table.insert(lines, ("[%s] %s\n    %s"):format(r.kind, r.label, r.detail))
			end
			local ok, where = Config.export("scanner_" .. mode, table.concat(lines, "\n"), "txt")
			Library.notify(ok and ("Salvo em " .. where) or where, ok and "ok" or "warn", 4)
		end,
	})

	local counter = bar:Counter({ label = "achados", color = C.accent })

	--── aviso de capacidade ──────────────────────────────────────────────
	local warning
	if not Env.getgc then
		warning = Create.text({
			Parent = page,
			Text = "Seu executor nao expoe getgc. Modos de memoria ficam indisponiveis; modulos e conexoes ainda funcionam.",
			TextSize = T.font.small,
			TextColor3 = C.warn,
			Position = UDim2.fromOffset(12, T.metrics.toolbarHeight + 6),
			Size = UDim2.new(1, -24, 0, 16),
		})
	end

	local topOffset = T.metrics.toolbarHeight + (warning and 26 or 0)

	local split = Library.splitPane(page, {
		Position = UDim2.fromOffset(0, topOffset),
		Size = UDim2.new(1, 0, 1, -topOffset),
		leftWidth = 520, minLeft = 320, minRight = 280,
	})

	local listHolder = Create.frame({ Parent = split.left, Size = UDim2.fromScale(1, 1) })
	Create.padding(listHolder, 6, 4, 6, 6)

	local list
	list = VirtualList.new({
		Parent = listHolder,
		RowHeight = 32,
		EmptyTitle = "Nenhuma varredura ainda",
		EmptyHint = "Escolha um modo, digite um termo (ex: o nome de um remote) e clique em Varrer.",
		CreateRow = function()
			local row = Create.button({
				Text = "",
				BackgroundColor3 = C.panelAlt,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
			})
			Create.corner(row, T.radius.sm)
			Create.padding(row, 0, 8, 0, 8)

			local kind = Create.text({
				Parent = row,
				Text = "",
				Font = T.faces.bold,
				TextSize = T.font.micro,
				TextColor3 = C.info,
				Size = UDim2.fromOffset(76, 32),
			})

			local label = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.small,
				TextColor3 = C.text,
				Position = UDim2.fromOffset(82, 3),
				Size = UDim2.new(1, -90, 0, 14),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})

			local detail = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.micro,
				TextColor3 = C.textFaint,
				Position = UDim2.fromOffset(82, 17),
				Size = UDim2.new(1, -90, 0, 12),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})

			return row, { kind = kind, label = label, detail = detail }
		end,
		BindRow = function(api, item, index, isSelected, frame)
			api.kind.Text = item.kind
			api.kind.TextColor3 = item.kind == "constante" and C.success
				or item.kind == "funcao" and C.magenta
				or item.kind == "upvalue" and C.warn
				or C.info
			api.label.Text = item.label
			api.detail.Text = item.detail
			frame.BackgroundTransparency = isSelected and 0 or 1
			frame.BackgroundColor3 = isSelected and C.selected or C.panelAlt
		end,
		OnActivate = function(item)
			selected = item
			Scanner.showDetail(item)
		end,
		OnContext = function(item)
			local mouse = Env.Services.UserInputService:GetMouseLocation()
			Library.contextMenu({
				{ text = "Copiar rotulo", icon = "⧉", action = function() Env.copy(item.label) end },
				{ text = "Copiar detalhe", icon = "⧉", action = function() Env.copy(item.detail) end },
			}, mouse.X, mouse.Y - 36)
		end,
	})

	--── detalhe ──────────────────────────────────────────────────────────
	local kv = Library.keyValue(split.right, {})
	kv:Empty("Selecione um resultado")

	function Scanner.showDetail(item)
		kv:Clear()
		kv:Section(item.kind)
		kv:Row("rotulo", item.label, { tall = true })
		kv:Row("detalhe", item.detail, { tall = true })

		if item.kind == "funcao" and Env.debug.getconstants then
			local ok, consts = pcall(Env.debug.getconstants, item.ref)
			if ok and consts then
				kv:Gap()
				kv:Section("constantes")
				for i, const in ipairs(consts) do
					if i > 60 then break end
					kv:Row("[" .. i .. "]", Serializer.preview(const, 60),
						{ color = Theme.typeColor(typeof(const)) })
				end
			end
			if Env.debug.getupvalues then
				local ok2, ups = pcall(Env.debug.getupvalues, item.ref)
				if ok2 and ups and next(ups) then
					kv:Gap()
					kv:Section("upvalues")
					for i, up in pairs(ups) do
						kv:Row("[" .. tostring(i) .. "]", Serializer.preview(up, 60),
							{ color = Theme.typeColor(typeof(up)) })
					end
				end
			end
		end

		if item.kind == "tabela" and type(item.ref) == "table" then
			kv:Gap()
			kv:Section("conteudo")
			local shown = 0
			for k, v in pairs(item.ref) do
				shown += 1
				if shown > 80 then break end
				kv:Row(tostring(k), Serializer.preview(v, 60), { color = Theme.typeColor(typeof(v)) })
			end
		end

		if item.kind == "modulo" then
			kv:Gap()
			kv:Section("acoes")
			kv:Row("caminho", Util.instancePath(item.ref), { tall = true, color = C.accent })
			if Env.decompile then
				kv:Row("decompilar", "clique aqui", { color = C.info, onClick = function()
					task.spawn(function()
						local ok, src = pcall(Env.decompile, item.ref)
						if ok and src then
							Env.copy(src)
							Library.notify("Fonte copiada", "ok", 3)
						else
							Library.notify("Decompilacao falhou", "erro", 3)
						end
					end)
				end })
			end
		end

		if item.kind == "conexao" then
			kv:Gap()
			kv:Section("controle")
			kv:Row("desconectar", "clique aqui", { color = C.danger, onClick = function()
				local ok = pcall(function() item.ref:Disable() end)
				if not ok then pcall(function() item.ref:Disconnect() end) end
				Library.notify(ok and "Conexao desabilitada" or "Nao consegui", ok and "warn" or "erro")
			end })
		end
	end

	--══════════════════════════════════════════════════════════════════════
	function Scanner.trigger()
		if Scanner.busy then
			Library.notify("Varredura em andamento", "warn", 1.5)
			return
		end
		runLabel.Text = "Varrendo…"
		window:SetStatus("varrendo memoria em modo " .. mode, C.info)
		Scanner.run(mode, query, function(summary)
			runLabel.Text = "Varrer"
			window:SetStatus(summary, C.textFaint)
			Library.notify(summary, "info", 3)
		end)
	end

	Scanner.Updated:Connect(function(results)
		list:SetItems(results)
		counter:Set(#results)
	end)

	return { list = list }
end

return Scanner
