--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/modules/Logs.lua
	Console unificado: LogService (output/info/warning/error), erros de
	script com stack, print/warn interceptados e eventos internos do UNICLUDE.

	Cada linha guarda nivel, horario, mensagem completa e stack quando existe.
	Filtro por nivel, busca, auto-scroll, exportacao e agrupamento de spam.
═══════════════════════════════════════════════════════════════════════════]]

local UNI     = ...
local Env     = UNI.require("src/core/Env")
local Util    = UNI.require("src/core/Util")
local Signal  = UNI.require("src/core/Signal")
local Config  = UNI.require("src/core/Config")
local Theme   = UNI.require("src/ui/Theme")
local Create  = UNI.require("src/ui/Create")
local Library = UNI.require("src/ui/Library")
local VirtualList = UNI.require("src/ui/VirtualList")

local T, C = Theme, Theme.c
local LogService = Env.Services.LogService

local Logs = {}
Logs.Name = "Logs"
Logs.entries = Util.Ring.new(Config.get("maxConsoleLogs"))
Logs.Added = Signal.new("Logs.Added")
Logs.Cleared = Signal.new("Logs.Cleared")
Logs.counts = { Output = 0, Info = 0, Warning = 0, Error = 0, Uniclude = 0 }
Logs.installed = false

local maid = Signal.newMaid()
local seq = 0

local TYPE_MAP = {
	[Enum.MessageType.MessageOutput]  = "Output",
	[Enum.MessageType.MessageInfo]    = "Info",
	[Enum.MessageType.MessageWarning] = "Warning",
	[Enum.MessageType.MessageError]   = "Error",
}

