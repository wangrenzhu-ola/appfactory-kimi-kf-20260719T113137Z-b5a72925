import Foundation

/// Centralized en-US user-facing copy. Every string rendered by the app
/// comes from here so locale, tone and the medical-disclaimer boundary stay
/// auditable in one place. All strings must remain ASCII-only English.
public enum Copy {

    public enum Common {
        public static let save = "Save"
        public static let cancel = "Cancel"
        public static let delete = "Delete"
        public static let edit = "Edit"
        public static let retry = "Try again"
        public static let done = "Done"
        public static let back = "Back"
        public static let confirm = "Confirm"
        public static let savedToast = "Meal saved"
        public static let updatedToast = "Meal updated"
        public static let deletedToast = "Meal deleted"
        public static let settingsSavedToast = "Settings saved"
    }

    public enum Onboarding {
        public static let title = "Welcome to CarbLens"
        public static let subtitle = "See the glucose impact of your meal before you eat."
        public static let goalHeading = "What is your goal?"
        public static let budgetHeading = "Daily carb budget"
        public static let budgetHint = "Most steady-glucose plans land between 100 and 160 grams."
        public static let cameraHeading = "Camera access"
        public static let cameraBody = "CarbLens needs your camera to estimate carbs from a photo of your plate. Photos are analyzed once, then deleted."
        public static let startButton = "Start tracking"
        public static let stepFormat = "Step %d of 3"
    }

    public enum Home {
        public static let title = "Today"
        public static let budgetRemaining = "g carbs left today"
        public static let budgetOver = "g over budget"
        public static let mealsToday = "Today's meals"
        public static let snapButton = "Snap a meal"
        public static let emptyTitle = "No meals yet today"
        public static let emptyBody = "Take a photo of your next meal to see its carb load and glucose impact before you eat."
        public static let emptyCTA = "Snap your first meal"
        public static let impactSummary = "glucose impact today"
    }

    public enum Capture {
        public static let title = "Snap your meal"
        public static let takePhoto = "Take photo"
        public static let choosePhoto = "Choose from library"
        public static let usePhoto = "Analyze this photo"
        public static let retake = "Retake"
        public static let analyzing = "Analyzing your meal…"
        public static let cameraDeniedTitle = "Camera access is off"
        public static let cameraDeniedBody = "Enable camera access in Settings to snap your meal, or log it manually."
        public static let openSettings = "Open Settings"
        public static let manualInstead = "Log manually instead"
    }

    public enum Analysis {
        public static let title = "Review estimate"
        public static let confidenceFormat = "Confidence %d%%"
        public static let totalCarbs = "Total carbs"
        public static let portionLabel = "Portion (g)"
        public static let addFood = "Add a food"
        public static let confirmSave = "Confirm and save"
        public static let editHint = "Adjust portions or swap items — totals update as you edit."
        public static let failureTitle = "We couldn't analyze this photo"
        public static let failureBody = "The photo was too unclear to estimate with confidence. Try again in better light, or log the meal manually."
        public static let failureRetake = "Retake photo"
        public static let failureManual = "Log manually"
        public static let lowConfidenceNotice = "Low confidence — please review each item carefully."
        public static let disclaimer = "Estimates are informational only and are not medical advice, diagnosis, or dosing guidance."
        public static let notSavedNotice = "Nothing is saved until you confirm."
    }

    public enum ManualLog {
        public static let title = "Log manually"
        public static let searchPlaceholder = "Search foods"
        public static let portionLabel = "Portion (g)"
        public static let addButton = "Add"
        public static let saveButton = "Save meal"
        public static let emptySearch = "Type a food name to search the database."
        public static let noResults = "No matching foods. Try a simpler name."
        public static let itemsHeading = "This meal"
    }

    public enum Log {
        public static let title = "Meal log"
        public static let emptyTitle = "No meals yet"
        public static let emptyBody = "Your confirmed meals will show up here with their carb load and glucose impact."
        public static let emptyCTA = "Snap your first meal"
        public static let deleteTitle = "Delete this meal?"
        public static let deleteBody = "This removes the meal from your log and returns its carbs to today's budget. This can't be undone."
        public static let deleteConfirm = "Delete meal"
    }

    public enum MealDetail {
        public static let title = "Meal"
        public static let carbsLabel = "Carbs"
        public static let impactLabel = "Glucose impact"
        public static let editPortion = "Edit portion"
        public static let delete = "Delete meal"
        public static let reanalyze = "Re-estimate"
    }

