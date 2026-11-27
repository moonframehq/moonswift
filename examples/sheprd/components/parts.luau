-- The pieces of Sheprd's Home rows: the agent's tile with its status
-- badge, the pills, the times. Plain functions that return elements.
local parts = {}

-- Status: color and the symbol in its badge, and the header's symbol.
parts.status = {
	blocked = { color = "red", badge = "exclamationmark", header = "exclamationmark.circle.fill", title = "Needs you" },
	working = { color = "yellow", badge = "ellipsis", header = "ellipsis.circle.fill", title = "Working" },
	done = { color = "teal", badge = "checkmark", header = "checkmark.circle.fill", title = "Done" },
	idle = { color = "green", header = "moon.circle.fill", title = "Idle" },
}

local tiles = {
	claude = { background = "#D9643A", ink = "white", symbol = "asterisk" },
	codex = { background = "#111111", ink = "white", symbol = "circle.hexagonpath" },
	gemini = { background = "#3B7CF0", ink = "white", symbol = "sparkle" },
}

-- The agent's tile, `size` points square, with its status in a corner.
function parts.agent(agent: string, size: number, status: string?)
	local tile = tiles[agent] or { background = "fill", ink = "primary", symbol = "terminal" }
	local mark = status and parts.status[status]
	return ui.column {
		width = size,
		height = size,
		align = "center",
		gap = 0,
		style = { background = tile.background, radius = size * 0.28 },
		overlay = mark and mark.badge and {
			place = "bottomTrailing",
			x = 6,
			y = 6,
			ui.column {
				width = 15,
				height = 15,
				align = "center",
				gap = 0,
				style = { background = mark.color, radius = 7.5, border = "secondaryGrouped", borderWidth = 2 },
				ui.spacer {},
				ui.icon {
					mark.badge,
					effect = status == "working" and "variableColor" or nil,
					style = { size = 8, weight = "black", color = "white" },
				},
				ui.spacer {},
			},
		} or nil,
		ui.spacer {},
		ui.icon { tile.symbol, style = { size = size * 0.5, weight = "semibold", color = tile.ink } },
		ui.spacer {},
	}
end

local tints = { "green", "orange", "blue", "purple", "pink", "teal", "indigo", "brown" }

-- A color for a name that stays the same: Sheprd's repository tints.
function parts.tint(name: string): string
	local sum = 0
	for _, code in utf8.codes(string.lower(name)) do
		sum += code
	end
	return tints[sum % #tints + 1]
end

function parts.pill(text: string, color: string, size: string?)
	return ui.text {
		text,
		digits = true,
		style = {
			font = size or "caption",
			weight = "semibold",
			color = color,
			background = color .. "/15",
			radius = 99,
			padding = { 3, 8 },
		},
	}
end

function parts.pills(labels: { string })
	if #labels == 0 then
		return false
	end
	local row = { gap = 4 }
	for _, label in labels do
		table.insert(row, parts.pill(label, parts.tint(label)))
	end
	return ui.row(row)
end

local tones = {
	attention = "red",
	held = "orange",
	merged = "purple",
	queued = "brown",
	ready = "green",
	waiting = "yellow",
}

-- The workspace's pull request, or a pill for commits not yet in one.
function parts.pullRequest(chat)
	if chat.pr then
		local tone = tones[chat.pr.tone] or "secondary"
		return ui.text {
			"#" .. chat.pr.number,
			digits = true,
			style = { font = "caption", weight = "semibold", color = tone, background = tone .. "/15", radius = 99, padding = { 2, 7 } },
		}
	elseif chat.unopened then
		return ui.text {
			"+PR",
			style = { font = "caption", weight = "semibold", color = "yellow", background = "yellow/15", radius = 99, padding = { 2, 7 } },
		}
	end
	return false
end

return parts
