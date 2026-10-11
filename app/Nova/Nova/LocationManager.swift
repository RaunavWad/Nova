import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorization: CLAuthorizationStatus
    @Published var declination: Double?          // true minus magnetic heading, degrees (east positive)
    @Published var headingNeedsCalibration = false
    @Published var missingUsageText = false      // true if the app's Info settings lack the location explanation
    @Published private(set) var placeName: String?        // e.g. "Edison, New Jersey" (display)
    @Published private(set) var spokenPlaceName: String?  // same, spelled out for speech

    static let demoCoordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocoded: CLLocation?

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
        if authorization == .notDetermined {
            guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil else {
                missingUsageText = true
                return
            }
            manager.requestWhenInUseAuthorization()
        }
        if isAuthorized {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func coordinate(demo: Bool) -> CLLocationCoordinate2D? {
        if demo { return Self.demoCoordinate }
        return location?.coordinate
    }

    var statusDescription: String {
        if missingUsageText {
            return "Location can't be requested because the app is missing its location permission text. In Xcode, open the Nova target, then Info, and add Privacy - Location When In Use Usage Description."
        }
        switch authorization {
        case .notDetermined: return "Location permission has not been requested yet."
        case .denied: return "Location access is turned off. Open the Settings app, then Nova, then Location, and choose While Using the App."
        case .restricted: return "Location access is restricted on this device."
        default: return location == nil ? "Waiting for your location." : "Location available."
        }
    }


    private func updatePlaceName(for loc: CLLocation) {
        if let last = lastGeocoded, loc.distance(from: last) < 5_000, placeName != nil { return }
        guard !geocoder.isGeocoding else { return }
        lastGeocoded = loc
        geocoder.reverseGeocodeLocation(loc) { [weak self] marks, _ in
            guard let m = marks?.first else { return }
            let town = m.locality ?? m.subAdministrativeArea ?? m.name
            let region = m.administrativeArea
            Task { @MainActor in
                guard let self else { return }
                let full = region.flatMap { Self.usStates[$0] } ?? region
                let parts = [town, full].compactMap { $0 }.filter { !$0.isEmpty }
                guard !parts.isEmpty else { return }
                self.placeName = parts.joined(separator: ", ")
                self.spokenPlaceName = self.placeName
            }
        }
    }

    private static let usStates: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
        "CT": "Connecticut", "DE": "Delaware", "DC": "Washington, D.C.", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
        "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
        "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey",
        "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
        "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming"
    ]

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            if self.isAuthorized { self.start() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
            self.updatePlaceName(for: last)
        }
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
