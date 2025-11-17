import SwiftUI
import RealityKit
import ARKit
import CoreLocation

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
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        context.coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        // Try to align with gravity and heading for proper azimuth orientation.
        config.worldAlignment = .gravityAndHeading
        config.environmentTexturing = .automatic

        arView.session.run(config)

        // Start asking for location; when we get it, we'll compute and render the real sun path.
        context.coordinator.startLocationUpdates()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Nothing to update dynamically yet; sun path is recalculated when needed.
    }

    class Coordinator: NSObject, CLLocationManagerDelegate {
        let locationManager = CLLocationManager()
        weak var arView: ARView?

        private var hasRenderedPath = false

        override init() {
            super.init()
            locationManager.delegate = self
        }

        func startLocationUpdates() {
            let status = CLLocationManager.authorizationStatus()
            if status == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationManager.startUpdatingLocation()
            }
        }

        func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            default:
                break
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard !hasRenderedPath,
                  let location = locations.last,
                  let arView = arView else { return }

            hasRenderedPath = true
            manager.stopUpdatingLocation()

            let now = Date()
            // Sample the next 8 hours in 20-minute steps
            let samples = SunPathCalculator.samplePath(
                startDate: now,
                durationHours: 8,
                stepMinutes: 20,
                location: location
            )

            SunPathRenderer.addSunPath(samples: samples, to: arView)
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            // If location fails, we could fall back to a dummy path in front of the camera.
            guard !hasRenderedPath, let arView = arView else { return }
            hasRenderedPath = true
            SunPathRenderer.addDummyPath(to: arView)
        }
    }
}

// MARK: - Sun Path Types

struct SunSample {
    let date: Date
    let altitudeRad: Double
    let azimuthRad: Double
}

// MARK: - Sun Position Calculator

struct SunPathCalculator {
    /// Returns a list of sun samples for the given time range and location.
    static func samplePath(startDate: Date,
                           durationHours: Double,
                           stepMinutes: Double,
                           location: CLLocation) -> [SunSample] {
        var samples: [SunSample] = []

        let totalMinutes = durationHours * 60.0
        let steps = Int(totalMinutes / stepMinutes)

        for i in 0...steps {
            let minutesAhead = stepMinutes * Double(i)
            if let sampleDate = Calendar.current.date(byAdding: .minute,
                                                      value: Int(minutesAhead),
                                                      to: startDate) {
                let pos = solarPosition(date: sampleDate,
                                        latitude: location.coordinate.latitude,
                                        longitude: location.coordinate.longitude)
                // Only keep points when the sun is above the horizon
                if pos.altitudeRad > 0 {
                    samples.append(SunSample(date: sampleDate,
                                             altitudeRad: pos.altitudeRad,
                                             azimuthRad: pos.azimuthRad))
                }
            }
        }

        return samples
    }

    /// Compute solar altitude and azimuth (radians) using a standard algorithm.
    /// Azimuth is measured from north, increasing towards east (0..2π).
    private static func solarPosition(date: Date,
                                      latitude: Double,
                                      longitude: Double) -> (altitudeRad: Double, azimuthRad: Double) {
        // Convert lat/lon to radians
        let latRad = degreesToRadians(latitude)
        let lonDeg = longitude

        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone.current

        // Local components
        let components = calendar.dateComponents(in: timeZone, from: date)
        let year = components.year ?? 2000
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0

        // Day of year
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)

        // Fractional hour in local time
        let localMinutes = Double(hour * 60 + minute) + Double(second) / 60.0
        let localHours = localMinutes / 60.0

        // Fractional year (in radians)
        let gamma = 2.0 * Double.pi / 365.0 * (dayOfYear - 1.0 + (localHours - 12.0) / 24.0)

        // Equation of time (minutes)
        let eqTime = 229.18 * (
            0.000075 +
            0.001868 * cos(gamma) -
            0.032077 * sin(gamma) -
            0.014615 * cos(2 * gamma) -
            0.040849 * sin(2 * gamma)
        )

        // Solar declination (radians)
        let decl = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148  * sin(3 * gamma)

        // Time zone offset from GMT in minutes
        let tzOffsetMinutes = Double(timeZone.secondsFromGMT(for: date)) / 60.0

        // Time offset in minutes
        // 4 * longitude (deg) converts to minutes, then adjust for time zone and equation of time
        let timeOffset = eqTime + 4.0 * lonDeg - tzOffsetMinutes

        // True solar time (minutes)
        var trueSolarTime = localMinutes + timeOffset
        // Wrap into 0..1440
        trueSolarTime = trueSolarTime.truncatingRemainder(dividingBy: 1440.0)
        if trueSolarTime < 0 {
            trueSolarTime += 1440.0
        }

        // Hour angle (degrees)
        let hourAngleDeg = (trueSolarTime / 4.0) - 180.0
        let hourAngleRad = degreesToRadians(hourAngleDeg)

        // Solar zenith angle
        let cosZenith = sin(latRad) * sin(decl) + cos(latRad) * cos(decl) * cos(hourAngleRad)
        let zenith = acos(clamp(cosZenith, min: -1.0, max: 1.0))

        let altitude = (Double.pi / 2.0) - zenith

        // Solar azimuth
        // Formula adapted so azimuth is measured from north, increasing towards east.
        let sinAzimuth = -sin(hourAngleRad) * cos(decl) / cos(altitude)
        let cosAzimuth = (sin(decl) - sin(altitude) * sin(latRad)) / (cos(altitude) * cos(latRad))

        var azimuth = atan2(sinAzimuth, cosAzimuth)

        // Convert range from -π..π to 0..2π
        if azimuth < 0 {
            azimuth += 2.0 * Double.pi
        }

        return (altitudeRad: altitude, azimuthRad: azimuth)
    }

    private static func degreesToRadians(_ deg: Double) -> Double {
        return deg * Double.pi / 180.0
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}

// MARK: - Sun Path Renderer

struct SunPathRenderer {
    static func addSunPath(samples: [SunSample], to arView: ARView) {
        let anchor = AnchorEntity(world: .zero)

        let radius: Float = 8.0

        for (index, sample) in samples.enumerated() {
            let alt = Float(sample.altitudeRad)
            let az = Float(sample.azimuthRad)

            // Convert altitude/azimuth to AR world coordinates.
            // ARKit with .gravityAndHeading aligns:
            //  - Y axis: up
            //  - Z axis: roughly towards north / initial heading
            // We place points on a sphere of given radius.
            let x = radius * cos(alt) * sin(az)
            let y = radius * sin(alt)
            let z = -radius * cos(alt) * cos(az)

            let isCurrentSun = index == 0

            let sphereRadius: Float = isCurrentSun ? 0.25 : 0.12
            let color: UIColor = isCurrentSun ? .orange : .yellow

            let sphere = MeshResource.generateSphere(radius: sphereRadius)
            let material = SimpleMaterial(color: color, isMetallic: false)
            let entity = ModelEntity(mesh: sphere, materials: [material])
            entity.position = SIMD3<Float>(x, y, z)

            anchor.addChild(entity)
        }

        arView.scene.addAnchor(anchor)
    }

    static func addDummyPath(to arView: ARView) {
        let anchor = AnchorEntity(world: .zero)

        let radius: Float = 6.0
        let pointCount = 13

        for i in 0..<pointCount {
            let t = Float(i) / Float(pointCount - 1) // 0...1

            let horizontalAngle = (-Float.pi / 3) + t * (2 * Float.pi / 3)
            let maxAltitudeDeg: Float = 65.0
            let altitudeAngle = (maxAltitudeDeg * sin(t * .pi)) * (.pi / 180.0)

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
