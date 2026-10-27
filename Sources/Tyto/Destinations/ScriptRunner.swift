import Foundation
import Synchronization
import TytoCore

/// Runs one destination script with NSUserUnixTask, the sanctioned way for a sandboxed app to
/// run the user's own code: it runs outside the sandbox, as the user, so the script has
/// ~/.ssh, ~/.aws and the login keychain while Tyto itself has none of them.
nonisolated enum ScriptRunner {
    struct Run: Sendable {
        var termination: ScriptTermination
        var stdout = Data()
        var stderr = Data()
    }

    /// A script that keeps writing gets this much of the start of stdout and the end of stderr,
    /// which is all the contract reads.
    static let keepBytes = 64 * 1024

    static func run(_ url: URL, arguments: [String], timeout: Duration) async -> Run {
        let task: NSUserUnixTask
        do {
            task = try NSUserUnixTask(url: url)
        } catch {
            return Run(termination: .failedToRun((error as NSError).localizedDescription))
        }
        return await withCheckedContinuation { continuation in
            let collector = Collector(continuation)
            task.standardOutput = collector.stdoutPipe.fileHandleForWriting
            task.standardError = collector.stderrPipe.fileHandleForWriting
            task.execute(withArguments: arguments) { error in
                if let error = error as NSError? {
                    let reason = error.localizedFailureReason ?? error.localizedDescription
                    collector.exited(.from(errorReason: reason))
                } else {
                    collector.exited(.exited(0))
                }
            }
            // NSUserUnixTask cannot stop a script. After this Tyto stops listening, and once the
            // pipes are released the script's next write fails.
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeout.components.seconds)) {
                collector.finish(.timedOut)
            }
        }
    }

    /// Gathers both pipes and the exit, and resumes the caller exactly once.
    private final class Collector: Sendable {
        private struct State {
            var continuation: CheckedContinuation<Run, Never>?
            var stdout = Data()
            var stderr = Data()
            var stdoutOpen = true
            var stderrOpen = true
            var termination: ScriptTermination?
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        private let state: Mutex<State>

        init(_ continuation: CheckedContinuation<Run, Never>) {
            state = Mutex(State(continuation: continuation))
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] h in self?.read(h.availableData, stdout: true) }
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] h in self?.read(h.availableData, stdout: false) }
        }

        private func read(_ data: Data, stdout: Bool) {
            let done = state.withLock { s -> Bool in
                if data.isEmpty {
                    if stdout { s.stdoutOpen = false } else { s.stderrOpen = false }
                } else if stdout {
                    if s.stdout.count < ScriptRunner.keepBytes { s.stdout.append(data.prefix(ScriptRunner.keepBytes - s.stdout.count)) }
                } else {
                    s.stderr.append(data)
                    if s.stderr.count > ScriptRunner.keepBytes { s.stderr = s.stderr.suffix(ScriptRunner.keepBytes) }
                }
                return s.termination != nil && !s.stdoutOpen && !s.stderrOpen
            }
            if data.isEmpty { (stdout ? stdoutPipe : stderrPipe).fileHandleForReading.readabilityHandler = nil }
            if done { finish(nil) }
        }

        func exited(_ termination: ScriptTermination) {
            let done = state.withLock { s -> Bool in
                s.termination = s.termination ?? termination
                return !s.stdoutOpen && !s.stderrOpen
            }
            // The script's copies of the write ends are gone; closing ours lets the reads end.
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            if done { finish(nil); return }
            // Something the script started can keep a pipe open after it exits: an ssh
            // ControlPersist master holds stderr, for one. Take what has arrived by then.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.finish(nil) }
        }

        /// `fallback` (the timeout) applies only if the script has not exited by then.
        func finish(_ fallback: ScriptTermination?) {
            let resume = state.withLock { s -> (CheckedContinuation<Run, Never>, Run)? in
                guard let c = s.continuation, let t = s.termination ?? fallback else { return nil }
                s.continuation = nil
                return (c, Run(termination: t, stdout: s.stdout, stderr: s.stderr))
            }
            guard let (continuation, run) = resume else { return }
            // The read ends close when the pipes go away, not here: a handler already running
            // would raise on a closed handle.
            for pipe in [stdoutPipe, stderrPipe] {
                pipe.fileHandleForReading.readabilityHandler = nil
                try? pipe.fileHandleForWriting.close()
            }
            continuation.resume(returning: run)
        }
    }
}
