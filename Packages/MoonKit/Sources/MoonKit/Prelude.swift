/// Set up in every module's state before it is sealed, so a module can call
/// these but not change them. Each `ui` function tags a table with its
/// element type and the line that built it; the host checks the rest.
let prelude = #"""
local caller_line = __caller_line
local component_chunks = __components

local function element(kind: string, primary: string?)
	return function(props: any)
		if props == nil then
			props = {}
		elseif type(props) == "string" and primary then
			props = { [primary] = props }
		elseif type(props) ~= "table" then
			error(`ui.{kind} takes a table`, 2)
		end
		-- `ui.text { "hi", tone = "muted" }` reads as `text = "hi"`.
		-- Only plain values: `ui.link { ui.row { ... } }` keeps its row a child.
		local first = props[1]
		if primary and (type(first) == "string" or type(first) == "number") and props[primary] == nil then
			props[primary] = props[1]
			table.remove(props, 1)
		end
		props.type = kind
		props.__line = caller_line()
		return props
	end
end

local ui = {}
-- Each element, and the prop its first list item stands for, if any:
-- `ui.text { "hi" }` is `ui.text { text = "hi" }`.
for kind, primary in {
	row = false, column = false, panel = false, spacer = false, divider = false,
	scroll = false, grid = false, stack = false, tabs = false, split = false,
	list = false, form = false, image = false, progress = false, fits = false, edit = false,
	text = "text", badge = "text", label = "text", labeled = "text", share = "label", link = "text", tab = "text", unavailable = "text",
	section = "title",
	button = "label", toggle = "label", slider = "label", stepper = "label", picker = "label",
	menu = "label", disclosure = "label",
	input = "placeholder", secure = "placeholder", editor = "placeholder",
	icon = "name", native = "name", region = "name", mount = "mod",
} do
	ui[kind] = element(kind, if primary then primary else nil)
end

local function mod(definition: any)
	if type(definition) ~= "table" then
		error("mod takes a table", 2)
	end
	if type(definition.view) ~= "function" then
		error("a mod needs a view function", 2)
	end
	return definition
end

local function style(sheet: any)
	if type(sheet) ~= "table" then
		error("style takes a table", 2)
	end
	return sheet
end

local used = {}
local function use(name: string)
	if used[name] == nil then
		local chunk = component_chunks[name]
		if chunk == nil then
			error(`no component named {name}`, 2)
		end
		used[name] = chunk()
	end
	return used[name]
end

return ui, mod, style, use
"""#
