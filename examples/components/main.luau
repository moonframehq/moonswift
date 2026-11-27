-- Moonframe's components, as a desktop mod uses them, drawn on a phone. Each
-- comes from MoonKit's library (Moonframe's app/components); `just example
-- components` shows it on a simulator.
local stat_tile = use "stat-tile"
local card = use "card"
local pr_badge = use "pr-badge"
local avatar = use "avatar"
local meter = use "meter"
local sparkline = use "sparkline"
local segmented = use "segmented"
local tags = use "tags"
local empty_state = use "empty-state"
local key_values = use "key-values"
local status_dot = use "status-dot"
local pr_row = use "pr-row"
local usage_bar = use "usage-bar"
local notice = use "notice"

return mod {
	init = function(previous)
		return previous or { theme = "dark" }
	end,

	update = function(state, msg)
		if type(msg) == "table" and msg.theme then
			state.theme = msg.theme
		end
	end,

	view = function(state)
		return ui.column {
			gap = "large",
			padding = "large",
			scroll = true,
			grow = true,
			ui.row {
				gap = "normal",
				align = "center",
				avatar { name = "harbor-docs", size = "large", status = "working" },
				ui.column { gap = "none", ui.text { "harbor-docs", weight = "semibold" }, ui.text { "3 agents", size = "small", tone = "muted" } },
				ui.spacer(),
				status_dot { status = "blocked", chip = true },
			},
			stat_tile { label = "Tokens today", icon = "activity", value = "1.84M", delta = "+12%", detail = "vs. yesterday · 3 agents" },
			card {
				title = "Worktree",
				subtitle = "feature/gitlab-mrs",
				key_values { rows = { { "Branch", "main" }, { "Ahead", "2 commits" }, { "Changed", "14 files" } } },
				ui.row { gap = "small", align = "center", pr_badge { number = 850, tone = "ready", checks = "passed", label = "Ready" }, ui.spacer(), sparkline { values = { 0.1, 0.3, 0.2, 0.5, 0.4, 0.9, 0.6, 0.3, 0.2, 0.4, 0.7, 0.5 } } },
				meter { value = 0.62, width = 120, label = "Memory" },
			},
			segmented {
				selected = state.theme,
				options = { { id = "light", label = "Light" }, { id = "dark", label = "Dark" }, { id = "system", label = "System" } },
				msg = "theme",
			},
			tags { tags = { "rust", "gpui", "luau", "wasm", "swiftui", "ios" } },
			pr_row {
				number = 850,
				title = "Show GitLab merge requests in Pull requests",
				branch = "feature/gitlab-mrs",
				target = "main",
				author = "fanfei",
				seconds = 4 * 86400,
				checks = "passed",
				added = 412,
				removed = 87,
				comments = 3,
				labels = { "ui" },
				tone = "ready",
			},
			usage_bar { title = "Weekly", left = 0.97, pace = 0.61, resets = "Resets in 4d 6h", note = "36% in reserve", width = 320 },
			notice { id = "config", tone = "warning", title = "config.toml has 2 problems", text = "Line 14: unknown key `sidebar.density`; it is ignored." },
			empty_state { icon = "inbox", title = "No worktrees", message = "Create one to work on two branches at once.", action = "New worktree", msg = "new" },
		}
	end,
}
