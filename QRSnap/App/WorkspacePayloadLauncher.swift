import AppKit

/// A session-scoped OS adapter. The predicate is checked at the actual workspace
/// calls as well as by PayloadDispatcher. It must not claim an opening gate itself.
@MainActor public final class WorkspacePayloadLauncher: PayloadLaunching {
    private let workspace: NSWorkspace
    private let isCurrent: @MainActor () -> Bool

    public init(isCurrent: @escaping @MainActor () -> Bool, workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        self.isCurrent = isCurrent
    }

    public func handler(for url: URL) -> HandlerMetadata? {
        guard !Task.isCancelled, isCurrent(),
              let applicationURL = workspace.urlForApplication(toOpen: url) else { return nil }
        let name = FileManager.default.displayName(atPath: applicationURL.path)
        return HandlerMetadata(name: name, applicationURL: applicationURL)
    }

    public func open(_ url: URL) async -> LaunchResult {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.addsToRecentItems = false
        return await withCheckedContinuation { continuation in
            guard !Task.isCancelled, isCurrent() else {
                continuation.resume(returning: .failure(.launchFailed))
                return
            }
            workspace.open(url, configuration: configuration) { application, error in
                // Only immutable result data crosses the callback boundary. Do not
                // log the destination, payload, or potentially sensitive OS error.
                let result: LaunchResult = error == nil && application != nil
                    ? .handoffSucceeded : .failure(.launchFailed)
                continuation.resume(returning: result)
            }
        }
    }
}
