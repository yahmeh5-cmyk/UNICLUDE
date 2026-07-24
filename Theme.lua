--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/ui/Theme.lua
	Tokens de design do UNICLUDE.

	Direcao visual: grafite quente levemente esverdeado (nao o azul-neon padrao
	de todo script de Roblox) com um unico acento citron que carrega hierarquia.
	Sem gradiente decorativo, sem vidro fosco, sem sombra roxa.
	Densidade alta: essa e uma ferramenta de inspecao, nao uma landing page.
═══════════════════════════════════════════════════════════════════════════]]

local UNI = ...

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local Theme = {}

--══════════════════════════════════════════════════════════════════════════
-- PALETAS
--══════════════════════════════════════════════════════════════════════════
local palettes = {}

-- padrao: grafite quente + citron
palettes.citron = {
	name = "Citron",

	root        = rgb(17, 18, 16),
	panel       = rgb(23, 25, 22),
	panelAlt    = rgb(28, 30, 26),
	elevated    = rgb(34, 36, 31),
	hover       = rgb(43, 46, 40),
	pressed     = rgb(52, 55, 48),
	selected    = rgb(48, 54, 36),

	stroke      = rgb(45, 48, 42),
	strokeSoft  = rgb(35, 37, 33),
	strokeStrong= rgb(64, 68, 59),

	text        = rgb(233, 236, 226),
	textDim     = rgb(151, 156, 142),
	textFaint   = rgb(104, 109, 98),
	textInvert  = rgb(20, 22, 17),

	accent      = rgb(199, 233, 96),
	accentSoft  = rgb(146, 172, 68),
	accentDeep  = rgb(72, 88, 32),

	danger      = rgb(238, 118, 99),
	dangerDeep  = rgb(84, 40, 34),
	warn        = rgb(240, 190, 94),
	warnDeep    = rgb(84, 66, 30),
	info        = rgb(127, 199, 224),
	infoDeep    = rgb(31, 61, 72),
	success     = rgb(139, 214, 150),
	successDeep = rgb(35, 72, 41),
	magenta     = rgb(214, 141, 214),

	shadow      = rgb(0, 0, 0),
	scrim       = rgb(8, 9, 8),
}

-- alternativa fria, para quem odeia verde
palettes.slate = {
	name = "Slate",

	root        = rgb(16, 17, 20),
	panel       = rgb(22, 24, 28),
	panelAlt    = rgb(27, 29, 34),
	elevated    = rgb(33, 36, 42),
	hover       = rgb(42, 46, 53),
	pressed     = rgb(51, 56, 64),
	selected    = rgb(38, 50, 60),

	stroke      = rgb(44, 48, 55),
	strokeSoft  = rgb(33, 36, 42),
	strokeStrong= rgb(63, 69, 79),

	text        = rgb(228, 232, 238),
	textDim     = rgb(146, 153, 165),
	textFaint   = rgb(100, 106, 118),
	textInvert  = rgb(16, 18, 22),

	accent      = rgb(122, 214, 196),
	accentSoft  = rgb(84, 156, 143),
	accentDeep  = rgb(28, 66, 61),

	danger      = rgb(233, 122, 122),
	dangerDeep  = rgb(78, 38, 38),
	warn        = rgb(232, 186, 116),
	warnDeep    = rgb(78, 62, 32),
	info        = rgb(133, 178, 232),
	infoDeep    = rgb(34, 52, 78),
	success     = rgb(140, 206, 156),
	successDeep = rgb(36, 68, 44),
	magenta     = rgb(198, 148, 220),

	shadow      = rgb(0, 0, 0),
	scrim       = rgb(6, 7, 9),
}

--══════════════════════════════════════════════════════════════════════════
-- ESCALA / RITMO
--══════════════════════════════════════════════════════════════════════════
Theme.space = {
	xs = 4, sm = 6, md = 10, lg = 16, xl = 24, xxl = 36,
}

Theme.radius = {
	none = 0, sm = 4, md = 6, lg = 10, pill = 999,
}

-- escala tipografica com contraste real (ratio ~1.3)
Theme.font = {
	display = 22,
	title   = 16,
	heading = 13,
	body    = 12,
	small   = 11,
	micro   = 10,
}

Theme.faces = {
	regular = Enum.Font.Gotham,
	medium  = Enum.Font.GothamMedium,
	bold    = Enum.Font.GothamBold,
	black   = Enum.Font.GothamBlack,
	mono    = Enum.Font.Code,
}

Theme.metrics = {
	topbarHeight   = 40,
	statusHeight   = 24,
	sidebarWidth   = 168,
	sidebarNarrow  = 48,
	rowHeight      = 26,
	rowHeightTall  = 34,
	toolbarHeight  = 34,
	inputHeight    = 26,
	scrollbar      = 4,
	minWindow      = Vector2.new(720, 420),
}

--══════════════════════════════════════════════════════════════════════════
-- MOVIMENTO (ease-out exponencial, sem bounce)
--══════════════════════════════════════════════════════════════════════════
Theme.motion = {
	instant = TweenInfo.new(0.08, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	fast    = TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	base    = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	slow    = TweenInfo.new(0.36, Enum.EasingStyle.Expo,  Enum.EasingDirection.Out),
}

--══════════════════════════════════════════════════════════════════════════
-- CORES SEMANTICAS POR CONTEXTO
--══════════════════════════════════════════════════════════════════════════
local function buildSemantics(p)
	return {
		-- tipos de remote
		remoteKind = {
			event      = p.accent,
			unreliable = p.warn,
			["function"] = p.info,
			bindable   = p.magenta,
			bindfunc   = p.magenta,
			desconhecido = p.textDim,
		},
		-- niveis de log
		logLevel = {
			Output   = p.textDim,
			Info     = p.info,
			Warning  = p.warn,
			Error    = p.danger,
			Script   = p.accent,
			Uniclude = p.accentSoft,
		},
		-- destaque de sintaxe luau
		syntax = {
			keyword  = p.accent,
			builtin  = p.info,
			string   = p.success,
			number   = p.warn,
			comment  = p.textFaint,
			operator = p.textDim,
			ident    = p.text,
			global   = p.magenta,
			bracket  = p.strokeStrong,
		},
		-- tipos de valor no inspetor
		valueType = {
			string = p.success, number = p.warn, boolean = p.magenta,
			table = p.info, Instance = p.accent, ["nil"] = p.textFaint,
			userdata = p.textDim, ["function"] = p.magenta, buffer = p.warn,
		},
	}
end

--══════════════════════════════════════════════════════════════════════════
-- API
--══════════════════════════════════════════════════════════════════════════
Theme.palettes = palettes
Theme.current = "citron"
Theme.c = palettes.citron
Theme.s = buildSemantics(palettes.citron)

function Theme.use(name)
	local p = palettes[name]
	if not p then return false end
	Theme.current = name
	Theme.c = p
	Theme.s = buildSemantics(p)
	return true
end

--- Cor de um tipo de valor (fallback textDim)
function Theme.typeColor(t)
	return Theme.s.valueType[t] or Theme.c.textDim
end

function Theme.kindColor(kind)
	return Theme.s.remoteKind[kind] or Theme.c.textDim
end

function Theme.levelColor(level)
	return Theme.s.logLevel[level] or Theme.c.textDim
end

--- Mistura duas cores (0 = a, 1 = b)
function Theme.mix(a, b, alpha)
	return a:Lerp(b, math.clamp(alpha, 0, 1))
end

--- Versao mais escura de uma cor, util pra fundo de badge
function Theme.deepen(color, amount)
	return color:Lerp(Theme.c.root, amount or 0.78)
end

return Theme
