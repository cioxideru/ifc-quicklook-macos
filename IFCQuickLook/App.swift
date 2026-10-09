import SwiftUI

@main
struct IFCQuickLookApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("IFC Quick Look")
                    .font(.title2.bold())
                Text("This app only hosts the Quick Look extension for IFC files. Select an .ifc file in Finder and press Space to preview it in 3D.")
                Text("If previews do not appear: System Settings → General → Login Items & Extensions → Quick Look, enable \"IFC Preview\". Then run `qlmanage -r` in Terminal or log out and back in.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
            .frame(width: 480, height: 220, alignment: .topLeading)
        }
        .windowResizability(.contentSize)
    }
}
