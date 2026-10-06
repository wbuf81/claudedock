import Foundation

/// Why a refresh left an org (or every org) without a fresh reading.
public enum RefreshProblem: Equatable, Sendable {
    /// claude.ai couldn't be reached: offline, or the hidden page didn't load.
    case offline
    /// The site's bot check answered instead of the API.
    case blocked
    /// claude.ai answered with something Claude Dock can't read.
    case unreadable
    /// claude.ai refused access (a JSON 403 while still signed in).
    case refused
    case http(Int)
    /// The org's usage has no weekly limit to show.
    case noWeeklyLimit

    public init(_ error: Error) {
        switch error {
        case WebSessionError.blocked: self = .blocked
        case WebSessionError.forbidden: self = .refused
        case WebSessionError.http(let code): self = .http(code)
        case WebSessionError.badResult: self = .unreadable
        case UsageParserError.noWeeklyLimit: self = .noWeeklyLimit
        case is UsageParserError: self = .unreadable
        // The page didn't load, or its fetch() couldn't connect.
        default: self = .offline
        }
    }

    /// A few words for the widget, which has room for little more than a caption.
    public var short: String {
        switch self {
        case .offline: "no connection"
        case .blocked: "blocked by a bot check"
        case .unreadable: "unexpected answer"
        case .refused: "access refused"
        case .http(let code): "claude.ai error \(code)"
        case .noWeeklyLimit: "no weekly limit"
        }
    }
}

/// One refresh across every shown org.
public enum UsageRound {
    public struct Failure: Equatable, Sendable {
        public var org: Org
        public var problem: RefreshProblem

        public init(org: Org, problem: RefreshProblem) {
            self.org = org
            self.problem = problem
        }
    }

    public struct Outcome: Sendable {
        public var readings: [Reading] = []
        public var failures: [Failure] = []
    }

    /// Reads each org in turn. An org that can't be read only loses its own reading, so a
    /// free plan or a refused org never blanks the others; a sign-out ends the round, since
    /// every org would fail the same way.
    public static func run(_ orgs: [Org], at now: Date, isolation: isolated (any Actor)? = #isolation,
                           fetch: (Org) async throws -> Data) async throws -> Outcome {
        var outcome = Outcome()
        for org in orgs {
            do {
                outcome.readings.append(try UsageParser.reading(from: try await fetch(org), org: org.id, at: now))
            } catch WebSessionError.signedOut {
                throw WebSessionError.signedOut
            } catch {
                outcome.failures.append(Failure(org: org, problem: RefreshProblem(error)))
            }
        }
        return outcome
    }
}

extension Copy {
    /// The panel's line after a round where some orgs failed; nil when none did.
    public static func problem(_ failures: [UsageRound.Failure], shown: Int) -> String? {
        guard let first = failures.first else { return nil }
        let orgs = failures.map(\.org)
        guard failures.count < shown else { return problem(first.problem, orgs: orgs) }
        return "Couldn't read \(names(orgs)): \(first.problem.short)."
    }

    /// The panel's line when nothing could be read. `orgs` names who it failed for, when known.
    public static func problem(_ problem: RefreshProblem, orgs: [Org] = []) -> String {
        let retry = "Trying again in a few minutes."
        switch problem {
        case .offline: return "Can't reach claude.ai. \(retry)"
        case .blocked: return "claude.ai's bot check stopped Claude Dock. \(retry)"
        case .http(let code): return "claude.ai answered with error \(code). \(retry)"
        case .unreadable: return "claude.ai answered in a way Claude Dock can't read; its usage page may have changed."
        case .refused: return orgs.isEmpty ? "claude.ai refused to share usage." : "claude.ai refused to share usage for \(names(orgs))."
        case .noWeeklyLimit: return "claude.ai shows no weekly limit for \(orgs.isEmpty ? "this account" : names(orgs))."
        }
    }

    /// "Pikachu", "Pikachu and Charizard", "Pikachu, Charizard and Mew".
    static func names(_ orgs: [Org]) -> String {
        let all = orgs.map(\.name)
        guard all.count > 1 else { return all.first ?? "" }
        return all.dropLast().joined(separator: ", ") + " and " + all.last!
    }
}