--══════════════════════════════════════════════════════════════════════════
-- REGISTRO
--══════════════════════════════════════════════════════════════════════════
function Logs.push(level, message, extra)
	message = tostring(message)

	-- agrupa repeticao imediata
	local list = Logs.entries:list()
	local last = list[#list]
	if last and last.level == level and last.message == message then
		last.count += 1
		last.time = Util.timestampMs()
		Logs.Added:Fire(last, true)
		return last
	end

	seq += 1
	local entry = {
		id = seq,
		level = level,
		message = message,
		short = Util.oneLine(message, 220),
		time = Util.timestampMs(),
		clock = os.clock(),
		stack = extra and extra.stack,
		source = extra and extra.source,
		count = 1,
	}

	Logs.entries:push(entry)
	Logs.counts[level] = (Logs.counts[level] or 0) + 1
	Logs.Added:Fire(entry, false)
	return entry
end

--- Log interno do UNICLUDE (aparece com cor propria)
function Logs.internal(message)
	return Logs.push("Uniclude", message)
end

function Logs.clear()
	Logs.entries:clear()
	for k in pairs(Logs.counts) do Logs.counts[k] = 0 end
	Logs.Cleared:Fire()
end

--══════════════════════════════════════════════════════════════════════════
-- CAPTURA
--══════════════════════════════════════════════════════════════════════════
local function levelEnabled(level)
	if level == "Output"  then return Config.get("captureOutput") end
	if level == "Info"    then return Config.get("captureInfo") end
	if level == "Warning" then return Config.get("captureWarnings") end
	if level == "Error"   then return Config.get("captureErrors") end
	return true
end

function Logs.install()
	if Logs.installed then return end

	if LogService then
		maid:Add(LogService.MessageOut:Connect(function(message, messageType)
			local level = TYPE_MAP[messageType] or "Output"
			if not levelEnabled(level) then return end
			Logs.push(level, message)
		end))

		-- historico ja existente
		pcall(function()
			for _, item in ipairs(LogService:GetLogHistory()) do
				local level = TYPE_MAP[item.messageType] or "Output"
				if levelEnabled(level) then
					Logs.push(level, item.message)
				end
			end
		end)
	end

	-- erros de script com stack completo
	pcall(function()
		local ScriptContext = game:GetService("ScriptContext")
		maid:Add(ScriptContext.Error:Connect(function(message, stack, source)
			if not Config.get("captureErrors") then return end
			Logs.push("Error", message, {
				stack = stack,
				source = source and Util.fullName(source) or nil,
			})
		end))
	end)

	Logs.installed = true
	UNI.onCleanup(function()
		maid:Clean()
		Logs.installed = false
	end)

	Logs.internal("Captura de logs ativa · executor " .. Env.ExecutorName)
end

--══════════════════════════════════════════════════════════════════════════
-- EXPORTACAO
--══════════════════════════════════════════════════════════════════════════
function Logs.export(filtered)
	local lines = {
		("UNICLUDE · log de console · %s"):format(os.date("%Y-%m-%d %H:%M:%S")),
		("place %d · job %s"):format(game.PlaceId, tostring(game.JobId)),
		("-"):rep(72),
	}
	for _, e in ipairs(filtered or Logs.entries:list()) do
		table.insert(lines, ("[%s] %-8s %s%s"):format(
			e.time, e.level, e.message, e.count > 1 and (" (x" .. e.count .. ")") or ""))
		if e.stack then
			table.insert(lines, "    stack: " .. tostring(e.stack):gsub("\n", "\n    "))
		end
	end
	return table.concat(lines, "\n")
end

--══════════════════════════════════════════════════════════════════════════
-- PAINEL
--══════════════════════════════════════════════════════════════════════════
function Logs.buildPage(page, window)
	local filter = { query = "", level = "todos" }
	local selected = nil
	local autoScroll = Config.get("logAutoScroll")

	local bar = Library.toolbar(page)

	bar:Button({
		text = "Limpar", variant = "ghost",
		onClick = function() Logs.clear() end,
	})

	bar:Separator()

	bar:Input({
		placeholder = "Buscar no console",
		icon = "⌕",
		Size = UDim2.new(0, 240, 0, T.metrics.inputHeight),
		debounce = 0.18,
		onChange = function(text) filter.query = text; Logs.refreshList() end,
	})

	bar:Dropdown({
		prefix = "nivel: ",
		options = {
			{ text = "todos", value = "todos" },
			{ text = "output", value = "Output" },
			{ text = "warning", value = "Warning" },
			{ text = "error", value = "Error" },
			{ text = "info", value = "Info" },
			{ text = "uniclude", value = "Uniclude" },
		},
		value = "todos",
		onChange = function(v) filter.level = v; Logs.refreshList() end,
	})

	bar:Toggle({
		text = "auto-scroll",
		value = autoScroll,
		onChange = function(v)
			autoScroll = v
			Config.set("logAutoScroll", v)
		end,
	})

	bar:Separator()

	bar:Button({
		text = "Exportar", variant = "ghost",
		onClick = function()
			local ok, where = Config.export("console", Logs.export(), "txt")
			Library.notify(ok and ("Salvo em " .. where) or where, ok and "ok" or "warn", 4)
		end,
	})

	local errCounter = bar:Counter({ label = "erros", color = C.danger })
	local warnCounter = bar:Counter({ label = "avisos", color = C.warn })

	--── corpo ────────────────────────────────────────────────────────────
	local split = Library.splitPane(page, {
		Position = UDim2.fromOffset(0, T.metrics.toolbarHeight),
		Size = UDim2.new(1, 0, 1, -T.metrics.toolbarHeight),
		leftWidth = 620, minLeft = 380, minRight = 240,
	})

	local listHolder = Create.frame({ Parent = split.left, Size = UDim2.fromScale(1, 1) })
	Create.padding(listHolder, 4, 4, 6, 6)

	local list
	list = VirtualList.new({
		Parent = listHolder,
		RowHeight = 20,
		Gap = 1,
		StickToBottom = true,
		EmptyTitle = "Console vazio",
		EmptyHint = "Nada foi impresso ainda. print, warn e erros de script aparecem aqui.",
		CreateRow = function()
			local row = Create.button({
				Text = "",
				BackgroundColor3 = C.panelAlt,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
			})
			Create.corner(row, T.radius.sm)

			local time = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.micro,
				TextColor3 = C.textFaint,
				Position = UDim2.fromOffset(6, 0),
				Size = UDim2.fromOffset(72, 20),
			})

			local level = Create.text({
				Parent = row,
				Text = "",
				Font = T.faces.bold,
				TextSize = T.font.micro,
				TextColor3 = C.textDim,
				Position = UDim2.fromOffset(80, 0),
				Size = UDim2.fromOffset(52, 20),
			})

			local msg = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.small,
				TextColor3 = C.text,
				Position = UDim2.fromOffset(136, 0),
				Size = UDim2.new(1, -180, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})

			local badge = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.micro,
				TextColor3 = C.warn,
				Position = UDim2.new(1, -42, 0, 0),
				Size = UDim2.fromOffset(36, 20),
				TextXAlignment = Enum.TextXAlignment.Right,
			})

			return row, { time = time, level = level, msg = msg, badge = badge }
		end,
		BindRow = function(api, entry, index, isSelected, frame)
			local color = Theme.levelColor(entry.level)
			api.time.Text = entry.time
			api.level.Text = string.lower(entry.level)
			api.level.TextColor3 = color
			api.msg.Text = entry.short
			api.msg.TextColor3 = entry.level == "Error" and C.danger
				or entry.level == "Warning" and C.warn
				or C.text
			api.badge.Text = entry.count > 1 and ("×" .. entry.count) or ""
			frame.BackgroundTransparency = isSelected and 0 or 1
			frame.BackgroundColor3 = isSelected and C.selected or C.panelAlt
		end,
		OnActivate = function(entry)
			selected = entry
			Logs.showDetail(entry)
		end,
		OnContext = function(entry)
			local mouse = Env.Services.UserInputService:GetMouseLocation()
			Library.contextMenu({
				{ text = "Copiar mensagem", icon = "⧉", action = function()
					Env.copy(entry.message)
					Library.notify("Copiado", "ok", 1.4)
				end },
				{ text = "Copiar com stack", icon = "⧉", action = function()
					Env.copy(entry.message .. "\n\n" .. tostring(entry.stack or "sem stack"))
					Library.notify("Copiado", "ok", 1.4)
				end },
				{ separator = true },
				{ text = "Filtrar por esse nivel", icon = "⌕", action = function()
					filter.level = entry.level
					Logs.refreshList()
				end },
			}, mouse.X, mouse.Y - 36)
		end,
	})

	--── detalhe ──────────────────────────────────────────────────────────
	local detailHolder = Create.frame({ Parent = split.right, Size = UDim2.fromScale(1, 1) })
	Create.padding(detailHolder, 8, 8, 8, 8)

	local detailLevel = Create.text({
		Parent = detailHolder,
		Text = "detalhe",
		Font = T.faces.bold,
		TextSize = T.font.heading,
		TextColor3 = C.textDim,
		Size = UDim2.new(1, 0, 0, 18),
	})

	local detailScroll = Create.scroll({
		Parent = detailHolder,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 1, -24),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	Create.list(detailScroll, "v", 8)

	local detailMessage = Create.mono({
		Parent = detailScroll,
		Text = "Selecione uma linha para ver a mensagem completa.",
		TextSize = T.font.small,
		TextColor3 = C.textFaint,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 1,
	})

	local stackTitle = Create.text({
		Parent = detailScroll,
		Text = "STACK",
		Font = T.faces.bold,
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Size = UDim2.new(1, 0, 0, 14),
		Visible = false,
		LayoutOrder = 2,
	})

	local detailStack = Create.mono({
		Parent = detailScroll,
		Text = "",
		TextSize = T.font.micro,
		TextColor3 = C.textDim,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		LayoutOrder = 3,
	})

	function Logs.showDetail(entry)
		if not entry then return end
		detailLevel.Text = ("%s · %s"):format(string.lower(entry.level), entry.time)
		detailLevel.TextColor3 = Theme.levelColor(entry.level)
		detailMessage.Text = entry.message
		detailMessage.TextColor3 = C.text

		local hasStack = entry.stack ~= nil and entry.stack ~= ""
		stackTitle.Visible = hasStack
		detailStack.Visible = hasStack
		detailStack.Text = hasStack and tostring(entry.stack) or ""
	end

	--══════════════════════════════════════════════════════════════════════
	local function passes(entry)
		if filter.level ~= "todos" and entry.level ~= filter.level then return false end
		if filter.query ~= "" and not Util.fuzzy(entry.message, filter.query) then return false end
		return true
	end

	local refresh = Util.throttle(function()
		local items = {}
		for _, e in ipairs(Logs.entries:list()) do
			if passes(e) then table.insert(items, e) end
		end
		local wasBottom = list:IsAtBottom()
		list:SetItems(items, not autoScroll)
		if autoScroll and wasBottom then list:ScrollToBottom() end
		errCounter:Set(Logs.counts.Error or 0)
		warnCounter:Set(Logs.counts.Warning or 0)
	end, 0.15)

	Logs.refreshList = refresh

	Logs.Added:Connect(function() refresh() end)
	Logs.Cleared:Connect(function()
		selected = nil
		detailMessage.Text = "Console limpo."
		detailStack.Visible = false
		stackTitle.Visible = false
		refresh()
	end)

	refresh()
	return { list = list, refresh = refresh }
end

return Logs
