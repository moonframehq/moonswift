# Moonframe compatibility: one mod, two hosts

The goal: a Luau mod or component written for Moonframe (Rust and GPUI on the
desktop) loads unchanged in MoonSwift (SwiftUI on the Mac and iOS), and the
other way round. Only the top-level layout, usually `main.luau`, may differ
per platform, and it chooses by reading `app`, not by being a different file.

Moonframe is the reference. Its API is declared in
`types/moonframe.d.luau` and described by its `moonframe` and
`moonframe-components` skills. MoonSwift follows it wherever a phone can, and
where a phone can't, the change is proposed on Moonframe's side instead.

The conformance suite in `conformance/` (section 7) is the contract: the same
mods, run by `just test` here and by a test in Moonframe, must draw the same
trees and send the same messages on both.

## 1. Where the two stood

| Area | Moonframe | MoonSwift before | Now |
| --- | --- | --- | --- |
| Shell's name | `shell` | `main` | `shell` |
| `mod { }` keys | `init update view region order title styles window subscribe tab menus about keys paste`, anything else an error | anything; `providers` and `views` read | Moonframe's list, anything else an error |
| `init` | `init(previous, props, restored)` returns state, and sends | `init(previous)` returns state | Moonframe's |
| `update` | `update(state, msg, props)` returns nothing (state changed in place), or `state, sends` | the same, without `props` | Moonframe's |
| `view` | `view(state, app, props)` | `view(state, app)` | Moonframe's |
| Sends | `{ to, msg }`; `send "to" (msg)` builds one | `{ to, msg }` | both |
| Topics | `subscribe = { "name", "prefix/*" }`; value kept and replayed to a mod as it loads; `provider/<name>` carries each publish | exact names only, not kept | Moonframe's |
| Provider data | `app.<name>`, nil until the first publish; a mod redraws when a provider it read publishes | listed in `providers = { ... }`, an empty table until published | Moonframe's |
| Components | `return component { build = function(props) ... }`, `use` returns `build` | `use` returns whatever the file returns | both: a `component` gives its `build`, anything else comes back as it is |
| Lazy rows | `ui.list { id, count, row_height, row = function(i) }` | `rows = keys, row = "name"` and `views.name(state, key, app)` | Moonframe's; `ui.section` and `ui.stack` take functions too |
| `app` | `dark`, `appearance = { mode, dark, ... }`, `window = { platform, width, height, ... }`, `renderer`, providers | `appearance = "dark"`, `platform`, `window = { width, height }`, `phase` | Moonframe's, plus `phase` |
| Space tokens | `none small normal large` (0, 4, 8, 16) | `none small medium large` and points | Moonframe's tokens and values; points still work here |
| `grow` | `true`: along the parent's axis, and across it where a growing parent stretches it | `true` both ways, `"x"`, `"y"` | Moonframe's; `"x"` and `"y"` stay as MoonSwift extras |
| Icons | Lucide names (`git-branch`, `trash-2`) | SF Symbol names | Lucide names, mapped to SF Symbols; an SF Symbol name (it has a dot) still works here |
| Stylesheet selectors | `row` an element type, `.name` a class, `:hover` `:selected` `:<state>` | a bare name matched type or class | Moonframe's |
| Stylesheet properties | `border` edges, `border_color` a color, tokens for `size`, `padding` and `gap` | `border` a color | Moonframe's; `border` as a color still read |

## 2. The shared core

What a portable mod may use. Every case in `conformance/` stays inside it.

### Files

```text
main.luau              the shell (`shell` when sending to it)
style.luau             return style { colors = {...}, rules = {...} }
mods/<name>/main.luau  return mod { ... }
components/<name>.luau return component { build = function(props) ... end }
```

### A mod

```lua
return mod {
	region = "left", order = 0, title = "Files",
	subscribe = { "page", "provider/git" },
	init = function(previous, props, restored)
		return previous or { count = 0 }       -- , { { to = ..., msg = ... } }
	end,
	update = function(state, msg, props)
		if msg == "add" then
			state.count += 1                     -- nothing returned: kept in place
		elseif msg == "tell" then
			return state, { send "status" { count = state.count } }
		end
	end,
	view = function(state, app, props)
		return ui.panel { title = "Files", ui.text(`{state.count}`) }
	end,
}
```

- State and messages are plain data: nil, booleans, numbers, strings, lists
  and string-keyed tables.
- `update` returning nothing keeps the table it changed. Returning a state
  replaces it. A second result is a list of sends. This was already both
  hosts' rule; nothing needs a shim.
- Sends go to a mod by name, to `shell`, to `topic:<name>`, to
  `provider:<name>`, or to `app:<what>`. Which `app:` requests a host
  answers is its own (section 5).

### Topics

