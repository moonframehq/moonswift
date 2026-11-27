/// Native data and capabilities for sealed Luau, as in Moonframe. A view
/// finds a provider's data as `app.clock`, nil until it first publishes, and
/// runs again whenever it publishes; a mod that subscribes to
/// `provider/clock` hears each publish in `update`. A mod asks a provider
/// for something by sending to `provider:clock`, and the answer comes back
/// as a message.
///
/// Providers are Swift the app links, so a store build has exactly the ones
/// it was reviewed with: Luau can only reach what they offer.
public protocol Provider: AnyObject {
    /// What mods call it: `app.<name>` and `provider:<name>`.
    var name: String { get }
    /// Called once, when the workspace takes it on.
    func start(_ link: ProviderLink)
    /// A message a mod sent to `provider:<name>`.
    func receive(_ message: LuauValue, from mod: String?)
}

extension Provider {
    public func start(_ link: ProviderLink) {}
    public func receive(_ message: LuauValue, from mod: String?) {}
}

/// A provider's way back into the workspace.
public final class ProviderLink {
    private weak var workspace: Workspace?
    private let name: String

    init(workspace: Workspace, name: String) {
        self.workspace = workspace
        self.name = name
    }

    /// Replaces what mods read as `app.<name>`, and redraws those that read it.
    public func publish(_ value: LuauValue) {
        guard let workspace, let slot = workspace.providers[name], slot.value != value else { return }
        slot.value = value
        slot.version += 1
        workspace.providerChanged(name)
    }

    /// Sends a message to a mod, or to `topic:<name>`.
    public func send(_ message: LuauValue, to mod: String) {
        workspace?.send(message, to: mod, from: "provider:\(name)")
    }
}

final class ProviderSlot {
    let provider: any Provider
    /// What it last published, nil before the first time.
    var value: LuauValue?
    /// Goes up with each publish, so a VM copies the data only when it changed.
    var version = 0

    init(provider: any Provider) {
        self.provider = provider
    }
}

extension Workspace {
    /// Takes `provider` on: mods can read and ask it from now on.
    public func attach(_ provider: any Provider) {
        providers[provider.name] = ProviderSlot(provider: provider)
        provider.start(ProviderLink(workspace: self, name: provider.name))
    }

    func deliverToProvider(_ queued: Queued) {
        let name = String(queued.send.to.dropFirst("provider:".count))
        guard let slot = providers[name] else {
            problems["provider:\(name)"] = Problem(file: "provider:\(name)", message: "no provider named \(name)")
            return
        }
        slot.provider.receive(queued.send.message, from: queued.from)
    }
}
