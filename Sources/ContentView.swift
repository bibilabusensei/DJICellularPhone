import SwiftUI

struct ContentView: View {
    @State private var number = ""
    @State private var log = ["Demo mode: no hardware connection established."]
    private let diagnostics = MockModemDiagnostics()

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Label("IG831T: Not connected", systemImage: "cable.connector.slash")
                    Label("SIM: Unknown", systemImage: "simcard")
                    Label("Cellular data: Unavailable", systemImage: "antenna.radiowaves.left.and.right.slash")
                    Label("Voice / VoLTE: Unverified", systemImage: "phone.down")
                }
                Section("Dialer (demo only)") {
                    TextField("Phone number", text: $number)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    Button("Check call availability") {
                        log.insert("Call unavailable: IG831T voice transport has not been implemented.", at: 0)
                    }
                    .disabled(number.isEmpty)
                }
                Section("Diagnostics") {
                    Button("Run safe diagnostics") {
                        log.insert(contentsOf: diagnostics.run(), at: 0)
                    }
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.footnote.monospaced())
                    }
                }
                Section {
                    Text("This is an experimental interface. It does not make cellular calls, expose a modem, or provide Internet access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("DJI Cellular Phone")
        }
    }
}
