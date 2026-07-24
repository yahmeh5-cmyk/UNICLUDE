--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/modules/Explorer.lua
	Explorador da DataModel: arvore navegavel de Workspace, ReplicatedStorage,
	Players, Lighting, StarterGui, StarterPack, instancias em nil e mais.

	Painel direito: propriedades (lista curada por classe + heuristica),
	atributos, tags, filhos, e acoes (copiar caminho, copiar codigo de
	referencia, destruir, congelar, exportar subarvore).

	A arvore e achatada num array plano e desenhada com VirtualList, entao
	abrir o Workspace de um jogo com 40k instancias nao trava nada.
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

local Explorer = {}
Explorer.Name = "Explorer"
Explorer.expanded = {}     -- [instance] = true
Explorer.selected = nil
Explorer.Selected = Signal.new("Explorer.Selected")

--══════════════════════════════════════════════════════════════════════════
-- PROPRIEDADES CONHECIDAS
--══════════════════════════════════════════════════════════════════════════
local COMMON = { "Name", "ClassName", "Parent", "Archivable" }

local BY_CLASS = {
	BasePart = { "Position", "Size", "CFrame", "Anchored", "CanCollide", "CanTouch", "CanQuery",
		"Transparency", "Reflectance", "Color", "Material", "Massless", "Velocity",
		"AssemblyLinearVelocity", "CollisionGroup", "Locked", "CastShadow" },
	Model = { "PrimaryPart", "WorldPivot", "LevelOfDetail", "ModelStreamingMode" },
	Humanoid = { "Health", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight", "HipHeight",
		"AutoRotate", "PlatformStand", "Sit", "MoveDirection", "RigType", "DisplayName",
		"HealthDisplayType", "UseJumpPower" },
	Player = { "UserId", "DisplayName", "Team", "TeamColor", "CharacterAppearanceId",
		"AccountAge", "Neutral", "MembershipType", "FollowUserId" },
	Tool = { "Grip", "Enabled", "CanBeDropped", "RequiresHandle", "ToolTip", "TextureId" },
	Sound = { "SoundId", "Volume", "Playing", "Looped", "PlaybackSpeed", "TimePosition", "TimeLength" },
	GuiObject = { "Position", "Size", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency",
		"Visible", "ZIndex", "ClipsDescendants", "Rotation", "LayoutOrder", "Active" },
	TextLabel = { "Text", "TextColor3", "TextSize", "Font", "TextTransparency", "RichText",
		"TextXAlignment", "TextYAlignment", "TextWrapped", "TextScaled" },
	ImageLabel = { "Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter" },
	ScreenGui = { "Enabled", "DisplayOrder", "IgnoreGuiInset", "ResetOnSpawn", "ZIndexBehavior" },
	ValueBase = { "Value" },
	Script = { "Enabled", "RunContext", "Source" },
	Camera = { "CFrame", "FieldOfView", "CameraType", "CameraSubject", "Focus" },
	Attachment = { "Position", "CFrame", "WorldPosition", "Axis", "Visible" },
	ProximityPrompt = { "ActionText", "ObjectText", "HoldDuration", "MaxActivationDistance",
		"Enabled", "RequiresLineOfSight", "KeyboardKeyCode" },
	Lighting = { "Ambient", "Brightness", "ClockTime", "FogEnd", "FogStart", "GlobalShadows",
		"OutdoorAmbient", "TimeOfDay", "ExposureCompensation" },
	Team = { "TeamColor", "AutoAssignable" },
	Decal = { "Texture", "Transparency", "Face", "Color3" },
	ParticleEmitter = { "Rate", "Lifetime", "Speed", "Enabled", "Texture", "Color" },
	Beam = { "Attachment0", "Attachment1", "Color", "Enabled", "Width0", "Width1" },
	Animation = { "AnimationId" },
	AnimationTrack = { "IsPlaying", "Speed", "TimePosition" },
	RemoteEvent = {},
	RemoteFunction = {},
	Folder = {},
	Backpack = {},
}

local INHERITS = {
	Part = "BasePart", MeshPart = "BasePart", UnionOperation = "BasePart",
	WedgePart = "BasePart", TrussPart = "BasePart", SpawnLocation = "BasePart",
	CornerWedgePart = "BasePart", Seat = "BasePart", VehicleSeat = "BasePart",
	Frame = "GuiObject", TextButton = "TextLabel", TextBox = "TextLabel",
	ImageButton = "ImageLabel", ScrollingFrame = "GuiObject", ViewportFrame = "GuiObject",
	IntValue = "ValueBase", NumberValue = "ValueBase", StringValue = "ValueBase",
	BoolValue = "ValueBase", ObjectValue = "ValueBase", CFrameValue = "ValueBase",
	Vector3Value = "ValueBase", Color3Value = "ValueBase", BrickColorValue = "ValueBase",
	LocalScript = "Script", ModuleScript = "Script",
}

