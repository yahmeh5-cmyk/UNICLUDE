--!nocheck
--[[═══════════════════════════════════════════════════════════════════════════
	src/ui/Highlighter.lua
	Tokenizador Luau -> RichText colorido.

	Usado no visualizador de codigo (script gerado do remote, fonte
	decompilada, dump de tabela, console). Lida com: comentarios de linha e
	de bloco com nivel [==[, strings simples/duplas/longas, escapes,
	numeros hex/binarios/cientificos com separador _, palavras-chave,
	globais conhecidas, chamadas de metodo e operadores.
═══════════════════════════════════════════════════════════════════════════]]

local UNI   = ...
local Theme = UNI.require("src/ui/Theme")
local Util  = UNI.require("src/core/Util")

local Highlighter = {}

--══════════════════════════════════════════════════════════════════════════
-- DICIONARIOS
--══════════════════════════════════════════════════════════════════════════
local KEYWORDS = {
	["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,["end"]=1,
	["for"]=1,["function"]=1,["if"]=1,["in"]=1,["local"]=1,["not"]=1,
	["or"]=1,["repeat"]=1,["return"]=1,["then"]=1,["until"]=1,["while"]=1,
	["continue"]=1,["export"]=1,["type"]=1,
}

local LITERALS = { ["true"]=1, ["false"]=1, ["nil"]=1 }

local GLOBALS = {
	["game"]=1,["workspace"]=1,["script"]=1,["shared"]=1,["_G"]=1,["plugin"]=1,
	["Enum"]=1,["Instance"]=1,["Vector2"]=1,["Vector3"]=1,["CFrame"]=1,
	["Color3"]=1,["UDim"]=1,["UDim2"]=1,["BrickColor"]=1,["Ray"]=1,["Rect"]=1,
	["Region3"]=1,["NumberRange"]=1,["NumberSequence"]=1,["ColorSequence"]=1,
	["NumberSequenceKeypoint"]=1,["ColorSequenceKeypoint"]=1,["TweenInfo"]=1,
	["PhysicalProperties"]=1,["Faces"]=1,["Axes"]=1,["DateTime"]=1,["Font"]=1,
	["Random"]=1,["RaycastParams"]=1,["OverlapParams"]=1,["buffer"]=1,
}

local BUILTINS = {
	["print"]=1,["warn"]=1,["error"]=1,["assert"]=1,["pcall"]=1,["xpcall"]=1,
	["select"]=1,["type"]=1,["typeof"]=1,["tostring"]=1,["tonumber"]=1,
	["pairs"]=1,["ipairs"]=1,["next"]=1,["unpack"]=1,["rawget"]=1,["rawset"]=1,
	["rawequal"]=1,["rawlen"]=1,["setmetatable"]=1,["getmetatable"]=1,
	["require"]=1,["loadstring"]=1,["newproxy"]=1,["collectgarbage"]=1,
	["task"]=1,["math"]=1,["string"]=1,["table"]=1,["os"]=1,["coroutine"]=1,
	["debug"]=1,["bit32"]=1,["utf8"]=1,
	-- ambiente de executor
	["getgenv"]=1,["getrenv"]=1,["getgc"]=1,["getreg"]=1,["hookfunction"]=1,
	["hookmetamethod"]=1,["getrawmetatable"]=1,["setreadonly"]=1,
	["newcclosure"]=1,["checkcaller"]=1,["getcallingscript"]=1,
	["getnamecallmethod"]=1,["getloadedmodules"]=1,["getconnections"]=1,
	["setclipboard"]=1,["writefile"]=1,["readfile"]=1,["isfile"]=1,
	["makefolder"]=1,["listfiles"]=1,["request"]=1,["decompile"]=1,
	["cloneref"]=1,["gethui"]=1,["fireclickdetector"]=1,["firetouchinterest"]=1,
}

--══════════════════════════════════════════════════════════════════════════
-- CORES (resolvidas na hora, respeita troca de paleta)
--══════════════════════════════════════════════════════════════════════════
local function hex(color)
	return ("#%02X%02X%02X"):format(
		math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

local function span(text, color)
	return ('<font color="%s">%s</font>'):format(hex(color), text)
end

--══════════════════════════════════════════════════════════════════════════
-- TOKENIZADOR
--══════════════════════════════════════════════════════════════════════════

-- encontra fechamento de bracket longo [==[ ... ]==]
local function longBracket(src, i)
	local level = src:match("^%[(=*)%[", i)
	if not level then return nil end
	local open = #level + 2
	local close = "]" .. level .. "]"
	local endPos = src:find(close, i + open, true)
	if endPos then
		return i, endPos + #close - 1
	end
	return i, #src
end

--- Retorna lista de tokens { kind, text }
function Highlighter.tokenize(src)
	local tokens = {}
	local i, n = 1, #src

	local function push(kind, text)
		if text ~= "" then tokens[#tokens + 1] = { kind = kind, text = text } end
	end

	while i <= n do
		local c = src:sub(i, i)

		-- espaco em branco
		local ws = src:match("^%s+", i)
		if ws then
			push("space", ws)
			i += #ws
			continue
		end

		-- comentario
		if src:sub(i, i + 1) == "--" then
			local bs, be = longBracket(src, i + 2)
			if bs then
				push("comment", src:sub(i, be))
				i = be + 1
			else
				local line = src:match("^[^\n]*", i)
				push("comment", line)
				i += #line
			end
			continue
		end

		-- string longa
		if c == "[" then
			local bs, be = longBracket(src, i)
			if bs then
				push("string", src:sub(bs, be))
				i = be + 1
				continue
			end
		end

		-- string simples/dupla
		if c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local ch = src:sub(j, j)
				if ch == "\\" then
					j += 2
				elseif ch == c then
					j += 1
					break
				elseif ch == "\n" then
					break
				else
					j += 1
				end
			end
			push("string", src:sub(i, j - 1))
			i = j
			continue
		end

		-- numero
		if c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
			local numText = src:match("^0[xX][%x_]+", i)
				or src:match("^0[bB][01_]+", i)
				or src:match("^[%d_]*%.?[%d_]+[eE][%+%-]?%d+", i)
				or src:match("^[%d_]*%.?[%d_]+", i)
			push("number", numText)
			i += #numText
			continue
		end

		-- identificador
		if c:match("[%a_]") then
			local word = src:match("^[%w_]+", i)
			local prev
			for k = #tokens, 1, -1 do
				if tokens[k].kind ~= "space" then prev = tokens[k] break end
			end
			local kind
			if KEYWORDS[word] then
				kind = "keyword"
			elseif LITERALS[word] then
				kind = "literal"
			elseif prev and (prev.text == ":" or prev.text == ".") then
				kind = "field"
			elseif GLOBALS[word] then
				kind = "global"
			elseif BUILTINS[word] then
				kind = "builtin"
			else
				kind = "ident"
			end
			push(kind, word)
			i += #word
			continue
		end

		-- operadores multi-caractere
		local op3 = src:sub(i, i + 2)
		local op2 = src:sub(i, i + 1)
		if op3 == "..." then
			push("operator", op3); i += 3; continue
		end
		if op2 == "==" or op2 == "~=" or op2 == "<=" or op2 == ">="
			or op2 == ".." or op2 == "::" or op2 == "+=" or op2 == "-="
			or op2 == "*=" or op2 == "/=" or op2 == "^=" or op2 == "%=" then
			push("operator", op2); i += 2; continue
		end

		if c:match("[%(%)%[%]{}]") then
			push("bracket", c); i += 1; continue
		end

		push("operator", c)
		i += 1
	end

	return tokens
end

--══════════════════════════════════════════════════════════════════════════
-- RENDER
--══════════════════════════════════════════════════════════════════════════
local function colorFor(kind)
	local s = Theme.s.syntax
	local c = Theme.c
	if kind == "keyword"  then return s.keyword end
	if kind == "literal"  then return c.magenta end
	if kind == "string"   then return s.string end
	if kind == "number"   then return s.number end
	if kind == "comment"  then return s.comment end
	if kind == "global"   then return s.global end
	if kind == "builtin"  then return s.builtin end
	if kind == "field"    then return c.text end
	if kind == "operator" then return s.operator end
	if kind == "bracket"  then return s.bracket end
	return s.ident
end

--- Converte fonte Luau em RichText pronto pra TextLabel
function Highlighter.render(src, maxChars)
	src = tostring(src or "")
	if maxChars and #src > maxChars then
		src = src:sub(1, maxChars) .. "\n-- [truncado pelo visualizador]"
	end

	local tokens = Highlighter.tokenize(src)
	local out = table.create(#tokens)

	for idx, tok in ipairs(tokens) do
		local text = Util.escapeRich(tok.text)
		if tok.kind == "space" then
			out[idx] = text
		else
			out[idx] = span(text, colorFor(tok.kind))
		end
	end

	return table.concat(out)
end

--- Versao com numeros de linha alinhados (retorna richtext do codigo + gutter)
function Highlighter.renderWithGutter(src, maxChars)
	local body = Highlighter.render(src, maxChars)
	local count = 1
	for _ in tostring(src):gmatch("\n") do count += 1 end
	local gutter = {}
	for i = 1, count do gutter[i] = tostring(i) end
	return body, table.concat(gutter, "\n"), count
end

--- Realce simples de ocorrencias de busca (sobre texto ja escapado)
function Highlighter.markMatches(escapedText, query, color)
	if not query or query == "" then return escapedText end
	local esc = Util.escapeRich(query)
	local pattern = esc:gsub("(%W)", "%%%1")
	local result = escapedText:gsub(pattern, function(m)
		return ('<font color="%s"><b>%s</b></font>'):format(hex(color or Theme.c.accent), m)
	end)
	return result
end

Highlighter.hex = hex
Highlighter.span = span

return Highlighter
