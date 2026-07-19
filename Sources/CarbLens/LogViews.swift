import SwiftUI

/// /log — timeline of confirmed meals, grouped by day, swipe-to-delete with
/// a mandatory confirmation dialog.
struct LogView: View {
    @EnvironmentObject private var mealStore: MealStore
    @EnvironmentObject private var viewModel: AppViewModel
    let onSnap: () -> Void
    @State private var pendingDelete: MealLog?

    var body: some View {
        Group {
            if mealStore.meals.isEmpty {
                ScrollView {
                    EmptyStateView(
                        title: Copy.Log.emptyTitle,
                        message: Copy.Log.emptyBody,
                        ctaTitle: Copy.Log.emptyCTA,
                        ctaAction: onSnap
                    ) {
                        PlateIllustration()
                    }
                }
            } else {
                List {
                    ForEach(groupedDays, id: \.0) { day, meals in
                        Section(header: Text(day, style: .date)) {
                            ForEach(meals) { meal in
                                NavigationLink(destination: MealDetailView(mealID: meal.id)) {
                                    MealRow(meal: meal)
                                }
                                .accessibilityLabel(Text(Copy.Accessibility.mealRow))
                            }
                            .onDelete { offsets in
                                if let index = offsets.first {
                                    pendingDelete = meals[index]
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarTitle(Copy.Log.title, displayMode: .large)
        .alert(item: $pendingDelete) { meal in
            Alert(
                title: Text(Copy.Log.deleteTitle),
                message: Text(Copy.Log.deleteBody),
                primaryButton: .destructive(Text(Copy.Log.deleteConfirm)) {
                    viewModel.deleteMeal(id: meal.id)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var groupedDays: [(Date, [MealLog])] {
        let calendar = Calendar.current
        var groups: [Date: [MealLog]] = [:]
        for meal in mealStore.sortedMeals {
            let day = calendar.startOfDay(for: meal.capturedAt)
            groups[day, default: []].append(meal)
        }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }
}

/// /meal/:id — detail, portion editing, delete with confirmation.
struct MealDetailView: View {
    let mealID: UUID
    @EnvironmentObject private var mealStore: MealStore
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.presentationMode) private var presentationMode
    @State private var editingItem: FoodItem?
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private var meal: MealLog? { mealStore.meal(id: mealID) }

    var body: some View {
        ScrollView {
            if let meal = meal {
                VStack(spacing: 16) {
                    if let error = errorMessage {
                        ErrorBanner(message: error, retryTitle: Copy.Common.retry) {
                            errorMessage = nil
                        }
                    }
                    header(meal)
                    ForEach(Array(meal.items.enumerated()), id: \.element.id) { _, item in
                        itemRow(meal: meal, item: item)
                    }
                    totalsCard(meal)
                    deleteButton
                }
                .padding()
            } else {
                Text(Copy.Errors.generic)
                    .foregroundColor(Theme.inkSoft)
                    .padding()
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarTitle(Copy.MealDetail.title, displayMode: .inline)
        .sheet(item: $editingItem) { item in
            PortionEditorView(item: item) { newPortion in
                updatePortion(itemID: item.id, portion: newPortion)
            }
        }
        .alert(isPresented: $confirmingDelete) {
            Alert(
                title: Text(Copy.Log.deleteTitle),
                message: Text(Copy.Log.deleteBody),
                primaryButton: .destructive(Text(Copy.Log.deleteConfirm)) {
                    viewModel.deleteMeal(id: mealID)
                    presentationMode.wrappedValue.dismiss()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func header(_ meal: MealLog) -> some View {
        HStack(spacing: 16) {
            MealThumbnail(ref: meal.thumbnailLocalRef, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(meal.capturedAt, style: .date)
                    .font(.headline)
                    .foregroundColor(Theme.ink)
                Text(meal.capturedAt, style: .time)
                    .font(.subheadline)
                    .foregroundColor(Theme.inkSoft)
            }
            Spacer()
            ImpactBadge(level: meal.impactLevel)
        }
        .padding()
        .background(Theme.surface)
        .cornerRadius(Theme.cardRadius)
    }

    private func itemRow(meal: MealLog, item: FoodItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.ink)
                Text("\(Int(item.portionGrams)) g")
                    .font(.caption)
                    .foregroundColor(Theme.inkSoft)
            }
            Spacer()
            GramsText(item.carbsGrams)
            Button(action: { editingItem = item }) {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(Theme.teal)
                    .font(.title3)
            }
            .accessibilityLabel(Text(Copy.Accessibility.editPortion))
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(Theme.chipRadius)
    }

    private func totalsCard(_ meal: MealLog) -> some View {
        Card {
            HStack {
                Text(Copy.MealDetail.carbsLabel)
                    .font(.headline)
                Spacer()
                GramsText(meal.totalCarbsGrams)
            }
        }
    }

    private var deleteButton: some View {
        Button(action: { confirmingDelete = true }) {
            Text(Copy.MealDetail.delete)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.amber)
                .cornerRadius(Theme.cardRadius)
        }
        .accessibilityLabel(Text(Copy.Accessibility.deleteMeal))
    }

    private func updatePortion(itemID: UUID, portion: Double) {
        guard var meal = meal else { return }
        guard let index = meal.items.firstIndex(where: { $0.id == itemID }) else { return }
        meal.items[index].portionGrams = portion
        if let ref = FoodDatabase().reference(named: meal.items[index].name) {
            meal.items[index].carbsGrams = ref.carbs(forPortionGrams: portion)
        }
        meal.items[index].editedByUser = true
        if var estimate = meal.estimate {
            estimate.estimatedCarbLoad = meal.totalCarbsGrams
            estimate.level = GlucoseImpactLevel.level(forCarbLoad: meal.totalCarbsGrams)
            meal.estimate = estimate
        }
        if !viewModel.updateMeal(meal) {
            errorMessage = Copy.Errors.saveFailed
        }
    }
}
