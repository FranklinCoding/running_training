import SwiftUI

struct RootView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @Environment(LocationRecorder.self) private var recorder

    var body: some View {
        TabView {
            ExploredMapScreen()
                .tabItem { Label("Map", systemImage: "hexagon") }
            RecordingScreen()
                .tabItem { Label("Recording", systemImage: "waveform.path.ecg") }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboardingComplete }, set: { _ in })) {
            OnboardingView {
                onboardingComplete = true
                recorder.startIfAuthorized()
            }
        }
    }
}
