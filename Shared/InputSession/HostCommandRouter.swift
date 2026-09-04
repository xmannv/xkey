import Foundation

struct HostCommandRouter<Context> {
    typealias Handler = (HostCommand, Context) -> HostCommandResult

    private let capabilities: HostCapabilities
    private let handler: Handler
    private let log: (String) -> Void

    init(capabilities: HostCapabilities,
         handler: @escaping Handler,
         log: @escaping (String) -> Void = { _ in }) {
        self.capabilities = capabilities
        self.handler = handler
        self.log = log
    }

    @discardableResult
    func route(_ command: HostCommand, context: Context) -> HostCommandResult {
        guard capabilities.supports(command.requiredCapability) else {
            let reason = capabilities.unsupportedReason(for: command.requiredCapability)
                ?? "capability unavailable"
            log("Unsupported host command: \(command.rawValue) — \(reason)")
            return .unsupported
        }

        let result = handler(command, context)
        if result != .handled {
            log("Host command \(command.rawValue) was not handled: \(result)")
        }
        return result
    }
}

extension HostCommandRouter where Context == Void {
    init(capabilities: HostCapabilities,
         handler: @escaping (HostCommand) -> HostCommandResult,
         log: @escaping (String) -> Void = { _ in }) {
        self.init(capabilities: capabilities,
                  handler: { command, _ in handler(command) },
                  log: log)
    }

    @discardableResult
    func route(_ command: HostCommand) -> HostCommandResult {
        route(command, context: ())
    }
}