local function propertyList(inst)
	local class = Env.safeIndex(inst, "ClassName", "")
	local list = {}

	for _, p in ipairs(COMMON) do table.insert(list, p) end

	local chain = {}
	local cur = class
	local guard = 0
	while cur and guard < 6 do
		guard += 1
		table.insert(chain, cur)
		cur = INHERITS[cur]
	end

	-- GuiObject e TextLabel herdam de GuiObject tambem
	if BY_CLASS[class] == nil and class:find("Gui") then table.insert(chain, "GuiObject") end
	if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
		table.insert(chain, "GuiObject")
	end
	if class == "ImageLabel" or class == "ImageButton" then table.insert(chain, "GuiObject") end

	local seen = {}
	for _, p in ipairs(list) do seen[p] = true end

	for i = #chain, 1, -1 do
		for _, p in ipairs(BY_CLASS[chain[i]] or {}) do
			if not seen[p] then
				seen[p] = true
				table.insert(list, p)
			end
		end
	end

	return list
end

--══════════════════════════════════════════════════════════════════════════
-- RAIZES
--══════════════════════════════════════════════════════════════════════════
function Explorer.roots()
	local out = {}
	for _, name in ipairs(Config.get("explorerRoots")) do
		local svc = Env.Services[name]
		if svc then table.insert(out, svc) end
	end
	return out
end

--══════════════════════════════════════════════════════════════════════════
-- ACHATAMENTO DA ARVORE
--══════════════════════════════════════════════════════════════════════════
local function sortChildren(a, b)
	local ac = Env.safeIndex(a, "ClassName", "")
	local bc = Env.safeIndex(b, "ClassName", "")
	local aContainer = ac == "Folder" or ac == "Model"
	local bContainer = bc == "Folder" or bc == "Model"
	if aContainer ~= bContainer then return aContainer end
	return Env.safeIndex(a, "Name", "") < Env.safeIndex(b, "Name", "")
end

