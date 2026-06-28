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
            VStack(spacing: FinmateTokens.spacing) {
                header

                GlassCard {
                    VStack(spacing: 0) {
                        DetailRow(label: "Monthly", value: subscription.monthlyAmount.formatted())
                        Divider().padding(.vertical, 8)
                        DetailRow(label: "Annual", value: annualAmount.formatted())
                        Divider().padding(.vertical, 8)
                        DetailRow(label: "Billing", value: subscription.billingPeriod.rawValue.capitalized)
                    }
                }

                GlassCard {
                    VStack(spacing: 0) {
                        DetailRow(label: "Category", value: inferredCategory)
                        Divider().padding(.vertical, 8)
                        DetailRow(label: "Usage", value: subscription.usageState.rawValue.capitalized)
                        Divider().padding(.vertical, 8)
                        DetailRow(label: "Payment", value: paymentMethodLabel(subscription.paymentMethod))
                    }
                }

                if let urlString = subscription.vendorURL, let url = vendorURL(from: urlString) {
                    Button {
                        openURL(url)
                    } label: {
                        GlassCard {
                            HStack {
                                Label("Open website", systemImage: "safari.fill")
                                    .font(.headline)
                                Spacer()
                                Text(urlString).font(.caption).foregroundStyle(.secondary)
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(subscription.name) website in Safari")
                }

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete subscription", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle(subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(FinmateGradient())
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
            HStack(spacing: 16) {
                Image(systemName: subscription.icon ?? "creditcard.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscription.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(subscription.monthlyAmount.formatted() + " / mo")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
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
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit()).fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
    }
}
