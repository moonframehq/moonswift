-- Benchmark B6: Sheprd's Pull Requests tab, the shape of its Luau
-- (sheprd-labs/sheprd#1715): two sections of 50 pull requests, each row
-- about 25 elements with a context menu, drawn as it scrolls into view.
-- MoonSwift/Examples/PullRequestsBench.swift draws the same list in
-- SwiftUI and scrolls both; `just prs-bench` compares them.
local repos = { "sheprd", "sheprd-apns", "herdr-site", "infra" }
local titles = {
	"Read pull requests on the phone with a lent GitHub sign-in",
	"Keep the relay's dial keys after a restart",
	"Docs: GitHub on the phone",
	"Group tabs by worktree in the iPad sidebar",
	"Bump relay droplets to 2 vCPU",
	"Teleport: carry checkpoints across hosts and keep their labels when the worktree moves",
}
local decisions = { "none", "approved", "changesRequested", "reviewRequired" }
local authors = { "octocat", "hubot", "monalisa", "dependabot" }
local computers = { "Studio", "MacBook Pro", "Mac mini" }
local count = 50

-- A lifecycle as icon, word, and color.
local looks = {
	open = { symbol = "arrow.triangle.pull", label = "Open", color = "green" },
	draft = { symbol = "pencil.circle", label = "Draft", color = "secondary" },
}

-- A review decision, when somebody needs to review.
local reviews = {
	approved = { symbol = "checkmark.seal.fill", label = "Approved", color = "green" },
	changesRequested = { symbol = "exclamationmark.bubble.fill", label = "Changes requested", color = "red" },
	reviewRequired = { symbol = "eye", label = "Review required", color = "orange" },
}

local tints = { "indigo", "teal", "pink", "orange", "blue", "purple", "mint", "red", "cyan", "brown" }

-- The made-up pull request at `index` (0-based), as the SwiftUI side makes it.
local function pull(index: number, mine: boolean)
	local number = (mine and 1000 or 2000) + index
	local minutes = index * 30
	local places = {}
	if index % 3 == 0 then
		table.insert(places, { computer = computers[index % #computers + 1] })
	end
	return {
		id = tostring(number),
		repository = "sheprd-labs/" .. repos[index % #repos + 1] .. " #" .. number,
		title = titles[index % #titles + 1],
		state = index % 9 == 4 and "draft" or "open",
		review = decisions[index % #decisions + 1],
		author = authors[index % #authors + 1],
		age = minutes < 60 and (minutes == 0 and "now" or minutes .. "m") or math.floor(minutes / 60) .. "h",
		checks = { failing = index % 4 == 2 and 1 or 0, pending = index % 3, passed = 3 + index % 11 },
		places = places,
		computers = #places,
		url = "https://github.com/sheprd-labs/" .. repos[index % #repos + 1] .. "/pull/" .. number,
	}
end

-- A person's initial on a color of their own, the same for every login.
local function avatar(login: string, size: number)
	local sum = 0
	for _, code in utf8.codes(string.lower(login)) do
		sum = bit32.band(sum * 31 + code, 0xFFFF)
	end
	return ui.column {
		width = size,
		height = size,
		align = "center",
		gap = 0,
		style = { background = tints[sum % #tints + 1], radius = size / 2 },
		ui.spacer {},
		ui.text {
			string.upper(string.sub(login, 1, 1)),
			style = { size = size * 0.48, weight = "bold", design = "rounded", color = "white" },
		},
		ui.spacer {},
	}
end

local function iconText(text: string, icon: string, style)
	return ui.row {
		gap = 4,
		ui.icon { icon, style = style },
		ui.text { text, lines = 1, style = style },
	}
end

local function tally(value: number, icon: string, color: string)
	return ui.row {
		gap = 3,
		ui.icon { icon, style = { font = "caption", weight = "semibold", color = color } },
		ui.text { tostring(value), digits = true, style = { font = "caption", weight = "semibold", color = "secondary" } },
	}
end

local function checks(counts)
	return ui.row {
		gap = 8,
		counts.failing > 0 and tally(counts.failing, "xmark.circle.fill", "red") or false,
		counts.pending > 0 and tally(counts.pending, "clock.fill", "yellow") or false,
		counts.passed > 0 and tally(counts.passed, "checkmark.circle.fill", "green") or false,
	}
end

local function byline(pull, showsAuthor: boolean)
	if showsAuthor and pull.author then
		return ui.row {
			gap = 8,
			avatar(pull.author, 16),
			ui.text { pull.author, lines = 1, style = { font = "caption", color = "secondary" } },
		}
	end
	local review = reviews[pull.review]
	if review then
		return iconText(review.label, review.symbol, { font = "caption", weight = "medium", color = review.color })
	end
	return ui.text { looks[pull.state].label, style = { font = "caption", color = "secondary" } }
end

local function whereLine(pull)
	local first = pull.places[1]
	if not first then
		return iconText("No workspace on any computer", "icloud", { font = "caption2", color = "tertiary" })
	end
	return iconText("Workspace on " .. first.computer, "laptopcomputer", { font = "caption2", color = "secondary" })
end

local function menu(pull)
	local items = {}
	for _, place in pull.places do
		table.insert(items, ui.button { "Open Workspace on " .. place.computer, icon = "laptopcomputer", msg = "open" })
	end
	table.insert(items, ui.button { "Open on GitHub", icon = "safari", msg = "web" })
	table.insert(items, ui.share { url = pull.url })
	return items
end

local function row(pull, showsAuthor: boolean)
	local look = looks[pull.state]
	return ui.link {
		route = { pull = pull.id },
		context = menu(pull),
		ui.column {
			gap = 5,
			padding = { 2, 0 },
			ui.row {
				gap = 6,
				ui.icon { look.symbol, style = { font = "caption", weight = "semibold", color = look.color } },
				ui.text { pull.repository, lines = 1, style = { font = "caption", design = "monospaced", color = "secondary" } },
				ui.spacer {},
				ui.text { pull.age, style = { font = "caption", color = "secondary" } },
			},
			ui.text { pull.title, lines = 2 },
			ui.row {
				gap = 8,
				byline(pull, showsAuthor),
				ui.spacer {},
				checks(pull.checks),
			},
			whereLine(pull),
		},
	}
end

local function header(title: string)
	return ui.row {
		ui.text { title },
		ui.spacer {},
		ui.text { count .. " of " .. count * 2, digits = true },
	}
end

local function section(key: string, title: string, mine: boolean)
	return ui.section {
		key = key,
		header = header(title),
		count = count,
		row = function(i: number)
			return row(pull(i - 1, mine), not mine)
		end,
	}
end

return mod {
	init = function()
		return { query = "" }
	end,

	view = function(state)
		return ui.list {
			id = "prs.list",
			variant = "inset",
			titleMode = "inline",
			refresh = "refresh",
			search = { value = state.query, change = "query", prompt = "Title, repository, author, branch" },
			section("requested", "Review requested", false),
			section("mine", "Mine", true),
		}
	end,
}
