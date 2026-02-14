import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
  static let shared = LocationService()

  private let manager: CLLocationManager
  private var continuation: CheckedContinuation<CLLocation?, Never>?
  private var timeoutTask: Task<Void, Never>?

  override init() {
    self.manager = CLLocationManager()
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func requestAuthorizationIfNeeded() {
    let status = manager.authorizationStatus
    if status == .notDetermined {
      manager.requestWhenInUseAuthorization()
    }
  }

  func currentLocation(timeoutSeconds: Double = 2.5) async -> CLLocation? {
    let status = manager.authorizationStatus
    if status == .notDetermined {
      manager.requestWhenInUseAuthorization()
      // User may still be deciding. We try once; worst case we time out.
    }
    if status == .denied || status == .restricted {
      return nil
    }

    // Cancel any in-flight request.
    if let c = continuation {
      continuation = nil
      c.resume(returning: nil)
    }
    timeoutTask?.cancel()
    timeoutTask = nil

    return await withCheckedContinuation { cont in
      continuation = cont
      timeoutTask = Task {
        let ns = UInt64(max(0.2, timeoutSeconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
        if let c = continuation {
          continuation = nil
          c.resume(returning: nil)
        }
      }
      manager.requestLocation()
    }
  }

  // MARK: - CLLocationManagerDelegate

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in
      self.handleDidUpdateLocations(locations)
    }
  }

  @MainActor
  private func handleDidUpdateLocations(_ locations: [CLLocation]) {
    timeoutTask?.cancel()
    timeoutTask = nil
    let loc = locations.last
    if let c = continuation {
      continuation = nil
      c.resume(returning: loc)
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      self.handleDidFail(error)
    }
  }

  @MainActor
  private func handleDidFail(_ error: Error) {
    timeoutTask?.cancel()
    timeoutTask = nil
    if let c = continuation {
      continuation = nil
      c.resume(returning: nil)
    }
  }
}
