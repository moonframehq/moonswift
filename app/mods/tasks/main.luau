-- A list with a text field: the field's text lives in the state, like
-- everything else, so it survives reloads too.
return mod {
	init = function(previous)
		return previous or {
			draft = "",
			tasks = {
				{ title = "Press the sparkles and pick something", done = false },
				{ title = "Change it in the inspector", done = false },
			},
		}
	end,

	update = function(state, msg)
		if type(msg) ~= "table" then
			return
		end
		if msg.msg == "type" then
			state.draft = msg.value
		elseif msg.msg == "add" and state.draft ~= "" then
			table.insert(state.tasks, { title = state.draft, done = false })
			state.draft = ""
		elseif msg.toggle then
			local task = state.tasks[msg.toggle]
			task.done = not task.done
		end
		local open = 0
		for _, task in state.tasks do
			open += if task.done then 0 else 1
		end
		return state, { { to = "topic:open-tasks", msg = open } }
	end,

	view = function(state)
		local rows = { title = "Tasks", gap = "small", grow = true, scroll = true }
		table.insert(rows, ui.input {
			id = "draft",
			value = state.draft,
			placeholder = "Add a task and press return",
			change = "type",
			submit = "add",
		})
		for index, task in state.tasks do
			table.insert(rows, ui.row {
				key = `task-{index}`,
				class = "task",
				gap = "small",
				align = "center",
				msg = { toggle = index },
				ui.icon { if task.done then "circle-check" else "circle" },
				ui.text { task.title, class = if task.done then "done" else nil },
			})
		end
		return ui.panel(rows)
	end,
}
