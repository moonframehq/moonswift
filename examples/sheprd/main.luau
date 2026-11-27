-- Sheprd's Home, in Luau: every agent across computers, in sections by
-- what it needs, read from the `home` provider. Four tabs, as on iPhone.
local parts = use "parts"
local settings = use "settings"
local workspaces = use "workspaces"
local chat = use "chat"

type State = {
	tab: string,
	path: { any },
	query: string,
	sort: string,
	unreadOnly: boolean,
	folded: { [string]: boolean },
	closing: string?,
	settingsPath: { any },
	appearance: string,
	links: string,
	rowLines: number,
	returnSends: boolean,
	speak: boolean,
	haptics: boolean,
	sounds: boolean,
	keys: { string },
	workspacesPath: { any },
	foldedMachines: { [string]: boolean },
	holdAlerts: { [string]: boolean },
	forgetting: string?,
	draft: string,
	sessionSheet: boolean,
	prQuery: string,
	prSort: string,
}

local order = { "blocked", "done", "working", "idle" }

-- The sections, in order: favorites first, then by status.
local function sections(state: State, chats)
	local found = {}
	local function add(id, title, key)
		if not found[id] then
			found[id] = { id = id, title = title, keys = {} }
		end
		table.insert(found[id].keys, key)
	end
	for _, chat in chats do
		local shown = state.query == "" or string.find(string.lower(chat.title), string.lower(state.query), 1, true)
		if shown and (not state.unreadOnly or chat.unread) then
			if chat.favorite then
				add("favorites", "Favorites", chat.key)
			elseif state.sort == "recent" then
				add("recent", "Recent", chat.key)
			else
				local status = parts.status[chat.status] and chat.status or "idle"
				add(status, parts.status[status].title, chat.key)
			end
		end
	end
	local list = {}
	for _, id in { "favorites", "recent", table.unpack(order) } do
		if found[id] then
			table.insert(list, found[id])
		end
	end
	return list
end

local function byKey(app)
	local chats = {}
	for _, chat in app.home.chats or {} do
		chats[chat.key] = chat
	end
	return chats
end

