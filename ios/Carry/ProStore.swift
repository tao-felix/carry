import Foundation
import StoreKit
import UIKit

/// The single plan through StoreKit 2: one set of features, two billing periods (yearly first).
/// Writes `license.json` (§7) whenever the entitlement changes and on every launch while it is active;
/// the Mac verifies the JWS offline.
@MainActor
final class ProStore: ObservableObject {
    static let yearlyID = "app.carry.pro.annual"
    static let monthlyID = "app.carry.pro"
    static let productIDs = [yearlyID, monthlyID]

    enum Availability: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    @Published private(set) var availability: Availability = .loading
    @Published private(set) var product: Product?   // yearly, the primary offer
    @Published private(set) var monthly: Product?
    @Published private(set) var isSubscribed = false
    @Published private(set) var expiresAt: Date?
    @Published private(set) var willRenew = true
    @Published private(set) var licenseWrittenAt: Date?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    private var store: ContainerStore?
    private var updates: Task<Void, Never>?
    private var demoPrice: String?
    private var demoMonthly: String?

    /// `$39.99 / year`, from the App Store.
    var priceLine: String? {
        if let product { return "\(product.displayPrice) / \(Self.periodWord(product))" }
        return demoPrice
    }

    /// `$5.99 / month`, the same plan billed monthly.
    var monthlyLine: String? {
        if let monthly { return "\(monthly.displayPrice) / \(Self.periodWord(monthly))" }
        return demoMonthly
    }

    /// DEBUG simulator runs without a StoreKit configuration show a placeholder price.
    var isDemo: Bool { product == nil && demoPrice != nil }

    func start(store: ContainerStore) async {
        self.store = store
        updates?.cancel()
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.apply(result)
                if case .verified(let transaction) = result { await transaction.finish() }
            }
        }
        await load()
        await refreshEntitlement()
    }

    func load() async {
        availability = .loading
        do {
            let found = try await Product.products(for: Self.productIDs)
            product = found.first { $0.id == Self.yearlyID }
            monthly = found.first { $0.id == Self.monthlyID }
            if product != nil || monthly != nil {
                if product == nil { product = monthly; monthly = nil }
                availability = .ready
            } else {
                availability = .unavailable("The App Store has no price for Carry Pro yet.")
            }
        } catch {
            availability = .unavailable("Could not reach the App Store. \(error.localizedDescription)")
        }
        #if DEBUG
        if product == nil, LaunchOptions.demo {
            demoPrice = "$39.99 / year"
            demoMonthly = "$5.99 / month"
            availability = .ready
        }
        #endif
    }

    /// Reads the current entitlement and writes `license.json` when Pro is active.
    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            active = true
            expiresAt = transaction.expirationDate
            await writeLicense(result.jwsRepresentation, productID: transaction.productID)
        }
        isSubscribed = active
        if !active { expiresAt = nil }
        if active, let statuses = try? await product?.subscription?.status {
            for status in statuses {
                if case .verified(let info) = status.renewalInfo { willRenew = info.willAutoRenew }
            }
        }
    }

    func purchase(monthly wantsMonthly: Bool = false) async {
        guard let product = wantsMonthly ? (monthly ?? product) : product else {
            if isDemo { setMessage("Simulator placeholder. Run from Xcode with Carry.storekit to test a purchase.", error: false) }
            return
        }
        busy = true
        defer { busy = false }
        do {
            switch try await purchaseResult(product) {
            case .success(let verification):
                await apply(verification)
                if case .verified(let transaction) = verification { await transaction.finish() }
                setMessage(isSubscribed ? "Pro is on. license.json written; your Mac verifies it offline."
                                        : "The App Store could not verify this purchase.", error: !isSubscribed)
            case .userCancelled:
                message = nil
            case .pending:
                setMessage("Waiting for approval (Ask to Buy).", error: false)
            @unknown default:
                break
            }
        } catch {
            setMessage(error.localizedDescription, error: true)
        }
    }

    private func purchaseResult(_ product: Product) async throws -> Product.PurchaseResult {
        if #available(iOS 18.2, *),
           let scene = UIApplication.shared.connectedScenes
               .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            return try await product.purchase(confirmIn: scene)
        }
        return try await product.purchase()
    }

    func restore() async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            setMessage(isSubscribed ? "Restored. Pro is on." : "No Carry Pro subscription on this Apple Account.",
                       error: !isSubscribed)
        } catch {
            setMessage(error.localizedDescription, error: true)
        }
    }

    private func apply(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID) else { return }
        if transaction.revocationDate != nil {
            isSubscribed = false
            expiresAt = nil
            return
        }
        if let expiry = transaction.expirationDate, expiry < Date() {
            isSubscribed = false
            expiresAt = expiry
            return
        }
        isSubscribed = true
        expiresAt = transaction.expirationDate
        await writeLicense(result.jwsRepresentation, productID: transaction.productID)
    }

    private func writeLicense(_ jws: String, productID: String) async {
        guard let store else { return }
        try? await store.writeLicense(License(productId: productID, jws: jws))
        licenseWrittenAt = Date()
    }

    private func setMessage(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }

    private static func periodWord(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "month" }
        switch period.unit {
        case .day: return period.value == 7 ? "week" : "\(period.value) days"
        case .week: return period.value == 1 ? "week" : "\(period.value) weeks"
        case .month: return period.value == 1 ? "month" : "\(period.value) months"
        case .year: return period.value == 1 ? "year" : "\(period.value) years"
        @unknown default: return "month"
        }
    }
}
