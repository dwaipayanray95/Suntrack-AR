import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    var body: some View {
        ZStack {
            ARViewContainer()
                .ignoresSafeArea()

            // Simple overlay for now
            VStack {
                Text("Suntrack AR")
                    .font(.headline)
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 40)

                Spacer()
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Basic AR configuration
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity // important for sun direction
        config.environmentTexturing = .automatic

        arView.session.run(config)

        // For now: add a simple test sphere 5m in front of the camera
        addTestSphere(to: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // For this simple version, nothing to update yet
    }

    private func addTestSphere(to arView: ARView) {
        let sphere = MeshResource.generateSphere(radius: 0.1)
        let material = SimpleMaterial()
        let entity = ModelEntity(mesh: sphere, materials: [material])

        // Place it 5 meters straight ahead of the camera
        var transform = Transform.identity
        transform.translation = [0, 0, -5]
        entity.transform = transform

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
    }
}
