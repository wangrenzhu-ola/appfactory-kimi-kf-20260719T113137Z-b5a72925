import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The in-flight capture → analyze → confirm session. Lives only until the
/// user confirms or discards; nothing here is persisted before confirmation.
public final class CaptureSession: ObservableObject {
    public enum Stage: Equatable {
        case picking
        case confirmingPhoto(Data)
        case analyzing
        case review(EditableEstimate)
        case failed(String)
    }

    @Published public var stage: Stage = .picking
    /// Original photo kept only for the analysis round-trip and the possible
    /// retry; deleted from memory and disk right after analysis.
    public private(set) var originalPhoto: Data?
    /// Small JPEG thumbnail kept for the saved log entry.
    public private(set) var thumbnailRef: String?

    private let analyzer: MealAnalyzer
    private let subscriptionStore: SubscriptionStore

    public init(analyzer: MealAnalyzer, subscriptionStore: SubscriptionStore) {
        self.analyzer = analyzer
        self.subscriptionStore = subscriptionStore
    }

    public func begin() {
        stage = .picking
        originalPhoto = nil
        thumbnailRef = nil
    }

    public func photoPicked(_ data: Data) {
        originalPhoto = data
        stage = .confirmingPhoto(data)
    }

    /// Runs the analysis. Consumes one free scan on the free tier.
    public func analyze() async {
        guard let photo = originalPhoto else { return }
        guard subscriptionStore.consumeScan() else {
            stage = .failed("quota")
            return
        }
        stage = .analyzing
        do {
            let estimate = try await analyzer.analyze(photo: PhotoInput(pixelBytes: photo))
            thumbnailRef = CaptureSession.makeThumbnailRef()
            stage = .review(EditableEstimate(estimate: estimate))
        } catch let error as AnalysisError {
            switch error {
            case .lowConfidence:
                stage = .failed(Copy.Analysis.failureTitle)
            case .imageUnreadable, .serviceUnavailable:
                stage = .failed(Copy.Analysis.failureTitle)
            }
        } catch {
            stage = .failed(Copy.Analysis.failureTitle)
        }
    }

    /// Called after the user confirms or abandons the estimate. The original
    /// photo bytes are released here — only the compressed thumbnail survives.
    public func discardOriginalPhoto() {
        originalPhoto = nil
    }

    public static func makeThumbnailRef() -> String {
        "thumb-\(UUID().uuidString).jpg"
    }
}

/// Root application model: owns the stores and routes the capture session
/// into the confirmed log.
public final class AppViewModel: ObservableObject {
    @Published public var mealStore: MealStore
    @Published public var profileStore: ProfileStore
    @Published public var subscriptionStore: SubscriptionStore
    @Published public private(set) var captureSession: CaptureSession
    @Published public var toast: String?
    @Published public var showingPaywall = false
    @Published public var paywallReason: String?

    private let analyzer: MealAnalyzer

    public init(dataDirectory: URL, analyzer: MealAnalyzer) {
        let meals = MealStore(storage: JSONMealStorage(directory: dataDirectory))
        self.mealStore = meals
        self.profileStore = ProfileStore(directory: dataDirectory)
        let subscription = SubscriptionStore(storefront: AppViewModel.makeStorefront(), directory: dataDirectory)
        self.subscriptionStore = subscription
        self.analyzer = analyzer
        self.captureSession = CaptureSession(analyzer: analyzer, subscriptionStore: subscription)
    }

    public static func makeStorefront() -> Storefront {
        #if canImport(StoreKit)
        if #available(iOS 15.0, *) {
            return StoreKitStorefront()
        }
        #endif
        return LocalCatalogStorefront()
    }

    public func startCapture() {
        captureSession = CaptureSession(analyzer: analyzer, subscriptionStore: subscriptionStore)
        captureSession.begin()
    }

    /// Confirmation gate: only here does an estimate become a MealLog entry.
    public func confirmEstimate(_ editable: EditableEstimate) {
        guard let data = captureSession.originalPhoto else { return }
        let thumbRef = CaptureSession.makeThumbnailRef()
        // Compress the thumbnail; the original is discarded immediately after.
        #if canImport(UIKit)
        if let image = UIImage(data: data),
           let thumb = image.jpegData(compressionQuality: 0.3) {
            try? mealStore.saveThumbnail(thumb, named: thumbRef)
        }
        #endif
        let meal = editable.confirmedMeal(thumbnailLocalRef: thumbRef)
        captureSession.discardOriginalPhoto()
        do {
            _ = try mealStore.save(meal)
            toast = Copy.Common.savedToast
        } catch {
            toast = Copy.Errors.saveFailed
        }
    }

    public func deleteMeal(id: UUID) {
        do {
            _ = try mealStore.delete(id: id)
            toast = Copy.Common.deletedToast
        } catch {
            toast = Copy.Errors.deleteFailed
        }
    }

    public func updateMeal(_ meal: MealLog) -> Bool {
        do {
            _ = try mealStore.save(meal)
            toast = Copy.Common.updatedToast
            return true
        } catch {
            toast = Copy.Errors.saveFailed
            return false
        }
    }

    public func presentPaywall(reason: String) {
        paywallReason = reason
        showingPaywall = true
    }

    public func exportData() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = ExportPayload(
            exportedAt: Date(),
            profile: profileStore.profile,
            meals: mealStore.sortedMeals
        )
        let data = try encoder.encode(payload)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("carblens-export.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    public func deleteAllData() throws {
        try mealStore.deleteAll()
    }
}

private struct ExportPayload: Codable {
    var exportedAt: Date
    var profile: UserProfile
    var meals: [MealLog]
}
