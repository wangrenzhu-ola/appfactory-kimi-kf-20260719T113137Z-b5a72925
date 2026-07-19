import SwiftUI

@main
struct CarbLensApp: App {
    @StateObject private var viewModel: AppViewModel

    init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // AI-first analysis: on-device preprocessing + structured refinement,
        // with the deterministic on-device analyzer as the automatic fallback.
        let analyzer: MealAnalyzer = FallbackMealAnalyzer(
            primary: RefiningMealAnalyzer(transport: CodingAnalysisTransport()),
            fallback: HeuristicMealAnalyzer()
        )
        _viewModel = StateObject(wrappedValue: AppViewModel(dataDirectory: directory, analyzer: analyzer))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.mealStore)
                .environmentObject(viewModel.profileStore)
                .environmentObject(viewModel.subscriptionStore)
                .environmentObject(viewModel.captureSession)
        }
    }
}

/// Chooses onboarding vs. the main tab shell from the persisted profile.
struct RootView: View {
    @EnvironmentObject private var profileStore: ProfileStore

    var body: some View {
        if profileStore.profile.onboardingCompleted {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showingCapture = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $viewModel.selectedTab) {
                NavigationView { HomeView(onSnap: { showingCapture = true }) }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem { Label("Today", systemImage: "house") }
                    .tag(0)
                NavigationView { LogView(onSnap: { showingCapture = true }) }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem { Label("Log", systemImage: "list.bullet") }
                    .tag(1)
                NavigationView { TrendsView(onSnap: { showingCapture = true }) }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem { Label("Trends", systemImage: "chart.bar") }
                    .tag(2)
                NavigationView { InsightsView(onSnap: { showingCapture = true }) }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem { Label("Insights", systemImage: "lightbulb") }
                    .tag(3)
                NavigationView { SettingsView() }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(4)
            }
            .accentColor(Theme.teal)

            // Persistent center camera affordance on the Today tab.
            if viewModel.selectedTab == 0 {
                Button(action: { showingCapture = true }) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(16)
                        .background(Theme.teal)
                        .clipShape(Circle())
                        .shadow(radius: 6)
                }
                .accessibilityLabel(Text(Copy.Accessibility.snapMeal))
                .padding(.bottom, 56)
            }
        }
        .fullScreenCover(isPresented: $showingCapture) {
            viewModel.startCapture()
        } content: {
            CaptureFlowView(session: viewModel.captureSession, isPresented: $showingCapture)
                .environmentObject(viewModel)
                .environmentObject(viewModel.mealStore)
                .environmentObject(viewModel.profileStore)
                .environmentObject(viewModel.subscriptionStore)
        }
        .sheet(isPresented: $viewModel.showingPaywall) {
            PaywallView(reason: viewModel.paywallReason)
                .environmentObject(viewModel.subscriptionStore)
        }
        .overlay(
            Group {
                if let toast = viewModel.toast {
                    ToastView(message: toast)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { viewModel.toast = nil }
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            },
            alignment: .top
        )
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.ink.opacity(0.92))
            .cornerRadius(20)
            .padding(.top, 8)
            .accessibilityLabel(Text(message))
    }
}
