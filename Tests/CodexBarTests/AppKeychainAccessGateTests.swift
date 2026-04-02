import Security
import Testing
@testable import CodexBar

@Suite(.serialized)
struct AppKeychainAccessGateTests {
    @Test
    func `record denied blocks further prompts until cooldown expires`() {
        AppKeychainAccessGate.resetForTesting()

        let service = "com.steipete.CodexBar"
        let account = "test-account"

        #expect(AppKeychainAccessGate.shouldAllowPrompt(service: service, account: account))
        AppKeychainAccessGate.recordDenied(service: service, account: account)
        #expect(AppKeychainAccessGate.shouldAllowPrompt(service: service, account: account) == false)
    }

    @Test
    func `record denied if needed tracks canceled status`() {
        AppKeychainAccessGate.resetForTesting()

        let service = "com.steipete.CodexBar"
        let account = "test-account"

        #expect(AppKeychainAccessGate.shouldAllowPrompt(service: service, account: account))
        AppKeychainAccess.recordDeniedIfNeeded(status: errSecUserCanceled, service: service, account: account)
        #expect(AppKeychainAccessGate.shouldAllowPrompt(service: service, account: account) == false)
    }
}
