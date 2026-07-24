--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/modules/Inventory.lua
	Inventario universal.

	Jogo nenhum guarda inventario do mesmo jeito, entao esse modulo varre
	todas as fontes plausiveis e junta tudo numa lista unica:

	  1. Backpack           → ferramentas nao equipadas
	  2. Character          → ferramentas equipadas + acessorios
	  3. StarterGear        → itens persistentes
	  4. leaderstats        → moeda, nivel, kills, o que o jogo expuser
	  5. Atributos          → do Player e do Character
	  6. Pastas de dados    → Folder/Configuration com *Value sob o Player
	  7. Dados replicados   → ReplicatedStorage/<qualquer>/<nome do jogador>
	  8. GUI de inventario  → slots detectados em ScreenGuis
	  9. Tabelas na memoria → getgc procurando chaves tipo Inventory/Items/Slots

	Cada item vira { categoria, nome, valor, tipo, origem, instancia }.
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
local Players = Env.Services.Players
local LP = Env.LocalPlayer

local Inventory = {}
Inventory.Name = "Inventory"
Inventory.items = {}
Inventory.Updated = Signal.new("Inventory.Updated")
Inventory.lastScan = 0
Inventory.scanning = false

local VALUE_CLASSES = {
	IntValue = true, NumberValue = true, StringValue = true, BoolValue = true,
	ObjectValue = true, CFrameValue = true, Vector3Value = true,
	Color3Value = true, BrickColorValue = true, IntConstrainedValue = true,
	RayValue = true,
}

local INVENTORY_WORDS = {
	"inventory", "inventario", "items", "itens", "backpack", "mochila",
	"slots", "storage", "stash", "bag", "loadout", "equipment", "gear",
	"pets", "weapons", "armas", "skins", "cards", "crates", "collection",
}

local function looksLikeInventory(name)
	local lower = tostring(name):lower()
	for _, word in ipairs(INVENTORY_WORDS) do
		if lower:find(word, 1, true) then return true, word end
	end
	return false
end

--══════════════════════════════════════════════════════════════════════════
-- COLETORES
--══════════════════════════════════════════════════════════════════════════
local function add(out, category, name, value, kind, source, instance)
	table.insert(out, {
		category = category,
		name = tostring(name),
		value = value,
		display = Serializer.preview(value, 70),
		kind = kind or typeof(value),
		source = source or "",
		instance = instance,
	})
end

local function collectBackpack(out, player)
	local backpack = player and player:FindFirstChildOfClass("Backpack")
	if not backpack then return end
	for _, item in ipairs(backpack:GetChildren()) do
		local desc = {}
		if item:IsA("Tool") then
			desc.tooltip = Env.safeIndex(item, "ToolTip", "")
		end
		add(out, "Mochila", item.Name, item.ClassName, "Tool",
			Util.fullName(item), item)

		-- valores dentro da ferramenta (municao, dano, raridade...)
		for _, child in ipairs(item:GetChildren()) do
			if VALUE_CLASSES[child.ClassName] then
				add(out, "Mochila", ("%s.%s"):format(item.Name, child.Name),
					child.Value, child.ClassName, Util.fullName(child), child)
			end
		end
		local attrs = item:GetAttributes()
		for k, v in pairs(attrs) do
			add(out, "Mochila", ("%s @%s"):format(item.Name, k), v, "atributo",
				Util.fullName(item), item)
		end
	end
end