`{ to = "topic:page", msg = value }` keeps `value` and tells every mod whose
`subscribe` names `page`, or a prefix of it ending in `*`, with
`{ topic = "page", value = value }`. A mod that loads, or reloads, hears each
of its topics' current values at once, so it starts in step. A provider's
publish goes out as `provider/<name>`; a mod can't publish under `provider/`
or `app/`.

### Providers

Native code feeding data to Luau. A view reads `app.<name>`, which is nil
until the provider first publishes; a view that read it runs again when it
publishes. A mod asks a provider for something by sending to
`provider:<name>`, and the provider answers with a message to the mod. The
provider itself is per host: Rust (built in, process or Wasm) on Moonframe,
Swift (`Provider`) on MoonSwift. Two providers that publish the same shape
under the same name make a mod portable across them.

### `app`

| Key | Value |
| --- | --- |
| `dark` | whether the window draws dark |
| `appearance` | `{ mode = "system" \| "light" \| "dark", dark }`, more on Moonframe |
| `window.platform` | `macos`, `linux`, `windows`, or `ios` |
| `window.width`, `window.height` | the content's size in points |
| `renderer` | `gpui` or `rune` on Moonframe, `swiftui` on MoonSwift |
| `<provider>` | what each provider last published |

`window.platform` and `renderer` are how a layout picks: `renderer ==
"swiftui"` to use a MoonSwift-only element, `platform == "ios"` or a narrow
`window.width` for a phone layout.

### Shared elements

Every element both hosts draw, with the props both read. A prop outside this
table is host-specific: Moonframe rejects keys it doesn't know, MoonSwift
ignores them.

| Element | Primary | Shared props |
| --- | --- | --- |
| `ui.row`, `ui.column` | | `gap`, `padding`, `grow`, `width`, `height`, `align`, `justify`, `scroll`, `class`, `style`, `state`, `selected`, `key`, `msg`, `to`, `tooltip` |
| `ui.panel` | | the stack's, and `title`, `actions` |
| `ui.text` | `text` | `tone`, `size`, `weight`, `lines`, `truncate`, `class`, `style` |
| `ui.badge` | `text` | `tone`, `class`, `style` |
| `ui.icon` | `name` | `tone`, `size`, `class`, `style` |
| `ui.image` | `src` | `width`, `height`, `fit`, `class`, `style` |
| `ui.button` | `label` | `icon`, `variant`, `small`, `disabled`, `msg`, `to`, `tooltip`, `class`, `style` |
| `ui.item` | `label` | `detail`, `badge`, `selected`, `msg`, `to`, `tooltip`, `class`, `style` |
| `ui.markdown` | `text` | `link`, `to`, `class`, `style` |
| `ui.input` | | `id`, `value`, `placeholder`, `change`, `submit`, `multiline`, `secret`, `disabled`, `to`, `class`, `style` |
| `ui.list` | | `id`, `count`, `row_height`, `row`, `grow`, `class`, `style` |
| `ui.popover` | | `open`, `dismiss`, `content`, `side`, `to`, children (the anchor) |
| `ui.overlay` | | `open`, `dismiss`, `content`, `place`, `backdrop` |
| `ui.divider`, `ui.spacer` | | |
| `ui.region` | `name` | `direction`, `gap` |
| `ui.mount` | `mod` | |

Tokens, the same on both: space `none small normal large` (0, 4, 8, 16);
tone `normal muted accent success warning danger`; text size `small normal
large title headline display hero`; weight `light normal medium semibold
bold`; align `stretch start center end`; justify `start center end between`;
button variant `normal primary ghost outline danger`.

A row's height is the host's to decide on a phone: MoonSwift reads
`row_height` as a hint and lets rows size themselves, so a row that wraps on
a narrow screen isn't cut.

### style.luau

```lua
return style {
	colors = { accent = { light = "#4f46e5", dark = "#818cf8" }, brand = "#ff3366" },
	rules = {
		panel = { background = "card", radius = 12, padding = "normal" },  -- an element type
		[".hero"] = { size = "title", weight = "bold", color = "accent" },  -- a class
		["item:selected"] = { background = "accent/15", color = "accent" },
		["item:hover"] = { background = "accent/8" },
	},
}
```

Shared properties: `background`, `color`, `border` (`true` or an edge),
`border_color`, `radius`, `padding`, `margin`, `gap`, `size`, `weight`,
`opacity`, `shadow` (`small medium large none`), `font` (`sans`, `mono`).
Colors are `#rgb`, `#rrggbb`, a name from `colors`, or a theme color
(`background foreground muted muted-foreground card secondary border accent
success warning danger`), each with an optional `/NN` opacity. On MoonSwift
the theme colors are the system's semantic ones, so they follow light, dark
and the accent the user chose.

A mod's own `styles` apply only to what it draws, under `style.luau`'s rules
at the same step, as on Moonframe.

## 3. Icons

