import SwiftUI

/// /capture → /analysis flow inside a full-screen cover.
/// Stages: pick → confirm photo → analyzing → review (editable) → confirm.
/// Failure stage always offers retake and the manual-log fallback.
struct CaptureFlowView: View {
    @ObservedObject var session: CaptureSession
    @Binding var isPresented: Bool
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var pickerSource: CameraPicker.Source?
    @State private var showingManualLog = false

    var body: some View {
        NavigationView {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationBarTitle(Copy.Capture.title, displayMode: .inline)
            .navigationBarItems(leading: Button(Copy.Common.cancel) {
                session.discardOriginalPhoto()
                isPresented = false
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(item: $pickerSource) { source in
            #if canImport(UIKit)
            CameraPicker(source: source,
                         onImage: { data in
                             pickerSource = nil
                             session.photoPicked(data)
                         },
                         onCancel: { pickerSource = nil })
            .ignoresSafeArea()
            #else
            EmptyView()
            #endif
        }
        .sheet(isPresented: $showingManualLog) {
            NavigationView {
                ManualLogView()
                    .environmentObject(viewModel)
                    .environmentObject(viewModel.mealStore)
                    .navigationBarItems(trailing: Button(Copy.Common.done) {
                        showingManualLog = false
                        if case .failed = session.stage { isPresented = false }
                    })
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.stage {
        case .picking:
            pickingStage
        case .confirmingPhoto(let data):
            confirmStage(data: data)
        case .analyzing:
            ScanOverlayView()
        case .review(let editable):
            AnalysisReviewView(editable: editable, isPresented: $isPresented)
                .environmentObject(viewModel)
        case .failed(let reason):
            failureStage(reason: reason)
        }
    }

    // MARK: - Picking

    private var pickingStage: some View {
        VStack(spacing: 24) {
            Spacer()
            PlateIllustration()
                .frame(height: 220)
            Text(Copy.Capture.title)
                .font(.title2.weight(.semibold))
                .foregroundColor(Theme.ink)
            VStack(spacing: 12) {
                Button(action: requestCamera) {
                    Label(Copy.Capture.takePhoto, systemImage: "camera.fill")
                        .primaryButtonStyle()
                }
                .accessibilityLabel(Text(Copy.Capture.takePhoto))
                Button(action: { pickerSource = .library }) {
                    Label(Copy.Capture.choosePhoto, systemImage: "photo.on.rectangle")
                        .secondaryButtonStyle()
                }
                .accessibilityLabel(Text(Copy.Capture.choosePhoto))
                Button(action: { showingManualLog = true }) {
                    Text(Copy.Capture.manualInstead)
                        .font(.subheadline)
                        .foregroundColor(Theme.teal)
                }
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
    }

    private func requestCamera() {
        #if canImport(UIKit)
        if CameraPermission.isGranted {
            pickerSource = .camera
        } else if CameraPermission.isDenied {
            cameraDenied = true
        } else {
            CameraPermission.request { granted in
                DispatchQueue.main.async {
                    if granted { pickerSource = .camera } else { cameraDenied = true }
                }
            }
        }
        #endif
    }

    @State private var cameraDenied = false

    // MARK: - Confirm photo

    private func confirmStage(data: Data) -> some View {
        VStack(spacing: 16) {
            #if canImport(UIKit)
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(Theme.cardRadius)
                    .padding(.horizontal)
            }
            #endif
            HStack(spacing: 12) {
                Button(action: { session.begin() }) {
                    Text(Copy.Capture.retake)
                        .secondaryButtonStyle()
                }
                .accessibilityLabel(Text(Copy.Capture.retake))
                Button(action: analyzePhoto) {
                    Label(Copy.Capture.usePhoto, systemImage: "sparkles")
                        .primaryButtonStyle()
                }
                .accessibilityLabel(Text(Copy.Capture.usePhoto))
            }
            .padding(.horizontal, 32)
        }
        .padding(.vertical)
        .alert(isPresented: $cameraDenied) {
            Alert(
                title: Text(Copy.Capture.cameraDeniedTitle),
                message: Text(Copy.Capture.cameraDeniedBody),
                primaryButton: .default(Text(Copy.Capture.openSettings)) {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                },
                secondaryButton: .cancel(Text(Copy.Capture.manualInstead)) {
                    showingManualLog = true
                }
            )
        }
    }

    private func analyzePhoto() {
        Task { await session.analyze() }
    }

    // MARK: - Failure (REQ-AI-03)

    private func failureStage(reason: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 44))
                .foregroundColor(Theme.amber)
            if reason == "quota" {
                Text(Copy.Paywall.quotaExhaustedTitle)
                    .font(.title3.weight(.semibold))
                Text(Copy.Paywall.quotaExhaustedBody)
                    .font(.subheadline)
                    .foregroundColor(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: { viewModel.presentPaywall(reason: "quota") }) {
                    Text(Copy.Paywall.title).primaryButtonStyle()
                }
                .padding(.horizontal, 32)
            } else {
                Text(Copy.Analysis.failureTitle)
                    .font(.title3.weight(.semibold))
                Text(Copy.Analysis.failureBody)
                    .font(.subheadline)
                    .foregroundColor(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: { session.begin() }) {
                    Text(Copy.Analysis.failureRetake).primaryButtonStyle()
                }
                .padding(.horizontal, 32)
            }
            Button(action: { showingManualLog = true }) {
                Text(Copy.Analysis.failureManual)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.teal)
            }
            .accessibilityLabel(Text(Copy.Analysis.failureManual))
            Spacer()
        }
    }
}

extension CameraPicker.Source: Identifiable {
    var id: Int {
        switch self {
        case .camera: return 1
        case .library: return 2
        }
    }
}

// MARK: - Button styles shared across screens

extension View {
    func primaryButtonStyle() -> some View {
        font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.teal)
            .cornerRadius(Theme.cardRadius)
    }

    func secondaryButtonStyle() -> some View {
        font(.headline)
            .foregroundColor(Theme.teal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.tealSoft)
            .cornerRadius(Theme.cardRadius)
    }
}
