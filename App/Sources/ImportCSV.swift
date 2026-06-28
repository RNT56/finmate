import SwiftUI
import Domain
import DataLayer

// MARK: - CSV import (docs/02 §8, docs/13 §9, M6) — paste · preview · partial import.
//
// A pasteable CSV editor that runs the pure `SubscriptionCSVImporter` to build an
// `ImportPreview` (valid rows + per-row errors) before any write. Importing adds only
// the valid rows through the shared `SubscriptionsStore` / repository — the same
// create path as manual add. A file picker is a follow-up (see note in the UI).

struct ImportView: View {
    /// Shares the same repository the Subscriptions tab reads (injected), so imported
    /// rows appear there too.
    @Environment(\.repositories) private var repositories
    @State private var store = SubscriptionsStore(repository: SampleData.repository)
    @State private var didBind = false

    @State private var csvText: String = ""
    @State private var preview: ImportPreview?
    @State private var importedCount: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                if isInitial { initialEmptyState }
                editorCard
                if let preview {
                    previewSummaryCard(preview)
                    if !preview.valid.isEmpty { validRowsCard(preview) }
                    if !preview.errors.isEmpty { errorsCard(preview) }
                    importButton(preview)
                }
                if let importedCount {
                    GlassCard {
                        Label("Imported \(importedCount) subscription\(importedCount == 1 ? "" : "s").",
                              systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Import CSV")
        .navigationBarTitleDisplayMode(.inline)
        .background(FinmateGradient())
        .task {
            if !didBind {
                store = SubscriptionsStore(repository: repositories.subscriptions)
                didBind = true
            }
            await store.load()
        }
    }

    /// True before the user has typed anything or run a preview/import — the
    /// initial empty state guiding them to paste or load the sample.
    private var isInitial: Bool {
        csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preview == nil && importedCount == nil
    }

    // MARK: Initial empty state

    private var initialEmptyState: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Import subscriptions")
                    .font(.headline)
                Text("Paste CSV below or load the sample to preview, then import the valid rows.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    csvText = Self.sampleCSV
                } label: {
                    Label("Load sample CSV", systemImage: "doc.text")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Editor

    private var editorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste CSV")
                    .font(.headline)
                Text("Columns: name, amount, currency, billing_period, payment_method, category, usage_state, start_date, url. Header aliases are accepted. A file picker is a follow-up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $csvText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("CSV input")

                HStack {
                    Button {
                        csvText = Self.sampleCSV
                        preview = nil
                        importedCount = nil
                    } label: {
                        Label("Sample CSV", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csvText)
                        importedCount = nil
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: Preview cards

    private func previewSummaryCard(_ preview: ImportPreview) -> some View {
        GlassCard {
            HStack {
                summaryStat(value: preview.valid.count, label: "Valid", color: .green)
                Divider().frame(height: 32)
                summaryStat(value: preview.errors.count, label: "Errors", color: preview.errors.isEmpty ? .secondary : .red)
                Divider().frame(height: 32)
                summaryStat(value: preview.totalRows, label: "Rows", color: .secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func summaryStat(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func validRowsCard(_ preview: ImportPreview) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Valid rows").font(.headline)
                ForEach(preview.valid) { sub in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.name).font(.subheadline.weight(.medium))
                            Text(sub.billingPeriod.rawValue.capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money(minorUnits: sub.amountMinor, currency: sub.currency).formatted())
                            .font(.subheadline.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func errorsCard(_ preview: ImportPreview) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Errors", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.red)
                ForEach(Array(preview.errors.enumerated()), id: \.offset) { _, err in
                    HStack(alignment: .top, spacing: 8) {
                        Text("Row \(err.row)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        Text(errorText(err))
                            .font(.caption)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func errorText(_ err: ImportRowError) -> String {
        if let field = err.field { return "\(field): \(err.message)" }
        return err.message
    }

    private func importButton(_ preview: ImportPreview) -> some View {
        Button {
            let toImport = preview.valid
            Task {
                for sub in toImport { await store.add(sub) }
                importedCount = toImport.count
                self.preview = nil
                csvText = ""
            }
        } label: {
            Label("Import \(preview.valid.count) subscription\(preview.valid.count == 1 ? "" : "s")",
                  systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(preview.valid.isEmpty)
    }

    // MARK: Sample

    static let sampleCSV = """
    name,amount,currency,billing_period,payment_method,usage_state
    Netflix,12.99,EUR,monthly,credit_card,active
    GitHub,100,USD,yearly,paypal,active
    Adobe,"1.234,56",EUR,yearly,credit_card,rarely
    ,9.99,EUR,monthly,credit_card,active
    Disney+,abc,EUR,monthly,paypal,active
    """
}