local function collectCharacter(out, player)
	local char = player and player.Character
	if not char then return end

	for _, item in ipairs(char:GetChildren()) do
		if item:IsA("Tool") then
			add(out, "Equipado", item.Name, "equipado agora", "Tool", Util.fullName(item), item)
		elseif item:IsA("Accessory") then
			local handle = item:FindFirstChild("Handle")
			local mesh = handle and handle:FindFirstChildOfClass("SpecialMesh")
			add(out, "Acessorios", item.Name,
				mesh and mesh.MeshId or item.ClassName, "Accessory", Util.fullName(item), item)
		end
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		add(out, "Personagem", "Health", ("%.0f / %.0f"):format(humanoid.Health, humanoid.MaxHealth), "number", Util.fullName(humanoid), humanoid)
		add(out, "Personagem", "WalkSpeed", humanoid.WalkSpeed, "number", Util.fullName(humanoid), humanoid)
		add(out, "Personagem", "JumpPower", humanoid.UseJumpPower and humanoid.JumpPower or humanoid.JumpHeight, "number", Util.fullName(humanoid), humanoid)
		local desc = humanoid:FindFirstChildOfClass("HumanoidDescription")
		if desc then
			add(out, "Personagem", "HumanoidDescription", desc.Name, "Instance", Util.fullName(desc), desc)
		end
	end

	for k, v in pairs(char:GetAttributes()) do
		add(out, "Personagem", "@" .. k, v, "atributo", Util.fullName(char), char)
	end
end

local function collectStarterGear(out, player)
	local gear = player and player:FindFirstChild("StarterGear")
	if not gear then return end
	for _, item in ipairs(gear:GetChildren()) do
		add(out, "StarterGear", item.Name, item.ClassName, "Tool", Util.fullName(item), item)
	end
end

local function collectLeaderstats(out, player)
	local stats = player and player:FindFirstChild("leaderstats")
	if not stats then return end
	for _, v in ipairs(stats:GetDescendants()) do
		if VALUE_CLASSES[v.ClassName] then
			add(out, "Leaderstats", v.Name, v.Value, v.ClassName, Util.fullName(v), v)
		end
	end
end

local function collectPlayerAttributes(out, player)
	if not player then return end
	for k, v in pairs(player:GetAttributes()) do
		add(out, "Atributos", k, v, "atributo", Util.fullName(player), player)
	end
end

local function collectValueFolders(out, root, category, maxDepth)
	if not root then return end
	local depth = 0

	local function walk(node, d)
		if d > (maxDepth or Config.get("inventoryMaxDepth")) then return end
		local children
		if not pcall(function() children = node:GetChildren() end) then return end
		for _, child in ipairs(children) do
			local class = child.ClassName
			if VALUE_CLASSES[class] then
				add(out, category, Util.relativePath(child, root), child.Value, class,
					Util.fullName(child), child)
			elseif class == "Folder" or class == "Configuration" or class == "Model" then
				walk(child, d + 1)
			end
			for k, v in pairs(child:GetAttributes()) do
				add(out, category, ("%s @%s"):format(child.Name, k), v, "atributo",
					Util.fullName(child), child)
			end
		end
	end

	walk(root, 0)
end

local function collectReplicatedData(out, player)
	local rs = Env.Services.ReplicatedStorage
	if not rs or not player then return end

	local candidates = {}
	pcall(function()
		for _, child in ipairs(rs:GetChildren()) do
			local isData, word = looksLikeInventory(child.Name)
			if isData or child.Name:lower():find("data") or child.Name:lower():find("player") then
				table.insert(candidates, child)
			end
		end
	end)

	for _, folder in ipairs(candidates) do
		-- pasta por jogador?
		local mine = folder:FindFirstChild(player.Name) or folder:FindFirstChild(tostring(player.UserId))
		local target = mine or folder
		collectValueFolders(out, target, "Dados replicados", 5)
	end
end

local function collectInventoryGui(out, player)
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end

	pcall(function()
		for _, gui in ipairs(pg:GetChildren()) do
			if gui:IsA("ScreenGui") then
				local isInv = looksLikeInventory(gui.Name)
				for _, d in ipairs(gui:GetDescendants()) do
					if isInv or looksLikeInventory(d.Name) then
						if d:IsA("TextLabel") or d:IsA("TextButton") then
							local text = Env.safeIndex(d, "Text", "")
							if text ~= "" and #text < 80 then
								add(out, "Interface", Util.relativePath(d, gui), text, "TextLabel",
									Util.fullName(d), d)
							end
						end
					end
				end
			end
		end
	end)
