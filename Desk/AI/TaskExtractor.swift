import Foundation
import FoundationModels

/// Reads freeform notes with Apple's on-device language model (the one behind Apple
/// Intelligence) and returns the to-dos in them. Runs entirely on this Mac: nothing is sent
/// anywhere. Needs macOS 26+, Apple silicon and Apple Intelligence turned on; everywhere else
/// `isAvailable` is false and the UI hides the feature.
enum TaskExtractor {
    enum Failure: LocalizedError {
        case unavailable, notReady, unsupportedLanguage, declined, tooLong, other

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Intelligence isn’t available on this Mac."
            case .notReady: "Apple Intelligence is still getting ready. Try again in a moment."
            case .unsupportedLanguage: "Apple Intelligence can’t read notes in this language yet."
            case .declined: "Apple Intelligence wouldn’t read these notes."
            case .tooLong: "These notes are too long to read in one go."
            case .other: "Couldn’t read your notes just now."
            }
        }
    }

    struct Result: Sendable {
        var tasks: [String]
        /// Only the first part of very long notes was read.
        var wasTruncated: Bool
    }

    @MainActor
    static var isAvailable: Bool {
        #if DEBUG
        if fakeEnabled { return true }
        #endif
        if #available(macOS 26, *) { return SystemLanguageModel.default.isAvailable }
        return false
    }

    /// Loads the model ahead of a likely request (the first one otherwise takes ~5 s).
    @MainActor
    static func prewarm() {
        guard #available(macOS 26, *), SystemLanguageModel.default.isAvailable else { return }
        LanguageModelSession(instructions: instructions).prewarm()
    }

    static func extract(from notes: String, existing: [TaskItem]) async throws -> Result {
        let (text, truncated) = TaskSuggestions.promptNotes(notes)
        guard !text.isEmpty else { return Result(tasks: [], wasTruncated: false) }

        #if DEBUG
        if fakeEnabled {
            try await Task.sleep(for: .milliseconds(600))
            let lines = text.split(separator: "\n").map(String.init)
            return Result(tasks: TaskSuggestions.clean(lines, existing: existing), wasTruncated: truncated)
        }
        #endif

        guard #available(macOS 26, *) else { throw Failure.unavailable }
        let raw = try await generate(notes: text, existing: existing)
        return Result(tasks: TaskSuggestions.clean(raw, existing: existing), wasTruncated: truncated)
    }

    @available(macOS 26, *)
    private static func generate(notes: String, existing: [TaskItem]) async throws -> [String] {
        switch SystemLanguageModel.default.availability {
        case .available: break
        case .unavailable(.modelNotReady): throw Failure.notReady
        case .unavailable: throw Failure.unavailable
        }
        let session = LanguageModelSession(instructions: instructions)
        var prompt = ""
        let open = existing.filter { !$0.isDone && !$0.isBlankText }.map(\.text)
        if !open.isEmpty {
            prompt += "Already in the task list:\n" + open.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        prompt += "Notes:\n\(notes)"
        do {
            let response = try await session.respond(
                to: prompt, generating: ExtractedTasks.self, options: GenerationOptions(temperature: 0.2))
            return response.content.tasks
        } catch {
            throw failure(for: error)
        }
    }

    /// The model's errors in words for the popover. macOS 27 throws `LanguageModelError` /
    /// `SystemLanguageModel.Error`; macOS 26 threw `LanguageModelSession.GenerationError`.
    @available(macOS 26, *)
    private static func failure(for error: Error) -> Error {
        if error is CancellationError || error is Failure { return error }
        if #available(macOS 27, *) {
            if let e = error as? LanguageModelError {
                switch e {
                case .contextSizeExceeded: return Failure.tooLong
                case .unsupportedLanguageOrLocale: return Failure.unsupportedLanguage
                case .guardrailViolation, .refusal: return Failure.declined
                default: return Failure.other
                }
            }
            if error is SystemLanguageModel.Error { return Failure.notReady }
        }
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize: return Failure.tooLong
            case .unsupportedLanguageOrLocale: return Failure.unsupportedLanguage
            case .guardrailViolation, .refusal: return Failure.declined
            case .assetsUnavailable: return Failure.notReady
            default: return Failure.other
            }
        }
        return Failure.other
    }

    private static let instructions = """
        You turn someone's freeform planner notes into to-do items.
        Include only things the person needs to do: errands, calls, emails, follow-ups, purchases, \
        work to finish, appointments to book.
        Skip feelings, reflections, observations and ideas with no clear action.
        Skip anything already in their task list.
        Write each task as a short imperative phrase of at most ten words, in the same language as the notes.
        Keep names, numbers and dates exactly as written. Never invent tasks.
        """

    #if DEBUG
    /// `DESK_FAKE_TASK_EXTRACTION=1`: every note line becomes a suggestion, no model needed
    /// (UI tests, screenshots on Macs without Apple Intelligence).
    static var fakeEnabled: Bool { ProcessInfo.processInfo.environment["DESK_FAKE_TASK_EXTRACTION"] == "1" }
    #endif
}

@available(macOS 26, *)
@Generable
private struct ExtractedTasks {
    @Guide(description: "Action items found in the notes. Each is a short imperative phrase, in the same language as the notes. Empty when the notes contain nothing to do.", .maximumCount(12))
    var tasks: [String]
}
