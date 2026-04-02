import CodexBarCore
import Foundation

enum MetricsExportInterval: String, CaseIterable, Identifiable {
    case off
    case fiveMinutes
    case fifteenMinutes
    case hourly

    var id: String {
        self.rawValue
    }

    var seconds: TimeInterval? {
        switch self {
        case .off: nil
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .hourly: 3600
        }
    }

    var label: String {
        switch self {
        case .off: "Off"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        case .hourly: "1 hour"
        }
    }
}

struct UsageMetricsCSVRow: Equatable {
    static let columns: [String] = [
        "exported_at",
        "provider",
        "source",
        "usage_updated_at",
        "status_indicator",
        "status_description",
        "error",
        "primary_used_percent",
        "primary_remaining_percent",
        "primary_window_minutes",
        "primary_resets_at",
        "secondary_used_percent",
        "secondary_remaining_percent",
        "secondary_window_minutes",
        "secondary_resets_at",
        "tertiary_used_percent",
        "tertiary_remaining_percent",
        "tertiary_window_minutes",
        "tertiary_resets_at",
        "provider_cost_used",
        "provider_cost_limit",
        "provider_cost_currency",
        "provider_cost_period",
        "provider_cost_resets_at",
    ]

    static let headerLine = Self.columns.joined(separator: ",") + "\n"

    let exportedAt: Date
    let provider: UsageProvider
    let source: String
    let usageUpdatedAt: Date?
    let statusIndicator: String
    let statusDescription: String
    let error: String
    let primaryUsedPercent: String
    let primaryRemainingPercent: String
    let primaryWindowMinutes: String
    let primaryResetsAt: String
    let secondaryUsedPercent: String
    let secondaryRemainingPercent: String
    let secondaryWindowMinutes: String
    let secondaryResetsAt: String
    let tertiaryUsedPercent: String
    let tertiaryRemainingPercent: String
    let tertiaryWindowMinutes: String
    let tertiaryResetsAt: String
    let providerCostUsed: String
    let providerCostLimit: String
    let providerCostCurrency: String
    let providerCostPeriod: String
    let providerCostResetsAt: String

    init(
        exportedAt: Date,
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        sourceLabel: String?,
        status: ProviderStatus?,
        error: String?)
    {
        self.exportedAt = exportedAt
        self.provider = provider
        self.source = sourceLabel ?? ""
        self.usageUpdatedAt = snapshot?.updatedAt
        self.statusIndicator = status?.indicator.rawValue ?? ""
        self.statusDescription = Self.singleLine(status?.description)
        self.error = Self.singleLine(error)
        self.primaryUsedPercent = Self.number(snapshot?.primary?.usedPercent)
        self.primaryRemainingPercent = Self.number(snapshot?.primary?.remainingPercent)
        self.primaryWindowMinutes = Self.integer(snapshot?.primary?.windowMinutes)
        self.primaryResetsAt = Self.timestamp(snapshot?.primary?.resetsAt)
        self.secondaryUsedPercent = Self.number(snapshot?.secondary?.usedPercent)
        self.secondaryRemainingPercent = Self.number(snapshot?.secondary?.remainingPercent)
        self.secondaryWindowMinutes = Self.integer(snapshot?.secondary?.windowMinutes)
        self.secondaryResetsAt = Self.timestamp(snapshot?.secondary?.resetsAt)
        self.tertiaryUsedPercent = Self.number(snapshot?.tertiary?.usedPercent)
        self.tertiaryRemainingPercent = Self.number(snapshot?.tertiary?.remainingPercent)
        self.tertiaryWindowMinutes = Self.integer(snapshot?.tertiary?.windowMinutes)
        self.tertiaryResetsAt = Self.timestamp(snapshot?.tertiary?.resetsAt)
        self.providerCostUsed = Self.number(snapshot?.providerCost?.used)
        self.providerCostLimit = Self.number(snapshot?.providerCost?.limit)
        self.providerCostCurrency = snapshot?.providerCost?.currencyCode ?? ""
        self.providerCostPeriod = snapshot?.providerCost?.period ?? ""
        self.providerCostResetsAt = Self.timestamp(snapshot?.providerCost?.resetsAt)
    }

    var line: String {
        self.values.map(Self.escapeCSVField).joined(separator: ",") + "\n"
    }

    var values: [String] {
        [
            Self.timestamp(self.exportedAt),
            self.provider.rawValue,
            self.source,
            Self.timestamp(self.usageUpdatedAt),
            self.statusIndicator,
            self.statusDescription,
            self.error,
            self.primaryUsedPercent,
            self.primaryRemainingPercent,
            self.primaryWindowMinutes,
            self.primaryResetsAt,
            self.secondaryUsedPercent,
            self.secondaryRemainingPercent,
            self.secondaryWindowMinutes,
            self.secondaryResetsAt,
            self.tertiaryUsedPercent,
            self.tertiaryRemainingPercent,
            self.tertiaryWindowMinutes,
            self.tertiaryResetsAt,
            self.providerCostUsed,
            self.providerCostLimit,
            self.providerCostCurrency,
            self.providerCostPeriod,
            self.providerCostResetsAt,
        ]
    }

    static func escapeCSVField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.4f", value)
    }

    private static func integer(_ value: Int?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private static func timestamp(_ value: Date?) -> String {
        guard let value else { return "" }
        return Self.timestamp(value)
    }

    private static func timestamp(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }

    private static func singleLine(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor UsageMetricsCSVExporter {
    static let defaultURL: URL = {
        let fallbackRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fallbackRoot
        return root
            .appendingPathComponent("com.steipete.codexbar", isDirectory: true)
            .appendingPathComponent("usage-metrics.csv")
    }()

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL = UsageMetricsCSVExporter.defaultURL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func append(rows: [UsageMetricsCSVRow]) throws {
        guard !rows.isEmpty else { return }
        try self.prepareFile()
        let data = Data(rows.map(\.line).joined().utf8)
        let handle = try FileHandle(forWritingTo: self.fileURL)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        try handle.write(contentsOf: data)
    }

    func currentURL() -> URL {
        self.fileURL
    }

    private func prepareFile() throws {
        let directory = self.fileURL.deletingLastPathComponent()
        if !self.fileManager.fileExists(atPath: directory.path) {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !self.fileManager.fileExists(atPath: self.fileURL.path) {
            try Data(UsageMetricsCSVRow.headerLine.utf8).write(to: self.fileURL, options: .atomic)
        }
    }
}
