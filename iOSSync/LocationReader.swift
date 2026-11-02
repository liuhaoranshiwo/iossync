import Foundation
import CoreLocation

/// 定位 + 反向地理编码（城市名）；失败时回退佛山坐标
final class LocationReader: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationReader()

    private let manager = CLLocationManager()
    private var handler: ((Double, Double, String) -> Void)?
    private var requesting = false

    @Published var lat: Double = 0
    @Published var lon: Double = 0
    @Published var name: String = "佛山市"
    @Published var denied = false

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 定位一次，完成后回调 (lat, lon, 城市名)
    func locate(completion: @escaping (Double, Double, String) -> Void) {
        handler = completion
        requesting = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            // 权限被拒：回退到佛山坐标
            requesting = false
            denied = true
            completion(23.0218, 113.1219, "佛山市")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if requesting { manager.requestLocation() }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        lat = loc.coordinate.latitude
        lon = loc.coordinate.longitude
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self = self else { return }
            if let p = placemarks?.first {
                let city = [p.locality, p.subAdministrativeArea, p.administrativeArea, p.name]
                    .compactMap { $0 }.first { !$0.isEmpty }
                if let c = city { self.name = c }
            }
            let cb = self.handler
            self.handler = nil
            self.requesting = false
            DispatchQueue.main.async {
                cb?(self.lat, self.lon, self.name)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let cb = handler
        handler = nil
        requesting = false
        DispatchQueue.main.async {
            cb?(self.lat == 0 ? 23.0218 : self.lat, self.lon == 0 ? 113.1219 : self.lon, self.name)
        }
    }
}
