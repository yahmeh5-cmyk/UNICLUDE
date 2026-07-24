--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/ui/Create.lua
	Fabrica de instancias declarativa + primitivos de UI reutilizados por
	toda a Library: tween, drag, hover, stroke, corner, padding, layout,
	scroll com barra fina, texto medido e ripple discreto.
═══════════════════════════════════════════════════════════════════════════]]

local UNI   = ...
local Env   = UNI.require("src/core/Env")
local Theme = UNI.require("src/ui/Theme")

local TweenService = Env.Services.TweenService
local UIS          = Env.Services.UserInputService
local RunService    = Env.Services.RunService

local Create = {}

--══════════════════════════════════════════════════════════════════════════
-- FABRICA
--══════════════════════════════════════════════════════════════════════════

--- Create.new("Frame", { props }, { filhos })
function Create.new(className, props, children)
	local inst = Instance.new(className)
	props = props or {}

	local parent = props.Parent
	props.Parent = nil

	for k, v in pairs(props) do
		if type(k) == "string" then
			local ok, err = pcall(function() inst[k] = v end)
			if not ok then
				warn(("[UNICLUDE/Create] %s.%s invalido: %s"):format(className, k, tostring(err)))
			end
		end
	end

	if children then
		for _, child in ipairs(children) do
			if typeof(child) == "Instance" then child.Parent = inst end
		end
	end

	if parent then inst.Parent = parent end
	return inst
end

local new = Create.new

--══════════════════════════════════════════════════════════════════════════
-- MODIFICADORES
--══════════════════════════════════════════════════════════════════════════

function Create.corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.radius.md), Parent = parent })
end

function Create.stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or Theme.c.stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Create.padding(parent, top, right, bottom, left)
	top = top or 0
	right = right or top
	bottom = bottom or top
	left = left or right
	return new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
		Parent = parent,
	})
end

function Create.list(parent, direction, gap, align)
	return new("UIListLayout", {
		FillDirection = direction == "h" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or Theme.space.sm),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

function Create.grid(parent, cellSize, gap)
	return new("UIGridLayout", {
		CellSize = cellSize,
		CellPadding = UDim2.fromOffset(gap or Theme.space.sm, gap or Theme.space.sm),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Create.constraint(parent, minSize, maxSize)
	return new("UISizeConstraint", {
		MinSize = minSize or Vector2.new(0, 0),
		MaxSize = maxSize or Vector2.new(math.huge, math.huge),
		Parent = parent,
	})
end

--══════════════════════════════════════════════════════════════════════════
-- BLOCOS BASE
--══════════════════════════════════════════════════════════════════════════

function Create.frame(props, children)
	local f = new("Frame", props, children)
	if props and props.BackgroundTransparency == nil and props.BackgroundColor3 == nil then
		f.BackgroundTransparency = 1
	end
	f.BorderSizePixel = 0
	return f
end

function Create.text(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.faces.regular,
		TextSize = Theme.font.body,
		TextColor3 = Theme.c.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false,
	}
	for k, v in pairs(props or {}) do defaults[k] = v end
	return new("TextLabel", defaults)
end

function Create.mono(props)
	props = props or {}
	props.Font = Theme.faces.mono
	props.TextSize = props.TextSize or Theme.font.small
	return Create.text(props)
end

function Create.button(props)
	local defaults = {
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = Theme.faces.medium,
		TextSize = Theme.font.body,
		TextColor3 = Theme.c.text,
		Text = "",
		BorderSizePixel = 0,
	}
	for k, v in pairs(props or {}) do defaults[k] = v end
	return new("TextButton", defaults)
end

function Create.scroll(props)
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = Theme.metrics.scrollbar,
		ScrollBarImageColor3 = Theme.c.strokeStrong,
		ScrollBarImageTransparency = 0.25,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
	}
	for k, v in pairs(props or {}) do defaults[k] = v end
	return new("ScrollingFrame", defaults)
end

--- Linha divisoria de 1px
function Create.divider(parent, horizontal, inset)
	inset = inset or 0
	if horizontal == false then
		return Create.frame({
			Parent = parent,
			BackgroundColor3 = Theme.c.strokeSoft,
			BackgroundTransparency = 0,
			Size = UDim2.new(0, 1, 1, -inset * 2),
			Position = UDim2.new(0, 0, 0, inset),
		})
	end
	return Create.frame({
		Parent = parent,
		BackgroundColor3 = Theme.c.strokeSoft,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, -inset * 2, 0, 1),
		Position = UDim2.new(0, inset, 0, 0),
	})
end

--══════════════════════════════════════════════════════════════════════════
-- MOVIMENTO
--══════════════════════════════════════════════════════════════════════════

function Create.tween(inst, props, info)
	local t = TweenService:Create(inst, info or Theme.motion.fast, props)
	t:Play()
	return t
end

--- Hover que troca cor de fundo (e opcionalmente texto)
function Create.hoverFill(inst, idle, hover, textIdle, textHover)
	local target = inst
	inst.MouseEnter:Connect(function()
		Create.tween(target, { BackgroundColor3 = hover }, Theme.motion.instant)
		if textIdle and textHover and target:IsA("TextButton") then
			Create.tween(target, { TextColor3 = textHover }, Theme.motion.instant)
		end
	end)
	inst.MouseLeave:Connect(function()
		Create.tween(target, { BackgroundColor3 = idle }, Theme.motion.fast)
		if textIdle and textHover and target:IsA("TextButton") then
			Create.tween(target, { TextColor3 = textIdle }, Theme.motion.fast)
		end
	end)
end

--- Feedback de clique: leve escurecida, sem ripple exagerado
function Create.pressFeedback(btn, base, pressed)
	btn.MouseButton1Down:Connect(function()
		Create.tween(btn, { BackgroundColor3 = pressed }, Theme.motion.instant)
	end)
	btn.MouseButton1Up:Connect(function()
		Create.tween(btn, { BackgroundColor3 = base }, Theme.motion.fast)
	end)
end

--══════════════════════════════════════════════════════════════════════════
-- ARRASTAR
--══════════════════════════════════════════════════════════════════════════

--- Torna `target` arrastavel por `handle`. onEnd(position) opcional.
function Create.draggable(handle, target, onEnd)
	local dragging, dragStart, startPos = false, nil, nil
	local conns = {}

	table.insert(conns, handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			local changed
			changed = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					changed:Disconnect()
					if onEnd then onEnd(target.Position) end
				end
			end)
		end
	end))

	table.insert(conns, UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))

	return function()
		for _, c in ipairs(conns) do c:Disconnect() end
	end
