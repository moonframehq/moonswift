# MoonSwift

A proof of concept of [Moonframe](../moonframe)'s idea in Swift: a native macOS
app whose whole window is written in [Luau](https://luau.org) and reshapes
itself while it runs. Swift and SwiftUI draw it, check it and keep it safe;
every panel and row is a Luau file that reloads as you save, with its state kept.

## Run it

Needs Xcode 26+, `just`, and `xcodegen`.

```sh
just run      # opens the app on ./app, reloading as you save
just ci       # lint, Luau check, unit tests, Mac smoke, iOS builds, store audit
```

Then press **+** a few times, change `app/mods/counter/main.luau` or the accent in
`app/style.luau` in any editor, and watch the window follow with the count kept.
Save a syntax error: the window keeps the last good version and says why.

## Three apps, one codebase

| Target | Platform | Live editing | Goes to |
| --- | --- | --- | --- |
| `MoonSwift` | macOS | yes | Developer ID, outside the App Store |
| `MoonSwiftBeta` | iOS | yes | **internal** TestFlight only |
| `MoonSwiftStore` | iOS | no | the App Store |

App Review guideline 2.5.2 bars code that changes what an app does, and 2.5.19
bars dormant features, so live editing can't just be switched off in a store
build: it has to be absent. Everything that changes the app while it runs lives
in the `MoonLive` library, which `MoonSwiftStore` doesn't link. `just store-audit`
proves it on the Release binaries, and checks the beta for the same markers so
that a blind audit fails instead of passing. The beta has its own bundle ID, so
it can't be promoted to the App Store by mistake.

External TestFlight goes through review under the same guidelines: don't send
the beta there. Luau layouts stay in the store app, bundled and fixed.

The same Luau runs on all three: `app.window.width` gives a phone its layout.

## The sparkle

The ✨ in the toolbar (⇧⌘X, or ⌥⌘I) picks anything in the window, like a
browser's developer tools; ↑ and ↓ step to the elements around it, Esc stops. On
iOS, drag to aim and lift to pick. The card names the file and line that drew it, its props, and the elements around
it, and holds that file's source: **what you type there applies live**. The pick
is also saved to `~/.cache/moonswift/selection.md`, for an agent to act on.

On the Mac, the card also asks an agent: pick an element, say what should change,
and watch the window follow. It runs `claude -p` and carries the conversation
across requests. If an edit breaks the app, the error goes back to the agent once.
iOS can't start processes, so this is Mac only.

Text in the app can steer an agent, so its limits are set at launch, not in the
prompt: `--restricted` confines it to the app's folder with no command tools, and
an allowlist lets it change `.luau` files and nothing else. Without that, writing
`.claude/settings.json` would become code execution on the next run.

The sparkle belongs to the host, not to Luau, so no script can break it.

## How it fits together

```text
app/                       the app itself, in Luau
  main.luau                the shell: lays out the window
  style.luau               colors and rules by element type (`panel`) or class (`.hero`)
  mods/<name>/main.luau    a mod: init, update, view, like an Elm program
  components/<name>.luau   shared pieces, `component { build }`, with `use "name"`
conformance/               mods both MoonSwift and Moonframe must draw alike
MoonSwift/                 the entry point of all three apps, and the Mac self-drive
iOSTests/                  real taps on the beta, in a simulator
Packages/MoonKit/
  Sources/CLuau            vendored Luau and moon.cpp, the seam to Swift
  Sources/MoonKit          headless runtime: VMs, mods, reloads, trees, styles
  Sources/MoonUI           draws trees in SwiftUI
  Sources/MoonLive         the sparkle, editor, watcher, writes: never in a store build
  Sources/moon             `moon check <folder>`
project.yml                generates MoonSwift.xcodeproj (`just generate`)
```

- **Mods.** Each runs in its own sealed VM: no files, network or processes, a
  64 MB cap and an instruction budget per call. They talk with sends and topics.
- **Reloads.** A changed file loads into a new VM, and `init` gets the old state.
  Only if that and its first `view` succeed does it replace the running mod.
- **Exceptions.** Luau raises C++ exceptions, which must never unwind through
  Swift, so everything that can raise lives in `moon.cpp`.
- **Your folder.** The installed app reads its bundled `app/` with
  `~/.config/moonswift` laid over it; edits land there, as in Moonframe.

## Elements

A mod is written as for Moonframe, the desktop host on GPUI: the same `mod { }`,
messages, topics, providers, stylesheet, icon names and shared elements, so it
loads on both. `plans/moonframe-compat.md` says what is shared, how each host's
own elements degrade on the other, and `app.renderer` and
`app.window.platform` let a layout pick. Moonframe's elements here: `item`,
`hsplit`, `vsplit`, `pane`, `popover`, `overlay`, `view`, `terminal`,
`browser`, and placeholders for the rest. MoonSwift's own follow.

Layout: `ui.row`, `column`, `panel`, `scroll`, `grid`, `fits`, `spacer`, `divider`.
Navigation and lists: `stack`, `link`, `tabs`, `tab`, `split`, `list`, `section`,
`form`, `disclosure`, `edit`. Content: `text`, `label`, `labeled`, `badge`, `icon`,
`image`, `progress`, `unavailable`. Controls: `button`, `input`, `secure`, `editor`,
`toggle`, `slider`, `stepper`, `picker`, `menu`, `share`. The host's: `region`,
`mount`, and `native` for views the app registers in Swift.

Anything can take `msg`, `class`, `style`, `grow` (`true`; here also `"x"`, `"y"`), `width`,
`height`, `padding`, `tooltip`, `key` or `id`, and asks the system around it with
props: `title`, `toolbar`, `search`, `refresh`, `swipe`, `context`, `badge`,
`overlay`, `inset`, `transition`, `sheet`, `cover`, `popover`, `alert`, `confirm`.

A list's `count` and `row = function(i)` draw rows only as they scroll in, as
in Moonframe: a 10,000-row list costs what the visible ones do. A stack's
`screen = function(route)` draws pushed routes the same way. `plans/ios-parity.md` maps
all of it to SwiftUI, and `examples/sheprd` uses most of it: `just example sheprd`.

## Providers

Native data and capabilities reach a mod through providers, Swift the app
links: a view reads `app.system` (nil until it first publishes) and redraws
when it publishes, a mod can hear each publish on the `provider/system` topic,
and it sends `provider:system` requests. `system` gives haptics, copying and the
device's idiom; an app adds its own with `workspace.attach(...)`.

## Testing

- `just test`: the runtime, including broken files, endless loops and the
  sandbox, and the conformance suite Moonframe runs too.
- `just smoke`: the debug Mac app drives itself with real mouse events, file
  changes and a scripted agent, and leaves pictures in `build/snapshots`. It lives in the app because
  XCUITest on macOS needs Automation Mode, which takes an admin's approval.
- `just smoke-agent`: the same with the real agent, which spends real tokens.
  `just smoke` uses `scripts/fake-agent.sh`, which breaks the app on purpose.
- `just ios-test`: real taps on the beta in a simulator, including
  `examples/sheprd`. Slow to start, so it's not in `just ci`.
- `just bench`: the headless benchmarks, optimized. `just ios-bench`: 10,000
  rows flicked in Luau and in SwiftUI, side by side.
- `just store-audit`: the store binary has no trace of live editing.

Luau is pinned by version and checksum in `scripts/vendor-luau.sh`.
