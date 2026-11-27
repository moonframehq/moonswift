-- The navigation. It says which page is showing on the `page` topic, which
-- the shell and the status bar listen to.
local PAGES = {
	{ id = "counter", title = "Counter", icon = "hash" },
	{ id = "tasks", title = "Tasks", icon = "list-checks" },
}

return mod {
	region = "left",

	init = function(previous)
		return previous or { page = "counter" }
	end,

	update = function(state, msg)
		if type(msg) == "table" and msg.go then
			state.page = msg.go
			return state, { { to = "topic:page", msg = msg.go } }
		end
	end,

	view = function(state, app)
		local wide = app.window.width > 560
		local rows = { class = "sidebar", gap = "small" }
		if wide then
			rows.width = 180
			table.insert(rows, ui.text { "MOONSWIFT", class = "panel-title" })
		end
		for _, page in PAGES do
			table.insert(rows, ui.row {
				id = `nav-{page.id}`,
				class = "nav",
				gap = "small",
				align = "center",
				selected = state.page == page.id,
				msg = { go = page.id },
				ui.icon { page.icon },
				ui.text { page.title },
			})
		end
		table.insert(rows, ui.spacer {})
		return if wide then ui.column(rows) else ui.row(rows)
	end,
}
