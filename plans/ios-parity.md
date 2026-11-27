# iOS parity: everything Sheprd iOS does, in Luau

The goal: MoonSwift can express every screen of the Sheprd iOS app
(`~/code/herdr-gpui/ios`, about 230 shipping Swift files) in Luau, as fast as
the same screen written in SwiftUI. We don't port Sheprd; we make MoonSwift
able to. The proof is one real screen, Home, rebuilt in Luau and shown beside
the original in light and dark.

## 1. What Sheprd iOS is made of

Four tabs on iPhone (Home, Workspaces, PRs, Settings), each with its own
`NavigationStack`; on iPad a hand-built `HStack` with a 360 pt sidebar (a
`TabView` of `List(selection:)`, `.sidebar` style) and a detail column. About
30 pushed screens, 20 sheets, 3 full-screen covers, 1 popover. iOS 26 only:
Liquid Glass, `Tab(...)`, `WebView`.

| Screen | How it's reached | What it needs |
| --- | --- | --- |
| Home (sessions) | tab | List with folding sections, lazy rows, swipe both edges, context menu, search (drawer, always), refresh, toolbar menus with pickers and toggles, confirm dialog, alert, empty states, tab badge, relative times |
| Workspaces | tab | inset-grouped List, section index, header menus, context menu, search, refresh, toolbar |
| PRs | tab | inset-grouped List, search, refresh, context menu with ShareLink, sort menu, empty and loading states |
| Settings | tab | List of sections of `NavigationLink(value:)` rows, menu pickers, footers, `LabeledContent` |
| Chat | push | ScrollView + LazyVStack anchored at the bottom, glass overlays, principal toolbar title, 3 sheets with detents, markdown, composer (native), effects (native) |
| Terminal | push | native: server-drawn cells, UIKit keyboard, selection, zoom |
| Workspace | push | List with sections, grid of big buttons, rename alert with a text field, confirm dialog, `numericText` |
| Changes, file diff | push | segmented picker, DisclosureGroup, refresh, big scrolling text (native) |
| Computer, Settings pages (about 12) | push | List/Form, Toggle, Picker (menu, segmented, inline), TextField, SecureField, swipe, refresh, EditButton/onMove, LazyVGrid |
| Pair, New workspace/chat/project, Session, Question, Brief, Voice, Link browser, Write text, GitHub sign-in, Send log | sheet | NavigationStack + Form in a sheet, cancel/confirm toolbar items, detents, TextEditor, QR scanner (native), web view (native) |
| Image viewer, camera | cover | paging TabView, zoom (native), camera (native) |
| Sync list | popover | compact adaptation to popover |

Counts across the shipping app (grep, upper bounds): Section 149, ForEach
152, Image(systemName:) 153, Label 101, toolbar items 56 (topBarTrailing 21,
topBarLeading 12, cancellation 12, confirmation 8, principal 3, bottomBar 2),
ProgressView 50, NavigationStack 34, List 33, ScrollView 29, NavigationLink
25, TextField 23, ContentUnavailableView 23, LabeledContent 21, Toggle 21,
Picker 20 (segmented 5, menu 4, inline 2, navigationLink 1), sheet 19, Menu
19, navigationDestination 18, Link 15, alert 12, contextMenu 12, Form 9,
refreshable 9, confirmationDialog 8, TimelineView 7, searchable 6, swipeActions
4 (+3 helpers), DisclosureGroup 4, ShareLink 4, LazyVGrid 4, fullScreenCover 3,
Canvas 3, SecureField 2, TextEditor 1, Slider 1, popover 1. No Map, no
AsyncImage, no NavigationSplitView (iPad is hand-built), no Stepper or
DatePicker.

There is no central theme: system semantic colors (`.secondary`, `.tint`,
`.fill.secondary`, `.background.secondary`), Dynamic Type styles (caption 143,
subheadline 103, footnote 50, headline 27), `.monospacedDigit()`, glass
buttons (`.glass` 31, `.glassProminent` 16) and glass cards.

## 2. Elements, modifiers and overlays, by how many screens they unblock

Status: ✅ built and tested, ◐ built, needs work, ☐ to do.

