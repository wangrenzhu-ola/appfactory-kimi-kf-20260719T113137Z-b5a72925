import SwiftUI

/// /onboarding — goal, daily carb budget, camera permission. Three steps
/// with progress, then the profile persists and the home tab appears.
struct OnboardingView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var profileStore: ProfileStore
    @State private var step = 0
    @State private var goal: GlucoseGoalType = .prediabetesSteady
    @State private var budget: Double = 130

    var body: some View {
        NavigationView {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                VStack(spacing: 20) {
                    progressIndicator
                    Spacer()
                    stepContent
                    Spacer()
                    nextButton
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Theme.teal : Theme.tealSoft)
                    .frame(height: 4)
            }
        }
        .accessibilityLabel(Text(String(format: Copy.Onboarding.stepFormat, step + 1)))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            VStack(spacing: 20) {
                GlucoseCurveIllustration()
                    .frame(height: 180)
                Text(Copy.Onboarding.title)
                    .font(.title.weight(.bold))
                    .foregroundColor(Theme.ink)
                Text(Copy.Onboarding.subtitle)
                    .font(.subheadline)
                    .foregroundColor(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                Text(Copy.Onboarding.goalHeading)
                    .font(.headline)
                    .foregroundColor(Theme.ink)
                VStack(spacing: 10) {
                    ForEach(GlucoseGoalType.allCases, id: \.self) { option in
                        Button(action: { goal = option }) {
                            HStack {
                                Text(option.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(goal == option ? .white : Theme.ink)
                                Spacer()
                                if goal == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(12)
                            .background(goal == option ? Theme.teal : Theme.surface)
                            .cornerRadius(Theme.chipRadius)
                        }
                        .accessibilityLabel(Text(option.displayName))
                    }
                }
            }
        case 1:
            VStack(spacing: 20) {
                Text(Copy.Onboarding.budgetHeading)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Theme.ink)
                Text(String(format: "%.0f g", budget))
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.teal)
                Slider(value: $budget, in: 60...250, step: 5)
                    .accentColor(Theme.teal)
                    .accessibilityLabel(Text(Copy.Onboarding.budgetHeading))
                Text(Copy.Onboarding.budgetHint)
                    .font(.caption)
                    .foregroundColor(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
        default:
            VStack(spacing: 20) {
                PlateIllustration()
                    .frame(height: 160)
                Text(Copy.Onboarding.cameraHeading)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Theme.ink)
                Text(Copy.Onboarding.cameraBody)
                    .font(.subheadline)
                    .foregroundColor(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private var nextButton: some View {
        Button(action: advance) {
            Text(step == 2 ? Copy.Onboarding.startButton : "Continue")
                .primaryButtonStyle()
        }
        .accessibilityLabel(Text(step == 2 ? Copy.Onboarding.startButton : "Continue"))
    }

    private func advance() {
        if step == 2 {
            #if canImport(UIKit)
            CameraPermission.request { _ in }
            #endif
            completeOnboarding()
        } else {
            withAnimation { step += 1 }
        }
    }

    private func completeOnboarding() {
        do {
            try profileStore.update { profile in
                profile.goalType = goal
                profile.dailyCarbBudget = budget
                profile.onboardingCompleted = true
            }
        } catch {
            viewModel.toast = Copy.Errors.generic
        }
    }
}

/// /home — today's budget ring, impact split, today's meals.
struct HomeView: View {
    @EnvironmentObject private var mealStore: MealStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    let onSnap: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                let summary = mealStore.dailySummary(for: Date(), budget: profileStore.profile.dailyCarbBudget)
                BudgetRingView(summary: summary)
                    .frame(width: 220, height: 220)
                    .padding(.top, 12)
                if !subscriptionStore.isPremium {
                    Text(String(format: Copy.Settings.scansLeftFormat, subscriptionStore.scansRemaining()))
                        .font(.caption)
                        .foregroundColor(Theme.inkSoft)
                }
                if summary.mealCount == 0 {
                    EmptyStateView(
                        title: Copy.Home.emptyTitle,
                        message: Copy.Home.emptyBody,
                        ctaTitle: Copy.Home.emptyCTA,
                        ctaAction: onSnap
                    ) {
                        PlateIllustration()
                    }
                } else {
                    impactStrip(summary: summary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Copy.Home.mealsToday)
                            .font(.headline)
                            .foregroundColor(Theme.ink)
                        ForEach(mealStore.meals(on: Date())) { meal in
                            NavigationLink(destination: MealDetailView(mealID: meal.id)) {
                                MealRow(meal: meal)
                            }
                            .accessibilityLabel(Text(Copy.Accessibility.mealRow))
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarTitle(Copy.Home.title, displayMode: .large)
    }

    private func impactStrip(summary: DailySummary) -> some View {
        let todaysMeals = mealStore.meals(on: Date())
        let low = todaysMeals.filter { $0.impactLevel == .low }.count
        let medium = todaysMeals.filter { $0.impactLevel == .medium }.count
        let high = todaysMeals.filter { $0.impactLevel == .high }.count
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(Copy.Home.impactSummary)
                    .font(.caption)
                    .foregroundColor(Theme.inkSoft)
                HStack(spacing: 16) {
                    impactCount(level: .low, count: low)
                    impactCount(level: .medium, count: medium)
                    impactCount(level: .high, count: high)
                }
            }
        }
    }

    private func impactCount(level: GlucoseImpactLevel, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.impactColor(level)).frame(width: 10, height: 10)
            Text("\(count)")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(Theme.ink)
        }
        .accessibilityLabel(Text("\(level.displayName): \(count)"))
    }
}

/// Shared meal row used by home and log.
struct MealRow: View {
    let meal: MealLog

    var body: some View {
        HStack(spacing: 12) {
            MealThumbnail(ref: meal.thumbnailLocalRef)
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.items.first?.name ?? "Meal")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                Text(meal.capturedAt, style: .time)
                    .font(.caption)
                    .foregroundColor(Theme.inkSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                GramsText(meal.totalCarbsGrams)
                ImpactBadge(level: meal.impactLevel)
            }
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(Theme.chipRadius)
    }
}