local function flatten(inst, depth, out, budget)
	if #out >= budget then return end

	local children
	local ok = pcall(function() children = inst:GetChildren() end)
	if not ok or not children then return end

	table.sort(children, sortChildren)

	for _, child in ipairs(children) do
		if #out >= budget then return end
		local hasKids = false
		pcall(function() hasKids = #child:GetChildren() > 0 end)

		table.insert(out, {
			instance = child,
			depth = depth,
			hasChildren = hasKids,
			expanded = Explorer.expanded[child] == true,
		})

		if Explorer.expanded[child] and hasKids then
			flatten(child, depth + 1, out, budget)
		end
	end
end

function Explorer.buildRows(budget)
	local out = {}
	budget = budget or 4000

	for _, root in ipairs(Explorer.roots()) do
		local hasKids = false
		pcall(function() hasKids = #root:GetChildren() > 0 end)
		table.insert(out, {
			instance = root,
			depth = 0,
			hasChildren = hasKids,
			expanded = Explorer.expanded[root] == true,
			isRoot = true,
		})
		if Explorer.expanded[root] then
			flatten(root, 1, out, budget)
		end
	end

	if Config.get("explorerShowNil") and Env.getnilinstances then
		local nilList = {}
		pcall(function() nilList = Env.getnilinstances() end)
		if #nilList > 0 then
			table.insert(out, { header = true, text = ("instancias em nil (%d)"):format(#nilList), depth = 0 })
			for i, inst in ipairs(nilList) do
				if i > 250 then break end
				table.insert(out, { instance = inst, depth = 1, hasChildren = false, orphan = true })
			end
		end
	end

	return out
end

--══════════════════════════════════════════════════════════════════════════
-- BUSCA GLOBAL
--══════════════════════════════════════════════════════════════════════════
function Explorer.search(query, limit)
	limit = limit or 300
	local results = {}
	if query == "" then return results end

	for _, root in ipairs(Explorer.roots()) do
		pcall(function()
			for _, d in ipairs(root:GetDescendants()) do
				if #results >= limit then break end
				local name = Env.safeIndex(d, "Name", "")
				local class = Env.safeIndex(d, "ClassName", "")
				if Util.fuzzy(name, query) or Util.fuzzy(class, query) then
					table.insert(results, { instance = d, depth = 0, hasChildren = false, isResult = true })
				end
			end
		end)
		if #results >= limit then break end
	end

	return results
end

--══════════════════════════════════════════════════════════════════════════
-- EXPORTACAO DE SUBARVORE
--══════════════════════════════════════════════════════════════════════════
function Explorer.dumpTree(inst, maxDepth)
	maxDepth = maxDepth or 6
	local lines = {}

	local function walk(node, depth, prefix)
		if depth > maxDepth then return end
		local class = Env.safeIndex(node, "ClassName", "?")
		local name = Env.safeIndex(node, "Name", "?")
		table.insert(lines, ("%s%s  [%s]"):format(prefix, name, class))
		local children
		pcall(function() children = node:GetChildren() end)
		if not children then return end
		table.sort(children, sortChildren)
		for i, child in ipairs(children) do
			if i > 400 then
				table.insert(lines, prefix .. "  … (+" .. (#children - 400) .. ")")
				break
			end
			walk(child, depth + 1, prefix .. "  ")
		end
	end

	walk(inst, 0, "")
	return ("-- UNICLUDE · arvore de %s\n-- %s\n\n%s")
		:format(Util.fullName(inst), os.date("%Y-%m-%d %H:%M:%S"), table.concat(lines, "\n"))
end

--══════════════════════════════════════════════════════════════════════════
-- PAINEL
--══════════════════════════════════════════════════════════════════════════
function Explorer.buildPage(page, window)
	local mode = "tree"     -- tree | search
	local searchResults = {}
	local rows = {}

	local bar = Library.toolbar(page)

	bar:Button({
		text = "Atualizar", variant = "ghost",
		tooltip = "Recarrega a arvore",
		onClick = function() Explorer.refresh() end,
	})

	bar:Button({
		text = "Recolher tudo", variant = "ghost",
		onClick = function()
			table.clear(Explorer.expanded)
			Explorer.refresh()
		end,
	})

	bar:Separator()

	bar:Input({
		placeholder = "Buscar instancia em toda a DataModel",
		icon = "⌕",
		Size = UDim2.new(0, 300, 0, T.metrics.inputHeight),
		debounce = 0.25,
		onChange = function(text)
			if text == "" then
				mode = "tree"
			else
				mode = "search"
				searchResults = Explorer.search(text, 400)
			end
			Explorer.refresh()
		end,
	})

	bar:Toggle({
		text = "nil instances",
		value = Config.get("explorerShowNil"),
		tooltip = "Mostra instancias fora da DataModel (precisa de getnilinstances)",
		onChange = function(v) Config.set("explorerShowNil", v); Explorer.refresh() end,
	})

	local counter = bar:Counter({ label = "nos", color = C.accent })

	--── split ────────────────────────────────────────────────────────────
	local split = Library.splitPane(page, {
		Position = UDim2.fromOffset(0, T.metrics.toolbarHeight),
		Size = UDim2.new(1, 0, 1, -T.metrics.toolbarHeight),
		leftWidth = 380, minLeft = 260, minRight = 320,
	})

	local treeHolder = Create.frame({ Parent = split.left, Size = UDim2.fromScale(1, 1) })
	Create.padding(treeHolder, 4, 4, 6, 4)

	local list
	list = VirtualList.new({
		Parent = treeHolder,
		RowHeight = 22,
		Gap = 1,
		EmptyTitle = "Arvore vazia",
		EmptyHint = "Nenhum servico acessivel. Verifique as raizes nas configuracoes.",
		CreateRow = function()
			local row = Create.button({
				Text = "",
				BackgroundColor3 = C.panelAlt,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
			})
			Create.corner(row, T.radius.sm)

			local arrow = Create.button({
				Parent = row,
				Text = "",
				Font = T.faces.mono,
				TextSize = T.font.micro,
				TextColor3 = C.textFaint,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(14, 22),
			})

			local icon = Create.text({
				Parent = row,
				Text = "◦",
				TextSize = T.font.small,
				TextColor3 = C.textDim,
				Size = UDim2.fromOffset(14, 22),
			})

			local name = Create.text({
				Parent = row,
				Text = "",
				TextSize = T.font.small,
				TextColor3 = C.text,
				Size = UDim2.new(1, -60, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})

			local class = Create.mono({
				Parent = row,
				Text = "",
				TextSize = T.font.micro,
				TextColor3 = C.textFaint,
				Size = UDim2.new(1, -8, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
			})

			return row, { arrow = arrow, icon = icon, name = name, class = class }
		end,
		BindRow = function(api, node, index, isSelected, frame)
			if node.header then
				api.arrow.Text = ""
				api.icon.Text = ""
				api.name.Text = string.upper(node.text)
				api.name.TextColor3 = C.textFaint
				api.name.Font = T.faces.bold
				api.name.Position = UDim2.fromOffset(6, 0)
				api.class.Text = ""
				frame.BackgroundTransparency = 1
				return
			end

			local inst = node.instance
			local indent = 6 + node.depth * 13
			local className = Env.safeIndex(inst, "ClassName", "?")

			api.arrow.Position = UDim2.fromOffset(indent - 14, 0)
			api.arrow.Text = node.hasChildren and (node.expanded and "▾" or "▸") or ""
			api.arrow.Visible = node.hasChildren

			api.icon.Position = UDim2.fromOffset(indent, 0)
			api.icon.Text = Util.classIcon(className)
			api.icon.TextColor3 = Util.isRemote(inst) and Theme.kindColor(Util.remoteKind(inst)) or C.textDim

			api.name.Position = UDim2.fromOffset(indent + 16, 0)
			api.name.Font = T.faces.regular
			api.name.Text = Env.safeIndex(inst, "Name", "?")
			api.name.TextColor3 = node.orphan and C.warn or C.text
			api.name.Size = UDim2.new(1, -(indent + 16) - 86, 1, 0)

			api.class.Text = className

			frame.BackgroundTransparency = isSelected and 0 or 1
			frame.BackgroundColor3 = isSelected and C.selected or C.panelAlt

			api.arrow.MouseButton1Click:Connect(function() end)
		end,
		OnActivate = function(node, index, frame, api)
			if node.header then return end
			-- clique no terco esquerdo alterna expansao
			local mouse = Env.Services.UserInputService:GetMouseLocation()
			local relX = mouse.X - frame.AbsolutePosition.X
			local indent = 6 + node.depth * 13
			if node.hasChildren and relX <= indent + 12 then
				Explorer.expanded[node.instance] = not Explorer.expanded[node.instance]
				Explorer.refresh()
				return
			end
			Explorer.select(node.instance)
		end,
		OnContext = function(node)
			if node.header then return end
			local inst = node.instance
			local mouse = Env.Services.UserInputService:GetMouseLocation()
			Library.contextMenu({
				{ text = "Copiar caminho", icon = "⌁", action = function()
					Env.copy(Util.fullName(inst))
					Library.notify("Caminho copiado", "ok", 1.5)
				end },
				{ text = "Copiar codigo de referencia", icon = "⧉", action = function()
					Env.copy("local alvo = " .. Util.instancePath(inst))
					Library.notify("Codigo copiado", "ok", 1.5)
				end },
				{ text = "Exportar subarvore", icon = "⤓", action = function()
					local ok, where = Config.export("arvore_" .. Env.safeIndex(inst, "Name", "no"),
						Explorer.dumpTree(inst, 8), "txt")
					Library.notify(ok and ("Salvo em " .. where) or where, ok and "ok" or "warn", 4)
				end },
				{ separator = true },
				{ text = "Expandir tudo abaixo", icon = "⊞", action = function()
					pcall(function()
						local n = 0
						for _, d in ipairs(inst:GetDescendants()) do
							n += 1
							if n > 800 then break end
							Explorer.expanded[d] = true
						end
					end)
					Explorer.expanded[inst] = true
					Explorer.refresh()
				end },
				{ text = "Destruir", icon = "⊘", color = C.danger, action = function()
					local ok = pcall(function() inst:Destroy() end)
					Library.notify(ok and "Instancia destruida" or "Nao consegui destruir", ok and "warn" or "erro")
					Explorer.refresh()
				end },
			}, mouse.X, mouse.Y - 36)
		end,
	})

	--── propriedades ─────────────────────────────────────────────────────
	local rightHolder = Create.frame({ Parent = split.right, Size = UDim2.fromScale(1, 1) })

	local propHeader = Create.frame({
		Parent = rightHolder,
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0,
	})
	Create.padding(propHeader, 7, 10, 0, 12)

	local propTitle = Create.text({
		Parent = propHeader,
		Text = "Nada selecionado",
		Font = T.faces.bold,
		TextSize = T.font.heading,
		TextColor3 = C.textDim,
		Size = UDim2.new(1, 0, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local propPath = Create.mono({
		Parent = propHeader,
		Text = "clique numa instancia",
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Position = UDim2.fromOffset(0, 19),
		Size = UDim2.new(1, 0, 0, 14),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local kv = Library.keyValue(rightHolder, {
		Position = UDim2.fromOffset(4, 46),
		Size = UDim2.new(1, -8, 1, -50),
	})
	kv:Empty("Selecione uma instancia na arvore")

	--══════════════════════════════════════════════════════════════════════
	function Explorer.select(inst)
		Explorer.selected = inst
		Explorer.Selected:Fire(inst)

		propTitle.Text = Env.safeIndex(inst, "Name", "?")
		propTitle.TextColor3 = C.text
		propPath.Text = Util.fullName(inst)

		kv:Clear()

		kv:Section("identidade")
		kv:Row("ClassName", Env.safeIndex(inst, "ClassName", "?"), { color = C.accent })
		kv:Row("caminho", Util.fullName(inst), { tall = true })
		local childCount = 0
		pcall(function() childCount = #inst:GetChildren() end)
		kv:Row("filhos", childCount)
		kv:Row("descendentes", Util.countDescendants(inst, 20000))

		kv:Gap()
		kv:Section("propriedades")
		local props = propertyList(inst)
		local shown = 0
		for _, prop in ipairs(props) do
			if prop ~= "Parent" and prop ~= "ClassName" then
				local ok, value = pcall(function() return inst[prop] end)
				if ok and value ~= nil then
					shown += 1
					local t = typeof(value)
					kv:Row(prop, Serializer.preview(value, 64), { color = Theme.typeColor(t) })
				end
			end
		end
		if shown == 0 then
			kv:Row("—", "nenhuma propriedade conhecida para essa classe", { color = C.textFaint })
		end

		-- atributos
		local attrs
		pcall(function() attrs = inst:GetAttributes() end)
		if attrs and next(attrs) then
			kv:Gap()
			kv:Section("atributos")
			for k, v in pairs(attrs) do
				kv:Row(k, Serializer.preview(v, 64), { color = Theme.typeColor(typeof(v)) })
			end
		end

		-- tags
		local tags
		pcall(function()
			local cs = game:GetService("CollectionService")
			tags = cs:GetTags(inst)
		end)
		if tags and #tags > 0 then
			kv:Gap()
			kv:Section("tags")
			kv:Row("CollectionService", table.concat(tags, ", "), { tall = true })
		end

		-- se for remote, atalho pro spy
		if Util.isRemote(inst) then
			kv:Gap()
			kv:Section("remote")
			kv:Row("tipo", Util.remoteKind(inst), { color = Theme.kindColor(Util.remoteKind(inst)) })
			kv:Row("bloqueado", tostring(Config.isBlocked(Util.fullName(inst))),
				{ color = C.danger, onClick = function()
					Config.toggleBlocked(Util.fullName(inst))
					Explorer.select(inst)
				end })
			kv:Row("codigo de disparo",
				("%s:FireServer()"):format(Util.instancePath(inst)),
				{ tall = true, color = C.accent })
		end

		-- se tiver source legivel
		if Env.safeIndex(inst, "ClassName", ""):find("Script") then
			kv:Gap()
			kv:Section("codigo")
			local src
			if Env.decompile then
				kv:Row("decompilar", "clique para tentar", { color = C.info, onClick = function()
					Library.notify("Decompilando…", "info", 2)
					task.spawn(function()
						local ok, result = pcall(Env.decompile, inst)
						if ok and result then
							Env.copy(result)
							Library.notify("Fonte copiada pro clipboard", "ok", 3)
						else
							Library.notify("Decompilacao falhou", "erro", 3)
						end
					end)
				end })
			else
				kv:Row("decompilar", "executor nao suporta", { color = C.textFaint })
			end
		end
	end

	--══════════════════════════════════════════════════════════════════════
	local doRefresh = Util.throttle(function()
		if mode == "search" then
			rows = searchResults
		else
			rows = Explorer.buildRows(4000)
		end
		list:SetItems(rows, true)
		counter:Set(Util.compactNumber(#rows))
	end, 0.1)

	Explorer.refresh = doRefresh

	-- expande as raizes principais no primeiro uso
	for _, root in ipairs(Explorer.roots()) do
		if root == Env.Services.ReplicatedStorage or root == Env.Services.Workspace then
			Explorer.expanded[root] = true
		end
	end

	doRefresh()
	return { list = list, refresh = doRefresh }
end

return Explorer
