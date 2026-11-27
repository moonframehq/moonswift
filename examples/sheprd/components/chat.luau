-- Sheprd's chat: the conversation as a document, newest at the bottom.
-- Each turn opens with its prompt as a heading; the agent's answer is
-- markdown. The last prompt stays pinned on top, and the composer floats
-- over the bottom.
local chat = {}

local function prompt(text: string)
	return ui.row {
		gap = 10,
		align = "start",
		fixed = "y",
		ui.column { width = 3, grow = "y", style = { background = "tint" } },
		ui.text { text, selectable = true, style = { font = "title3", weight = "semibold" } },
	}
end

local function circle(icon: string, msg)
	return ui.button { icon = icon, variant = "glass", size = "large", msg = msg }
end

function chat.screen(state, key, conversation, entries)
	local last = nil
	local view = {
		axis = "y",
		gap = 20,
		anchor = "bottom",
		lazy = false,
		style = { padding = { top = 76, x = 16, bottom = 16 } },
		titleMode = "inline",
		hidesTabBar = true,
		toolbar = {
			ui.button { icon = "square.stack.3d.up", place = "leading", msg = "toWorkspace" },
			ui.row {
				place = "principal",
				gap = 6,
				msg = "sessionSheet",
				ui.text { conversation.title, lines = 1, style = { font = "headline" } },
				ui.icon { "chevron.down.circle.fill", style = { font = "subheadline", color = "secondary" } },
			},
		},
		inset = {
			edge = "bottom",
			ui.row {
				gap = 10,
				align = "end",
				style = { padding = { 8, 16 } },
				circle("plus", "attach"),
				ui.input {
					"Message Claude Code",
					id = "composer",
					value = state.draft,
					change = "draft",
					submit = "send",
					multiline = true,
					variant = "plain",
					grow = "x",
					style = { padding = { 12, 16 }, glass = true, radius = 22 },
				},
				circle("mic.fill", "dictate"),
			},
		},
		sheet = {
			open = state.sessionSheet,
			dismiss = "closeSession",
			detents = { "medium", "large" },
			grabber = true,
			ui.form {
				ui.section {
					"Session",
					ui.labeled { "Agent", value = "Claude Code" },
					ui.labeled { "Computer", value = conversation.computer },
					ui.labeled { "Workspace", value = conversation.workspace },
				},
				ui.section {
					ui.button { "Close this chat", role = "destructive", variant = "borderless", msg = { asking = key } },
				},
			},
		},
	}
	for _, entry in entries do
		if entry.kind == "user" then
			last = entry.text
			table.insert(view, prompt(entry.text))
		else
			table.insert(view, ui.markdown { entry.text, key = "e" .. entry.id })
		end
	end
	if #entries == 0 then
		table.insert(view, ui.unavailable { "No messages yet", icon = "bubble.left", description = "Send the first prompt below." })
	end
	if last then
		view.overlay = {
			place = "top",
			ui.row {
				gap = 10,
				align = "start",
				fixed = "y",
				style = { padding = { 10, 14 }, glass = true, radius = 16, margin = { top = 8, x = 16 } },
				ui.column { width = 3, grow = "y", style = { background = "tint" } },
				ui.text { last, lines = 3, grow = "x", style = { font = "subheadline", weight = "semibold" } },
			},
		}
	end
	return ui.scroll(view)
end

return chat
