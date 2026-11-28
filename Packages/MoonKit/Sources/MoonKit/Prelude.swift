/// Set up in every module's state before it is sealed, so a module can call
/// these but not change them. Each `ui` function tags a table with its
/// element type and the line that built it; the host checks the rest.
/// Moonframe's prelude is the reference: the same names, the same primary
/// props, `send`, `component` and `ui.memo`.
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
	-- Moonframe's.
	row = false, column = false, panel = false, hsplit = false, vsplit = false, pane = false,
	divider = false, spacer = false, popover = false, overlay = false, input = false, line = false,
	paths = false, hatch = false, map = false, list = false, revision_timeline = false,
	text = "text", badge = "text", markdown = "text", icon = "name", image = "src",
	terminal = "id", browser = "url", video = "source", view = "name",
	button = "label", item = "label", region = "name", mount = "mod",
	-- MoonSwift's own: a portable mod uses them behind `app.renderer == "swiftui"`.
	scroll = false, grid = false, stack = false, tabs = false, split = false, form = false,
	progress = false, fits = false, edit = false,
	label = "text", labeled = "text", share = "label", link = "text", tab = "text", unavailable = "text",
	section = "title", toggle = "label", slider = "label", stepper = "label", picker = "label",
	menu = "label", disclosure = "label", secure = "placeholder", editor = "placeholder", native = "name",
} do
	ui[kind] = element(kind, if primary then primary else nil)
end

-- `ui.memo(key, deps, build)`: what `build()` returned the last time this
-- view asked for `key` with equal `deps`, or `build()` now.
local memos = {}
local memo_count = 0

function ui.memo(key: string, deps: { any }, build: () -> any)
	if type(key) ~= "string" or type(deps) ~= "table" or type(build) ~= "function" then
		error("ui.memo takes a key (a string), its dependencies (a list), and a function", 2)
	end
	local kept = memos[key]
	if kept and #kept.deps == #deps then
		local same = true
		for index = 1, #deps do
			if kept.deps[index] ~= deps[index] then
				same = false
				break
			end
		end
		if same then
			return kept.tree
		end
	end
	local tree = build()
	if not kept then
		if memo_count >= 512 then
			memos = {}
			memo_count = 0
		end
		memo_count += 1
	end
	memos[key] = { deps = table.clone(deps), tree = tree }
	return tree
end

local function mod(definition: any)
	if type(definition) ~= "table" then
		error("mod takes a table", 2)
	end
	if type(definition.view) ~= "function" then
		error("mod needs a `view` function", 2)
	end
	return definition
end

local function style(sheet: any)
	if type(sheet) ~= "table" then
		error("style takes a table", 2)
	end
	return sheet
end

local function component(definition: any)
	if type(definition) ~= "table" then
		error("component takes a table", 2)
	end
	if type(definition.build) ~= "function" then
		error("component needs a `build` function", 2)
	end
	return definition
end

-- `send "provider:clock" { zone = "UTC" }` is `{ to = "provider:clock", msg = { zone = "UTC" } }`.
local function send(to: string)
	if type(to) ~= "string" then
		error("send takes where to send, a string", 2)
	end
	return function(msg: any)
		return { to = to, msg = msg }
	end
end

-- A component's `build`; a file that returns anything else is used as it is.
-- One that is missing, or keeps state of its own (Moonframe's instances,
-- not here yet), draws as a placeholder the host warns about, so a desktop
-- mod still loads on a phone.
local missing = element("missing", "name")
local instance = element("instance", "component")
local used = {}
local function use(name: string)
	if used[name] == nil then
		local chunk = component_chunks[name]
		local value
		if chunk == nil then
			value = function()
				return missing(name)
			end
		else
			value = chunk()
		end
		if type(value) == "table" and type(value.build) == "function" then
			if value.update == nil then
				value = value.build
			else
				value = function(props: any)
					return instance { name, id = type(props) == "table" and props.id or "main" }
				end
			end
		end
		used[name] = value
	end
	return used[name]
end

-- `app` as a view sees it: the host's fields, and each provider's data
-- looked up as it is read, noting the names read so only the views that
-- read a provider run again when it publishes.
local function lens(fields: any, data: any, reads: any)
	return setmetatable(fields, {
		__index = function(_, key)
			reads[key] = true
			return data[key]
		end,
	})
end

return ui, mod, style, use, send, component, lens
"""#
