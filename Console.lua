--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/modules/Console.lua
	Console Luau embutido: edita, roda, captura retorno e erro, guarda
	historico e traz atalhos prontos que usam o proprio UNICLUDE.

	O print/warn de dentro do console e redirecionado para o painel de saida
	(e tambem para a aba Logs, marcado como Uniclude).
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
local Highlighter= UNI.require("src/ui/Highlighter")

local T, C = Theme, Theme.c

local Console = {}
Console.Name = "Console"
Console.history = {}
Console.Output = Signal.new("Console.Output")

local SNIPPETS = {
	{
		name = "Listar todos os remotes",
		code = [[local Spy = getgenv().UNICLUDE.Modules.RemoteSpy
for _, r in ipairs(Spy.discover()) do
	print(r.kind, r.path)
end]],
	},
	{
		name = "Dump do inventario",
		code = [[local Inv = getgenv().UNICLUDE.Modules.Inventory
Inv.scan()
for _, item in ipairs(Inv.items) do
	print(item.category, item.name, item.display)
end]],
	},
	{
		name = "Bloquear um remote",
		code = [[local Config = getgenv().UNICLUDE.Modules.Config
Config.setBlocked("game.ReplicatedStorage.Remotes.NomeDoRemote", true)
print("bloqueado")]],
	},
	{
		name = "Anti-AFK",
		code = [[local vu = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
	vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
	task.wait(1)
	vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end)
print("anti-afk ligado")]],
	},
	{
		name = "Info do lugar",
		code = [[print("PlaceId", game.PlaceId)
print("JobId", game.JobId)
print("Jogadores", #game:GetService("Players"):GetPlayers())
print("Ping", math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()) .. "ms")]],
	},
	{
		name = "Teleportar personagem",
		code = [[local char = game:GetService("Players").LocalPlayer.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
if root then
	root.CFrame = CFrame.new(0, 50, 0)
end]],
	},
}

--══════════════════════════════════════════════════════════════════════════
-- EXECUCAO
--══════════════════════════════════════════════════════════════════════════
function Console.run(source)
	local outputLines = {}

	local function capture(prefix, color)
		return function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = Serializer.preview(select(i, ...), 400)
				local v = select(i, ...)
				if type(v) == "string" then parts[i] = v end
			end
			local line = table.concat(parts, "  ")
			table.insert(outputLines, { text = prefix .. line, color = color })
			Console.Output:Fire(prefix .. line, color)
		end
	end

	local sandbox = setmetatable({
		print = capture("", C.text),
		warn  = capture("⚠ ", C.warn),
		UNICLUDE = UNI,
	}, { __index = getfenv and getfenv(0) or _G, __newindex = function(t, k, v) rawset(t, k, v) end })

	local chunk, compileError = loadstring(source, "@UNICLUDE/console")
	if not chunk then
		table.insert(outputLines, { text = "erro de sintaxe: " .. tostring(compileError), color = C.danger })
		return false, outputLines
	end

	if setfenv then pcall(setfenv, chunk, sandbox) end

	local t0 = os.clock()
	local results = table.pack(pcall(chunk))
	local elapsed = os.clock() - t0

	if not results[1] then
		table.insert(outputLines, { text = "erro: " .. tostring(results[2]), color = C.danger })
		return false, outputLines
	end

	for i = 2, results.n do
		table.insert(outputLines, {
			text = "→ " .. Serializer.value(results[i], { maxDepth = 4 }),
			color = C.info,
		})
	end

	table.insert(outputLines, {
		text = ("executado em %.1f ms"):format(elapsed * 1000),
		color = C.textFaint,
	})

	table.insert(Console.history, 1, { code = source, time = Util.timestamp() })
	if #Console.history > 40 then table.remove(Console.history) end

	return true, outputLines
end

