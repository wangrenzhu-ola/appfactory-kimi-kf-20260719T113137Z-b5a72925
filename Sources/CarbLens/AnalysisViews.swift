import SwiftUI

/// /analysis — reviewable AI estimate. Every item is editable before the
/// explicit confirm; nothing reaches the log without the confirm button.
struct AnalysisReviewView: View {
    @State var editable: EditableEstimate
    @Binding var isPresented: Bool
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var editingItem: FoodItem?
    @State private var addingFood = false

    init(editable: EditableEstimate, isPresented: Binding<Bool>) {
        _editable = State(initialValue: editable)
        _isPresented = isPresented
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                itemsList
                addFoodButton
                totalsCard
                disclaimer
                confirmButton
            }
            .padding()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarTitle(Copy.Analysis.title, displayMode: .inline)
        .sheet(item: $editingItem) { item in
            PortionEditorView(item: item) { updatedPortion in
                editable.updatePortion(itemID: item.id, portionGrams: updatedPortion, using: FoodDatabase())
            }
        }
        .sheet(isPresented: $addingFood) {
            FoodSearchView { reference in
                editable.addItem(from: reference)
                addingFood = false
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ImpactBadge(level: editable.impactLevel)
            Text(String(format: Copy.Analysis.confidenceFormat, Int(editable.overallConfidence * 100)))
                .font(.caption)
                .foregroundColor(Theme.inkSoft)
            if editable.lowestConfidence < HeuristicMealAnalyzer.confidenceFloor + 0.15 {
                Text(Copy.Analysis.lowConfidenceNotice)
                    .font(.caption)
                    .foregroundColor(Theme.amber)
            }
            Text(Copy.Analysis.editHint)
                .font(.caption)
                .foregroundColor(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    private var itemsList: some View {
        VStack(spacing: 10) {
            ForEach(editable.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Theme.ink)
                        Text(String(format: Copy.Analysis.confidenceFormat, Int(item.confidence * 100)))
                            .font(.caption2)
                            .foregroundColor(Theme.inkSoft)
                    }
                    Spacer()
                    GramsText(item.carbsGrams)
                    Button(action: { editingItem = item }) {
                        Text("\(Int(item.portionGrams)) g")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.teal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.tealSoft)
                            .cornerRadius(8)
                    }
                    .accessibilityLabel(Text(Copy.Accessibility.editPortion))
                    Button(action: { editable.removeItem(itemID: item.id) }) {
                        Image(systemName: "trash")
                            .foregroundColor(Theme.amber)
                    }
                    .accessibilityLabel(Text(Copy.Common.delete))
                }
                .padding(12)
                .background(Theme.surface)
                .cornerRadius(Theme.chipRadius)
            }
        }
    }

    private var addFoodButton: some View {
        Button(action: { addingFood = true }) {
            Label(Copy.Analysis.addFood, systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.teal)
        }
        .accessibilityLabel(Text(Copy.Analysis.addFood))
    }

    private var totalsCard: some View {
        Card {
            HStack {
                Text(Copy.Analysis.totalCarbs)
                    .font(.headline)
                    .foregroundColor(Theme.ink)
                Spacer()
                GramsText(editable.totalCarbsGrams)
                ImpactBadge(level: editable.impactLevel)
            }
        }
    }

    private var disclaimer: some View {
        VStack(spacing: 6) {
            Text(Copy.Analysis.disclaimer)
                .font(.caption2)
                .foregroundColor(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Text(Copy.Analysis.notSavedNotice)
                .font(.caption2.weight(.medium))
                .foregroundColor(Theme.teal)
        }
    }

    private var confirmButton: some View {
        Button(action: confirmEstimate) {
            Text(Copy.Analysis.confirmSave)
                .primaryButtonStyle()
        }
        .accessibilityLabel(Text(Copy.Accessibility.confirmEstimate))
        .disabled(editable.items.isEmpty)
    }

    private func confirmEstimate() {
        if viewModel.confirmEstimate(editable) {
            isPresented = false
        }
    }
}

/// Portion editor sheet — keeps the user in control of the estimate.
struct PortionEditorView: View {
    let item: FoodItem
    let onSave: (Double) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var portionText: String

