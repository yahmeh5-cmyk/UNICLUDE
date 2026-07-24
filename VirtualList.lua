--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/ui/VirtualList.lua
	Lista virtualizada com reuso de linhas.

	Um remote spy de jogo pesado gera milhares de entradas por minuto. Criar
	uma Frame por entrada mata o FPS. Aqui so existem (altura visivel / altura
	da linha) + 4 frames, recicladas conforme o scroll.

	Uso:
		local list = VirtualList.new({
			Parent = holder,
			RowHeight = 26,
			CreateRow = function() return frame, api end,
			BindRow   = function(api, item, index, selected) ... end,
			OnActivate= function(item, index, rowFrame) ... end,
		})
		list:SetItems(arrayDeItens)
═══════════════════════════════════════════════════════════════════════════]]

local UNI    = ...
local Env    = UNI.require("src/core/Env")
local Theme  = UNI.require("src/ui/Theme")
local Create = UNI.require("src/ui/Create")
local Signal = UNI.require("src/core/Signal")

local RunService = Env.Services.RunService

local VirtualList = {}
VirtualList.__index = VirtualList

local OVERSCAN = 3

function VirtualList.new(opts)
	local self = setmetatable({}, VirtualList)

	self.rowHeight  = opts.RowHeight or Theme.metrics.rowHeight
	self.createRow  = assert(opts.CreateRow, "VirtualList precisa de CreateRow")
	self.bindRow    = assert(opts.BindRow, "VirtualList precisa de BindRow")
	self.onActivate = opts.OnActivate
	self.onContext  = opts.OnContext
	self.gap        = opts.Gap or 2
	self.items      = {}
	self.pool       = {}
	self.active     = {}      -- index do item -> row
	self.selected   = nil
	self.stickBottom= opts.StickToBottom == true
	self.maid       = Signal.newMaid()

	self.Selected   = Signal.new("VirtualList.Selected")

	self.scroll = Create.scroll({
		Parent = opts.Parent,
		Size = opts.Size or UDim2.fromScale(1, 1),
		Position = opts.Position or UDim2.new(),
		ScrollBarThickness = Theme.metrics.scrollbar,
		ScrollBarImageColor3 = Theme.c.strokeStrong,
	})

	self.canvas = Create.frame({
		Parent = self.scroll,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
	})

	-- estado vazio
	self.empty = Create.frame({
		Parent = opts.Parent,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local emptyStack = Create.frame({ Parent = self.empty, Size = UDim2.fromScale(1, 1) })
	Create.list(emptyStack, "v", 4, Enum.HorizontalAlignment.Center)
	emptyStack:FindFirstChildOfClass("UIListLayout").VerticalAlignment = Enum.VerticalAlignment.Center

	self.emptyTitle = Create.text({
		Parent = emptyStack,
		Text = opts.EmptyTitle or "Nada aqui ainda",
		Font = Theme.faces.medium,
		TextSize = Theme.font.heading,
		TextColor3 = Theme.c.textDim,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	self.emptyHint = Create.text({
		Parent = emptyStack,
		Text = opts.EmptyHint or "",
		TextSize = Theme.font.small,
		TextColor3 = Theme.c.textFaint,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
	})

	self.maid:Add(self.scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_render()
	end))
	self.maid:Add(self.scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_render()
	end))

	return self
end

--══════════════════════════════════════════════════════════════════════════
-- POOL
--══════════════════════════════════════════════════════════════════════════
function VirtualList:_acquire()
	local row = table.remove(self.pool)
	if row then
		row.frame.Visible = true
		return row
	end

	local frame, api = self.createRow()
	frame.Parent = self.canvas
	frame.Size = UDim2.new(1, -2, 0, self.rowHeight)

	local row = { frame = frame, api = api, index = nil }

	if frame:IsA("TextButton") or frame:IsA("ImageButton") then
		frame.MouseButton1Click:Connect(function()
			if row.index then
				self:Select(row.index)
				if self.onActivate then
					self.onActivate(self.items[row.index], row.index, frame, api)
				end
			end
		end)
		frame.MouseButton2Click:Connect(function()
			if row.index and self.onContext then
				self.onContext(self.items[row.index], row.index, frame, api)
			end
		end)
	end

	return row
end

function VirtualList:_release(row)
	row.frame.Visible = false
	row.index = nil
	table.insert(self.pool, row)
end

--══════════════════════════════════════════════════════════════════════════
-- RENDER
--══════════════════════════════════════════════════════════════════════════
function VirtualList:_render()
	local total = #self.items
	local step = self.rowHeight + self.gap

	self.empty.Visible = total == 0
	self.scroll.Visible = total > 0
	if total == 0 then
		for idx, row in pairs(self.active) do
			self:_release(row)
			self.active[idx] = nil
		end
		self.canvas.Size = UDim2.new(1, 0, 0, 0)
		self.scroll.CanvasSize = UDim2.new()
		return
	end

	local contentHeight = total * step
	self.canvas.Size = UDim2.new(1, 0, 0, contentHeight)
	self.scroll.CanvasSize = UDim2.new(0, 0, 0, contentHeight)

	local viewTop = self.scroll.CanvasPosition.Y
	local viewHeight = self.scroll.AbsoluteSize.Y
	if viewHeight <= 0 then return end

	local first = math.max(1, math.floor(viewTop / step) - OVERSCAN)
	local last  = math.min(total, math.ceil((viewTop + viewHeight) / step) + OVERSCAN)

	-- solta linhas fora da janela
	for idx, row in pairs(self.active) do
		if idx < first or idx > last then
			self:_release(row)
			self.active[idx] = nil
		end
	end

	-- ocupa linhas da janela
	for idx = first, last do
		local row = self.active[idx]
		if not row then
			row = self:_acquire()
			self.active[idx] = row
		end
		row.index = idx
		row.frame.Position = UDim2.fromOffset(1, (idx - 1) * step)
		local item = self.items[idx]
		local ok, err = pcall(self.bindRow, row.api, item, idx, self.selected == idx, row.frame)
		if not ok then
			warn("[UNICLUDE/VirtualList] erro ao renderizar linha: " .. tostring(err))
		end
	end
end

--══════════════════════════════════════════════════════════════════════════
-- API
--══════════════════════════════════════════════════════════════════════════
function VirtualList:SetItems(items, keepScroll)
	local wasAtBottom = self:IsAtBottom()
	self.items = items or {}
	self:_render()
	if self.stickBottom and wasAtBottom and not keepScroll then
		self:ScrollToBottom()
	end
end

function VirtualList:GetItems() return self.items end
function VirtualList:Count() return #self.items end

function VirtualList:Refresh()
	self:_render()
end

function VirtualList:Select(index)
	if self.selected == index then return end
	self.selected = index
	self:_render()
	self.Selected:Fire(self.items[index], index)
end

function VirtualList:ClearSelection()
	self.selected = nil
	self:_render()
end

function VirtualList:GetSelected()
	if not self.selected then return nil end
	return self.items[self.selected], self.selected
end

function VirtualList:IsAtBottom(tolerance)
	local step = self.rowHeight + self.gap
	local maxScroll = math.max(0, #self.items * step - self.scroll.AbsoluteSize.Y)
	return self.scroll.CanvasPosition.Y >= maxScroll - (tolerance or 24)
end

function VirtualList:ScrollToBottom()
	local step = self.rowHeight + self.gap
	self.scroll.CanvasPosition = Vector2.new(0, math.max(0, #self.items * step))
end

function VirtualList:ScrollToIndex(index)
	local step = self.rowHeight + self.gap
	self.scroll.CanvasPosition = Vector2.new(0, math.max(0, (index - 1) * step - self.scroll.AbsoluteSize.Y / 2))
end

function VirtualList:SetEmptyState(title, hint)
	self.emptyTitle.Text = title or self.emptyTitle.Text
	self.emptyHint.Text = hint or ""
end

function VirtualList:Destroy()
	self.maid:Clean()
	for _, row in pairs(self.active) do row.frame:Destroy() end
	for _, row in ipairs(self.pool) do row.frame:Destroy() end
	table.clear(self.active)
	table.clear(self.pool)
	self.scroll:Destroy()
	self.empty:Destroy()
end

return VirtualList