end

--- Alca de redimensionamento no canto inferior direito
function Create.resizable(grip, target, minSize, onEnd)
	local resizing, startPos, startSize = false, nil, nil
	local conns = {}

	table.insert(conns, grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			startPos = input.Position
			startSize = target.AbsoluteSize
			local changed
			changed = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
					changed:Disconnect()
					if onEnd then onEnd(target.AbsoluteSize) end
				end
			end)
		end
	end))

	table.insert(conns, UIS.InputChanged:Connect(function(input)
		if not resizing then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - startPos
			local w = math.max(minSize.X, startSize.X + delta.X)
			local h = math.max(minSize.Y, startSize.Y + delta.Y)
			target.Size = UDim2.fromOffset(w, h)
		end
	end))

	return function()
		for _, c in ipairs(conns) do c:Disconnect() end
	end
end

--- Divisor arrastavel entre dois paineis horizontais
function Create.splitter(handle, container, leftPane, rightPane, minLeft, minRight, onEnd)
	local dragging = false
	local conns = {}

	table.insert(conns, handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			local changed
			changed = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					changed:Disconnect()
					if onEnd then onEnd(leftPane.Size.X.Offset) end
				end
			end)
		end
	end))

	table.insert(conns, UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
		local rel = input.Position.X - container.AbsolutePosition.X
		local total = container.AbsoluteSize.X
		local leftW = math.clamp(rel, minLeft, total - minRight)
		leftPane.Size = UDim2.new(0, leftW, 1, 0)
		rightPane.Position = UDim2.new(0, leftW + handle.AbsoluteSize.X, 0, 0)
		rightPane.Size = UDim2.new(1, -(leftW + handle.AbsoluteSize.X), 1, 0)
		handle.Position = UDim2.new(0, leftW, 0, 0)
	end))

	return function()
		for _, c in ipairs(conns) do c:Disconnect() end
	end
end

--══════════════════════════════════════════════════════════════════════════
-- MEDICAO
--══════════════════════════════════════════════════════════════════════════
local measureLabel

function Create.measureText(text, font, size, maxWidth)
	local TextService = Env.Services.TextService
	local ok, result = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(maxWidth or 10000, 100000))
	end)
	if ok then return result end
	return Vector2.new(#text * size * 0.55, size)
end

--══════════════════════════════════════════════════════════════════════════
-- ATALHOS DE COMPOSICAO
--══════════════════════════════════════════════════════════════════════════

--- Superficie padrao: fundo + borda + canto
function Create.surface(props, radius)
	local f = Create.frame(props)
	f.BackgroundTransparency = props and props.BackgroundTransparency or 0
	Create.corner(f, radius or Theme.radius.md)
	Create.stroke(f, Theme.c.stroke)
	return f
end

--- Badge de texto compacto (usado em tipo de remote, nivel de log, contadores)
function Create.badge(parent, text, color, order)
	local holder = Create.frame({
		Parent = parent,
		BackgroundColor3 = Theme.deepen(color, 0.8),
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order or 0,
	})
	Create.corner(holder, Theme.radius.sm)
	Create.padding(holder, 0, 6, 0, 6)
	local label = Create.text({
		Parent = holder,
		Text = text,
		TextColor3 = color,
		Font = Theme.faces.bold,
		TextSize = Theme.font.micro,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	return holder, label
end

return Create
