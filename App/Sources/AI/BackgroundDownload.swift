import BackgroundTasks
import Foundation
import os
import UIKit

/// Keeps the model's first download going when the author leaves the app:
/// iOS's continued processing task, which starts from the author's action
/// (opening the companion) and shows the download in a Live Activity, where
/// they can also cancel it. The download itself is unchanged; this only feeds
/// iOS its progress so the app keeps running until it's done.
@MainActor
enum BackgroundDownload {
    /// Listed in Info.plist (BGTaskSchedulerPermittedIdentifiers).
    private static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "com.tecn01r.worldeditor") + ".companion-download"
    }
    private static var registered = false
    private static var task: BGContinuedProcessingTask?
    private static var latest: Download?
    /// Stops the download: cancelled from the Live Activity, or iOS ended the task, while
    /// the author was away.
    static var onCancel: (() -> Void)?

    /// The download moved on (`nil`: it ended). Starts the task with a real
    /// download, keeps its progress current, and ends it with the download.
    static func update(_ download: Download?) {
        let started = latest == nil && download.map { $0.done < $0.total } == true
        latest = download
        if started { begin() }
        guard let task else { return }
        guard let download else {
            task.setTaskCompleted(success: true)
            self.task = nil
            return
        }
        task.progress.totalUnitCount = download.total
        task.progress.completedUnitCount = download.done
        task.updateTitle(task.title, subtitle: download.detail)
    }

    private static func begin() {
        if !registered {
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
                guard let task = task as? BGContinuedProcessingTask else { return }
                MainActor.assumeIsolated {
                    guard latest != nil else { task.setTaskCompleted(success: true); return }   // already done
                    self.task = task
                    // Cancelled from the Live Activity, or ended by iOS: the task is told it's
                    // done (iOS may close an app that doesn't), and if the author is away from
                    // the app, the download stops too, as it can't go on there anyway.
                    task.expirationHandler = {
                        Task { @MainActor in
                            self.task?.setTaskCompleted(success: false)
                            self.task = nil
                            if UIApplication.shared.applicationState != .active { onCancel?() }
                        }
                    }
                    update(latest)
                }
            }
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier, title: "Companion Download",
            subtitle: latest?.detail ?? "A one-time download")
        // Off the main thread, as iOS asks, saying why when it can't.
        Task.detached {
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
            } catch {
                Logger(subsystem: "com.tecn01r.worldeditor", category: "companion")
                    .error("The download's background task couldn't start: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