    init(item: FoodItem, onSave: @escaping (Double) -> Void) {
        self.item = item
        self.onSave = onSave
        _portionText = State(initialValue: String(format: "%.0f", item.portionGrams))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(item.name)) {
                    HStack {
                        Text(Copy.Analysis.portionLabel)
                        Spacer()
                        TextField("150", text: $portionText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel(Text(Copy.Accessibility.editPortion))
                    }
                }
            }
            .navigationBarTitle(Copy.MealDetail.editPortion, displayMode: .inline)
            .navigationBarItems(
                leading: Button(Copy.Common.cancel) { presentationMode.wrappedValue.dismiss() },
                trailing: Button(Copy.Common.save) {
                    if let value = Double(portionText), value >= 0 {
                        onSave(value)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            )
        }
    }
}

/// Food search reused by the analysis add-item flow and manual logging.
struct FoodSearchView: View {
    let onPick: (FoodReference) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var query = ""
    private let database = FoodDatabase()

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(Theme.inkSoft)
                    TextField(Copy.ManualLog.searchPlaceholder, text: $query)
                        .autocapitalization(.none)
                }
                .padding(10)
                .background(Theme.surface)
                .cornerRadius(Theme.chipRadius)
                .padding()

                let results = database.search(query)
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Spacer()
                    Text(Copy.ManualLog.emptySearch)
                        .font(.subheadline)
                        .foregroundColor(Theme.inkSoft)
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text(Copy.ManualLog.noResults)
                        .font(.subheadline)
                        .foregroundColor(Theme.inkSoft)
                    Spacer()
                } else {
                    List(results, id: \.name) { ref in
                        Button(action: {
                            onPick(ref)
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack {
                                Text(ref.name).foregroundColor(Theme.ink)
                                Spacer()
                                GramsText(ref.carbsPer100g, unit: "g/100g")
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarTitle(Copy.Analysis.addFood, displayMode: .inline)
            .navigationBarItems(trailing: Button(Copy.Common.cancel) {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

/// /log/new — full manual fallback: search, portion, save. No AI involved.
struct ManualLogView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var mealStore: MealStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var items: [FoodItem] = []
    @State private var searching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                ErrorBanner(message: error, retryTitle: Copy.Common.retry) {
                    save()
                }
                .padding()
            }
            List {
                Section(header: Text(Copy.ManualLog.itemsHeading)) {
                    ForEach(items) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("\(Int(item.portionGrams)) g").foregroundColor(Theme.inkSoft)
                            GramsText(item.carbsGrams)
                        }
                    }
                    .onDelete { offsets in items.remove(atOffsets: offsets) }
                    Button(action: { searching = true }) {
                        Label(Copy.Analysis.addFood, systemImage: "plus.circle.fill")
                            .foregroundColor(Theme.teal)
                    }
                }
                Section {
                    HStack {
                        Text(Copy.Analysis.totalCarbs)
                        Spacer()
                        GramsText(items.reduce(0) { $0 + $1.carbsGrams })
                        ImpactBadge(level: GlucoseImpactLevel.level(forCarbLoad: items.reduce(0) { $0 + $1.carbsGrams }))
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            Button(action: save) {
                Text(Copy.ManualLog.saveButton)
                    .primaryButtonStyle()
                    .padding()
            }
            .disabled(items.isEmpty)
            .accessibilityLabel(Text(Copy.ManualLog.saveButton))
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarTitle(Copy.ManualLog.title, displayMode: .inline)
        .sheet(isPresented: $searching) {
            FoodSearchView { reference in
                items.append(FoodItem(
                    name: reference.name,
                    portionGrams: reference.typicalServingGrams,
                    carbsGrams: reference.carbs(forPortionGrams: reference.typicalServingGrams),
                    confidence: 1.0,
                    editedByUser: true
                ))
                searching = false
            }
        }
    }

    private func save() {
        let meal = MealLog(items: items, source: .manual, confirmed: true)
        do {
            _ = try mealStore.save(meal)
            errorMessage = nil
            viewModel.toast = Copy.Common.savedToast
            presentationMode.wrappedValue.dismiss()
        } catch {
            // Keep items intact so retry loses nothing (REQ-ERR-01).
            errorMessage = Copy.Errors.saveFailed
        }
    }
}
