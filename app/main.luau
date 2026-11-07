-- The shell: lays out the whole window. Mods fill the regions it draws.
-- Edit anything here while the app runs: the window redraws in place and
-- every mod keeps its state.
return mod {
	subscribe = { "page" },

	init = function(previous)
		return previous or { page = "counter" }
	end,

	update = function(state, msg)
		if type(msg) == "table" and msg.topic == "page" then
			state.page = msg.value
		end
	end,

	view = function(state, app)
		local page = ui.column {
			class = "main",
			grow = true,
			ui.mount { state.page, key = state.page },
		}
		-- Layout is just code: a phone gets the navigation on top.
		local wide = app.window.width > 560
		return ui.column {
			class = "shell",
			grow = true,
			gap = "none",
			if wide
				then ui.row { grow = true, gap = "none", ui.region { "left" }, page }
				else ui.column { grow = true, gap = "none", ui.region { "left" }, page },
			ui.region { "status" },
		}
	end,
}
