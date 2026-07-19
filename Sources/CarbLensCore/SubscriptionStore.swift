import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

public enum SubscriptionError: Error, Equatable {
    case storefrontUnavailable
    case productUnavailable
    case purchaseFailed
    case purchaseCancelled
    case restoreFoundNothing
}

/// One purchasable Premium product as displayed on the paywall.
public struct PremiumProduct: Equatable, Identifiable {
    public var id: String
    public var tier: SubscriptionTier
    public var displayName: String
    public var displayPrice: String
    public var billingPeriod: String

    public init(id: String, tier: SubscriptionTier, displayName: String, displayPrice: String, billingPeriod: String) {
        self.id = id
        self.tier = tier
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.billingPeriod = billingPeriod
    }
}

/// Store abstraction so the paywall logic is testable without StoreKit.
public protocol Storefront {
    func loadProducts() async throws -> [PremiumProduct]
    func purchase(productID: String) async throws -> SubscriptionEntitlement
    func restorePurchases() async throws -> SubscriptionEntitlement
}

/// Offline catalog used when StoreKit is unavailable (older OS, no network,
/// sandbox without products). Prices mirror the configured App Store
/// products so the paywall copy is never blank; purchase attempts report a
/// plain, recoverable unavailable error.
public struct LocalCatalogStorefront: Storefront {
    public init() {}

    public static let monthlyProductID = "com.carblens.premium.monthly"
    public static let yearlyProductID = "com.carblens.premium.yearly"

    public func loadProducts() async throws -> [PremiumProduct] {
        [
            PremiumProduct(
                id: LocalCatalogStorefront.monthlyProductID,
                tier: .premiumMonthly,
                displayName: "Premium Monthly",
                displayPrice: "$4.99",
                billingPeriod: "per month"
            ),
            PremiumProduct(
                id: LocalCatalogStorefront.yearlyProductID,
                tier: .premiumYearly,
                displayName: "Premium Yearly",
                displayPrice: "$39.99",
                billingPeriod: "per year"
            ),
        ]
    }

    public func purchase(productID: String) async throws -> SubscriptionEntitlement {
        throw SubscriptionError.storefrontUnavailable
    }

    public func restorePurchases() async throws -> SubscriptionEntitlement {
        throw SubscriptionError.restoreFoundNothing
    }
}

#if canImport(StoreKit)
/// StoreKit 2 storefront. Requires iOS 15+; on iOS 14 the subscription store
/// keeps the local catalog so the paywall stays readable and purchase
/// surfaces the explicit unavailable state instead of failing silently.
@available(iOS 15.0, macOS 12.0, *)
public final class StoreKitStorefront: Storefront {
    public init() {}

    public func loadProducts() async throws -> [PremiumProduct] {
        let ids = [LocalCatalogStorefront.monthlyProductID, LocalCatalogStorefront.yearlyProductID]
        let products = try await Product.products(for: ids)
        if products.isEmpty { throw SubscriptionError.productUnavailable }
        return products.compactMap { product in
            let tier: SubscriptionTier = product.id == LocalCatalogStorefront.yearlyProductID ? .premiumYearly : .premiumMonthly
            return PremiumProduct(
                id: product.id,
                tier: tier,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                billingPeriod: tier == .premiumYearly ? "per year" : "per month"
            )
        }
    }

    public func purchase(productID: String) async throws -> SubscriptionEntitlement {
        guard let product = try await Product.products(for: [productID]).first else {
            throw SubscriptionError.productUnavailable
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw SubscriptionError.purchaseFailed
            }
            await transaction.finish()
            return SubscriptionEntitlement(
                tier: productID == LocalCatalogStorefront.yearlyProductID ? .premiumYearly : .premiumMonthly,
                expiresAt: transaction.expirationDate,
                willRenew: true,
                originalTransactionID: String(transaction.originalID)
            )
        case .userCancelled:
            throw SubscriptionError.purchaseCancelled
        default:
            throw SubscriptionError.purchaseFailed
        }
    }

    public func restorePurchases() async throws -> SubscriptionEntitlement {
        var latest: SubscriptionEntitlement?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == LocalCatalogStorefront.monthlyProductID
                    || transaction.productID == LocalCatalogStorefront.yearlyProductID else { continue }
            latest = SubscriptionEntitlement(
                tier: transaction.productID == LocalCatalogStorefront.yearlyProductID ? .premiumYearly : .premiumMonthly,
                expiresAt: transaction.expirationDate,
                willRenew: true,
                originalTransactionID: String(transaction.originalID)
            )
        }
        guard let entitlement = latest else { throw SubscriptionError.restoreFoundNothing }
        return entitlement
    }
}
#endif

/// Free scan quota: 3 analyses per calendar day on the free tier.
public struct ScanQuota: Equatable {
    public static let freeDailyLimit = 3

