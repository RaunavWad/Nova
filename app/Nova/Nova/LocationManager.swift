import Foundation
import CoreLocation
import Combine

/// Location is used only to compute where objects are in *your* sky. Reduced accuracy (kilometers) is plenty
/// (1 km on the ground changes star positions by ~0.01°) and is better for privacy. Nothing leaves the device.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorization: CLAuthorizationStatus
    @Published var declination: Double?          // true minus magnetic heading, degrees (east positive)
    @Published var headingNeedsCalibration = false

    /// Fixed location used only in Demo mode (clearly announced as such).
    static let demoCoordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 5_000
        manager.headingFilter = 5
    }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func start() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        if isAuthorized {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// Coordinates to use for astronomy. nil means "no valid location".
    func coordinate(demo: Bool) -> CLLocationCoordinate2D? {
        if demo { return Self.demoCoordinate }
        return location?.coordinate
    }

    var statusDescription: String {
        switch authorization {
        case .notDetermined: return "Location permission has not been requested yet."
        case .denied: return "Location access is turned off. Open the Settings app, then Nova, then Location, and choose While Using the App."
        case .restricted: return "Location access is restricted on this device."
        default: return location == nil ? "Waiting for your location." : "Location available."
        }
    }

    // MARK: CLLocationManagerDelegate
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            if self.isAuthorized { self.start() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0, newHeading.trueHeading >= 0 else { return }
        let decl = AstronomyEngine.norm180(newHeading.trueHeading - newHeading.magneticHeading)
        Task { @MainActor in self.declination = decl }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        Task { @MainActor in self.headingNeedsCalibration = true }
        return true
    }
}