| Rank | SwiftUI | Screens | Luau | Status |
| --- | --- | --- | --- | --- |
| 1 | List, Section | ~30 | `ui.list { variant = "inset", ui.section { "Pinned", footer = ..., ... } }`; lazy rows: `rows = keys, row = "name"` draws `views.name(state, key, app)` per visible row | ✅ |
| 2 | toolbar, ToolbarItem, ToolbarSpacer | ~25 | `toolbar = { ui.button { icon = "plus", place = "trailing", msg = ... }, ui.menu {...}, ui.spacer { place = ... } }` | ✅ |
| 3 | NavigationStack, NavigationLink(value:), navigationDestination, navigationTitle | ~22 | `ui.stack { path = state.path, change = "path", screen = "screen", <root> }`, `ui.link { route = {...}, <label> }`, `title = "..."`, `titleMode = "inline"` | ✅ |
| 4 | ContentUnavailableView | 16 | `ui.unavailable { "No chats", icon = ..., description = ..., <actions> }`, `variant = "search"` | ✅ |
| 5 | ProgressView | ~15 | `ui.progress { value = 0.4, variant = "linear", label = ... }` | ✅ |
| 6 | Toggle, TextField, SecureField, TextEditor | ~12 | `ui.toggle`, `ui.input { multiline = true }`, `ui.secure`, `ui.editor` | ✅ |
| 7 | sheet (+ detents), fullScreenCover, popover | ~12 | `sheet = { open = ..., dismiss = msg, detents = { "medium", "large" }, <content> }`, `cover = {...}`, `popover = {...}` | ✅ |
| 8 | Picker (segmented, menu, inline, navigationLink, palette) | ~10 | `ui.picker { "Sort", value = ..., change = ..., options = {...}, variant = "segmented" }` | ✅ |
| — | ViewThatFits, toggle and tab styles, sheet sizing, scroll to, keys, appearance | several | `ui.fits`, `variant = "button"` / `"page"`, `sizing = "page"`, `scrollTo = key`, `shortcut = "cmd+n"`, `scheme = "dark"` | ✅ |
| — | overlays on any element, rotation | Home rows | `overlay = { place = "bottomTrailing", x = 6, y = 6, <element> }`, `rotate = 90` | ✅ |
| 9 | LabeledContent | 9 | `ui.labeled { "Version", value = "1.0", iconView = <tile> }` | ✅ |
| 10 | Form | 8 | `ui.form { ui.section {...} }` | ✅ |
| 11 | refreshable | 8 | `refresh = msg`, spinner held while the view says `refreshing = true` | ✅ |
| 12 | alert (with text fields), confirmationDialog | 8 + 6 | `alert = { open, title, message, dismiss, ui.button { role = "destructive" }, ui.input {...} }`, `confirm = {...}` | ✅ |
| 13 | contextMenu, Menu | 7 + 16 | `context = { ui.button {...}, ui.divider {}, ui.menu {...}, ui.picker {...}, ui.toggle {...} }`, `ui.menu { "More", icon = ..., msg = primary }` | ✅ |
| 14 | searchable | 5 | `search = { value, change, prompt, submit, placement = "always" }` | ✅ |
| 15 | ScrollView + LazyVStack/LazyVGrid | ~8 | `ui.scroll { anchor = "bottom", rows = ..., row = ... }`, `ui.grid { min = 92 }` | ✅ |
| 16 | swipeActions | 4 | `swipe = { leading = {...}, trailing = { ui.button { "Close", icon = "xmark", role = "destructive", tint = "red" } } }` | ✅ |
| 17 | TabView / Tab with badge | 2 roots | `ui.tabs { selection, change, ui.tab { "Home", icon = "house", badge = 1, <content> } }` | ✅ |
| 18 | DisclosureGroup, collapsible Section | 4 + Home | `ui.disclosure { "Steps", expanded, change }`, `ui.section { collapsed = ..., change = ... }` | ✅ |
| 19 | ShareLink | 4 | `ui.share { url = ..., text = ..., label = ... }` | ✅ |
| 20 | TimelineView for times | 7 | `ui.text { date = t, format = "relative" | "timer" | "ago" }`, the system keeps it current | ✅ |
| 21 | List selection (iPad sidebar) | 1 | `ui.list { selection = ..., change = ... }`, rows tagged by key | ✅ |
| 22 | EditButton, onMove, onDelete | 2 | `ui.section { move = msg, delete = msg }`, `ui.edit {}` | ✅ |
| 23 | NavigationSplitView | 0 (iPad hand-built) | `ui.split { <sidebar>, <detail> }` | ✅ |
| 24 | glassEffect, glass buttons | many | style `glass = true`; `variant = "glass" | "prominentGlass"` | ✅ |
| 25 | contentTransition(.numericText), transition | 3 + 19 | `numeric = true`, `transition = "bottom"` | ✅ |
| 26 | safeAreaInset, overlay | 8 + 40 | `inset = { edge = "bottom", <element> }`, `overlay = { place = "top", <element> }` | ✅ |
| 27 | focus, onSubmit | 4 | `submit = msg`, `focus = true`, `blur = msg` | ✅ |
| 28 | list row insets, backgrounds, separators | Home answer cards | `rowInsets = { top = 4 }`, `rowBackground = "clear"`, `separator = false` | ✅ |
| 29 | section index | Workspaces | `index = "A"` on sections, `indexed = true` on the list | ✅ |
| 30 | symbolEffect, haptics | 7 + 17 | `effect = "pulse"`; `provider:system { haptic = "success" }` | ✅ |

