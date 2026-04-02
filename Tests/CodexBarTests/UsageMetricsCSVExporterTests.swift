import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UsageMetricsCSVExporterTests {
    @Test
    func `row maps snapshot and metadata into stable CSV fields`() {
        let exportedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let resetsAt = Date(timeIntervalSince1970: 1_710_000_300)
        let costReset = Date(timeIntervalSince1970: 1_710_003_600)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: resetsAt, resetDescription: nil),
            secondary: RateWindow(usedPercent: 60, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: RateWindow(usedPercent: 10, windowMinutes: 60, resetsAt: nil, resetDescription: nil),
            providerCost: ProviderCostSnapshot(
                used: 12.5,
                limit: 50,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: costReset,
                updatedAt: exportedAt),
            updatedAt: exportedAt)
        let status = ProviderStatus(indicator: .minor, description: "Partial outage", updatedAt: exportedAt)

        let row = UsageMetricsCSVRow(
            exportedAt: exportedAt,
            provider: .codex,
            snapshot: snapshot,
            sourceLabel: "openai-web",
            status: status,
            error: "timeout\nretrying")

        #expect(row.provider == .codex)
        #expect(row.source == "openai-web")
        #expect(row.statusIndicator == "minor")
        #expect(row.statusDescription == "Partial outage")
        #expect(row.error == "timeout retrying")
        #expect(row.primaryUsedPercent == "25.0000")
        #expect(row.primaryRemainingPercent == "75.0000")
        #expect(row.primaryWindowMinutes == "300")
        #expect(row.secondaryUsedPercent == "60.0000")
        #expect(row.tertiaryUsedPercent == "10.0000")
        #expect(row.providerCostUsed == "12.5000")
        #expect(row.providerCostLimit == "50.0000")
        #expect(row.providerCostCurrency == "USD")
        #expect(row.providerCostPeriod == "Monthly")
        #expect(!row.primaryResetsAt.isEmpty)
        #expect(!row.providerCostResetsAt.isEmpty)
    }

    @Test
    func `csv escaping quotes commas and newlines`() {
        let escaped = UsageMetricsCSVRow.escapeCSVField("hello,\"csv\"\nworld")
        #expect(escaped == "\"hello,\"\"csv\"\"\nworld\"")
    }

    @Test
    func `exporter creates header once and appends rows`() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("usage-metrics.csv")
        let exporter = UsageMetricsCSVExporter(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_710_000_000)

        let first = UsageMetricsCSVRow(
            exportedAt: now,
            provider: .codex,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: now),
            sourceLabel: "cli",
            status: nil,
            error: nil)
        let second = UsageMetricsCSVRow(
            exportedAt: now.addingTimeInterval(60),
            provider: .claude,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: now),
            sourceLabel: "web",
            status: nil,
            error: "oops")

        try await exporter.append(rows: [first])
        try await exporter.append(rows: [second])

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(contents.hasPrefix(UsageMetricsCSVRow.headerLine))
        #expect(contents.components(separatedBy: UsageMetricsCSVRow.headerLine).count == 2)
        #expect(lines.count >= 3)
        #expect(contents.contains(",codex,cli,"))
        #expect(contents.contains(",claude,web,"))
    }
}

@MainActor
struct UsageStoreMetricsExportTests {
    @Test
    func `store builds export rows for enabled providers with source status and error`() throws {
        let suite = "UsageStoreMetricsExportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            kimiK2TokenStore: InMemoryKimiK2TokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let metadata = ProviderRegistry.shared.metadata

        try settings.setProviderEnabled(provider: .codex, metadata: #require(metadata[.codex]), enabled: true)
        try settings.setProviderEnabled(provider: .claude, metadata: #require(metadata[.claude]), enabled: false)

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_710_000_000)),
            provider: .codex)
        store._setSourceLabelForTesting("openai-web", provider: .codex)
        store._setStatusForTesting(
            ProviderStatus(indicator: .none, description: "Operational", updatedAt: nil),
            provider: .codex)
        store._setErrorForTesting("transient issue", provider: .codex)

        let rows = store.metricsExportRows(exportedAt: Date(timeIntervalSince1970: 1_710_000_100))

        #expect(rows.count == 1)
        #expect(rows[0].provider == .codex)
        #expect(rows[0].source == "openai-web")
        #expect(rows[0].statusIndicator == "none")
        #expect(rows[0].error == "transient issue")
        #expect(rows[0].primaryUsedPercent == "42.0000")
    }
}