--══════════════════════════════════════════════════════════════════════════
-- PAINEL
--══════════════════════════════════════════════════════════════════════════
function Console.buildPage(page, window)
	local bar = Library.toolbar(page)

	local editorHolder, outputScroll, outputLayout, editor, preview

	local function appendOutput(text, color)
		local label = Create.mono({
			Parent = outputScroll,
			Text = text,
			TextSize = T.font.small,
			TextColor3 = color or C.text,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = #outputScroll:GetChildren(),
		})
		task.defer(function()
			outputScroll.CanvasPosition = Vector2.new(0, outputScroll.AbsoluteCanvasSize.Y)
		end)
		return label
	end

	local function clearOutput()
		for _, child in ipairs(outputScroll:GetChildren()) do
			if child:IsA("TextLabel") then child:Destroy() end
		end
	end

	bar:Button({
		text = "Executar", variant = "solid",
		tooltip = "Roda o codigo do editor",
		onClick = function()
			local src = editor.Text
			if Util.trim(src) == "" then return end
			appendOutput(("─ %s ─"):format(Util.timestamp()), C.textFaint)
			local ok, lines = Console.run(src)
			for _, line in ipairs(lines) do
				appendOutput(line.text, line.color)
			end
		end,
	})

	bar:Button({
		text = "Limpar saida", variant = "ghost",
		onClick = clearOutput,
	})

	bar:Button({
		text = "Limpar editor", variant = "ghost",
		onClick = function() editor.Text = "" end,
	})

	bar:Separator()

	bar:Dropdown({
		prefix = "atalho: ",
		options = (function()
			local opts = {}
			for i, s in ipairs(SNIPPETS) do
				table.insert(opts, { text = s.name, value = i })
			end
			return opts
		end)(),
		value = 1,
		Size = UDim2.new(0, 190, 0, T.metrics.inputHeight),
		onChange = function(index)
			editor.Text = SNIPPETS[index].code
		end,
	})

	bar:Button({
		text = "Historico", variant = "ghost",
		onClick = function()
			if #Console.history == 0 then
				Library.notify("Historico vazio", "info", 1.5)
				return
			end
			local items = {}
			for i, h in ipairs(Console.history) do
				if i > 15 then break end
				table.insert(items, {
					text = ("%s  %s"):format(h.time, Util.truncate(Util.oneLine(h.code, 40), 40)),
					action = function() editor.Text = h.code end,
				})
			end
			local mouse = Env.Services.UserInputService:GetMouseLocation()
			Library.contextMenu(items, mouse.X - 100, mouse.Y - 36)
		end,
	})

	bar:Button({
		text = "Salvar .lua", variant = "ghost",
		onClick = function()
			local ok, where = Config.export("script", editor.Text, "lua")
			Library.notify(ok and ("Salvo em " .. where) or where, ok and "ok" or "warn", 4)
		end,
	})

	--── layout ───────────────────────────────────────────────────────────
	local split = Library.splitPane(page, {
		Position = UDim2.fromOffset(0, T.metrics.toolbarHeight),
		Size = UDim2.new(1, 0, 1, -T.metrics.toolbarHeight),
		leftWidth = 560, minLeft = 320, minRight = 260,
	})

	--── editor ───────────────────────────────────────────────────────────
	editorHolder = Create.frame({ Parent = split.left, Size = UDim2.fromScale(1, 1) })
	Create.padding(editorHolder, 8, 6, 8, 8)

	Create.text({
		Parent = editorHolder,
		Text = "EDITOR",
		Font = T.faces.bold,
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Size = UDim2.new(1, 0, 0, 14),
	})

	local editorFrame = Create.frame({
		Parent = editorHolder,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 1, -18),
		BackgroundColor3 = C.root,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
	})
	Create.corner(editorFrame, T.radius.sm)
	Create.stroke(editorFrame, C.strokeSoft)

	local editorScroll = Create.scroll({
		Parent = editorFrame,
		Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	Create.padding(editorScroll, 8, 8, 8, 8)

	-- camada de realce por baixo do TextBox transparente
	preview = Create.mono({
		Parent = editorScroll,
		Text = "",
		RichText = true,
		TextSize = T.font.small,
		TextColor3 = C.text,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	editor = Create.new("TextBox", {
		Parent = editorScroll,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = T.faces.mono,
		TextSize = T.font.small,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,          -- texto real invisivel, o realce aparece
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		MultiLine = true,
		ClearTextOnFocus = false,
		PlaceholderText = "-- escreva Luau aqui e clique em Executar",
		PlaceholderColor3 = C.textFaint,
		Text = SNIPPETS[1].code,
		TextWrapped = false,
	})

	local function syncHighlight()
		if editor.Text == "" then
			preview.Text = ""
			return
		end
		preview.Text = Highlighter.render(editor.Text, 20000)
	end

	editor:GetPropertyChangedSignal("Text"):Connect(Util.debounce(syncHighlight, 0.08))
	syncHighlight()

	-- cursor visivel: quando focado, mostra o texto real com transparencia leve
	editor.Focused:Connect(function()
		editor.TextTransparency = 0.55
		preview.TextTransparency = 0.25
	end)
	editor.FocusLost:Connect(function()
		editor.TextTransparency = 1
		preview.TextTransparency = 0
		syncHighlight()
	end)

	--── saida ────────────────────────────────────────────────────────────
	local outHolder = Create.frame({ Parent = split.right, Size = UDim2.fromScale(1, 1) })
	Create.padding(outHolder, 8, 8, 8, 8)

	Create.text({
		Parent = outHolder,
		Text = "SAIDA",
		Font = T.faces.bold,
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Size = UDim2.new(1, 0, 0, 14),
	})

	local outFrame = Create.frame({
		Parent = outHolder,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 1, -18),
		BackgroundColor3 = C.root,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
	})
	Create.corner(outFrame, T.radius.sm)
	Create.stroke(outFrame, C.strokeSoft)

	outputScroll = Create.scroll({
		Parent = outFrame,
		Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	Create.padding(outputScroll, 8, 8, 8, 8)
	outputLayout = Create.list(outputScroll, "v", 3)
	outputLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	appendOutput("console pronto · " .. Env.ExecutorName, C.accentSoft)
	appendOutput("dica: getgenv().UNICLUDE da acesso a todos os modulos", C.textFaint)

	return { editor = editor, output = outputScroll }
end

Console.snippets = SNIPPETS
return Console