Fonts and colors: rules take `font` (a Dynamic Type style), `weight`,
`design`, `size`; color names fall back to the system's (`secondary`,
`tertiary`, `tint`, `red`... `grouped`, `fill`, `separator`), so a screen needs
no stylesheet to look native. A text with no font set inherits the system's,
as SwiftUI does.

## 3. Native capabilities

Luau stays sealed. What reaches the machine is Swift the app links, in three
kinds.

**Providers** publish plain data as `app.<name>` to mods that list them in
`providers = { ... }`, and take requests sent to `provider:<name>`; answers
come back as messages. Only mods that read a provider redraw when it changes.

| Provider | Data | Requests |
| --- | --- | --- |
| `home` | the fleet's machines, their workspaces with chats and terminals, waiting and working counts, link status | `favorite`, `read`, `close`, `summarize`, `refresh` |
| `chat` (per pane) | the reduced transcript (the reducer stays in Swift), status, plan, queue, outgoing sends | `prompt`, `answer`, `unqueue`; streamed `append`s as messages, not whole snapshots |
| `term` (per pane) | meta: panes, label, prompt | `split`, `zoom`, `tab`, `close`, `rename`, `convert` |
| `changes`, `github`, `search` | request and answer | |
| `settings` | a whitelist of `@AppStorage` keys | `set` |
| `relays`, `nearby`, `computers`, `notifications` | lists and status | add, forget, dismiss |
| `system` | scene phase, size class, appearance | `haptic`, `copy`, `open`, `share` |

**Native elements**: `ui.native { "terminal", pane = ... }`, registered by
the app with `NativeViews.register`. For what runs at frame rate or owns
UIKit: the terminal and its keyboard, the markdown renderer, the composer,
message effects, the web view, image zoom, the QR scanner, big diffs, the
voice sheet.

**Stays native**: widgets, controls and Live Activities (other processes,
archived SwiftUI), the Watch app, the share and notification extensions,
App Intents, Siri and Spotlight (declared at compile time), the keychain,
Secure Enclave keys, App Attest, TLS pinning, the relay tunnel, pairing, APNs
and ActivityKit tokens, Face ID and the app lock, background Bluetooth, the
cache and message index. Luau sees their outcome through providers.

## 4. Performance

### Benchmarks, defined before building

| # | What | How | Budget |
| --- | --- | --- | --- |
| B1 | Scroll a 10k-row List at 120 Hz | `just ios-bench` on a ProMotion device: XCUITest flicks the list with `XCTOSSignpostMetric.scrollDecelerationMetric`, Luau screen against the same screen in SwiftUI (`MOONSWIFT_BENCH=luau|swiftui`) | hitch ratio within 1 ms/s of SwiftUI's, no frame over 8.3 ms that SwiftUI doesn't drop too |
| B2 | Rebuild per keystroke | headless (`just bench`): a search keystroke on 10k rows runs `update`, `view`, reads the tree, digests it | under 2 ms optimized (a quarter frame), within 2× of the same filter in Swift |
| B3 | Rows after a state change | headless: 30 visible rows redrawn after an update | under 1 ms optimized; cached rows free |
| B4 | Cold start | headless: load and first view of a 10k-item mod and of the bundled app; on device, `XCTApplicationLaunchMetric` | under 10 ms headless; launch within 50 ms of SwiftUI's |
| B5 | Memory | the VM's bytes for 10k items; on device `XCTMemoryMetric` against SwiftUI | under 8 MB headless |

Headless results, Apple silicon laptop, `-c release` (2026-11-26):

```text
keystroke, 10k rows        luau 1.15 ms   swift 0.87 ms   ×1.3
30 rows after a change     luau 1.59 ms   (includes the keystroke's update and view; rows alone ≈0.4 ms)
cold start, 10k items      luau 5.04 ms   swift 0.97 ms
cold start, bundled app    luau 2.10 ms
memory, 10k items          luau 3.2 MB    swift 0.6 MB
```

### How the design gets there

- **Lazy rows.** A list's `rows` is a list of keys; a row is drawn by
  `views.<row>(state, key, app)` only when SwiftUI shows it. A 10k-row view
  returns one array, not 10k tables, and scrolling calls Luau once per row
  that comes into view.
