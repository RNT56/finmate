import SwiftUI
import Domain

// MARK: - Subscription detail (docs/02 — subscription detail flow)
// Pushed from the Subscriptions list. Shows normalized monthly + annual amounts
// (computed through Domain.BillingPeriodMath — never Double), usage state, payment
// method, an opens-in-Safari vendor link, and a delete action wired to the store.

struct SubscriptionDetailView: View {
    let subscription: Subscription
    let store: SubscriptionsStore

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false

    /// Header glyph size + slot — scale with Dynamic Type so the icon tracks the title.
    @ScaledMetric(relativeTo: .title2) private var headerIconSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title2) private var headerIconSlot: CGFloat = 48

    /// Canonical annual amount in the subscription's own currency (Domain math).
    private var annualAmount: Money {
        Money(
            minorUnits: BillingPeriodMath.annualMinorUnits(
                amountMinor: subscription.amountMinor, period: subscription.billingPeriod),
            currency: subscription.currency)
    }

    /// Display category derived from the service name (sample data has no category
    /// rows yet) — docs/13 §10 inference.
    private var inferredCategory: String {
        SubscriptionPredictor.inferCategory(name: subscription.name)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateSpacing.md) {
                // Group the detail's stacked glass surfaces so iOS 26 blends them as
                // one cluster (no-op container ≤25).
                FinmateGlassGroup(spacing: FinmateSpacing.md) {
                  VStack(spacing: FinmateSpacing.md) {
                    header

                    GlassCard {
                        VStack(spacing: 0) {
                            DetailRow(label: "Monthly", value: subscription.monthlyAmount.formatted())
                            Divider().padding(.vertical, FinmateSpacing.sm)
                            DetailRow(label: "Annual", value: annualAmount.formatted())
                            Divider().padding(.vertical, FinmateSpacing.sm)
                            DetailRow(label: "Billing", value: subscription.billingPeriod.rawValue.capitalized)
                        }
                    }

                    GlassCard {
                        VStack(spacing: 0) {
                            DetailRow(label: "Category", value: inferredCategory)
                            Divider().padding(.vertical, FinmateSpacing.sm)
                            DetailRow(label: "Usage", value: subscription.usageState.rawValue.capitalized)
                            Divider().padding(.vertical, FinmateSpacing.sm)
                            DetailRow(label: "Payment", value: paymentMethodLabel(subscription.paymentMethod))
                        }
                    }
                  }
                }

                if let urlString = subscription.vendorURL, let url = vendorURL(from: urlString) {
                    Button {
                        openURL(url)
                    } label: {
                        GlassCard {
                            HStack {
                                Label("Open website", systemImage: "safari.fill")
                                    .font(FinmateType.headline)
                                Spacer()
                                Text(urlString).font(FinmateType.caption).foregroundStyle(FinmateColor.labelSecondary)
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(FinmateColor.bronze)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(subscription.name) website in Safari")
                    .accessibilityHint("Opens in Safari")
                }

                GlassButton("Delete subscription", systemImage: "trash",
                            kind: .destructive, fullWidth: true) {
                    showingDeleteConfirm = true
                }
                .padding(.top, FinmateSpacing.xs)
            }
            .padding()
        }
        .navigationTitle(subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(FinmateBackground())
        .confirmationDialog("Delete \(subscription.name)?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.delete(id: subscription.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the subscription from your tracker. This cannot be undone.")
        }
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: FinmateSpacing.lg) {
                Image(systemName: subscription.icon ?? "creditcard.fill")
                    .font(.system(size: headerIconSize))
                    .foregroundStyle(FinmateColor.bronze)
                    .frame(width: headerIconSlot)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: FinmateSpacing.xs) {
                    Text(subscription.name)
                        .font(FinmateType.title2.weight(.bold))
                    Text(subscription.monthlyAmount.formatted() + " / mo")
                        .font(FinmateType.money(.subheadline, weight: .regular))
                        .foregroundStyle(FinmateColor.labelSecondary)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(subscription.name), \(subscription.monthlyAmount.formatted()) per month")
        }
    }

    /// Accept bare hosts ("netflix.com") as well as full URLs.
    private func vendorURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") { return URL(string: trimmed) }
        return URL(string: "https://" + trimmed)
    }

    private func paymentMethodLabel(_ method: PaymentMethod) -> String {
        switch method {
        case .creditCard:   return "Credit Card"
        case .debitCard:    return "Debit Card"
        case .paypal:       return "PayPal"
        case .bankTransfer: return "Bank Transfer"
        case .applePay:     return "Apple Pay"
        case .googlePay:    return "Google Pay"
        case .crypto:       return "Crypto"
        case .other:        return "Other"
        }
    }
}

/// A label/value row used inside detail glass cards.
struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(FinmateType.body).foregroundStyle(FinmateColor.labelSecondary)
            Spacer()
            Text(value).font(FinmateType.money(.body, weight: .medium))
        }
        .accessibilityElement(children: .combine)
    }
}