One set of names: Moonframe's `IconName` (Lucide, plus agent and brand
logos). MoonSwift maps each to an SF Symbol in
`Packages/MoonKit/Sources/MoonUI/Icons.swift`; the table there is the full
mapping, and a test checks it covers every name in `conformance/icons.txt`,
a copy of Moonframe's list. Examples:

| Name | SF Symbol |
| --- | --- |
| `git-branch` | `arrow.triangle.branch` |
| `git-pull-request` | `arrow.triangle.pull` |
| `git-merge` | `arrow.triangle.merge` |
| `trash-2` | `trash` |
| `circle-check` | `checkmark.circle` |
| `triangle-alert` | `exclamationmark.triangle` |
| `settings` | `gearshape` |
| `search` | `magnifyingglass` |
| `agent-claude`, `brand-anthropic` | `asterisk` (no logo ships in SF Symbols) |

A name with a dot is taken as an SF Symbol as it is, so a MoonSwift-only
screen can still use any symbol; Moonframe rejects it, so a portable mod
doesn't. An unknown name without a dot draws as a warning mark, as on
Moonframe.

## 4. Elements only one host has

Each degrades, so a mod that uses one still draws something sensible on the
other. Where degrading would lose too much, the layout reads
`app.renderer` and builds what fits.

### Moonframe's, on MoonSwift

| Element | Mac | iPhone and iPad |
| --- | --- | --- |
| `ui.hsplit` of `ui.pane`s | a split view, panes side by side | a navigation split view: the first pane is the sidebar, the last the detail; on an iPhone it collapses to a stack, which is the phone's way of showing a split |
| `ui.vsplit` of `ui.pane`s | panes stacked, each taking its `size` | the same |
| `ui.pane` | its children, as a column | the same |
| `ui.popover` | a popover on its anchor | a popover, which iOS shows as a sheet on an iPhone |
| `ui.overlay` | a sheet for `center`, a floating layer for the edges | the same |
| `ui.view` | a view the app registered (`ui.native` here) | the same |
| `ui.terminal` | the app's `terminal` native view, if it registered one | the same |
| `ui.browser` | a link opening `url` in the browser | the same |
| `ui.map`, `ui.video`, `ui.line`, `ui.paths`, `ui.hatch`, `ui.revision_timeline` | a placeholder naming the element | the same |

### MoonSwift's, on Moonframe

These stay MoonSwift extras; a portable mod uses them only behind
`app.renderer == "swiftui"`.

| Element | What Moonframe draws instead |
| --- | --- |
| `ui.tabs`, `ui.tab` | a sidebar: one `ui.item` per tab and the selected tab's content beside it (`use "tabs"` or `side-nav`) |
| `ui.stack`, `ui.link` | the root screen with the pushed screen in an `hsplit` beside it, a link an `ui.item` |
| `ui.split` | `ui.hsplit` |
| `ui.section`, `ui.form` | a `ui.panel` with the section's title, a column of rows |
| `ui.picker`, `ui.toggle`, `ui.slider`, `ui.stepper` | the `dropdown`, `switch`, `slider` and `segmented` components |
| `ui.menu` | a `dropdown` component |
| `ui.label`, `ui.labeled` | `ui.row { ui.icon, ui.text }`, the `key-values` component |
| `ui.progress` | the `progress` component |
| `ui.unavailable` | the `empty-state` component |
| `ui.secure`, `ui.editor` | `ui.input { secret = true }`, `ui.input { multiline = true }`, which MoonSwift reads too |
| `ui.scroll`, `ui.grid`, `ui.fits` | `ui.column { scroll = true }`, `ui.row { wrap = true }`, the narrow layout |
| `ui.share`, `ui.edit`, `ui.native` | nothing; `ui.view` for a native view of the app's |
| A list's `edge` index | nothing: the desktop has a scroll bar |
| Screen props (`toolbar`, `search`, `refresh`, `swipe`, `sheet`, `alert`) | a panel's `actions`, a `search-field`, a button, `context`, `ui.overlay` |

The degradations on Moonframe's side are Luau components rather than host
changes: a phone-first mod can ship a small `adaptive` component that returns
`ui.tabs` under `swiftui` and the sidebar otherwise, and only that component
knows both.

## 5. What each host keeps to itself

- `app:` requests: Moonframe's `app:command`, `app:window`, `app:notify`
  and the rest are desktop requests; MoonSwift has none yet. A send to an
  `app:` target the host doesn't know is a problem on that mod, not a crash.
- Moonframe's instances (`ui.mount { id = ... }`, components with `update`),
  `keys`, `menus`, `about`, `paste` and `tab` are read but not acted on by
  MoonSwift yet: they load, and do nothing.
- MoonSwift's screen props and `app.phase` (`active`, `inactive`,
  `background`) are its own.