end

local function collectMemoryTables(out)
	if not Env.getgc or not Config.get("inventoryDeepScan") then return end

	local found = 0
	local ok = pcall(function()
		for _, obj in ipairs(Env.getgc(true)) do
			if found > 60 then break end
			if type(obj) == "table" and not getmetatable(obj) then
				for key, value in pairs(obj) do
					if type(key) == "string" and looksLikeInventory(key) then
						if type(value) == "table" then
							local count = 0
							for _ in pairs(value) do count += 1 end
							if count > 0 and count < 500 then
								found += 1
								add(out, "Memoria", key, ("tabela com %d entradas"):format(count),
									"table", "getgc", nil)
								local shown = 0
								for k2, v2 in pairs(value) do
									shown += 1
									if shown > 24 then break end
									add(out, "Memoria", ("%s.%s"):format(key, tostring(k2)),
										v2, typeof(v2), "getgc", nil)
								end
							end
						end
						break
					end
				end
			end
		end
	end)
end

local function collectOtherPlayers(out)
	if not Players then return end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local stats = plr:FindFirstChild("leaderstats")
			if stats then
				for _, v in ipairs(stats:GetChildren()) do
					if VALUE_CLASSES[v.ClassName] then
						add(out, "Outros jogadores", ("%s · %s"):format(plr.Name, v.Name),
							v.Value, v.ClassName, Util.fullName(v), v)
					end
				end
			end
			local bp = plr:FindFirstChildOfClass("Backpack")
			if bp then
				for _, item in ipairs(bp:GetChildren()) do
					add(out, "Outros jogadores", ("%s · %s"):format(plr.Name, item.Name),
						item.ClassName, "Tool", Util.fullName(item), item)
				end
			end
		end
	end
end

--══════════════════════════════════════════════════════════════════════════
-- SCAN
--══════════════════════════════════════════════════════════════════════════
function Inventory.scan()
	if Inventory.scanning then return Inventory.items end
	Inventory.scanning = true

	local out = {}
	local player = LP or (Players and Players.LocalPlayer)

	local steps = {
		function() collectBackpack(out, player) end,
		function() collectCharacter(out, player) end,
		function() collectStarterGear(out, player) end,
		function() collectLeaderstats(out, player) end,
		function() collectPlayerAttributes(out, player) end,
		function() collectValueFolders(out, player, "Pastas do jogador", 4) end,
		function() collectReplicatedData(out, player) end,
		function() collectInventoryGui(out, player) end,
		function() collectOtherPlayers(out) end,
		function() collectMemoryTables(out) end,
	}

	for _, step in ipairs(steps) do
		local ok, err = pcall(step)
		if not ok then
			warn("[UNICLUDE/Inventory] etapa falhou: " .. tostring(err))
		end
	end

	Inventory.items = out
	Inventory.lastScan = os.clock()
	Inventory.scanning = false
	Inventory.Updated:Fire(out)
	return out
end

function Inventory.categories()
	local set, order = {}, {}
	for _, item in ipairs(Inventory.items) do
		if not set[item.category] then
			set[item.category] = 0
			table.insert(order, item.category)
		end
		set[item.category] += 1
	end
	table.sort(order)
	return order, set
end

function Inventory.export()
	local grouped = {}
	for _, item in ipairs(Inventory.items) do
		grouped[item.category] = grouped[item.category] or {}
		table.insert(grouped[item.category], {
			nome = item.name,
			valor = tostring(item.value),
			tipo = item.kind,
			origem = item.source,
		})
	end
	return Serializer.dump("inventario completo", grouped)
end

