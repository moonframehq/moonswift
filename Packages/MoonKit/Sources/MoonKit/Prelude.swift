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
		if primary and props[1] ~= nil and props[primary] == nil then
			props[primary] = props[1]
			table.remove(props, 1)
		end
		props.type = kind
		props.__line = caller_line()
		return props
	end
end

local ui = {}
for _, kind in { "row", "column", "panel", "spacer", "divider", "input", "toggle", "slider" } do
	ui[kind] = element(kind)
end
ui.text = element("text", "text")
ui.badge = element("badge", "text")
ui.icon = element("icon", "name")
ui.button = element("button", "label")
ui.region = element("region", "name")
ui.mount = element("mount", "mod")

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
