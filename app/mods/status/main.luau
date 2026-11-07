-- The status bar: reads what other mods publish, and the host's `app`.
return mod {
	region = "status",
	subscribe = { "page", "open-tasks" },

	init = function(previous)
		return previous or { page = "counter", open = 2 }
	end,

	update = function(state, msg)
		if type(msg) ~= "table" then
			return
		elseif msg.topic == "page" then
			state.page = msg.value
		elseif msg.topic == "open-tasks" then
			state.open = msg.value
		end
	end,

	view = function(state, app)
		return ui.row {
			class = "status",
			gap = "medium",
			align = "center",
			ui.badge { state.page },
			ui.text { `{state.open} open tasks` },
			ui.spacer {},
			ui.text { `{math.floor(app.window.width)}×{math.floor(app.window.height)} · {app.appearance}` },
		}
	end,
}