local function header(state: State, section)
	local open = not state.folded[section.id]
	local mark = parts.status[section.id]
	return ui.row {
		gap = 6,
		msg = { fold = section.id },
		ui.icon { "chevron.right", rotate = open and 90 or 0, style = { font = "caption", weight = "bold", color = "secondary" } },
		if section.id == "favorites"
			then ui.icon { "star.fill", style = { color = "yellow" } }
			elseif mark then ui.icon { mark.header, style = { color = mark.color } }
			else false,
		ui.text { section.title, lines = 1, style = { color = "secondary" } },
		ui.text { tostring(#section.keys), digits = true, style = { color = "tertiary" } },
		ui.spacer {},
	}
end

local function home(state: State, app)
	local chats = app.home.chats or {}
	local unread = 0
	for _, chat in chats do
		if chat.unread then
			unread += 1
		end
	end
	if #chats == 0 then
		return ui.unavailable {
			"No chats",
			icon = "bubble.left.and.text.bubble.right",
			description = "Chats and agents running in Sheprd on your computers appear here.",
		}
	end

	local list = {
		titleMode = "inline",
		refresh = "refresh",
		search = { value = state.query, change = "query", prompt = "Workspaces, chats, terminals", placement = "always" },
		toolbar = {
			ui.menu {
				icon = "arrow.up.arrow.down",
				place = "leading",
				ui.picker {
					"Sort Agents",
					value = state.sort,
					change = "sort",
					options = {
						{ value = "priority", label = "Priority", icon = "exclamationmark.circle" },
						{ value = "recent", label = "Recent", icon = "clock" },
					},
				},
			},
			ui.menu {
				icon = "line.3.horizontal.decrease.circle",
				place = "leading",
				ui.button { "Show All Agents", icon = "xmark.circle", msg = "all" },
			},
			unread > 0 and ui.menu {
				place = "leading",
				face = ui.row {
					gap = 5,
					ui.icon { "circle.fill", style = { size = 10, color = "tint" } },
					ui.text { tostring(unread), digits = true, style = { font = "footnote", weight = "semibold" } },
				},
				ui.toggle { "Unread Only", value = state.unreadOnly, change = "unreadOnly" },
				ui.button { "Mark All Read", icon = "envelope.open", msg = "allRead" },
			} or false,
			ui.button { icon = "rectangle.compress.vertical", place = "trailing", msg = "foldAll" },
			ui.button { icon = "waveform", place = "trailing", msg = "talk" },
			ui.button { icon = "plus", place = "trailing", msg = "new" },
		},
		confirm = state.closing and {
			open = true,
			title = "Close " .. (byKey(app)[state.closing] or { title = "" }).title .. "?",
			message = "Its pane closes in Sheprd and the agent stops.",
			dismiss = "keep",
			ui.button { "Close Chat", role = "destructive", msg = { close = state.closing } },
		} or nil,
	}
	for _, section in sections(state, chats) do
		local folded = state.folded[section.id]
		table.insert(list, ui.section {
			key = section.id,
			header = header(state, section),
			rows = if folded then {} else section.keys,
			row = "chat",
		})
	end
	return ui.stack {
		path = state.path,
		change = "path",
		screen = "screen",
		ui.list(list),
	}
end

-- What a row says under its title.
local function detail(chat): string
	local text = chat.last ~= "" and chat.last or "No messages yet"
	return chat.computer .. " · " .. chat.workspace .. " · " .. text
end

local function chatRow(state: State, chat)
	local unread = chat.unread
	local time: any = false
	if chat.status == "working" and chat.started then
		time = ui.text { date = chat.started, format = "timer", digits = true, style = { font = "footnote", color = "secondary" } }
	end
	return ui.link {
		route = { chat = chat.key },
		overlay = unread and {
			place = "leading",
			x = -15,
			ui.column { width = 10, height = 10, style = { background = "tint", radius = 5 } },
		} or nil,
		swipe = {
			leading = {
				unread and ui.button { "Read", icon = "envelope.open.fill", tint = "gray", msg = { read = chat.key, value = true } }
					or ui.button { "Unread", icon = "envelope.badge.fill", tint = "blue", msg = { read = chat.key, value = false } },
				chat.favorite
						and ui.button { "Unfavorite", icon = "star.slash.fill", tint = "yellow", msg = { favorite = chat.key, value = false } }
					or ui.button { "Favorite", icon = "star.fill", tint = "yellow", msg = { favorite = chat.key, value = true } },
				ui.button { "Summarize", icon = "sparkles", tint = "indigo", msg = { summarize = chat.key } },
			},
			trailing = { ui.button { "Close", icon = "xmark", tint = "red", msg = { asking = chat.key } } },
		},
		context = {
			unread and ui.button { "Mark as Read", icon = "envelope.open", msg = { read = chat.key, value = true } }
				or ui.button { "Mark as Unread", icon = "envelope.badge", msg = { read = chat.key, value = false } },
			chat.favorite and ui.button { "Remove from Favorites", icon = "star.slash", msg = { favorite = chat.key, value = false } }
				or ui.button { "Add to Favorites", icon = "star", msg = { favorite = chat.key, value = true } },
			ui.button { "Close Chat", icon = "xmark.circle", role = "destructive", msg = { asking = chat.key } },
		},
		ui.row {
			gap = 12,
			parts.agent(chat.agent, 28, chat.status),
			ui.column {
				gap = 2,
				grow = "x",
				ui.row {
					gap = 6,
					align = "baseline",
					grow = "x",
					ui.text { chat.title, lines = 1, style = { weight = unread and "semibold" or nil } },
					ui.spacer {},
					time,
				},
				ui.row {
					gap = 6,
					ui.text { detail(chat), lines = 1, style = { font = "subheadline", color = unread and "primary" or "secondary" } },
					ui.spacer {},
					parts.pullRequest(chat),
				},
				parts.pills(chat.labels),
			},
		},
	}
end

-- A question the agent asks: answered in place, without opening the chat.
local function answerCard(chat)
	local buttons = { gap = 8 }
	for _, option in chat.question.options do
		local allow = option.kind == "allow_once"
		table.insert(buttons, ui.button {
			option.name,
			variant = allow and "prominentGlass" or "glass",
			tint = allow and "red" or nil,
			msg = { answer = chat.key, option = option.id },
		})
	end
	return ui.column {
		gap = 10,
		rowInsets = { top = 4, left = 0, bottom = 4, right = 0 },
		rowBackground = "clear",
		separator = false,
		style = { padding = 14, background = "secondaryGrouped", radius = 22, border = "red/35" },
		ui.row {
			gap = 8,
			parts.agent(chat.agent, 24),
			ui.column {
				gap = 0,
				ui.text { chat.title, style = { font = "subheadline", weight = "semibold" } },
				ui.text { chat.computer .. " · " .. chat.workspace, style = { font = "caption", color = "secondary" } },
			},
		},
		parts.pills(chat.labels),
		ui.text { chat.question.title },
		ui.row(buttons),
	}
end

return mod {
	providers = { "home", "system" },

	init = function(previous)
		local state = previous or {}
		return {
			tab = state.tab or "home",
			path = state.path or {},
			query = state.query or "",
			sort = state.sort or "priority",
			unreadOnly = state.unreadOnly or false,
			folded = state.folded or {},
			closing = nil,
			settingsPath = state.settingsPath or {},
			appearance = state.appearance or "System",
			links = state.links or "Sheprd",
			rowLines = state.rowLines or 1,
			returnSends = state.returnSends or false,
			speak = state.speak or false,
			haptics = if state.haptics == nil then true else state.haptics,
			sounds = if state.sounds == nil then true else state.sounds,
			workspacesPath = state.workspacesPath or {},
			foldedMachines = state.foldedMachines or {},
			holdAlerts = state.holdAlerts or {},
			forgetting = nil,
			draft = state.draft or "",
			sessionSheet = false,
			prQuery = state.prQuery or "",
			prSort = state.prSort or "updated",
			keys = state.keys or { "esc", "tab", "ctrl", "↑", "↓", "←", "→", "|", "~", "/" },
		}
	end,

	update = function(state: State, msg)
		if type(msg) ~= "table" then
			if msg == "foldAll" then
				local any = next(state.folded) ~= nil
				state.folded = any and {} or { favorites = true, blocked = true, done = true, working = true, idle = true }
			elseif msg == "keep" then
				state.closing = nil
			elseif msg == "allRead" then
				return state, { { to = "provider:home", msg = { readAll = true } } }
			elseif msg == "foldMachines" then
				local any = next(state.foldedMachines) ~= nil
				state.foldedMachines = any and {} or { Studio = true, ["MacBook Air"] = true }
			elseif msg == "sessionSheet" then
				state.sessionSheet = true
			elseif msg == "closeSession" then
				state.sessionSheet = false
			elseif msg == "send" then
				state.draft = ""
			elseif msg == "openGitHub" then
				-- Another tab, and the page in it: navigation is just state.
				state.tab = "settings"
				state.settingsPath = { { page = "github" } }
			elseif msg == "keepMachine" then
				state.forgetting = nil
			elseif msg == "tryHaptic" then
				return state, { { to = "provider:system", msg = { haptic = "success" } } }
			end
			return
		end
		if msg.msg == "tab" then
			state.tab = msg.value
		elseif msg.msg == "path" then
			state.path = msg.value
		elseif msg.msg == "query" then
			state.query = msg.value
		elseif msg.msg == "sort" then
			state.sort = msg.value
		elseif msg.msg == "unreadOnly" then
			state.unreadOnly = msg.value
		elseif msg.foldMachine then
			state.foldedMachines[msg.foldMachine] = not state.foldedMachines[msg.foldMachine] or nil
		elseif msg.forgetAsk then
			state.forgetting = msg.forgetAsk
		elseif msg.hold then
			state.holdAlerts[msg.hold] = msg.value
		elseif msg.msg == "workspacesPath" then
			state.workspacesPath = msg.value
		elseif msg.msg == "settingsPath" then
			state.settingsPath = msg.value
		elseif msg.msg == "moveKey" then
			-- Take the moved keys out, then put them back before `to`.
			local moved, kept, before = {}, {}, nil
			for _, key in msg.keys do
				moved[key] = true
			end
			local target = state.keys[msg.to]
			for _, key in state.keys do
				if not moved[key] then
					table.insert(kept, key)
				end
			end
			before = #kept + 1
			for i, key in kept do
				if key == target then
					before = i
				end
			end
			for i = #msg.keys, 1, -1 do
				table.insert(kept, before, msg.keys[i])
			end
			state.keys = kept
		elseif msg.msg == "dropKey" then
			local gone = {}
			for _, key in msg.keys do
				gone[key] = true
			end
			local kept = {}
			for _, key in state.keys do
				if not gone[key] then
					table.insert(kept, key)
				end
			end
			state.keys = kept
		elseif state[msg.msg] ~= nil and msg.value ~= nil then
			-- Settings: each control's `change` is the field it sets.
			state[msg.msg] = msg.value
			if state.haptics and msg.msg ~= "haptics" then
				return state, { { to = "provider:system", msg = { haptic = "selection" } } }
			end
		elseif msg.fold then
			state.folded[msg.fold] = not state.folded[msg.fold] or nil
		elseif msg.asking then
			state.closing = msg.asking
			state.sessionSheet = false
		elseif msg.read or msg.favorite or msg.answer or msg.close then
			if msg.close then
				state.closing = nil
			end
			return state, { { to = "provider:home", msg = msg } }
		end
	end,

	view = function(state: State, app)
		return ui.tabs {
			scheme = string.lower(state.appearance),
			selection = state.tab,
			change = "tab",
			ui.tab { "Home", icon = "house", key = "home", badge = app.home.waiting, home(state, app) },
			ui.tab {
				"Workspaces",
				icon = "square.stack.3d.up",
				key = "workspaces",
				ui.stack { path = state.workspacesPath, change = "workspacesPath", screen = "screen", workspaces.view(state, app) },
			},
			ui.tab {
				"PRs",
				icon = "arrow.triangle.pull",
				key = "prs",
				ui.stack {
					ui.unavailable {
						"No GitHub account",
						icon = "arrow.triangle.pull",
						description = "Sign in to GitHub on this iPhone, or let a paired computer lend its sign-in.",
						titleMode = "inline",
						search = { value = state.prQuery, change = "prQuery", prompt = "Title, repository, author, branch", placement = "always" },
						toolbar = {
							ui.menu {
								icon = "arrow.up.arrow.down",
								place = "leading",
								ui.picker {
									"Sort Pull Requests",
									value = state.prSort,
									change = "prSort",
									options = {
										{ value = "updated", label = "Recently Updated", icon = "clock" },
										{ value = "status", label = "Status", icon = "exclamationmark.circle" },
									},
								},
							},
						},
						ui.button { "Open Settings › GitHub", variant = "primary", size = "small", msg = "openGitHub" },
					},
				},
			},
			ui.tab {
				"Settings",
				icon = "gearshape",
				key = "settings",
				ui.stack { path = state.settingsPath, change = "settingsPath", screen = "screen", settings.hub(state, app) },
			},
		}
	end,

	views = {
		chat = function(state: State, key, app)
			local chat = byKey(app)[key]
			if not chat then
				return ui.text { "Gone" }
			end
			if chat.question then
				return answerCard(chat)
			end
			return chatRow(state, chat)
		end,

		screen = function(state: State, route, app)
			if route.page then
				return settings.page(state, route.page)
			end
			if route.workspace then
				return ui.unavailable {
					"Workspace",
					icon = "square.stack.3d.up",
					description = "The workspace screen is next.",
					title = route.workspace,
					titleMode = "inline",
				}
			end
			local conversation = byKey(app)[route.chat]
			if not conversation then
				return ui.unavailable { "This chat is gone", icon = "bubble.left.and.text.bubble.right" }
			end
			return chat.screen(state, route.chat, conversation, (app.home.transcripts or {})[route.chat] or {})
		end,
	},
}
