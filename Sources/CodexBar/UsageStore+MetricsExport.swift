import CodexBarCore
import Foundation

extension UsageStore {
    func exportMetricsIfNeeded(force: Bool = false) async {
        guard let interval = self.settings.metricsExportInterval.seconds else { return }

        let now = Date()
        if !force,
           let lastMetricsExportAt,
           now.timeIntervalSince(lastMetricsExportAt) < interval
        {
            return
        }

        let rows = self.metricsExportRows(exportedAt: now)
        guard !rows.isEmpty else { return }

        do {
            try await self.metricsExporter.append(rows: rows)
            self.lastMetricsExportAt = now
        } catch {
            CodexBarLog.logger(LogCategories.app).error("Failed to export usage metrics CSV: \(error)")
        }
    }

    func metricsExportRows(exportedAt: Date) -> [UsageMetricsCSVRow] {
        self.enabledProvidersForDisplay().map { provider in
            UsageMetricsCSVRow(
                exportedAt: exportedAt,
                provider: provider,
                snapshot: self.snapshots[provider],
                sourceLabel: self.lastSourceLabels[provider],
                status: self.statuses[provider],
                error: self.errors[provider])
        }
    }

    func startMetricsExportTimer() {
        self.metricsExportTimerTask?.cancel()
        guard let interval = self.settings.metricsExportInterval.seconds else { return }

        self.metricsExportTimerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                await self?.exportMetricsIfNeeded()
            }
        }
    }
}
