# Moonframe's WebAssembly providers on iOS

A Moonframe provider is a Rust crate behind a small WIT world
(`wit/provider.wit` in Moonframe): the host gives it `log`, `system-load` and
`host-call`, and it exports `start(settings)`, `tick()`, `receive(message)`,
and `save`/`restore` to keep state across builds. Data crosses as JSON.
MoonSwift's `Provider` protocol is the same shape (`start`, `receive`,
`link.publish`), so the gap is only in running the crate's code.

## What iOS rules out

- **No JIT.** iOS won't map pages writable then executable without an
  entitlement Apple only grants to browsers. Wasmtime's Cranelift, which
  Moonframe uses, compiles to machine code at run time, so it can't run.
  Code that was compiled ahead of time to native and then loaded at run time
  can't run either: the pages it needs are not signed.
- **No downloaded code in the store build.** App Review guideline 2.5.2 bars
  downloading code that adds features. Code that ships in the bundle, even
  interpreted, is fine. This is the rule that already keeps MoonLive out of
  the store build.
- **No processes.** A provider whose `host-call` capabilities run `git` or
  read the user's files has nothing to run on a phone.

## Three ways, by what the provider does

### A. Compiled in, for the store (recommended default)

Moonframe already builds a provider either way (`examples/portable`):
`kind = "wasm"` or `kind = "native"`, the same crate behind
`Portable::<T>`. For iOS, build that crate natively for
`aarch64-apple-ios` and the simulator as a static library, and link it into
the app.

- A shim crate, `moonframe-provider-ffi`, wraps `Portable<T>` in a C ABI:
  `create(name, settings_json)`, `tick`, `receive(json)`, `save`, `restore`,
  `free`, plus the host's `log` and `host_call` as function pointers that
  Swift fills in.
- On the Swift side, `NativeProvider: Provider` calls `tick` on the
  provider's `interval`, publishes the JSON through `ProviderLink` as a
  `LuauValue`, and passes `receive` messages through. It needs a JSON ⇄
  `LuauValue` helper in MoonKit.
- `system-load` and the registered capabilities map to Swift: a capability
  is a Swift closure the app registers by name, as `NativeViews` does for
  views.
- Speed is native. Apple reviews the code with the app, and the binary grows
  by the crate alone. A new build of the provider needs a new build of the
  app.

### B. Interpreted, for the beta and live work

Wasmtime has a portable interpreter backend, Pulley. It runs a component
compiled ahead of time to Pulley bytecode, which is data rather than machine
code, so it needs no JIT and no executable pages. It also keeps the
component model, which WAMR and wasm3 don't support.

- On the Mac: `wasmtime compile --target pulley64` (or
  `Engine::precompile_component` with that target), right after Moonframe
  builds the `.wasm`.
- On the phone: `Component::deserialize` on an engine configured for
  Pulley, with the same `moonframe:provider` bindings Moonframe's host uses,
  in a Rust static library behind the same C ABI as A. The Swift side is
  `NativeProvider` again.
- The `.cwasm` travels like a Luau edit does in the beta: over Sheprd's
  relay, so a provider rebuilds and reloads on the phone live, with
  `save`/`restore` keeping its state.
- Pulley is several times slower than native, which is fine for a
  provider's ticks and messages. It adds a few MB of wasmtime to the binary.
  It goes in the beta only, beside MoonLive, behind a `store-audit` marker,
  because downloaded code is what 2.5.2 forbids. A store build could still
  run `.cwasm` files that ship in its bundle.

### C. On the Mac, mirrored to the phone

Most of Moonframe's providers describe the Mac: `git`, `files`, terminals,
agents, usage. On a phone they mean the paired computer's data, not the
phone's, so they shouldn't run there at all. A `RemoteProvider: Provider`
named like the desktop one (`git`) publishes what the Mac's Moonframe
publishes, carried over Sheprd's encrypted relay, and forwards
`provider:git` messages back to it. The mod is the same file on both, and
`app.git` simply comes from farther away. This is the model Sheprd's
`home` and `pulls` providers already follow.

## Order

1. C first. It is where most desktop mods' data comes from, and it needs no
   new runtime: a JSON ⇄ `LuauValue` codec and a relay channel.
2. A for pure-compute providers (formatting, parsing, scoring), starting
   with Moonframe's `examples/portable` focus timer as the proof, run in a
   conformance case on both hosts.
3. B when live provider editing on a phone is worth a few MB in the beta.

The mod never knows which way was used: it reads `app.<name>`, subscribes to
`provider/<name>`, and sends to `provider:<name>`, as it does on the desktop.
