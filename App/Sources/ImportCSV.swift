import SwiftUI
import UniformTypeIdentifiers
import Domain
import DataLayer

// MARK: - CSV import (docs/02 §8, docs/13 §9, M6) — load · map · preview · partial import.
//
// A CSV importer that runs the pure `SubscriptionCSVImporter` to build an
// `ImportPreview` (valid rows + per-row errors) before any write. CSV arrives by
// **paste** or via a **.csv file picker** (read off the main actor for large files).
// After the header is read the user can review/override the detected column→field
// mapping (auto-seeded from the alias match) and then preview/import. Importing adds
// only the valid rows through the shared `SubscriptionsStore` / repository — the same
// create path as manual add.

private typealias CSVField = SubscriptionCSVImporter.CSVField

struct ImportView: View {
    /// Shares the same repository the Subscriptions tab reads (injected), so imported
    /// rows appear there too.
    @Environment(\.repositories) private var repositories
    @State private var store = SubscriptionsStore(repository: SampleData.repository)
    @State private var didBind = false

    @State private var csvText: String = ""
    @State private var preview: ImportPreview?
    @State private var importedCount: Int?

    // Column mapping: the detected header tokens + the user-overridable field→column
    // map. `nil` mapping = the header hasn't been analyzed yet (paste-only state).
    @State private var headers: [String] = []
    @State private var mapping: [CSVField: Int] = [:]
    @State private var headerAnalyzed = false

    // File picker
    @State private var isImportingFile = false
    @State private var fileError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                if isInitial { initialEmptyState }
                editorCard
                if let fileError {
                    GlassCard {
                        Label(fileError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                if headerAnalyzed { mappingCard }
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
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .task {
            if !didBind {
                store = SubscriptionsStore(repository: repositories.subscriptions)
                didBind = true
            }
            await store.load()
        }
    }

    /// True before the user has typed anything or run a preview/import — the
    /// initial empty state guiding them to paste, load the sample, or pick a file.
    private var isInitial: Bool {
        csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preview == nil && importedCount == nil && !headerAnalyzed
    }

    // MARK: File import (off the main actor for large files)

    private func handleFileImport(_ result: Result<[URL], Error>) {
        fileError = nil
        switch result {
        case .failure(let error):
            fileError = "Could not open file: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let outcome = await Self.readCSV(from: url)
                await MainActor.run {
                    switch outcome {
                    case .text(let text):
                        resetFlow()
                        csvText = text
                        analyzeHeader()
                    case .failure(let message):
                        fileError = message
                    }
                }
            }
        }
    }

    /// The outcome of reading a CSV file: its text, or a user-facing failure message.
    private enum CSVReadOutcome: Sendable {
        case text(String)
        case failure(String)
    }

    /// Read a (possibly large) CSV file off the main actor. Honors the security-scoped
    /// resource the picker hands back. Returns the contents or a user-facing message.
    nonisolated private static func readCSV(from url: URL) async -> CSVReadOutcome {
        await Task.detached(priority: .userInitiated) { () -> CSVReadOutcome in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if let text = String(data: data, encoding: .utf8) {
                    return .text(text)
                }
                if let text = String(data: data, encoding: .isoLatin1) {
                    return .text(text)
                }
                return .failure("File is not valid text.")
            } catch {
                return .failure("Could not read file: \(error.localizedDescription)")
            }
        }.value
    }

    // MARK: Header analysis + mapping helpers

    /// Analyze the current `csvText`'s header and seed the user-overridable mapping
    /// from the alias auto-detection. Clears any stale preview.
    private func analyzeHeader() {
        let analysis = SubscriptionCSVImporter.analyzeHeader(csvText)
        headers = analysis.headers
        mapping = analysis.autoMapping
        headerAnalyzed = !analysis.headers.isEmpty
        preview = nil
        importedCount = nil
    }

    /// Reset everything back to the paste/empty state.
    private func resetFlow() {
        preview = nil
        importedCount = nil
        headerAnalyzed = false
        headers = []
        mapping = [:]
        fileError = nil
    }

    /// A binding for a field's selected column index, where `-1` means "ignore".
    private func columnBinding(for field: CSVField) -> Binding<Int> {
        Binding(
            get: { mapping[field] ?? -1 },
            set: { newValue in
                if newValue < 0 { mapping[field] = nil } else { mapping[field] = newValue }
                preview = nil   // mapping changed → stale preview
            }
        )
    }

    /// Required fields (name, amount) must be mapped before previewing.
    private var requiredFieldsMapped: Bool {
        CSVField.allCases.filter(\.isRequired).allSatisfy { mapping[$0] != nil }
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
                Text("Choose a .csv file or paste CSV below, map the columns, then import the valid rows.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button {
                        isImportingFile = true
                    } label: {
                        Label("Choose .csv file", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        csvText = Self.sampleCSV
                        analyzeHeader()
                    } label: {
                        Label("Load sample", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Editor

    private var editorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("CSV source")
                    .font(.headline)
                Text("Columns: name, amount, currency, billing_period, payment_method, category, usage_state, start_date, url. Header aliases are detected automatically; map any columns that don't match below.")
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
                        isImportingFile = true
                    } label: {
                        Label("Choose file", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        csvText = Self.sampleCSV
                        analyzeHeader()
                    } label: {
                        Label("Sample", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        analyzeHeader()
                    } label: {
                        Label("Map columns", systemImage: "tablecells")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: Column mapping

    /// After the header is read, show one Picker per target field — auto-selected from
    /// the alias match, user-overridable, with an "—  Ignore" option. Then the user
    /// runs the explicit-mapping parse into the preview below.
    private var mappingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Map columns", systemImage: "tablecells")
                    .font(.headline)
                Text("Detected \(headers.count) column\(headers.count == 1 ? "" : "s"). Match each Finmate field to a column. Name and Amount are required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(CSVField.allCases, id: \.self) { field in
                    HStack {
                        Text(field.displayName)
                            .font(.subheadline.weight(.medium))
                        if field.isRequired {
                            Text("Required")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Picker(field.displayName, selection: columnBinding(for: field)) {
                            Text("—  Ignore").tag(-1)
                            ForEach(Array(headers.enumerated()), id: \.offset) { idx, token in
                                Text(token.isEmpty ? "Column \(idx + 1)" : token).tag(idx)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityLabel("\(field.displayName) column")
                    }
                    .accessibilityElement(children: .combine)
                }

                if !requiredFieldsMapped {
                    Label("Map Name and Amount to continue.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    preview = SubscriptionCSVImporter.parse(csvText, mapping: mapping)
                    importedCount = nil
                } label: {
                    Label("Preview rows", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!requiredFieldsMapped)
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
                let count = toImport.count
                resetFlow()
                csvText = ""
                importedCount = count
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
