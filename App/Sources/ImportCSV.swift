import SwiftUI
import UniformTypeIdentifiers
import Domain
import DataLayer

// MARK: - CSV import (docs/02 §6/§8, docs/13 §9, M6) — type · load · map · preview · import.
//
// A CSV importer that runs the pure entity importers (`SubscriptionCSVImporter`,
// `IncomeCSVImporter`, `FixedExpenseCSVImporter`, `VariableExpenseCSVImporter` — all
// over the shared `CSVImportKit` tokenizer/validation machinery) to build a typed
// preview (valid rows + per-row errors) before any write. The user first picks an
// **import type** (Subscriptions / Income / Fixed expenses / Variable expenses); the
// mapping fields + preview columns adapt to it. CSV arrives by **paste** or via a
// **.csv file picker** (read off the main actor for large files). After the header is
// read the user can review/override the detected column→field mapping and then
// preview/import. Importing routes only the valid rows through the matching repository.

// MARK: - Import kind

/// The entity the import targets. Drives the field list, the per-type parse, and the
/// destination repository.
enum ImportKind: String, CaseIterable, Identifiable, Sendable {
    case subscriptions
    case income
    case fixedExpenses
    case variableExpenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscriptions:    return "Subscriptions"
        case .income:           return "Income"
        case .fixedExpenses:    return "Fixed expenses"
        case .variableExpenses: return "Variable expenses"
        }
    }

    /// Singular noun for the import button / confirmation.
    var singular: String {
        switch self {
        case .subscriptions:    return "subscription"
        case .income:           return "income source"
        case .fixedExpenses:    return "fixed expense"
        case .variableExpenses: return "variable expense"
        }
    }

    /// The mappable fields for this kind, as (canonicalKey, displayName, isRequired).
    /// The canonical key is the importer enum's `rawValue`, used as the stable mapping
    /// key shared across all kinds in `mapping`.
    var fields: [(key: String, name: String, required: Bool)] {
        switch self {
        case .subscriptions:
            return SubscriptionCSVImporter.CSVField.allCases.map { ($0.rawValue, $0.displayName, $0.isRequired) }
        case .income:
            return IncomeCSVImporter.CSVField.allCases.map { ($0.rawValue, $0.displayName, $0.isRequired) }
        case .fixedExpenses:
            return FixedExpenseCSVImporter.CSVField.allCases.map { ($0.rawValue, $0.displayName, $0.isRequired) }
        case .variableExpenses:
            return VariableExpenseCSVImporter.CSVField.allCases.map { ($0.rawValue, $0.displayName, $0.isRequired) }
        }
    }

    /// A one-line column hint for the editor card.
    var columnsHint: String {
        switch self {
        case .subscriptions:
            return "name, amount, currency, billing_period, payment_method, category, usage_state, start_date, url"
        case .income:
            return "name, amount, currency, frequency, next_payment, notes"
        case .fixedExpenses:
            return "name, amount, currency, category, frequency, due_date, autopay, notes"
        case .variableExpenses:
            return "name, amount, currency, category, spent_on, notes"
        }
    }

    var sampleCSV: String {
        switch self {
        case .subscriptions:
            return """
            name,amount,currency,billing_period,payment_method,usage_state
            Netflix,12.99,EUR,monthly,credit_card,active
            GitHub,100,USD,yearly,paypal,active
            Adobe,"1.234,56",EUR,yearly,credit_card,rarely
            ,9.99,EUR,monthly,credit_card,active
            Disney+,abc,EUR,monthly,paypal,active
            """
        case .income:
            return """
            name,amount,currency,frequency,next_payment,notes
            Salary,3000,EUR,monthly,2026-07-01,Main job
            Dividend,150,USD,yearly,,
            Gift,50,EUR,one_time,,Birthday
            ,500,EUR,monthly,,Missing name
            """
        case .fixedExpenses:
            return """
            name,amount,currency,category,frequency,due_date,autopay
            Rent,1200,EUR,Housing,monthly,2026-07-01,true
            Power,90,EUR,Utilities,monthly,2026-07-15,no
            Internet,40,EUR,Mystery,monthly,,
            Bad,abc,EUR,Housing,monthly,,
            """
        case .variableExpenses:
            return """
            name,amount,currency,category,spent_on
            Groceries,45.20,EUR,Food,2026-06-10
            Lunch,12.50,EUR,Food,2026-06-15
            NoDate,5,EUR,Food,
            """
        }
    }
}

