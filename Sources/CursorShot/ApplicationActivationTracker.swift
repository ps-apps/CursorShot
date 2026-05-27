import AppKit
import Foundation

@MainActor
final class ApplicationActivationTracker {
    private let workspace: NSWorkspace
    private var observer: NSObjectProtocol?
    private var orderedPIDs: [pid_t] = []

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        record(workspace.frontmostApplication)
        DebugLog.write("activation tracker init frontmost=\(describe(workspace.frontmostApplication)) order=\(orderedPIDs)")
    }

    func start() {
        guard observer == nil else {
            return
        }

        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                self?.record(app)
            }
        }
        DebugLog.write("activation tracker started")
    }

    func stop() {
        if let observer {
            workspace.notificationCenter.removeObserver(observer)
        }
        observer = nil
        DebugLog.write("activation tracker stopped")
    }

    func markCurrent(pid: pid_t) {
        record(pid: pid)
        DebugLog.write("activation tracker markCurrent pid=\(pid) order=\(orderedPIDs)")
    }

    func preferredNextOwnerPIDs(after currentPID: pid_t) -> [pid_t] {
        let pids: [pid_t] = orderedPIDs.compactMap { pid -> pid_t? in
            guard pid != currentPID,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  NSRunningApplication(processIdentifier: pid) != nil else {
                return nil
            }

            return pid
        }
        DebugLog.write("activation tracker preferredNext after=\(currentPID) result=\(pids) order=\(orderedPIDs)")
        return pids
    }

    private func record(_ app: NSRunningApplication?) {
        guard let app else {
            return
        }

        record(pid: app.processIdentifier)
    }

    private func record(pid: pid_t) {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        orderedPIDs.removeAll { $0 == pid || NSRunningApplication(processIdentifier: $0) == nil }
        orderedPIDs.insert(pid, at: 0)
    }

    private func describe(_ app: NSRunningApplication?) -> String {
        guard let app else {
            return "nil"
        }

        return "pid=\(app.processIdentifier) active=\(app.isActive) hidden=\(app.isHidden)"
    }
}
