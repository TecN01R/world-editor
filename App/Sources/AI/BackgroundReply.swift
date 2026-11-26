import BackgroundTasks
import Foundation
import os
import UIKit

/// Keeps a reply going when the author leaves the app (Kevin, 2026-11-26: "absolutely yes"):
/// iOS's continued processing task with the GPU, which the Duo offers
/// (`BGTaskScheduler.supportedResources`; Apple has said no earlier iPhone does). It starts
/// with the reply the author asked for, as iOS requires, and shows in a Live Activity, where
/// they can also stop it. Without it (the phone doesn't offer the GPU, the app lacks the
/// entitlement, or iOS ends it), a reply waits for the author to come back, as before.
enum BackgroundReply {
    /// Listed in Info.plist (BGTaskSchedulerPermittedIdentifiers).
    private static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "com.tecn01r.worldeditor") + ".companion-reply"
    }
    /// Only under `state`'s lock (iOS's task object isn't marked Sendable).
    private struct State: @unchecked Sendable {
        var task: BGContinuedProcessingTask?
        /// The reply under way, or nil: a task that starts after its reply ended finishes at once.
        var reply: UUID?
        var written: Int64 = 0
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())
    @MainActor private static var registered = false
    private static let log = Logger(subsystem: "com.tecn01r.worldeditor", category: "companion")

    /// The reply's task is running, so the reply keeps the GPU while the app is away.
    static var isRunning: Bool { state.withLock { $0.task != nil } }

    /// A reply begins: asks iOS to let it run on if the author leaves. Returns its id, for `end`.
    @MainActor static func begin() -> UUID? {
        guard BGTaskScheduler.supportedResources.contains(.gpu) else { return nil }
        let reply = UUID()
        // A reply this one replaces (asked again, another page) may not have ended yet: its task ends now.
        take(new: State(reply: reply))?.setTaskCompleted(success: true)
        if !registered {
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
                guard let task = task as? BGContinuedProcessingTask else { return }
                let live = state.withLockUnchecked { state -> Bool in
                    guard state.reply != nil else { return false }
                    state.task = task
                    return true
                }
                guard live else { task.setTaskCompleted(success: true); return }   // the reply is done already
                trialLog("BACKGROUND REPLY: started")   // TRIAL
                task.progress.totalUnitCount = 1000
                // Stopped from the Live Activity, or ended by iOS: a reply the author is away
                // from then waits for them, as before (`isRunning` is false).
                task.expirationHandler = {
                    trialLog("BACKGROUND REPLY: ended by iOS or the author")   // TRIAL
                    finish(success: false)
                }
            }
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Companion",
                                                       subtitle: "Writing its reply")
        request.requiredResources = .gpu
        request.strategy = .fail   // now or never: a reply later is no use
        // Off the main thread, as iOS asks, saying why when it can't.
        Task.detached {
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
            } catch {
                log.error("The reply's background task couldn't start: \(String(describing: error), privacy: .public)")
                trialLog("BACKGROUND REPLY: couldn't start: \(String(describing: error))")   // TRIAL
            }
        }
        return reply
    }

    /// The reply read or wrote some more: iOS ends a task whose progress stands still. A reply's
    /// length isn't known, so each step counts one, stopping short of the whole until it ends.
    static func progressed() {
        state.withLock { state in
            state.written += 1
            guard let progress = state.task?.progress else { return }
            progress.completedUnitCount = min(state.written, progress.totalUnitCount - 1)
        }
    }

    /// `reply` is done: its task, if it started, ends (unless a newer reply has taken over).
    static func end(_ reply: UUID?) {
        guard let reply else { return }
        take(if: reply)?.setTaskCompleted(success: true)
    }

    private static func finish(success: Bool) {
        take()?.setTaskCompleted(success: success)
    }

    /// The running task, if any, leaving `new` in its place: all of it, or nothing when the
    /// reply under way isn't `reply`, in one hold of the lock.
    private static func take(if reply: UUID? = nil, new: State = State()) -> BGContinuedProcessingTask? {
        state.withLockUnchecked { state in
            guard reply == nil || state.reply == reply else { return nil }
            let task = state.task
            state = new
            return task
        }
    }
}