    public enum Trends {
        public static let title = "Trends"
        public static let week = "Week"
        public static let month = "Month"
        public static let carbsHeading = "Daily carbs"
        public static let impactHeading = "High-impact meals"
        public static let emptyTitle = "No trends yet"
        public static let emptyBody = "Log a few meals and your weekly carb and glucose-impact trends will appear here."
        public static let emptyCTA = "Snap your first meal"
        public static let gramsShort = "g"
    }

    public enum Insights {
        public static let title = "Insights"
        public static let weeklyHeading = "This week"
        public static let helpful = "This was helpful"
        public static let emptyTitle = "No insights yet"
        public static let emptyBody = "After a few days of logged meals, you'll get a weekly read on what's driving your glucose impact."
        public static let emptyCTA = "Snap your first meal"
        public static let relatedMeals = "Related meals"
    }

    public enum Settings {
        public static let title = "Settings"
        public static let goal = "Goal"
        public static let budget = "Daily carb budget"
        public static let units = "Units"
        public static let subscription = "Subscription"
        public static let manageSubscription = "Manage Premium"
        public static let privacy = "Privacy & data"
        public static let exportData = "Export my data"
        public static let freePlan = "Free plan"
        public static let premiumPlan = "Premium"
        public static let scansLeftFormat = "%d free scans left today"
    }

    public enum Paywall {
        public static let title = "CarbLens Premium"
        public static let valueUnlimited = "Unlimited photo estimates"
        public static let valueInsights = "Weekly insights that spot your patterns"
        public static let valueTrends = "Full trend history and exports"
        public static let freeNote = "Free includes 3 photo estimates a day, forever."
        public static let subscribe = "Subscribe"
        public static let restore = "Restore purchase"
        public static let cancelAnytime = "Cancel anytime in App Store settings. No surprises."
        public static let unavailableTitle = "Purchases unavailable right now"
        public static let unavailableBody = "The store couldn't be reached. Check your connection and try again — your free scans are untouched."
        public static let cancelled = "Purchase cancelled."
        public static let restoredNone = "No previous purchase found for this Apple ID."
        public static let premiumActive = "Premium is active"
        public static let renewsFormat = "Renews %@"
        public static let quotaExhaustedTitle = "Out of free scans"
        public static let quotaExhaustedBody = "You've used today's 3 free photo estimates. Go Premium for unlimited, or log manually."
    }

    public enum Privacy {
        public static let title = "Privacy & data"
        public static let photoHeading = "Your photos"
        public static let photoBody = "Photos are used once to estimate your meal, then the original is deleted. Only a small compressed thumbnail is kept so your log has context."
        public static let cameraHeading = "Camera use"
        public static let cameraBody = "The camera is only used to capture meals you choose to log. CarbLens never records video or accesses your photo library without you picking a photo."
        public static let storageHeading = "Where data lives"
        public static let storageBody = "Your meal log, budget and settings are stored on this device. During an estimate, only derived food candidates — never your photo — are sent to the estimation service. Nothing else leaves this device unless you explicitly export it."
        public static let disclaimerHeading = "Not medical advice"
        public static let disclaimerBody = "CarbLens provides informational carb and glucose-impact estimates only. It does not provide medical advice, diagnosis, treatment, or insulin dosing guidance. Always follow your clinician's plan."
        public static let deleteHeading = "Delete everything"
        public static let deleteBody = "Removes all meals, settings and thumbnails from this device."
        public static let deleteButton = "Delete all my data"
        public static let deleteConfirmTitle = "Delete all data?"
        public static let deleteConfirmBody = "All meals, settings and thumbnails will be permanently removed from this device."
        public static let deleteConfirmButton = "Delete everything"
        public static let deletedToast = "All data deleted"
    }

    public enum Errors {
        public static let saveFailed = "Couldn't save. Your edits are still here — try again."
        public static let deleteFailed = "Couldn't delete this meal. Try again."
        public static let exportFailed = "Couldn't export your data. Try again."
        public static let generic = "Something went wrong. Try again."
    }

    public enum Accessibility {
        public static let budgetRing = "Daily carb budget ring"
        public static func budgetRingValue(remaining: Int, budget: Int) -> String {
            "\(remaining) of \(budget) grams of carbs left today"
        }
        public static let snapMeal = "Snap a meal photo"
        public static let mealRow = "Meal entry"
        public static let impactBadge = "Glucose impact level"
        public static let confirmEstimate = "Confirm and save estimate"
        public static let deleteMeal = "Delete this meal"
        public static let editPortion = "Edit portion in grams"
        public static let dismiss = "Dismiss"
    }
}
