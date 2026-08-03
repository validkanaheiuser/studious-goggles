import SwiftUI

struct ContentView: View {
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Hello World")
                .font(.largeTitle)
            Button("OK Bommer") {
                showAlert = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Hello", isPresented: $showAlert) {
            Button("OK") {}
        }
    }
}