// MARK: - Typed preview row (uniform for the preview UI across kinds)

/// A flattened, kind-agnostic view of one valid imported row for the preview list.
private struct PreviewRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let amount: Money
}

/// The valid rows + errors + total, plus the destination kind. Kept type-erased so the
/// preview UI is shared; the actual typed valid arrays live in `PendingImport`.
private struct UnifiedPreview {
    let rows: [PreviewRow]
    let errors: [ImportRowError]
    let totalRows: Int
    var validCount: Int { rows.count }
}

/// The typed valid rows captured at preview time, ready to write on import.
private enum PendingImport {
    case subscriptions([Subscription])
    case income([IncomeSource])
    case fixed([FixedExpense])
    case variable([VariableExpense])

    var count: Int {
        switch self {
        case .subscriptions(let v): return v.count
        case .income(let v):        return v.count
        case .fixed(let v):         return v.count
        case .variable(let v):      return v.count
        }
    }
}

struct ImportView: View {
    @Environment(\.repositories) private var repositories
    @State private var store = SubscriptionsStore(repository: SampleData.repository)
    @State private var cashFlowStore: CashFlowStore?
    @State private var didBind = false

    /// Expense categories (ADR-0022) for NAME → id resolution and label display.
    @State private var expenseCategories: [Domain.Category] = []

    @State private var kind: ImportKind = .subscriptions
    @State private var csvText: String = ""
    @State private var preview: UnifiedPreview?
    @State private var pending: PendingImport?
    @State private var importedCount: Int?

    // Column mapping: detected header tokens + the user-overridable canonicalKey→column
    // map (keyed by the importer enum's rawValue so it's shared across kinds).
    @State private var headers: [String] = []
    @State private var mapping: [String: Int] = [:]
    @State private var headerAnalyzed = false