    public var date: Date
    public var usedScans: Int

    public init(date: Date, usedScans: Int = 0) {
        self.date = date
        self.usedScans = usedScans
    }

    public func remaining(isPremium: Bool, on day: Date, calendar: Calendar = .current) -> Int {
        if isPremium { return .max }
        guard calendar.isDate(date, inSameDayAs: day) else { return ScanQuota.freeDailyLimit }
        return max(ScanQuota.freeDailyLimit - usedScans, 0)
    }

    public mutating func consume(on day: Date, calendar: Calendar = .current) {
        if calendar.isDate(date, inSameDayAs: day) {
            usedScans += 1
        } else {
            date = calendar.startOfDay(for: day)
            usedScans = 1
        }
    }
}

/// Owns entitlement, free-tier scan quota and paywall presentation state.
public final class SubscriptionStore: ObservableObject {
    @Published public private(set) var entitlement: SubscriptionEntitlement
    @Published public private(set) var quota: ScanQuota
    @Published public private(set) var products: [PremiumProduct] = []

    private let storefront: Storefront
    private let quotaURL: URL
    private let entitlementURL: URL
    private let calendar: Calendar

    public init(storefront: Storefront, directory: URL, now: Date = Date(), calendar: Calendar = .current) {
        self.storefront = storefront
        self.quotaURL = directory.appendingPathComponent("scan_quota.json")
        self.entitlementURL = directory.appendingPathComponent("entitlement.json")
        self.calendar = calendar
        if let data = try? Data(contentsOf: quotaURL),
           var decoded = try? JSONDecoder().decode(ScanQuotaCodable.self, from: data) {
            if !calendar.isDate(decoded.date, inSameDayAs: now) {
                decoded = ScanQuotaCodable(date: calendar.startOfDay(for: now), usedScans: 0)
            }
            self.quota = ScanQuota(date: decoded.date, usedScans: decoded.usedScans)
        } else {
            self.quota = ScanQuota(date: calendar.startOfDay(for: now))
        }
        if let data = try? Data(contentsOf: entitlementURL),
           let decoded = try? JSONDecoder().decode(SubscriptionEntitlement.self, from: data) {
            self.entitlement = decoded
        } else {
            self.entitlement = SubscriptionEntitlement()
        }
    }

    public var isPremium: Bool { entitlement.isPremium }

    public func scansRemaining(on day: Date = Date()) -> Int {
        quota.remaining(isPremium: isPremium, on: day, calendar: calendar)
    }

    /// One analysis consumes one daily scan on the free tier. Returns false
    /// when the quota is exhausted and the paywall must be shown instead.
    @discardableResult
    public func consumeScan(on day: Date = Date()) -> Bool {
        guard isPremium || scansRemaining(on: day) > 0 else { return false }
        if !isPremium {
            quota.consume(on: day, calendar: calendar)
            persistQuota()
        }
        return true
    }

    public func refreshProducts() async {
        products = (try? await storefront.loadProducts()) ?? []
    }

    /// Product list with the local catalog as guaranteed fallback so the
    /// paywall always renders real prices.
    public func displayProducts() async -> [PremiumProduct] {
        if products.isEmpty { await refreshProducts() }
        if !products.isEmpty { return products }
        return (try? await LocalCatalogStorefront().loadProducts()) ?? []
    }

    @discardableResult
    public func purchase(productID: String) async throws -> SubscriptionEntitlement {
        let updated = try await storefront.purchase(productID: productID)
        entitlement = updated
        persistEntitlement()
        return updated
    }

    @discardableResult
    public func restore() async throws -> SubscriptionEntitlement {
        let updated = try await storefront.restorePurchases()
        entitlement = updated
        persistEntitlement()
        return updated
    }

    /// Clears only locally persisted app data after the user confirms Delete all data.
    /// StoreKit ownership remains with Apple and is not modified here.
    public func resetLocalData(now: Date = Date()) {
        entitlement = SubscriptionEntitlement()
        quota = ScanQuota(date: calendar.startOfDay(for: now))
        products = []
        try? FileManager.default.removeItem(at: quotaURL)
        try? FileManager.default.removeItem(at: entitlementURL)
    }

    private struct ScanQuotaCodable: Codable {
        var date: Date
        var usedScans: Int
    }

    private func persistQuota() {
        guard let data = try? JSONEncoder().encode(ScanQuotaCodable(date: quota.date, usedScans: quota.usedScans)) else { return }
        try? FileManager.default.createDirectory(at: quotaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: quotaURL, options: .atomic)
    }

    private func persistEntitlement() {
        guard let data = try? JSONEncoder().encode(entitlement) else { return }
        try? FileManager.default.createDirectory(at: entitlementURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: entitlementURL, options: .atomic)
    }
}
