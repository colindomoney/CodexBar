import CodexBarCore
import Foundation
import Security

#if os(macOS)
import os.lock

enum AppKeychainAccessGate {
    private struct State {
        var loaded = false
        var deniedUntilByItem: [String: Date] = [:]
    }

    private static let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private static let defaultsKey = "appKeychainAccessDeniedUntil"
    private static let cooldownInterval: TimeInterval = 60 * 60 * 6

    static func shouldAllowPrompt(service: String, account: String, now: Date = Date()) -> Bool {
        guard !KeychainAccessGate.isDisabled else { return false }
        return self.lock.withLock { state in
            self.loadIfNeeded(&state)
            let key = self.key(service: service, account: account)
            if let deniedUntil = state.deniedUntilByItem[key] {
                if deniedUntil > now {
                    return false
                }
                state.deniedUntilByItem.removeValue(forKey: key)
                self.persist(state)
            }
            return true
        }
    }

    static func recordDenied(service: String, account: String, now: Date = Date()) {
        let deniedUntil = now.addingTimeInterval(self.cooldownInterval)
        self.lock.withLock { state in
            self.loadIfNeeded(&state)
            state.deniedUntilByItem[self.key(service: service, account: account)] = deniedUntil
            self.persist(state)
        }
    }

    #if DEBUG
    static func resetForTesting() {
        self.lock.withLock { state in
            state.loaded = true
            state.deniedUntilByItem.removeAll()
            UserDefaults.standard.removeObject(forKey: self.defaultsKey)
        }
    }
    #endif

    private static func key(service: String, account: String) -> String {
        "\(service)|\(account)"
    }

    private static func loadIfNeeded(_ state: inout State) {
        guard !state.loaded else { return }
        state.loaded = true
        guard let raw = UserDefaults.standard.dictionary(forKey: self.defaultsKey) as? [String: Double] else {
            return
        }
        state.deniedUntilByItem = raw.compactMapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func persist(_ state: State) {
        let raw = state.deniedUntilByItem.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(raw, forKey: self.defaultsKey)
    }
}
#else
enum AppKeychainAccessGate {
    static func shouldAllowPrompt(service _: String, account _: String, now _: Date = Date()) -> Bool {
        true
    }

    static func recordDenied(service _: String, account _: String, now _: Date = Date()) {}

    #if DEBUG
    static func resetForTesting() {}
    #endif
}
#endif

enum AppKeychainAccess {
    static func prepareForRead(
        kind: KeychainPromptContext.Kind,
        service: String,
        account: String) -> Bool
    {
        if case .interactionRequired = KeychainAccessPreflight
            .checkGenericPassword(service: service, account: account)
        {
            guard AppKeychainAccessGate.shouldAllowPrompt(service: service, account: account) else {
                return false
            }
            KeychainPromptHandler.notify(KeychainPromptContext(
                kind: kind,
                service: service,
                account: account))
        }
        return true
    }

    static func recordDeniedIfNeeded(status: OSStatus, service: String, account: String) {
        switch status {
        case errSecUserCanceled, errSecAuthFailed, errSecNoAccessForItem, errSecInteractionNotAllowed:
            AppKeychainAccessGate.recordDenied(service: service, account: account)
        default:
            break
        }
    }
}
