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

        // For now: add a simple dummy sun path arc in front of the camera
        addDummySunPath(to: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // For this simple version, nothing to update yet
    }

    private func addDummySunPath(to arView: ARView) {
        let anchor = AnchorEntity(world: .zero)

        let radius: Float = 5.0
        let pointCount = 13 // number of points along the path

        for i in 0..<pointCount {
            let t = Float(i) / Float(pointCount - 1) // 0...1

            // Horizontal sweep from -60° to +60°
            let horizontalAngle = (-Float.pi / 3) + t * (2 * Float.pi / 3)

            // Altitude: simple arch from 0° (horizon) up to ~65° at the center, back to 0°
            let maxAltitudeDeg: Float = 65.0
            let altitudeAngle = (maxAltitudeDeg * sin(t * .pi)) * (.pi / 180.0)

            // Convert spherical (radius, azimuth, altitude) to ARKit world space (x right, y up, z forward)
            let x = radius * cos(altitudeAngle) * sin(horizontalAngle)
            let y = radius * sin(altitudeAngle)
            let z = -radius * cos(altitudeAngle) * cos(horizontalAngle)

            let sphere = MeshResource.generateSphere(radius: 0.12)
            let material = SimpleMaterial(color: .yellow, isMetallic: false)
            let entity = ModelEntity(mesh: sphere, materials: [material])
            entity.position = SIMD3<Float>(x, y, z)

            anchor.addChild(entity)
        }

        arView.scene.addAnchor(anchor)
    }
}