--══════════════════════════════════════════════════════════════════════════
-- PAINEL
--══════════════════════════════════════════════════════════════════════════
function Inventory.buildPage(page, window)
	local filter = { query = "", category = "todas" }
	local selected = nil
	local categoryDropdown

	local bar = Library.toolbar(page)

	bar:Button({
		text = "Escanear", variant = "solid",
		tooltip = "Varre todas as fontes de inventario agora",
		onClick = function()
			Library.notify("Escaneando inventario…", "info", 1.5)
			task.spawn(function()
				Inventory.scan()
				Inventory.refreshList()
				Library.notify(("%d entradas encontradas"):format(#Inventory.items), "ok", 2.5)
			end)
		end,
	})

	bar:Separator()

	bar:Input({
		placeholder = "Buscar item, valor ou caminho",
		icon = "⌕",
		Size = UDim2.new(0, 240, 0, T.metrics.inputHeight),
		debounce = 0.18,
		onChange = function(text) filter.query = text; Inventory.refreshList() end,
	})

	categoryDropdown = bar:Dropdown({
		prefix = "categoria: ",
		options = { { text = "todas", value = "todas" } },
		value = "todas",
		Size = UDim2.new(0, 170, 0, T.metrics.inputHeight),
		onChange = function(v) filter.category = v; Inventory.refreshList() end,
	})

	bar:Toggle({
		text = "auto",
		value = Config.get("inventoryAutoRefresh"),
		tooltip = "Reescaneia periodicamente",
		onChange = function(v) Config.set("inventoryAutoRefresh", v) end,
	})

	bar:Toggle({
		text = "memoria",
		value = Config.get("inventoryDeepScan"),
		tooltip = "Inclui varredura de tabelas vivas via getgc (mais lento)",
		onChange = function(v) Config.set("inventoryDeepScan", v) end,
	})

	bar:Separator()

	bar:Button({
		text = "Exportar", variant = "ghost",
		onClick = function()
			local ok, where = Config.export("inventario", Inventory.export(), "lua")
			Library.notify(ok and ("Salvo em " .. where) or where, ok and "ok" or "warn", 4)
		end,
	})

	local counter = bar:Counter({ label = "entradas", color = C.accent })

	--── corpo ────────────────────────────────────────────────────────────
	local split = Library.splitPane(page, {
		Position = UDim2.fromOffset(0, T.metrics.toolbarHeight),
		Size = UDim2.new(1, 0, 1, -T.metrics.toolbarHeight),
		leftWidth = 560, minLeft = 360, minRight = 260,
	})

	local listHolder = Create.frame({ Parent = split.left, Size = UDim2.fromScale(1, 1) })
	Create.padding(listHolder, 6, 4, 6, 6)

	local list
	list = VirtualList.new({
		Parent = listHolder,
		RowHeight = 30,
		EmptyTitle = "Inventario nao escaneado",
		EmptyHint = "Clique em Escanear. O UNICLUDE procura mochila, leaderstats, atributos, pastas de dados, GUI e tabelas vivas.",
		CreateRow = function()
			local row = Create.button({
				Text = "",
				BackgroundColor3 = C.panelAlt,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
			})
			Create.corner(row, T.radius.sm)
			Create.padding(row, 0, 8, 0, 8)

			local cat = Create.text({
				Parent = row,
				Text = "",
				Font = T.faces.bold,
				TextSize = T.font.micro,
				TextColor3 = C.accentSoft,
				Size = UDim2.fromOffset(112, 30),
			})

			local name = Create.text({
				Parent = row,
				Text = "",
				TextSize = T.font.small,
				TextColor3 = C.text,
				Position = UDim2.fromOffset(118, 0),
				Size = UDim2.new(0.45, -118, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})

			local value = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.small,
				TextColor3 = C.warn,
				Position = UDim2.new(0.45, 4, 0, 0),
				Size = UDim2.new(0.4, -8, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})

			local kind = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.micro,
				TextColor3 = C.textFaint,
				Position = UDim2.new(0.85, 0, 0, 0),
				Size = UDim2.new(0.15, -4, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
			})

			return row, { cat = cat, name = name, value = value, kind = kind }
		end,
		BindRow = function(api, item, index, isSelected, frame)
			api.cat.Text = string.lower(item.category)
			api.name.Text = item.name
			api.value.Text = item.display
			api.value.TextColor3 = Theme.typeColor(item.kind) or C.warn
			api.kind.Text = item.kind
			frame.BackgroundTransparency = isSelected and 0 or 1
			frame.BackgroundColor3 = isSelected and C.selected or C.panelAlt
		end,
		OnActivate = function(item)
			selected = item
			Inventory.showDetail(item)
		end,
		OnContext = function(item)
			local mouse = Env.Services.UserInputService:GetMouseLocation()
			local menu = {
				{ text = "Copiar valor", icon = "⧉", action = function()
					Env.copy(tostring(item.value))
					Library.notify("Copiado", "ok", 1.4)
				end },
				{ text = "Copiar caminho", icon = "⌁", action = function()
					Env.copy(item.source)
					Library.notify("Copiado", "ok", 1.4)
				end },
			}
			if item.instance then
				table.insert(menu, { text = "Copiar codigo de acesso", icon = "≡", action = function()
					Env.copy("local alvo = " .. Util.instancePath(item.instance))
					Library.notify("Codigo copiado", "ok", 1.4)
				end })
			end
			Library.contextMenu(menu, mouse.X, mouse.Y - 36)
		end,
	})

	--── detalhe ──────────────────────────────────────────────────────────
	local kv = Library.keyValue(split.right, {})
	kv:Empty("Selecione uma entrada")

	function Inventory.showDetail(item)
		kv:Clear()
		kv:Section(item.category)
		kv:Row("nome", item.name)
		kv:Row("valor", tostring(item.value), { tall = true, color = Theme.typeColor(item.kind) })
		kv:Row("tipo", item.kind)
		kv:Row("origem", item.source, { tall = true })

		if item.instance then
			kv:Gap()
			kv:Section("instancia")
			kv:Row("classe", Env.safeIndex(item.instance, "ClassName", "?"))
			kv:Row("codigo", "local alvo = " .. Util.instancePath(item.instance), { tall = true, color = C.accent })

			local attrs
			pcall(function() attrs = item.instance:GetAttributes() end)
			if attrs and next(attrs) then
				kv:Gap()
				kv:Section("atributos")
				for k, v in pairs(attrs) do
					kv:Row(k, Serializer.preview(v, 60), { color = Theme.typeColor(typeof(v)) })
				end
			end
		end

		if type(item.value) == "table" then
			kv:Gap()
			kv:Section("conteudo")
			kv:Row("dump", Serializer.value(item.value, { maxDepth = 4 }), { tall = true })
		end
	end

	--══════════════════════════════════════════════════════════════════════
	local refresh = Util.throttle(function()
		local items = {}
		for _, item in ipairs(Inventory.items) do
			local okCat = filter.category == "todas" or item.category == filter.category
			local okQuery = filter.query == ""
				or Util.fuzzy(item.name .. " " .. tostring(item.value) .. " " .. item.source, filter.query)
			if okCat and okQuery then table.insert(items, item) end
		end
		list:SetItems(items)
		counter:Set(#items)

		local order = Inventory.categories()
		local options = { { text = "todas", value = "todas" } }
		for _, cat in ipairs(order) do
			table.insert(options, { text = string.lower(cat), value = cat })
		end
		categoryDropdown.options = options
	end, 0.12)

	Inventory.refreshList = refresh
	Inventory.Updated:Connect(function() refresh() end)

	-- auto scan
	task.spawn(function()
		task.wait(1)
		Inventory.scan()
		while page.Parent do
			task.wait(math.max(1, Config.get("inventoryInterval")))
			if Config.get("inventoryAutoRefresh") and page.Visible then
				Inventory.scan()
			end
		end
	end)

	refresh()
	return { list = list, refresh = refresh }
end

return Inventory