    // File picker
    @State private var isImportingFile = false
    @State private var fileError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                typePickerCard
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
                    if !preview.rows.isEmpty { validRowsCard(preview) }
                    if !preview.errors.isEmpty { errorsCard(preview) }
                    importButton(preview)
                }
                if let importedCount {
                    GlassCard {
                        Label("Imported \(importedCount) \(kind.singular)\(importedCount == 1 ? "" : "s").",
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
                cashFlowStore = CashFlowStore(
                    incomeRepository: repositories.income,
                    expenseRepository: repositories.expenses,
                    categoryRepository: repositories.categories,
                    subscriptions: []
                )
                didBind = true
            }
            await store.load()
            await cashFlowStore?.load()
            expenseCategories = (try? await repositories.categories.categories(kind: .expense)) ?? []
        }
    }

    /// True before the user has typed anything or run a preview/import.
    private var isInitial: Bool {
        csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preview == nil && importedCount == nil && !headerAnalyzed
    }

    // MARK: Type picker

    private var typePickerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import type")
                    .font(.headline)
                Picker("Import type", selection: $kind) {
                    ForEach(ImportKind.allCases) { k in
                        Text(k.title).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Import type")
                .onChange(of: kind) { _, _ in
                    // Switching type invalidates the mapping/preview built for the old one.
                    resetFlow()
                }
            }
        }
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

    private enum CSVReadOutcome: Sendable {
        case text(String)
        case failure(String)
    }

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

    /// Analyze the current `csvText`'s header for the chosen kind and seed the
    /// user-overridable mapping from the alias auto-detection.
    private func analyzeHeader() {
        let (h, m) = Self.analyze(kind: kind, text: csvText)
        headers = h
        mapping = m
        headerAnalyzed = !h.isEmpty
        preview = nil
        pending = nil
        importedCount = nil
    }

    /// Per-kind header analysis, normalized to (rawTokens, canonicalKey→columnIndex).
    private static func analyze(kind: ImportKind, text: String) -> ([String], [String: Int]) {
        switch kind {
        case .subscriptions:
            let a = SubscriptionCSVImporter.analyzeHeader(text)
            return (a.headers, Dictionary(uniqueKeysWithValues: a.autoMapping.map { ($0.key.rawValue, $0.value) }))
        case .income:
            let a = IncomeCSVImporter.analyzeHeader(text)
            return (a.headers, Dictionary(uniqueKeysWithValues: a.autoMapping.map { ($0.key.rawValue, $0.value) }))
        case .fixedExpenses:
            let a = FixedExpenseCSVImporter.analyzeHeader(text)
            return (a.headers, Dictionary(uniqueKeysWithValues: a.autoMapping.map { ($0.key.rawValue, $0.value) }))
        case .variableExpenses:
            let a = VariableExpenseCSVImporter.analyzeHeader(text)
            return (a.headers, Dictionary(uniqueKeysWithValues: a.autoMapping.map { ($0.key.rawValue, $0.value) }))
        }
    }

    private func resetFlow() {
        preview = nil
        pending = nil
        importedCount = nil
        headerAnalyzed = false
        headers = []
        mapping = [:]
        fileError = nil
    }

    /// A binding for a field's selected column index, where `-1` means "ignore".
    private func columnBinding(for key: String) -> Binding<Int> {
        Binding(
            get: { mapping[key] ?? -1 },
            set: { newValue in
                if newValue < 0 { mapping[key] = nil } else { mapping[key] = newValue }
                preview = nil
                pending = nil
            }
        )
    }

    /// Required fields must be mapped before previewing.
    private var requiredFieldsMapped: Bool {
        kind.fields.filter(\.required).allSatisfy { mapping[$0.key] != nil }
    }

    // MARK: Preview (per-kind parse → unified preview + typed pending rows)

    private func runPreview() {
        importedCount = nil
        let cats = expenseCategories
        switch kind {
        case .subscriptions:
            let m = typedMapping(SubscriptionCSVImporter.CSVField.self)
            let p = SubscriptionCSVImporter.parse(csvText, mapping: m)
            pending = .subscriptions(p.valid)
            preview = UnifiedPreview(
                rows: p.valid.map { PreviewRow(title: $0.name,
                                               subtitle: $0.billingPeriod.rawValue.capitalized,
                                               amount: Money(minorUnits: $0.amountMinor, currency: $0.currency)) },
                errors: p.errors, totalRows: p.totalRows)
        case .income:
            let m = typedMapping(IncomeCSVImporter.CSVField.self)
            let p = IncomeCSVImporter.parse(csvText, mapping: m)
            pending = .income(p.valid)
            preview = UnifiedPreview(
                rows: p.valid.map { PreviewRow(title: $0.name,
                                               subtitle: $0.frequency.rawValue.capitalized,
                                               amount: Money(minorUnits: $0.amountMinor, currency: $0.currency)) },
                errors: p.errors, totalRows: p.totalRows)
        case .fixedExpenses:
            let m = typedMapping(FixedExpenseCSVImporter.CSVField.self)
            let p = FixedExpenseCSVImporter.parse(csvText, mapping: m, categories: cats)
            pending = .fixed(p.valid)
            preview = UnifiedPreview(
                rows: p.valid.map { PreviewRow(title: $0.name,
                                               subtitle: categoryName($0.categoryID),
                                               amount: Money(minorUnits: $0.amountMinor, currency: $0.currency)) },
                errors: p.errors, totalRows: p.totalRows)
        case .variableExpenses:
            let m = typedMapping(VariableExpenseCSVImporter.CSVField.self)
            let p = VariableExpenseCSVImporter.parse(csvText, mapping: m, categories: cats)
            pending = .variable(p.valid)
            preview = UnifiedPreview(
                rows: p.valid.map { PreviewRow(title: $0.name,
                                               subtitle: categoryName($0.categoryID),
                                               amount: Money(minorUnits: $0.amountMinor, currency: $0.currency)) },
                errors: p.errors, totalRows: p.totalRows)
        }
    }

    /// Rebuild the canonical-key mapping as a typed `[Field: Int]` for a specific
    /// importer enum (keys that don't parse back into the enum are dropped).
    private func typedMapping<Field: RawRepresentable & Hashable>(_ type: Field.Type) -> [Field: Int]
    where Field.RawValue == String {
        var out: [Field: Int] = [:]
        for (k, v) in mapping {
            if let field = Field(rawValue: k) { out[field] = v }
        }
        return out
    }

    private func categoryName(_ id: UUID?) -> String {
        guard let id, let match = expenseCategories.first(where: { $0.id == id }) else {
            return "Uncategorized"
        }
        return match.name
    }

    // MARK: Initial empty state

    private var initialEmptyState: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Import \(kind.title.lowercased())")
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
                        csvText = kind.sampleCSV
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
                Text("Columns: \(kind.columnsHint). Header aliases are detected automatically; map any columns that don't match below.")
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
                        csvText = kind.sampleCSV
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

    private var mappingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Map columns", systemImage: "tablecells")
                    .font(.headline)
                Text("Detected \(headers.count) column\(headers.count == 1 ? "" : "s"). Match each Finmate field to a column. Required fields are marked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(kind.fields, id: \.key) { field in
                    HStack {
                        Text(field.name)
                            .font(.subheadline.weight(.medium))
                        if field.required {
                            Text("Required")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Picker(field.name, selection: columnBinding(for: field.key)) {
                            Text("—  Ignore").tag(-1)
                            ForEach(Array(headers.enumerated()), id: \.offset) { idx, token in
                                Text(token.isEmpty ? "Column \(idx + 1)" : token).tag(idx)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityLabel("\(field.name) column")
                    }
                    .accessibilityElement(children: .combine)
                }

                if !requiredFieldsMapped {
                    Label("Map all required fields to continue.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    runPreview()
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

    private func previewSummaryCard(_ preview: UnifiedPreview) -> some View {
        GlassCard {
            HStack {
                summaryStat(value: preview.validCount, label: "Valid", color: .green)
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

    private func validRowsCard(_ preview: UnifiedPreview) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Valid rows").font(.headline)
                ForEach(preview.rows) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.subheadline.weight(.medium))
                            Text(row.subtitle)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.amount.formatted())
                            .font(.subheadline.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func errorsCard(_ preview: UnifiedPreview) -> some View {
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

    private func importButton(_ preview: UnifiedPreview) -> some View {
        Button {
            guard let pending else { return }
            Task { await performImport(pending) }
        } label: {
            Label("Import \(preview.validCount) \(kind.singular)\(preview.validCount == 1 ? "" : "s")",
                  systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(preview.validCount == 0)
    }

    /// Route the typed valid rows to the matching repository (same create path as
    /// manual add), then reset to the empty state with a success banner.
    private func performImport(_ pending: PendingImport) async {
        let count = pending.count
        switch pending {
        case .subscriptions(let rows):
            for r in rows { await store.add(r) }
        case .income(let rows):
            for r in rows { await cashFlowStore?.addIncome(r) }
        case .fixed(let rows):
            for r in rows { await cashFlowStore?.addFixed(r) }
        case .variable(let rows):
            for r in rows { await cashFlowStore?.addVariable(r) }
        }
        resetFlow()
        csvText = ""
        importedCount = count
    }
}
