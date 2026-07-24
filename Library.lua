--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/ui/Library.lua
	Biblioteca de interface do UNICLUDE.

	Componentes: Window (topbar, sidebar, statusbar, arrastar, redimensionar,
	minimizar, atalho de teclado), Tab, Toolbar (botao, toggle, busca,
	dropdown, chip, contador), SplitPane, CodeView, KeyValue (inspetor de
	propriedades), Tree (linhas de arvore), ContextMenu, Toast e Tooltip.

	Nada de card generico repetido: cada painel tem densidade e ritmo proprios.
═══════════════════════════════════════════════════════════════════════════]]

local UNI     = ...
local Env     = UNI.require("src/core/Env")
local Util    = UNI.require("src/core/Util")
local Signal  = UNI.require("src/core/Signal")
local Config  = UNI.require("src/core/Config")
local Theme   = UNI.require("src/ui/Theme")
local Create  = UNI.require("src/ui/Create")
local Highlighter = UNI.require("src/ui/Highlighter")

local UIS = Env.Services.UserInputService
local T, C = Theme, Theme.c

local Library = {}
Library.ActiveWindow = nil

--══════════════════════════════════════════════════════════════════════════
-- TOOLTIP GLOBAL
--══════════════════════════════════════════════════════════════════════════
local tooltipHolder, tooltipLabel

local function ensureTooltip(screen)
	if tooltipHolder and tooltipHolder.Parent then return end
	tooltipHolder = Create.frame({
		Parent = screen,
		BackgroundColor3 = C.elevated,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		ZIndex = 500,
	})
	Create.corner(tooltipHolder, T.radius.sm)
	Create.stroke(tooltipHolder, C.strokeStrong)
	Create.padding(tooltipHolder, 0, 8, 0, 8)
	tooltipLabel = Create.text({
		Parent = tooltipHolder,
		Text = "",
		TextSize = T.font.small,
		TextColor3 = C.textDim,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 501,
	})
end

function Library.attachTooltip(gui, text)
	if not text or text == "" then return end
	gui.MouseEnter:Connect(function()
		if not tooltipHolder then return end
		tooltipLabel.Text = text
		tooltipHolder.Visible = true
	end)
	gui.MouseMoved:Connect(function(x, y)
		if not tooltipHolder or not tooltipHolder.Visible then return end
		tooltipHolder.Position = UDim2.fromOffset(x + 14, y + 18)
	end)
	gui.MouseLeave:Connect(function()
		if tooltipHolder then tooltipHolder.Visible = false end
	end)
end

--══════════════════════════════════════════════════════════════════════════
-- TOASTS
--══════════════════════════════════════════════════════════════════════════
local toastStack

local TOAST_COLORS = {
	info    = function() return C.info end,
	ok      = function() return C.success end,
	warn    = function() return C.warn end,
	erro    = function() return C.danger end,
	accent  = function() return C.accent end,
}

