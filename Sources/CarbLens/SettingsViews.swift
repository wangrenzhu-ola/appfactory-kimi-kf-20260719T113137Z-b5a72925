import SwiftUI

/// /settings — goal, budget, subscription state, privacy entry, data export.
struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @State private var budget: Double = 130
    @State private var goal: GlucoseGoalType = .prediabetesSteady
    @State private var showingPaywall = false
    @State private var exportError: String?

    var body: some View {
        Form {
            Section(header: Text(Copy.Settings.goal)) {
                Picker(Copy.Settings.goal, selection: $goal) {
                    ForEach(GlucoseGoalType.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .onChange(of: goal) { value in saveProfile { $0.goalType = value } }
            }
            Section(header: Text(Copy.Settings.budget)) {
                HStack {
                    Slider(value: $budget, in: 60...250, step: 5) { _ in
                        saveProfile { $0.dailyCarbBudget = budget }
                    }
                    .accentColor(Theme.teal)
                    Text(String(format: "%.0f g", budget))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }
                .accessibilityLabel(Text(Copy.Settings.budget))
            }
            Section(header: Text(Copy.Settings.subscription)) {
                HStack {
                    Text(subscriptionStore.isPremium ? Copy.Settings.premiumPlan : Copy.Settings.freePlan)
                    Spacer()
                    if !subscriptionStore.isPremium {
                        Text(String(format: Copy.Settings.scansLeftFormat, subscriptionStore.scansRemaining()))
                            .font(.caption)
                            .foregroundColor(Theme.inkSoft)
                    }
                }
                if !subscriptionStore.isPremium {
                    Button(Copy.Settings.manageSubscription) { showingPaywall = true }
                        .foregroundColor(Theme.teal)
                }
            }
            Section {
                NavigationLink(destination: PrivacyView()) {
                    Text(Copy.Settings.privacy)
                }
                Button(Copy.Settings.exportData) { exportData() }
                    .foregroundColor(Theme.teal)
                if let error = exportError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.amber)
                }
            }
        }
        .navigationBarTitle(Copy.Settings.title, displayMode: .large)
        .onAppear {
            budget = profileStore.profile.dailyCarbBudget
            goal = profileStore.profile.goalType
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(reason: nil)
                .environmentObject(subscriptionStore)
        }
    }

    private func saveProfile(_ mutate: @escaping (inout UserProfile) -> Void) {
        do {
            try profileStore.update(mutate)
            viewModel.toast = Copy.Common.settingsSavedToast
        } catch {
            viewModel.toast = Copy.Errors.saveFailed
        }
    }

    private func exportData() {
        do {
            let url = try viewModel.exportData()
            #if canImport(UIKit)
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(controller, animated: true)
            }
            #endif
            exportError = nil
        } catch {
            exportError = Copy.Errors.exportFailed
        }
    }
}

