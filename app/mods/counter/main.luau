-- The smallest whole mod: state, messages, a view. Press + a few times, then
-- change this file: the count survives every reload.
local stat = use "stat"

return mod {
	init = function(previous)
		return previous or { count = 0, step = 1 }
	end,

	update = function(state, msg)
		if msg == "more" then
			state.count += state.step
		elseif msg == "less" then
			state.count -= state.step
		elseif msg == "reset" then
			state.count = 0
		elseif type(msg) == "table" and msg.msg == "step" then
			state.step = msg.value
		end
	end,

	view = function(state)
		return ui.panel {
			title = "Counter",
			gap = "large",
			ui.row {
				align = "center",
				gap = "normal",
				ui.text { tostring(state.count), id = "count", class = "hero", numeric = true },
				ui.spacer {},
				ui.button { icon = "minus", label = "Less", id = "less", msg = "less" },
				ui.button { icon = "plus", label = "More", id = "more", variant = "primary", msg = "more" },
			},
			ui.row {
				gap = "normal",
				stat { label = "Doubled", value = state.count * 2 },
				stat { label = "Step", value = state.step },
			},
			ui.slider { id = "step", value = state.step, min = 1, max = 10, step = 1, change = "step" },
			ui.row { ui.button { "Reset", id = "reset", msg = "reset" } },
		}
	end,
}
