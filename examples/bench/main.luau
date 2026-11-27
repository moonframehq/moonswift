-- Benchmark B1 of plans/ios-parity.md: 10,000 rows, each drawn by Luau as
-- it scrolls into view. MoonSwift/Examples/BenchList.swift is the same
-- screen written in SwiftUI, to measure against.
local count = 10000
local agents = { "asterisk", "circle.hexagonpath", "sparkle", "terminal" }
local colors = { "orange", "gray", "blue", "green" }

-- One row, built as it scrolls into view.
local function row(i: number)
	local kind = i % 4 + 1
	return ui.row {
		gap = 12,
		ui.column {
			width = 28,
			height = 28,
			align = "center",
			gap = 0,
			style = { background = colors[kind], radius = 8 },
			ui.spacer {},
			ui.icon { agents[kind], style = { color = "white", weight = "semibold" } },
			ui.spacer {},
		},
		ui.column {
			gap = 2,
			grow = "x",
			ui.row {
				gap = 6,
				grow = "x",
				ui.text { "Session " .. i, lines = 1 },
				ui.spacer {},
				ui.text { tostring(i % 60) .. "m", digits = true, style = { font = "footnote", color = "secondary" } },
			},
			ui.text { "Studio · forecast · Row " .. i .. " of the benchmark", lines = 1, style = { font = "subheadline", color = "secondary" } },
		},
	}
end

return mod {
	view = function()
		return ui.stack {
			ui.list {
				id = "bench.list",
				title = "Luau",
				count = count,
				row_height = 56,
				row = row,
			},
		}
	end,
}