- **Digests.** Every checked node carries a hash of its subtree. Comparing a
  new tree with the last costs one integer, and `NodeView` is `Equatable` on
  it, so SwiftUI skips every subtree that didn't change without walking it.
- **One mod, one observation.** Each mod's tree lives in its own observable
  `Drawing`; an update redraws the views of that mod only, never the window.
- **Generations.** Rows and screens are cached per mod until its state
  changes; after a change only the visible rows are asked again, and a row
  that comes out the same stops at its digest.
- **No cost for what isn't used.** Box modifiers (padding, background,
  border, glass, shadow), hover tracking and the decorations apply only when
  set, so a plain text in a row is a plain `Text`.
- **Native containers.** Lists, forms, stacks and tabs are the system's own,
  with their cell reuse and prefetching; MoonSwift never draws a list itself.

Lessons from the proof: a `Spacer` only spaces when a stack sees it bare,
so children that are spacers are never wrapped (not even in `.equatable()`);
a list row's chrome (`listRowInsets`...) is applied where the row is made.

On a simulator (iPhone 17 Pro Max, both optimized, `just ios-bench`), five
flicks of 10,000 rows:

```text
metric                       luau        swiftui     ratio
CPU time                     0.370 s     0.372 s     ×1.00
CPU instructions retired     1.21 G      1.16 G      ×1.04
Scroll deceleration          2.434 s     2.433 s     ×1.00
Memory, peak                 58.7 MB     38.0 MB     ×1.55
```

The simulator reports no hitch ratio; that needs a device. The memory was
180 MB before a fix: a row whose list traits (`swipeActions`, `badge`,
`listRowInsets`) sat behind an `if` made SwiftUI build all 10,000 rows to read
them. Row traits are now always applied, with the system's defaults when
unset, outside a single-view wrapper. The remaining 20 MB is the Luau state,
the keys and the row cache.

Still to do for B1: cache stylesheet resolution per node digest; keep the
inspector's geometry tracking out of the measured build (it's beta only);
measure on a device.

## 5. Build order

1. ✅ Runtime: digests, per-mod drawings, lazy `views`, providers, benchmarks.
2. ✅ Navigation: `stack`, `link`, `tabs`, `split`, titles.
3. ✅ Lists: `list`, `section` (folding), lazy rows, selection, swipe,
   context menu, refresh, search.
4. ✅ Forms and controls: `form`, `picker`, `stepper`, `secure`, `editor`,
   `menu`, `disclosure`, `progress`, `unavailable`, `label`, `image`, `grid`,
   `scroll`.
5. ✅ Overlays: `sheet`, `cover`, `popover`, `alert`, `confirm`; toolbar.
6. ✅ Providers: the protocol; `system` (haptics, copy, idiom) in MoonUI;
   `DemoHome` serves Sheprd's demo data as `home`. Sheprd's real ones
   (`home`, `chat`...) belong to the app that links MoonSwift. `app.phase`
   follows the scene. No `open` or `paste`: either would give sealed Luau a
   way out.
7. ✅ Settings rebuilt too: the hub, a menu picker that switches the
   app's appearance, a form page, and Terminal Keys with edit mode;
   `docs/parity/settings-light.png`, `settings-dark.png`. `ExampleTests`
   drive both with real taps.
8. ✅ Proof: Home rebuilt in Luau (`examples/sheprd`, about 400 lines),
   beside the original, light and dark: `docs/parity/home-light.png`,
   `docs/parity/home-dark.png`. Same bars, search, folding sections, rows,
   pills, badges, answer card, timer and tab badge; the agent tiles use SF
   Symbols where Sheprd has brand marks. `just example sheprd` runs it.
9. ✅ Workspaces rebuilt: computer headers with load gauges, fold and an
   actions menu with a toggle and a confirm, repository sections with letter
   avatars, workspace rows with status marks, uncommitted and PR pills;
   `docs/parity/workspaces-light.png`.
10. ✅ PRs, as the demo shows it (no GitHub account): the empty state, sort
    menu and search; its button switches tab and pushes Settings › GitHub,
    as navigation is only state. `docs/parity/prs-light.png`. All four tabs
    now match the original.
11. ☐ Next: the chat screen with `ui.native`
   markdown and composer, hitch ratio on a device.

Live editing stays in MoonLive only, and `just store-audit` keeps passing.

## 6. Sandbox notes

Luau has no network, and no element may give it one: `ui.image { url }`
loads only over HTTPS from hosts the app lists in `imageHosts` (none by
default), since a fetch would carry whatever a mod puts in the address.
`ui.link { url }` opens only `https`, `http` and `mailto`, and only on a tap.
