-- Sheprd's Workspaces: each computer, then its repositories, then their
-- workspaces, as the desktop's sidebar lists them.
local parts = use "parts"

local workspaces = {}

-- A share of the computer in use: a label, a thin bar and the percent.
local function gauge(label: string, percent: number)
	local width = 34
	return ui.row {
		gap = 5,
		style = { color = "secondary" },
		ui.text { label, style = { font = "caption2", weight = "semibold", color = "secondary" } },
		ui.column {
			width = width,
			height = 5,
			style = { background = "fill", radius = 2.5 },
			overlay = {
				place = "leading",
				ui.column {
					width = width * math.clamp(percent, 0, 100) / 100,
					height = 5,
					style = { background = if percent >= 80 then "orange" else "secondary", radius = 2.5 },
				},
			},
		},
		ui.text { percent .. "%", digits = true, style = { font = "caption2", color = "secondary" } },
	}
end

local function machineHeader(state, machine)
	local open = not state.foldedMachines[machine.name]
	return ui.row {
		gap = 8,
		align = "start",
		ui.column {
			gap = 4,
			grow = "x",
			msg = { foldMachine = machine.name },
			ui.row {
				gap = 8,
				grow = "x",
				ui.icon { "chevron.right", rotate = open and 90 or 0, style = { font = "caption", weight = "bold", color = "secondary" } },
				ui.icon { "laptopcomputer" },
				ui.text { machine.name, lines = 1, style = { font = "headline" } },
				ui.spacer {},
				machine.waiting > 0 and ui.text {
					if machine.waiting == 1 then "1 needs you" else machine.waiting .. " need you",
					style = { font = "caption", weight = "semibold", color = "white", background = "red", radius = 99, padding = { 2, 8 } },
				} or false,
				ui.column { width = 8, height = 8, style = { background = "green", radius = 4 } },
			},
			ui.row { gap = 12, gauge("CPU", machine.cpu), gauge("MEM", machine.memory) },
		},
		ui.menu {
			icon = "ellipsis.circle",
			style = { font = "title3", color = "secondary" },
			ui.toggle { "Hold Alerts at the Desk", value = state.holdAlerts[machine.name] or false, change = { hold = machine.name } },
			ui.button { "New Project…", icon = "folder.badge.plus", msg = "newProject" },
			ui.button { "Computer Details", icon = "info.circle", msg = { details = machine.name } },
			ui.divider {},
			ui.button { "Forget…", icon = "trash", role = "destructive", msg = { forgetAsk = machine.name } },
		},
	}
end

-- A repository's letter, in a color that stays with its name.
local function avatar(label: string)
	return ui.column {
		width = 22,
		height = 22,
		align = "center",
		gap = 0,
		style = { background = parts.tint(label), radius = 6 },
		ui.spacer {},
		ui.text { string.upper(string.sub(label, 1, 1)), style = { size = 12, weight = "bold", design = "rounded", color = "white" } },
		ui.spacer {},
	}
end

-- A workspace's most pressing agent: a dot when it needs you, an orbit
-- while it works, a ring when idle.
local function mark(status: string)
	if status == "blocked" then
		return ui.column { width = 10, height = 10, style = { background = "red", radius = 5 } }
	elseif status == "working" then
		return ui.column {
			width = 10,
			height = 10,
			style = { border = "yellow/30", borderWidth = 1.5, radius = 5 },
			overlay = {
				place = "center",
				ui.icon { "circle.dotted", effect = "rotate", style = { size = 10, color = "yellow" } },
			},
		}
	end
	return ui.column { width = 10, height = 10, style = { border = "green", borderWidth = 1.5, radius = 5 } }
end

local function uncommitted()
	return ui.column {
		width = 20,
		height = 20,
		align = "center",
		gap = 0,
		style = { background = "yellow/15", border = "yellow/55", radius = 5.6 },
		ui.spacer {},
		ui.icon { "pencil", style = { size = 11, weight = "semibold", color = "yellow" } },
		ui.spacer {},
	}
end

local function row(workspace)
	return ui.link {
		key = workspace.key,
		route = { workspace = workspace.key },
		context = {
			ui.button { "Rename…", icon = "pencil", msg = { rename = workspace.key } },
			ui.share { text = workspace.branch, label = "Share Branch Name" },
		},
		ui.row {
			gap = 10,
			mark(workspace.status),
			ui.column {
				gap = 1,
				if workspace.own
					then ui.text { workspace.branch, lines = 1, style = { design = "monospaced" } }
					else ui.text { workspace.label, lines = 1 },
				ui.text { workspace.counts, style = { font = "caption", color = "secondary" } },
			},
			ui.spacer { min = 4 },
			workspace.uncommitted and uncommitted() or false,
			parts.pullRequest(workspace),
		},
	}
end

local function matches(state, workspace): boolean
	if state.query == "" then
		return true
	end
	local query = string.lower(state.query)
	return string.find(string.lower(workspace.label), query, 1, true) ~= nil
		or string.find(string.lower(workspace.branch), query, 1, true) ~= nil
end

function workspaces.view(state, app)
	local machines = (app.home or {}).machines or {}
	local list = {
		titleMode = "inline",
		refresh = "refresh",
		search = { value = state.query, change = "query", prompt = "Workspaces, chats, terminals", placement = "always" },
		toolbar = {
			ui.menu {
				icon = "line.3.horizontal.decrease",
				place = "leading",
				ui.button { "All Computers", icon = "checkmark", msg = "all" },
			},
			ui.button { icon = "rectangle.compress.vertical", place = "trailing", msg = "foldMachines" },
			ui.button { icon = "plus", place = "trailing", msg = "new" },
		},
		confirm = state.forgetting and {
			open = true,
			title = "Forget " .. state.forgetting .. "?",
			message = "This phone stops reaching it until you pair again.",
			dismiss = "keepMachine",
			ui.button { "Forget", role = "destructive", msg = "keepMachine" },
		} or nil,
	}
	if #machines == 0 then
		return ui.unavailable { "No computers yet", icon = "desktopcomputer", description = "Pair a computer to see its workspaces." }
	end
	for _, machine in machines do
		table.insert(list, ui.section { key = machine.name, header = machineHeader(state, machine) })
		if not state.foldedMachines[machine.name] then
			for _, repository in machine.repositories do
				local rows = {}
				for _, workspace in repository.workspaces do
					if matches(state, workspace) then
						table.insert(rows, row(workspace))
					end
				end
				if #rows > 0 then
					table.insert(list, ui.section {
						key = machine.name .. "/" .. repository.label,
						header = ui.row {
							gap = 8,
							avatar(repository.label),
							ui.text { repository.label, lines = 1, style = { font = "subheadline", weight = "semibold" } },
							ui.spacer {},
							ui.button { icon = "plus", variant = "borderless", msg = { newWorktree = repository.label } },
						},
						table.unpack(rows),
					})
				end
			end
		end
	end
	return ui.list(list)
end

return workspaces