/// /paywall — Premium value exchange, explicit prices, purchase, restore,
/// cancellation note, unavailable/error states. No dark patterns: free
/// scope is stated and every action is reversible.
struct PaywallView: View {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    let reason: String?
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var products: [PremiumProduct] = []
    @State private var purchasing = false
    @State private var notice: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if subscriptionStore.isPremium {
                        activeState
                    } else {
                        valueList
                        productButtons
                        restoreButton
                        finePrint
                    }
                    if let notice = notice {
                        ErrorBanner(message: notice, retryTitle: Copy.Common.retry) {
                            self.notice = nil
                        }
                    }
                }
                .padding()
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarTitle(Copy.Paywall.title, displayMode: .inline)
            .navigationBarItems(trailing: Button(Copy.Common.done) {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .onAppear {
            Task { products = await subscriptionStore.displayProducts() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            PlateIllustration()
                .frame(height: 120)
            Text(Copy.Paywall.title)
                .font(.title2.weight(.bold))
                .foregroundColor(Theme.ink)
            if reason == "quota" {
                Text(Copy.Paywall.quotaExhaustedBody)
                    .font(.subheadline)
                    .foregroundColor(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var valueList: some View {
        VStack(alignment: .leading, spacing: 12) {
            valueRow(icon: "camera.fill", text: Copy.Paywall.valueUnlimited)
            valueRow(icon: "lightbulb.fill", text: Copy.Paywall.valueInsights)
            valueRow(icon: "chart.bar.fill", text: Copy.Paywall.valueTrends)
            Text(Copy.Paywall.freeNote)
                .font(.caption)
                .foregroundColor(Theme.inkSoft)
                .padding(.top, 4)
        }
        .padding()
        .background(Theme.surface)
        .cornerRadius(Theme.cardRadius)
    }

    private func valueRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.teal)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.ink)
            Spacer()
        }
    }

    private var productButtons: some View {
        VStack(spacing: 10) {
            ForEach(products) { product in
                Button(action: { purchase(product) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName)
                                .font(.headline)
                                .foregroundColor(Theme.ink)
                            Text(product.billingPeriod)
                                .font(.caption)
                                .foregroundColor(Theme.inkSoft)
                        }
                        Spacer()
                        Text(product.displayPrice)
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(Theme.teal)
                    }
                    .padding()
                    .background(Theme.surface)
                    .cornerRadius(Theme.cardRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .stroke(Theme.teal.opacity(0.4), lineWidth: 1)
                    )
                }
                .accessibilityLabel(Text("\(product.displayName), \(product.displayPrice) \(product.billingPeriod)"))
                .disabled(purchasing)
            }
        }
    }

    private var restoreButton: some View {
        Button(action: restore) {
            Text(Copy.Paywall.restore)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Theme.teal)
        }
        .accessibilityLabel(Text(Copy.Paywall.restore))
        .disabled(purchasing)
    }

    private var finePrint: some View {
        Text(Copy.Paywall.cancelAnytime)
            .font(.caption)
            .foregroundColor(Theme.inkSoft)
            .multilineTextAlignment(.center)
    }

    private var activeState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundColor(Theme.leaf)
            Text(Copy.Paywall.premiumActive)
                .font(.headline)
                .foregroundColor(Theme.ink)
            if let expires = subscriptionStore.entitlement.expiresAt {
                Text(String(format: Copy.Paywall.renewsFormat, PaywallView.dateFormatter.string(from: expires)))
                    .font(.caption)
                    .foregroundColor(Theme.inkSoft)
            }
            Text(Copy.Paywall.cancelAnytime)
                .font(.caption)
                .foregroundColor(Theme.inkSoft)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.leafSoft)
        .cornerRadius(Theme.cardRadius)
    }

    private func purchase(_ product: PremiumProduct) {
        purchasing = true
        Task {
            defer { purchasing = false }
            do {
                _ = try await subscriptionStore.purchase(productID: product.id)
                notice = nil
            } catch let error as SubscriptionError {
                switch error {
                case .purchaseCancelled:
                    notice = Copy.Paywall.cancelled
                case .storefrontUnavailable, .productUnavailable, .purchaseFailed:
                    notice = "\(Copy.Paywall.unavailableTitle). \(Copy.Paywall.unavailableBody)"
                case .restoreFoundNothing:
                    notice = Copy.Paywall.restoredNone
                }
            } catch {
                notice = Copy.Paywall.unavailableBody
            }
        }
    }

    private func restore() {
        purchasing = true
        Task {
            defer { purchasing = false }
            do {
                _ = try await subscriptionStore.restore()
                notice = nil
            } catch {
                notice = Copy.Paywall.restoredNone
            }
        }
    }
}

/// /privacy — photo lifecycle, camera use, local storage, medical
/// disclaimer, delete-all with double confirmation.
struct PrivacyView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var confirmingDelete = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                section(heading: Copy.Privacy.photoHeading, body: Copy.Privacy.photoBody, icon: "camera.fill")
                section(heading: Copy.Privacy.cameraHeading, body: Copy.Privacy.cameraBody, icon: "video.fill")
                section(heading: Copy.Privacy.storageHeading, body: Copy.Privacy.storageBody, icon: "internaldrive.fill")
                section(heading: Copy.Privacy.disclaimerHeading, body: Copy.Privacy.disclaimerBody, icon: "info.circle.fill")
                if let error = deleteError {
                    ErrorBanner(message: error, retryTitle: Copy.Common.retry) { deleteError = nil }
                }
                Button(action: { confirmingDelete = true }) {
                    Text(Copy.Privacy.deleteButton)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.amber)
                        .cornerRadius(Theme.cardRadius)
                }
                .accessibilityLabel(Text(Copy.Privacy.deleteButton))
                Text(Copy.Privacy.deleteBody)
                    .font(.caption)
                    .foregroundColor(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarTitle(Copy.Privacy.title, displayMode: .inline)
        .alert(isPresented: $confirmingDelete) {
            Alert(
                title: Text(Copy.Privacy.deleteConfirmTitle),
                message: Text(Copy.Privacy.deleteConfirmBody),
                primaryButton: .destructive(Text(Copy.Privacy.deleteConfirmButton)) {
                    do {
                        try viewModel.deleteAllData()
                        viewModel.toast = Copy.Privacy.deletedToast
                    } catch {
                        deleteError = Copy.Errors.deleteFailed
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func section(heading: String, body: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.teal)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(heading)
                    .font(.headline)
                    .foregroundColor(Theme.ink)
                Text(body)
                    .font(.subheadline)
                    .foregroundColor(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
        .background(Theme.surface)
        .cornerRadius(Theme.cardRadius)
    }
}
