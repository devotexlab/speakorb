import Foundation

public enum CloudMode: String, Equatable, Sendable {
    case direct
    case polish
}

public enum RouteDecision: Equatable, Sendable {
    case local
    case cloud(ProviderID, mode: CloudMode)
    case unavailable(SpeakorbError)
}

public struct Router: Sendable {
    public init() {}

    public func decide(
        preferred: ProviderID,
        allowCloud: Bool,
        hasKey: (ProviderID) -> Bool,
        localAvailable: Bool,
        networkAvailable: Bool = true,
        consecutiveFailures: Int = 0
    ) -> RouteDecision {
        let cloudUsable = allowCloud && networkAvailable && hasKey(preferred) && consecutiveFailures < 2
        switch preferred {
        case .local:
            if localAvailable { return .local }
            if cloudUsable { return .cloud(preferred == .local ? .gemini : preferred, mode: .direct) }
            return .unavailable(.localModelUnavailable)
        case .deepseek:
            // DeepSeek 只做文字润色：需要先有本机转写。
            if cloudUsable && localAvailable { return .cloud(.deepseek, mode: .polish) }
            if localAvailable { return .local }
            return .unavailable(.localModelUnavailable)
        default:
            if cloudUsable { return .cloud(preferred, mode: .direct) }
            if localAvailable { return .local }
            if !allowCloud { return .unavailable(.missingAPIKey(preferred)) }
            return .unavailable(.networkUnavailable)
        }
    }
}
