-- The stylesheet: colors, corners and spacing on top of the layout the mods
-- describe. Change the accent while the window is open.
return style {
	colors = {
		accent = { light = "#4f46e5", dark = "#818cf8" },
		ground = { light = "#f4f4f6", dark = "#141417" },
		card = { light = "#ffffff", dark = "#1e1e22" },
		ink = { light = "#1b1b1f", dark = "#ececf1" },
		muted = { light = "#6b6b76", dark = "#9a9aa6" },
		line = { light = "#e2e2e8", dark = "#2c2c33" },
	},

	rules = {
		shell = { background = "ground", color = "ink" },
		main = { padding = 16 },

		panel = { background = "card", radius = 14, padding = 16, border = "line" },
		["panel-title"] = { size = 12, weight = "semibold", color = "muted" },

		sidebar = { padding = { top = 12, x = 10, bottom = 10 } },
		nav = { padding = { 7, 10 }, radius = 9 },
		["nav:hover"] = { background = "accent/8" },
		["nav:selected"] = { background = "accent/15", color = "accent" },

		hero = { size = 56, weight = "bold", color = "accent" },
		muted = { color = "muted" },
		stat = { background = "accent/8", radius = 10, padding = { 8, 12 } },

		task = { padding = { 6, 8 }, radius = 8 },
		["task:hover"] = { background = "accent/8" },
		done = { color = "muted", opacity = 0.6 },

		status = { padding = { 6, 12 }, size = 11, color = "muted" },
		badge = { background = "accent/15", color = "accent", radius = 6, padding = { 2, 7 }, size = 11, weight = "medium" },
	},
}