function Library.notify(text, kind, duration)
	if not Config.get("notifications") then return end
	if not toastStack then return end

	kind = kind or "info"
	local color = (TOAST_COLORS[kind] or TOAST_COLORS.info)()

	local card = Create.frame({
		Parent = toastStack,
		BackgroundColor3 = C.elevated,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 400,
	})
	Create.corner(card, T.radius.md)
	Create.stroke(card, C.strokeStrong)
	Create.padding(card, 8, 10, 8, 10)

	local row = Create.frame({ Parent = card, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 401 })
	Create.list(row, "h", 8)
	row:FindFirstChildOfClass("UIListLayout").VerticalAlignment = Enum.VerticalAlignment.Top

	Create.text({
		Parent = row,
		Text = "●",
		TextColor3 = color,
		TextSize = T.font.small,
		Size = UDim2.fromOffset(8, 16),
		ZIndex = 401,
	})

	Create.text({
		Parent = row,
		Text = text,
		TextColor3 = C.text,
		TextSize = T.font.small,
		Size = UDim2.new(1, -18, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 401,
	})

	card.BackgroundTransparency = 1
	Create.tween(card, { BackgroundTransparency = 0 }, T.motion.base)

	task.delay(duration or Config.get("notifyDuration"), function()
		if not card.Parent then return end
		local out = Create.tween(card, { BackgroundTransparency = 1 }, T.motion.base)
		out.Completed:Wait()
		card:Destroy()
	end)

	return card
end

--══════════════════════════════════════════════════════════════════════════
-- CONTEXT MENU
--══════════════════════════════════════════════════════════════════════════
local activeMenu

function Library.closeMenu()
	if activeMenu then
		activeMenu:Destroy()
		activeMenu = nil
	end
end

--- items = { { text, icon, color, action, disabled, separator } }
function Library.contextMenu(items, x, y)
	Library.closeMenu()
	local screen = Library.ActiveWindow and Library.ActiveWindow.screen
	if not screen then return end

	local menu = Create.frame({
		Parent = screen,
		BackgroundColor3 = C.elevated,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(196, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 450,
	})
	Create.corner(menu, T.radius.md)
	Create.stroke(menu, C.strokeStrong)
	Create.padding(menu, 4, 4, 4, 4)
	Create.list(menu, "v", 1)

	for _, item in ipairs(items) do
		if item.separator then
			local sep = Create.frame({
				Parent = menu,
				BackgroundColor3 = C.strokeSoft,
				BackgroundTransparency = 0,
				Size = UDim2.new(1, 0, 0, 1),
				ZIndex = 451,
			})
		else
			local btn = Create.button({
				Parent = menu,
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundColor3 = C.elevated,
				BackgroundTransparency = 1,
				Text = "",
				ZIndex = 451,
				AutoButtonColor = false,
			})
			Create.corner(btn, T.radius.sm)
			Create.padding(btn, 0, 8, 0, 8)

			local label = Create.text({
				Parent = btn,
				Text = (item.icon and (item.icon .. "  ") or "") .. item.text,
				TextColor3 = item.disabled and C.textFaint or (item.color or C.text),
				TextSize = T.font.small,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 452,
			})

			if item.shortcut then
				Create.text({
					Parent = btn,
					Text = item.shortcut,
					TextColor3 = C.textFaint,
					TextSize = T.font.micro,
					Font = T.faces.mono,
					Size = UDim2.fromScale(1, 1),
					TextXAlignment = Enum.TextXAlignment.Right,
					ZIndex = 452,
				})
			end

			if not item.disabled then
				btn.MouseEnter:Connect(function()
					btn.BackgroundTransparency = 0
					btn.BackgroundColor3 = C.hover
				end)
				btn.MouseLeave:Connect(function()
					btn.BackgroundTransparency = 1
				end)
				btn.MouseButton1Click:Connect(function()
					Library.closeMenu()
					task.spawn(item.action)
				end)
			end
		end
	end

	-- fecha ao clicar fora
	task.defer(function()
		local conn
		conn = UIS.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton2 then
				local mouse = UIS:GetMouseLocation()
				local pos, size = menu.AbsolutePosition, menu.AbsoluteSize
				local inside = mouse.X >= pos.X and mouse.X <= pos.X + size.X
					and mouse.Y >= pos.Y - 36 and mouse.Y <= pos.Y + size.Y - 36
				if not inside then
					conn:Disconnect()
					Library.closeMenu()
				end
			end
		end)
	end)

	activeMenu = menu
	return menu
end

--══════════════════════════════════════════════════════════════════════════
-- CONTROLES
--══════════════════════════════════════════════════════════════════════════
local Controls = {}
Library.Controls = Controls

function Controls.button(parent, opts)
	local variant = opts.variant or "ghost"
	local bg = C.panelAlt
	local fg = C.text
	if variant == "solid" then bg = C.accent; fg = C.textInvert end
	if variant == "danger" then bg = T.deepen(C.danger, 0.72); fg = C.danger end
	if variant == "ghost"  then bg = C.panelAlt; fg = C.textDim end

	local btn = Create.button({
		Parent = parent,
		Text = "",
		Size = opts.Size or UDim2.new(0, 0, 0, T.metrics.inputHeight),
		AutomaticSize = opts.Size and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
		BackgroundColor3 = bg,
		BackgroundTransparency = 0,
		LayoutOrder = opts.order or 0,
	})
	Create.corner(btn, T.radius.sm)
	Create.padding(btn, 0, 10, 0, 10)
	if variant ~= "solid" then Create.stroke(btn, C.stroke) end

	local label = Create.text({
		Parent = btn,
		Text = opts.text or "Botao",
		TextColor3 = fg,
		Font = T.faces.medium,
		TextSize = T.font.small,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local hoverBg = variant == "solid" and C.accent:Lerp(Color3.new(1,1,1), 0.12) or C.hover
	Create.hoverFill(btn, bg, hoverBg)
	Create.pressFeedback(btn, bg, C.pressed)

	if opts.tooltip then Library.attachTooltip(btn, opts.tooltip) end
	if opts.onClick then btn.MouseButton1Click:Connect(opts.onClick) end

	return btn, label
end

function Controls.iconButton(parent, opts)
	local btn = Create.button({
		Parent = parent,
		Text = opts.icon or "•",
		Font = T.faces.medium,
		TextSize = opts.textSize or 13,
		TextColor3 = opts.color or C.textDim,
		Size = UDim2.fromOffset(opts.size or 24, opts.size or 24),
		BackgroundColor3 = C.panelAlt,
		BackgroundTransparency = opts.flat and 1 or 0,
		LayoutOrder = opts.order or 0,
	})
	Create.corner(btn, T.radius.sm)

	btn.MouseEnter:Connect(function()
		btn.BackgroundTransparency = 0
		Create.tween(btn, { BackgroundColor3 = C.hover, TextColor3 = opts.hoverColor or C.text }, T.motion.instant)
	end)
	btn.MouseLeave:Connect(function()
		Create.tween(btn, { BackgroundColor3 = C.panelAlt, TextColor3 = opts.color or C.textDim }, T.motion.fast)
		if opts.flat then task.delay(0.15, function() btn.BackgroundTransparency = 1 end) end
	end)

	if opts.tooltip then Library.attachTooltip(btn, opts.tooltip) end
	if opts.onClick then btn.MouseButton1Click:Connect(opts.onClick) end
	return btn
end

function Controls.toggle(parent, opts)
	local state = opts.value == true

	local holder = Create.button({
		Parent = parent,
		Text = "",
		Size = UDim2.new(0, 0, 0, T.metrics.inputHeight),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panelAlt,
		BackgroundTransparency = 0,
		LayoutOrder = opts.order or 0,
	})
	Create.corner(holder, T.radius.sm)
	Create.stroke(holder, C.stroke)
	Create.padding(holder, 0, 9, 0, 7)
	Create.list(holder, "h", 7)

	local dot = Create.frame({
		Parent = holder,
		BackgroundColor3 = state and C.accent or C.strokeStrong,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(7, 7),
	})
	Create.corner(dot, T.radius.pill)

	local label = Create.text({
		Parent = holder,
		Text = opts.text or "Opcao",
		TextColor3 = state and C.text or C.textDim,
		Font = T.faces.medium,
		TextSize = T.font.small,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
	})

	local api = {}
	function api:Set(v, silent)
		state = v and true or false
		Create.tween(dot, { BackgroundColor3 = state and C.accent or C.strokeStrong }, T.motion.fast)
		Create.tween(label, { TextColor3 = state and C.text or C.textDim }, T.motion.fast)
		if not silent and opts.onChange then opts.onChange(state) end
	end
	function api:Get() return state end
	function api:Toggle() api:Set(not state) end

	holder.MouseButton1Click:Connect(function() api:Toggle() end)
	Create.hoverFill(holder, C.panelAlt, C.hover)
	if opts.tooltip then Library.attachTooltip(holder, opts.tooltip) end

	api.instance = holder
	return api
end

function Controls.input(parent, opts)
	local holder = Create.frame({
		Parent = parent,
		BackgroundColor3 = C.root,
		BackgroundTransparency = 0,
		Size = opts.Size or UDim2.new(0, 200, 0, T.metrics.inputHeight),
		LayoutOrder = opts.order or 0,
	})
	Create.corner(holder, T.radius.sm)
	local stroke = Create.stroke(holder, C.stroke)
	Create.padding(holder, 0, 8, 0, 8)

	local icon
	if opts.icon then
		icon = Create.text({
			Parent = holder,
			Text = opts.icon,
			TextColor3 = C.textFaint,
			TextSize = T.font.small,
			Size = UDim2.fromOffset(14, 0),
			Position = UDim2.new(0, 0, 0, 0),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
		})
		icon.Size = UDim2.new(0, 14, 1, 0)
	end

	local box = Create.new("TextBox", {
		Parent = holder,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, opts.icon and -18 or 0, 1, 0),
		Position = UDim2.fromOffset(opts.icon and 18 or 0, 0),
		Font = opts.mono and T.faces.mono or T.faces.regular,
		TextSize = T.font.small,
		TextColor3 = C.text,
		PlaceholderText = opts.placeholder or "",
		PlaceholderColor3 = C.textFaint,
		Text = opts.value or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
	})

	box.Focused:Connect(function()
		Create.tween(stroke, { Color = C.accentSoft }, T.motion.fast)
	end)
	box.FocusLost:Connect(function(enter)
		Create.tween(stroke, { Color = C.stroke }, T.motion.fast)
		if opts.onSubmit and enter then opts.onSubmit(box.Text) end
	end)

	if opts.onChange then
		local handler = opts.debounce and Util.debounce(opts.onChange, opts.debounce) or opts.onChange
		box:GetPropertyChangedSignal("Text"):Connect(function() handler(box.Text) end)
	end

	return { instance = holder, box = box,
		Get = function() return box.Text end,
		Set = function(_, v) box.Text = v end }
end

function Controls.dropdown(parent, opts)
	local options = opts.options or {}
	local current = opts.value or options[1]

	local btn = Create.button({
		Parent = parent,
		Text = "",
		Size = opts.Size or UDim2.new(0, 130, 0, T.metrics.inputHeight),
		BackgroundColor3 = C.panelAlt,
		BackgroundTransparency = 0,
		LayoutOrder = opts.order or 0,
	})
	Create.corner(btn, T.radius.sm)
	Create.stroke(btn, C.stroke)
	Create.padding(btn, 0, 8, 0, 8)

	local label = Create.text({
		Parent = btn,
		Text = (opts.prefix or "") .. tostring(current),
		TextColor3 = C.text,
		Font = T.faces.medium,
		TextSize = T.font.small,
		Size = UDim2.new(1, -12, 1, 0),
	})
	Create.text({
		Parent = btn,
		Text = "▾",
		TextColor3 = C.textFaint,
		TextSize = T.font.micro,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local api = { instance = btn }
	function api:Get() return current end
	function api:Set(v, silent)
		current = v
		label.Text = (opts.prefix or "") .. tostring(v)
		if not silent and opts.onChange then opts.onChange(v) end
	end

	btn.MouseButton1Click:Connect(function()
		local items = {}
		for _, o in ipairs(options) do
			local value = type(o) == "table" and o.value or o
			local text  = type(o) == "table" and o.text or tostring(o)
			table.insert(items, {
				text = text,
				icon = (value == current) and "✓" or "  ",
				color = (value == current) and C.accent or C.text,
				action = function() api:Set(value) end,
			})
		end
		local pos = btn.AbsolutePosition
		Library.contextMenu(items, pos.X, pos.Y + btn.AbsoluteSize.Y + 40)
	end)

	Create.hoverFill(btn, C.panelAlt, C.hover)
	return api
end

--- Contador vivo (usado no statusbar e nas abas)
function Controls.counter(parent, opts)
	local holder = Create.frame({
		Parent = parent,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = opts.order or 0,
	})
	Create.list(holder, "h", 5)

	local value = Create.text({
		Parent = holder,
		Text = "0",
		Font = T.faces.bold,
		TextSize = T.font.small,
		TextColor3 = opts.color or C.text,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	local caption = Create.text({
		Parent = holder,
		Text = opts.label or "",
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
	})

	return {
		instance = holder,
		Set = function(_, v) value.Text = tostring(v) end,
		SetLabel = function(_, v) caption.Text = v end,
		SetColor = function(_, c) value.TextColor3 = c end,
	}
end

--══════════════════════════════════════════════════════════════════════════
-- TOOLBAR
--══════════════════════════════════════════════════════════════════════════
function Library.toolbar(parent, opts)
	opts = opts or {}
	local bar = Create.frame({
		Parent = parent,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = opts.transparent and 1 or 0,
		Size = UDim2.new(1, 0, 0, T.metrics.toolbarHeight),
		Position = opts.Position or UDim2.new(),
		LayoutOrder = opts.order or 0,
		ZIndex = opts.ZIndex or 2,
	})
	Create.padding(bar, 0, 8, 0, 8)

	local left = Create.frame({ Parent = bar, Size = UDim2.new(1, 0, 1, 0) })
	Create.list(left, "h", 6)

	if not opts.noDivider then
		Create.frame({
			Parent = bar,
			BackgroundColor3 = C.strokeSoft,
			BackgroundTransparency = 0,
			Size = UDim2.new(1, 16, 0, 1),
			Position = UDim2.new(0, -8, 1, -1),
		})
	end

	local api = { instance = bar, row = left }

	function api:Button(o) o.order = o.order or #left:GetChildren(); return Controls.button(left, o) end
	function api:Icon(o)   o.order = o.order or #left:GetChildren(); return Controls.iconButton(left, o) end
	function api:Toggle(o) o.order = o.order or #left:GetChildren(); return Controls.toggle(left, o) end
	function api:Input(o)  o.order = o.order or #left:GetChildren(); return Controls.input(left, o) end
	function api:Dropdown(o) o.order = o.order or #left:GetChildren(); return Controls.dropdown(left, o) end
	function api:Counter(o) o.order = o.order or #left:GetChildren(); return Controls.counter(left, o) end

	function api:Label(text, color)
		return Create.text({
			Parent = left,
			Text = text,
			TextColor3 = color or C.textFaint,
			TextSize = T.font.small,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = #left:GetChildren(),
		})
	end

	function api:Separator()
		local sep = Create.frame({
			Parent = left,
			BackgroundColor3 = C.stroke,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(1, 14),
			LayoutOrder = #left:GetChildren(),
		})
		return sep
	end

	function api:Spacer(width)
		return Create.frame({
			Parent = left,
			Size = UDim2.fromOffset(width or 8, 1),
			LayoutOrder = #left:GetChildren(),
		})
	end

	--- empurra os proximos itens para a direita
	function api:Flex()
		local flex = Create.frame({
			Parent = left,
			Size = UDim2.new(1, -420, 1, 0),
			LayoutOrder = #left:GetChildren(),
		})
		return flex
	end

	return api
end

--══════════════════════════════════════════════════════════════════════════
-- SPLIT PANE
--══════════════════════════════════════════════════════════════════════════
function Library.splitPane(parent, opts)
	opts = opts or {}
	local leftWidth = opts.leftWidth or 340

	local container = Create.frame({
		Parent = parent,
		Size = opts.Size or UDim2.new(1, 0, 1, 0),
		Position = opts.Position or UDim2.new(),
		LayoutOrder = opts.order or 0,
	})

	local leftPane = Create.frame({
		Parent = container,
		Size = UDim2.new(0, leftWidth, 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})

	local handle = Create.frame({
		Parent = container,
		Position = UDim2.new(0, leftWidth, 0, 0),
		Size = UDim2.new(0, 5, 1, 0),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0,
	})
	Create.frame({
		Parent = handle,
		Position = UDim2.new(0, 2, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = C.strokeSoft,
		BackgroundTransparency = 0,
	})

	local rightPane = Create.frame({
		Parent = container,
		Position = UDim2.new(0, leftWidth + 5, 0, 0),
		Size = UDim2.new(1, -(leftWidth + 5), 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})

	handle.MouseEnter:Connect(function()
		Create.tween(handle, { BackgroundColor3 = C.accentDeep }, T.motion.instant)
	end)
	handle.MouseLeave:Connect(function()
		Create.tween(handle, { BackgroundColor3 = C.panel }, T.motion.fast)
	end)

	Create.splitter(handle, container, leftPane, rightPane,
		opts.minLeft or 220, opts.minRight or 260, opts.onResize)

	return { container = container, left = leftPane, right = rightPane, handle = handle }
end

--══════════════════════════════════════════════════════════════════════════
-- CODE VIEW
--══════════════════════════════════════════════════════════════════════════
function Library.codeView(parent, opts)
	opts = opts or {}

	local holder = Create.frame({
		Parent = parent,
		Size = opts.Size or UDim2.new(1, 0, 1, 0),
		Position = opts.Position or UDim2.new(),
		BackgroundColor3 = C.root,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
		LayoutOrder = opts.order or 0,
	})
	Create.corner(holder, T.radius.sm)
	Create.stroke(holder, C.strokeSoft)

	local scroll = Create.scroll({
		Parent = holder,
		Size = UDim2.new(1, 0, 1, 0),
		ScrollingDirection = Enum.ScrollingDirection.XY,
		CanvasSize = UDim2.new(),
	})
	Create.padding(scroll, 8, 10, 8, 8)

	local gutter = Create.mono({
		Parent = scroll,
		Text = "",
		TextColor3 = C.textFaint,
		TextSize = T.font.small,
		Size = UDim2.fromOffset(30, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = opts.gutter ~= false,
	})

	local code = Create.mono({
		Parent = scroll,
		Text = "",
		RichText = true,
		TextColor3 = C.text,
		TextSize = T.font.small,
		Position = UDim2.fromOffset(opts.gutter ~= false and 40 or 0, 0),
		Size = UDim2.new(1, opts.gutter ~= false and -40 or 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = false,
	})

	local placeholder = Create.text({
		Parent = holder,
		Text = opts.placeholder or "Selecione um item para ver o codigo",
		TextColor3 = C.textFaint,
		TextSize = T.font.small,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local raw = ""

	local api = { instance = holder, scroll = scroll }

	function api:Set(source, highlight)
		raw = tostring(source or "")
		if raw == "" then
			code.Text = ""
			gutter.Text = ""
			placeholder.Visible = true
			return
		end
		placeholder.Visible = false
		if highlight == false then
			code.Text = Util.escapeRich(raw)
		else
			code.Text = Highlighter.render(raw, opts.maxChars or 60000)
		end
		local count = 1
		for _ in raw:gmatch("\n") do count += 1 end
		local nums = table.create(count)
		for i = 1, count do nums[i] = tostring(i) end
		gutter.Text = table.concat(nums, "\n")
		task.defer(function()
			scroll.CanvasSize = UDim2.fromOffset(
				code.AbsoluteSize.X + 60,
				math.max(code.AbsoluteSize.Y + 16, gutter.AbsoluteSize.Y + 16))
			scroll.CanvasPosition = Vector2.new(0, 0)
		end)
	end

	function api:Get() return raw end
	function api:Clear() api:Set("") end
	function api:Copy() return Env.copy(raw) end

	return api
end

--══════════════════════════════════════════════════════════════════════════
-- KEY / VALUE (inspetor)
--══════════════════════════════════════════════════════════════════════════
function Library.keyValue(parent, opts)
	opts = opts or {}
	local scroll = Create.scroll({
		Parent = parent,
		Size = opts.Size or UDim2.new(1, 0, 1, 0),
		Position = opts.Position or UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		LayoutOrder = opts.order or 0,
	})
	Create.list(scroll, "v", 0)
	Create.padding(scroll, 4, 6, 8, 8)

	local rows = {}
	local api = { instance = scroll }

	function api:Clear()
		for _, r in ipairs(rows) do r:Destroy() end
		table.clear(rows)
	end

	--- Cabecalho de secao
	function api:Section(title)
		local head = Create.frame({
			Parent = scroll,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = #rows + 1,
		})
		Create.text({
			Parent = head,
			Text = string.upper(title),
			Font = T.faces.bold,
			TextSize = T.font.micro,
			TextColor3 = C.textFaint,
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.fromOffset(0, 4),
		})
		table.insert(rows, head)
		return head
	end

	--- Linha chave/valor. onClick e onCopy opcionais.
	function api:Row(key, value, o)
		o = o or {}
		local row = Create.button({
			Parent = scroll,
			Text = "",
			Size = UDim2.new(1, 0, 0, o.tall and 0 or 20),
			AutomaticSize = o.tall and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
			BackgroundColor3 = C.panelAlt,
			BackgroundTransparency = 1,
			LayoutOrder = #rows + 1,
		})
		Create.corner(row, T.radius.sm)

		Create.text({
			Parent = row,
			Text = key,
			TextColor3 = C.textDim,
			TextSize = T.font.small,
			Size = UDim2.new(0, 128, 0, 20),
			Position = UDim2.fromOffset(4, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})

		local valueLabel = Create.text({
			Parent = row,
			Text = tostring(value),
			Font = o.mono ~= false and T.faces.mono or T.faces.regular,
			TextColor3 = o.color or C.text,
			TextSize = T.font.small,
			Position = UDim2.fromOffset(136, 0),
			Size = UDim2.new(1, -142, 0, o.tall and 0 or 20),
			AutomaticSize = o.tall and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
			TextWrapped = o.tall == true,
			TextYAlignment = o.tall and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
			TextTruncate = (not o.tall) and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
			RichText = o.rich == true,
		})

		row.MouseEnter:Connect(function() row.BackgroundTransparency = 0 end)
		row.MouseLeave:Connect(function() row.BackgroundTransparency = 1 end)
		row.MouseButton1Click:Connect(function()
			if o.onClick then o.onClick() else
				if Env.copy(tostring(value)) then
					Library.notify("Copiado: " .. Util.truncate(tostring(key), 32), "ok", 1.6)
				end
			end
		end)
		if o.onContext then
			row.MouseButton2Click:Connect(o.onContext)
		end

		table.insert(rows, row)
		return row, valueLabel
	end

	function api:Gap(h)
		local g = Create.frame({ Parent = scroll, Size = UDim2.new(1, 0, 0, h or 8), LayoutOrder = #rows + 1 })
		table.insert(rows, g)
	end

	function api:Empty(text)
		api:Clear()
		local e = Create.text({
			Parent = scroll,
			Text = text or "Nada selecionado",
			TextColor3 = C.textFaint,
			TextSize = T.font.small,
			Size = UDim2.new(1, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 1,
		})
		table.insert(rows, e)
	end

	return api
end

--══════════════════════════════════════════════════════════════════════════
-- SUB-ABAS (dentro de uma pagina)
--══════════════════════════════════════════════════════════════════════════
function Library.segmented(parent, opts)
	local holder = Create.frame({
		Parent = parent,
		Size = UDim2.new(0, 0, 0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.root,
		BackgroundTransparency = 0,
		LayoutOrder = opts.order or 0,
	})
	Create.corner(holder, T.radius.sm)
	Create.padding(holder, 2, 2, 2, 2)
	Create.list(holder, "h", 2)

	local buttons = {}
	local current = opts.value or (opts.options[1] and (opts.options[1].value or opts.options[1]))

	local api = { instance = holder }

	local function refresh()
		for value, btn in pairs(buttons) do
			local isActive = value == current
			Create.tween(btn, {
				BackgroundColor3 = isActive and C.elevated or C.root,
				BackgroundTransparency = isActive and 0 or 1,
				TextColor3 = isActive and C.text or C.textFaint,
			}, T.motion.fast)
		end
	end

	for i, o in ipairs(opts.options) do
		local value = type(o) == "table" and o.value or o
		local text  = type(o) == "table" and o.text or tostring(o)
		local btn = Create.button({
			Parent = holder,
			Text = text,
			Font = T.faces.medium,
			TextSize = T.font.micro,
			TextColor3 = C.textFaint,
			BackgroundColor3 = C.root,
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
		})
		Create.corner(btn, T.radius.sm)
		Create.padding(btn, 0, 9, 0, 9)
		btn.MouseButton1Click:Connect(function()
			current = value
			refresh()
			if opts.onChange then opts.onChange(value) end
		end)
		buttons[value] = btn
	end

	refresh()

	function api:Get() return current end
	function api:Set(v, silent)
		current = v
		refresh()
		if not silent and opts.onChange then opts.onChange(v) end
	end

	return api
end

--══════════════════════════════════════════════════════════════════════════
-- WINDOW
--══════════════════════════════════════════════════════════════════════════
local Window = {}
Window.__index = Window

function Library.window(opts)
	local self = setmetatable({}, Window)
	self.maid = Signal.newMaid()
	self.tabs = {}
	self.tabOrder = {}
	self.visible = true

	local savedPos  = Config.get("windowPosition")
	local savedSize = Config.get("windowSize")

	local screen = Create.new("ScreenGui", {
		Name = "UNICLUDE_" .. Util.shortHash(tostring(os.clock())),
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9999,
		IgnoreGuiInset = true,
	})
	Env.mountGui(screen)
	self.screen = screen
	self.maid:Add(screen)

	--── shell ────────────────────────────────────────────────────────────
	local root = Create.frame({
		Parent = screen,
		Name = "Shell",
		BackgroundColor3 = C.root,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(savedPos[1], savedPos[2]),
		Size = UDim2.fromOffset(savedSize[1], savedSize[2]),
		ClipsDescendants = true,
	})
	Create.corner(root, T.radius.lg)
	Create.stroke(root, C.strokeStrong)
	self.root = root

	--── topbar ───────────────────────────────────────────────────────────
	local topbar = Create.frame({
		Parent = root,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 0, 0, T.metrics.topbarHeight),
	})
	Create.padding(topbar, 0, 10, 0, 14)

	local titleRow = Create.frame({ Parent = topbar, Size = UDim2.new(1, 0, 1, 0) })
	Create.list(titleRow, "h", 8)

	Create.text({
		Parent = titleRow,
		Text = opts.title or "UNICLUDE",
		Font = T.faces.black,
		TextSize = T.font.title,
		TextColor3 = C.text,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
	})

	local versionPill = Create.frame({
		Parent = titleRow,
		BackgroundColor3 = C.accentDeep,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(0, 15),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
	})
	Create.corner(versionPill, T.radius.sm)
	Create.padding(versionPill, 0, 5, 0, 5)
	Create.text({
		Parent = versionPill,
		Text = "v" .. (opts.version or "1.0.0"),
		Font = T.faces.bold,
		TextSize = T.font.micro,
		TextColor3 = C.accent,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
	})

	Create.text({
		Parent = titleRow,
		Text = opts.subtitle or "",
		TextSize = T.font.small,
		TextColor3 = C.textFaint,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
	})

	-- controles da direita
	local windowControls = Create.frame({
		Parent = topbar,
		Size = UDim2.new(0, 84, 1, 0),
		Position = UDim2.new(1, -84, 0, 0),
	})
	Create.list(windowControls, "h", 4, Enum.HorizontalAlignment.Right)

	Controls.iconButton(windowControls, {
		icon = "◐", tooltip = "Trocar paleta", order = 1, flat = true,
		onClick = function()
			local nextTheme = Theme.current == "citron" and "slate" or "citron"
			Config.set("theme", nextTheme)
			Library.notify("Paleta " .. nextTheme .. " sera aplicada no proximo boot", "info")
		end,
	})
	Controls.iconButton(windowControls, {
		icon = "—", tooltip = "Minimizar", order = 2, flat = true,
		onClick = function() self:Minimize() end,
	})
	Controls.iconButton(windowControls, {
		icon = "✕", tooltip = "Fechar (desliga os hooks)", order = 3, flat = true,
		color = C.textDim, hoverColor = C.danger,
		onClick = function() self:Close() end,
	})

	Create.frame({
		Parent = topbar,
		BackgroundColor3 = C.strokeSoft,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 24, 0, 1),
		Position = UDim2.new(0, -10, 1, -1),
	})

	Create.draggable(topbar, root, function(pos)
		Config.set("windowPosition", { pos.X.Offset, pos.Y.Offset }, true)
	end)

	--── corpo ────────────────────────────────────────────────────────────
	local body = Create.frame({
		Parent = root,
		Position = UDim2.fromOffset(0, T.metrics.topbarHeight),
		Size = UDim2.new(1, 0, 1, -(T.metrics.topbarHeight + T.metrics.statusHeight)),
	})

	local sidebar = Create.frame({
		Parent = body,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0,
		Size = UDim2.new(0, T.metrics.sidebarWidth, 1, 0),
	})
	Create.padding(sidebar, 8, 8, 8, 8)
	Create.list(sidebar, "v", 2)
	self.sidebar = sidebar

	Create.frame({
		Parent = body,
		BackgroundColor3 = C.strokeSoft,
		BackgroundTransparency = 0,
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.new(0, T.metrics.sidebarWidth, 0, 0),
	})

	local content = Create.frame({
		Parent = body,
		Position = UDim2.new(0, T.metrics.sidebarWidth + 1, 0, 0),
		Size = UDim2.new(1, -(T.metrics.sidebarWidth + 1), 1, 0),
		ClipsDescendants = true,
	})
	self.content = content

	--── statusbar ────────────────────────────────────────────────────────
	local status = Create.frame({
		Parent = root,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0,
		Position = UDim2.new(0, 0, 1, -T.metrics.statusHeight),
		Size = UDim2.new(1, 0, 0, T.metrics.statusHeight),
	})
	Create.padding(status, 0, 10, 0, 10)
	Create.frame({
		Parent = status,
		BackgroundColor3 = C.strokeSoft,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 20, 0, 1),
		Position = UDim2.new(0, -10, 0, 0),
	})

	local statusLeft = Create.frame({ Parent = status, Size = UDim2.new(0.6, 0, 1, 0) })
	Create.list(statusLeft, "h", 10)
	local statusRight = Create.frame({
		Parent = status,
		Size = UDim2.new(0.4, 0, 1, 0),
		Position = UDim2.new(0.6, 0, 0, 0),
	})
	Create.list(statusRight, "h", 10, Enum.HorizontalAlignment.Right)

	self.statusLeft = statusLeft
	self.statusRight = statusRight

	self.statusText = Create.text({
		Parent = statusLeft,
		Text = "pronto",
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 100,
	})

	Create.text({
		Parent = statusRight,
		Text = ("%s · %s"):format(Env.ExecutorName, Config.get("toggleKey")),
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 100,
	})

	--── grip de resize ───────────────────────────────────────────────────
	local grip = Create.frame({
		Parent = root,
		Position = UDim2.new(1, -14, 1, -14),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		ZIndex = 20,
	})
	for i = 1, 3 do
		Create.frame({
			Parent = grip,
			BackgroundColor3 = C.strokeStrong,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(2, 2),
			Position = UDim2.fromOffset(10 - (i - 1) * 4, 10),
		})
	end
	Create.resizable(grip, root, T.metrics.minWindow, function(size)
		Config.set("windowSize", { math.floor(size.X), math.floor(size.Y) }, true)
	end)

	--── toasts ───────────────────────────────────────────────────────────
	toastStack = Create.frame({
		Parent = screen,
		Position = UDim2.new(1, -280, 1, -20),
		Size = UDim2.fromOffset(264, 0),
		AnchorPoint = Vector2.new(0, 1),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 400,
	})
	local toastLayout = Create.list(toastStack, "v", 6)
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	ensureTooltip(screen)

	--── atalho de teclado ────────────────────────────────────────────────
	self.maid:Add(UIS.InputBegan:Connect(function(input, processed)
		if processed then return end
		local keyName = Config.get("toggleKey")
		if input.KeyCode == Enum.KeyCode[keyName] then
			self:Toggle()
		end
	end))

	Library.ActiveWindow = self
	return self
end

--══════════════════════════════════════════════════════════════════════════
function Window:AddTab(opts)
	local id = opts.id
	local order = #self.tabOrder + 1

	local btn = Create.button({
		Parent = self.sidebar,
		Text = "",
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	})
	Create.corner(btn, T.radius.sm)
	Create.padding(btn, 0, 8, 0, 8)

	local icon = Create.text({
		Parent = btn,
		Text = opts.icon or "◦",
		TextColor3 = C.textFaint,
		TextSize = T.font.body,
		Size = UDim2.fromOffset(16, 28),
	})

	local label = Create.text({
		Parent = btn,
		Text = opts.label,
		Font = T.faces.medium,
		TextSize = T.font.small,
		TextColor3 = C.textDim,
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -50, 1, 0),
	})

	local badge = Create.text({
		Parent = btn,
		Text = "",
		Font = T.faces.mono,
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Size = UDim2.new(1, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local page = Create.frame({
		Parent = self.content,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		BackgroundTransparency = 1,
	})

	local tab = {
		id = id, button = btn, page = page, icon = icon,
		label = label, badge = badge, order = order,
	}

	function tab:SetBadge(text, color)
		badge.Text = text and tostring(text) or ""
		badge.TextColor3 = color or C.textFaint
	end

	btn.MouseButton1Click:Connect(function() self:SelectTab(id) end)
	btn.MouseEnter:Connect(function()
		if self.activeTab ~= id then
			btn.BackgroundTransparency = 0
			btn.BackgroundColor3 = C.hover
		end
	end)
	btn.MouseLeave:Connect(function()
		if self.activeTab ~= id then btn.BackgroundTransparency = 1 end
	end)

	if opts.tooltip then Library.attachTooltip(btn, opts.tooltip) end

	self.tabs[id] = tab
	table.insert(self.tabOrder, id)

	if not self.activeTab then self:SelectTab(id) end
	return tab
end

function Window:SectionLabel(text)
	local lbl = Create.text({
		Parent = self.sidebar,
		Text = string.upper(text),
		Font = T.faces.bold,
		TextSize = T.font.micro,
		TextColor3 = C.textFaint,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = #self.tabOrder + 100,
	})
	Create.padding(lbl, 8, 0, 0, 8)
	return lbl
end

function Window:SelectTab(id)
	local tab = self.tabs[id]
	if not tab then return end

	for tabId, t in pairs(self.tabs) do
		local active = tabId == id
		t.page.Visible = active
		Create.tween(t.button, {
			BackgroundColor3 = active and C.selected or C.panel,
			BackgroundTransparency = active and 0 or 1,
		}, T.motion.fast)
		Create.tween(t.label, { TextColor3 = active and C.text or C.textDim }, T.motion.fast)
		Create.tween(t.icon, { TextColor3 = active and C.accent or C.textFaint }, T.motion.fast)
	end

	self.activeTab = id
	Config.set("activeTab", id, true)
	if tab.onShow then task.spawn(tab.onShow) end
end

function Window:SetStatus(text, color)
	self.statusText.Text = text or ""
	self.statusText.TextColor3 = color or C.textFaint
end

function Window:AddStatusItem(builder)
	return builder(self.statusLeft)
end

function Window:Toggle()
	self.visible = not self.visible
	if self.visible then
		self.root.Visible = true
		self.root.BackgroundTransparency = 1
		Create.tween(self.root, { BackgroundTransparency = 0 }, T.motion.base)
	else
		Library.closeMenu()
		self.root.Visible = false
	end
end

function Window:Minimize()
	self.minimized = not self.minimized
	local fullSize = Config.get("windowSize")
	if self.minimized then
		self.root.ClipsDescendants = true
		Create.tween(self.root, { Size = UDim2.fromOffset(320, T.metrics.topbarHeight) }, T.motion.base)
	else
		Create.tween(self.root, { Size = UDim2.fromOffset(fullSize[1], fullSize[2]) }, T.motion.base)
	end
end

function Window:Focus()
	self.visible = true
	self.root.Visible = true
	self.screen.DisplayOrder = 10000
end

function Window:Close()
	Library.notify("Desligando UNICLUDE…", "warn", 1.2)
	task.wait(0.2)
	UNI:Destroy()
end

function Window:Destroy()
	self.maid:Clean()
	if Library.ActiveWindow == self then Library.ActiveWindow = nil end
end

--══════════════════════════════════════════════════════════════════════════
--- Cabecalho de pagina: titulo + descricao curta, sem card em volta
function Library.pageHeader(parent, title, description)
	local header = Create.frame({
		Parent = parent,
		Size = UDim2.new(1, 0, 0, description and 44 or 30),
		LayoutOrder = 0,
	})
	Create.padding(header, 10, 12, 0, 12)

	Create.text({
		Parent = header,
		Text = title,
		Font = T.faces.bold,
		TextSize = T.font.heading,
		TextColor3 = C.text,
		Size = UDim2.new(1, 0, 0, 16),
	})

	if description then
		Create.text({
			Parent = header,
			Text = description,
			TextSize = T.font.small,
			TextColor3 = C.textFaint,
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 14),
		})
	end

	return header
end

Library.Window = Window
Library.notifyFn = Library.notify
return Library