- Not on MoonSwift yet: `ui.t`, `ui.number`, `ui.date` and `ui.locale`,
  `:focus` rules, transitions, `float`, and the `secondary` theme color, which
  here still means the system's secondary text color rather than a surface.

## 6. Changes proposed to Moonframe

Only what a phone can't do without, in moonframehq/moonframe:

1. `Platform` gains `"ios"` and `Renderer` gains `"swiftui"` in
   `types/moonframe.d.luau`, so a portable mod type-checks its phone branch.
2. The conformance suite and a test that runs it (section 7).

Both are moonframehq/moonframe#253. A later one: MoonSwift refuses a mod's
message to another mod that carries a `topic` under `provider/` or `app/`,
so no mod can forge a provider's or the app's event; Moonframe delivers it
as plain data today and should refuse it the same way.

Not proposed: everything else in section 1 moved MoonSwift's way.

## 7. The conformance suite

`conformance/` holds the cases, the same folder in both repositories:
Moonframe's copy is the reference, and `just conformance-sync` here copies it
from a Moonframe checkout. Each case is an app folder plus `case.json`:

```text
conformance/
  README.md          the format
  icons.txt          every shared icon name
  cases/<case>/
    main.luau        the shell
    mods/...         more mods, components/, as an app has them
    case.json        steps and what each one should leave
```

`case.json` is `{ "about": "...", "steps": [ ... ] }`, each step one of:

| Step | Does |
| --- | --- |
| `{ "send": msg, "to": "counter" }` | delivers `msg` to a mod, as a click would |
| `{ "publish": "clock", "data": value }` | a provider publishes |
| `{ "expect": { "<mod>": tree, ... } }` | each mod's view, as data, must equal `tree` |
| `{ "outbox": [ { "to": "clock", "from": "<mod>", "msg": msg } ] }` | the messages sent to providers since the last `outbox` step |

A tree is the view's table as the `ui` functions built it: `type`, the props,
and the children as `children`; the line number each `ui` call adds is left
out, and a function (a list's `row`) is the string `"<function>"`. A list
also gets `rows`: `row(i)` for every `i` up to `count`, at most 50. Both hosts
must also draw each tree without a problem, which is what catches a prop one
of them doesn't take.

Moonframe runs it in `crates/moonframe-core/src/tests/conformance.rs`, here
`ConformanceTests.swift` runs it in `just test`. A change on either side that
draws a case differently fails there.

## 8. What MoonSwift changed

- `Module`: checks the `mod { }` keys, calls `init(previous, props,
  restored)`, `update(state, msg, props)` and `view(state, app, props)`, and
  takes sends from `init`.
- Prelude: `send`, `component`, `ui.item`, Moonframe's other element names,
  `use` returning a component's `build`.
- `Workspace`: the shell is `shell`; topics are kept, replayed on load and
  matched by prefix; providers publish on `provider/<name>`; `app.<name>` is
  nil until published, and only the mods that read it redraw.
- `LuauVM`: a function in a view's tree (a list's `row`) is kept in the VM
  and called as rows scroll in, instead of being dropped.
- `MoonUI`: Moonframe's tokens, `tone`, text sizes and weights, Lucide icons,
  `ui.item`, `ui.list { count, row }`, the splits, `ui.popover` and
  `ui.overlay`, placeholders for the rest, and the stylesheet's `.class`
  selectors and `border_color`.

None of it adds a modifier to every element: new looks resolve in the
stylesheet, and new elements are new cases of the switch that already
exists, so the per-row cost measured in Sheprd's PR #1715 does not grow.

## 9. What Sheprd's `ios/Luau/pull-requests` must change

For sheprd-labs/sheprd PR #1715, not done here:

- `providers = { "pulls" }` goes: Moonframe and now MoonSwift reject it, and
  `app.pulls` redraws the mod by itself once read. The view already copes
  with `app.pulls` being nil.
- `views = { pull = ... }` goes. Each `ui.section { rows = keys, row = "pull" }`
  becomes `ui.section { count = #keys, row = function(i) return
  row.view(pulls.rows[keys[i]], key == "requested") end }`, building the
  data in `view` as Moonframe's lists do.
- `components/row.luau` returns `component { build = function(props) ... }`
  if it should be portable; returning its table of functions still works
  here.
- Icons: `arrow.triangle.pull` and the other SF Symbols still draw on
  MoonSwift. For a mod meant to run on Moonframe too, use the shared names
  (`git-pull-request`, `git-merge`, `circle-x`, `clock`, `eye`, `laptop`).
- `gap = 8` and other point gaps still work here; `gap = "normal"` is the
  portable spelling.
- `PullRequestsProvider` itself needs no change: it already publishes plain
  data as `app.pulls` and answers `provider:pulls`. Mods can now also
  subscribe to `provider/pulls` to react to a publish in `update`.
