-- Sheprd's Settings: a short hub of pages, as the system's is. Each row is
-- a colored tile, a title and a value; the pages behind are forms.
local settings = {}

-- A row icon in a colored rounded square, as the system's Settings draws.
function settings.tile(symbol: string, color: string)
	return ui.column {
		width = 28,
		height = 28,
		align = "center",
		gap = 0,
		style = { background = color, radius = 7 },
		ui.spacer {},
		ui.icon { symbol, style = { size = 14, weight = "semibold", color = "white" } },
		ui.spacer {},
	}
end

local function link(title: string, symbol: string, color: string, page: string, value: string?)
	return ui.link {
		route = { page = page },
		ui.labeled { title, value = value or "", iconView = settings.tile(symbol, color) },
	}
end

local appearances = { "System", "Light", "Dark" }

function settings.hub(state, app)
	local system = app.system or {}
	return ui.list {
		titleMode = "inline",
		ui.section {
			key = "problem",
			ui.label {
				iconView = settings.tile("exclamationmark.triangle.fill", "orange"),
				ui.text { "Last problem" },
				ui.text { "Keychain: A required entitlement isn't present.", style = { font = "footnote", color = "secondary" } },
			},
		},
		ui.section {
			key = "machines",
			link("Computers", "desktopcomputer", "blue", "computers", "0"),
			link("Fleet", "point.3.connected.trianglepath.dotted", "indigo", "fleet", "Not joined"),
			link("Relays", "antenna.radiowaves.left.and.right", "teal", "relays", "0"),
			link("GitHub", "arrow.triangle.pull", "github", "github"),
		},
		ui.section {
			key = "app",
			link("Notifications", "bell.badge.fill", "red", "notifications"),
			link("Chats", "bubble.left.and.bubble.right.fill", "green", "chats"),
			link("Voice", "waveform", "pink", "voice"),
			link("Terminal Keys", "terminal.fill", "gray", "keys", "22"),
			link("Sounds & Haptics", "speaker.wave.2.fill", "orange", "sounds"),
		},
		ui.section {
			key = "look",
			footer = "Terminals stay dark in either appearance.",
			ui.picker {
				"Appearance",
				iconView = settings.tile("circle.lefthalf.filled", "blue"),
				value = state.appearance,
				change = "appearance",
				variant = "menu",
				options = appearances,
			},
			ui.picker {
				"Open Links In",
				iconView = settings.tile("safari.fill", "blue"),
				value = state.links,
				change = "links",
				variant = "menu",
				options = { "Sheprd", "Safari" },
			},
			link("Privacy & Storage", "hand.raised.fill", "blue", "privacy"),
		},
		ui.section {
			key = "version",
			ui.labeled { "Version", value = "1.0 (" .. (system.idiom or "?") .. ")" },
		},
	}
end

local titles = {
	chats = "Chats",
	sounds = "Sounds & Haptics",
	keys = "Terminal Keys",
}

-- A page behind a row. The ones not rebuilt yet say so.
function settings.page(state, name: string)
	if name == "chats" then
		return ui.form {
			title = "Chats",
			titleMode = "inline",
			ui.section {
				"Rows",
				footer = "How many lines of the last message each row on Home shows.",
				ui.stepper { "Lines: " .. state.rowLines, value = state.rowLines, min = 1, max = 3, change = "rowLines" },
			},
			ui.section {
				"Sending",
				ui.toggle { "Return Sends", value = state.returnSends, change = "returnSends" },
				ui.toggle { "Speak Answers", value = state.speak, change = "speak" },
			},
		}
	elseif name == "sounds" then
		return ui.form {
			title = "Sounds & Haptics",
			titleMode = "inline",
			ui.section {
				footer = "Haptics need an iPhone; iPad has none.",
				ui.toggle { "Haptics", value = state.haptics, change = "haptics" },
				ui.toggle { "Sounds", value = state.sounds, change = "sounds" },
				ui.button { "Try a Haptic", icon = "hand.tap", variant = "borderless", msg = "tryHaptic", disabled = not state.haptics },
			},
		}
	elseif name == "keys" then
		local rows = {}
		for _, key in state.keys do
			table.insert(rows, ui.text { key, key = key, style = { design = "monospaced" } })
		end
		return ui.list {
			title = "Terminal Keys",
			titleMode = "inline",
			toolbar = { ui.edit { place = "trailing" } },
			ui.section { "Top Row", footer = "Drag to reorder; swipe to remove.", move = "moveKey", delete = "dropKey", table.unpack(rows) },
		}
	end
	return ui.unavailable {
		titles[name] or name,
		icon = "hammer",
		description = "Not rebuilt in Luau yet.",
		title = titles[name] or name,
		titleMode = "inline",
	}
end

return settings
