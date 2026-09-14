import Foundation
import WebKit
import LocalAuthentication
import CoreLocation
import CryptoKit
import UIKit

final class NativeSecurityBridge: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
    private weak var webView: WKWebView?
    private let locationManager = CLLocationManager()
    private var pendingRequestId: String?
    private var pendingPayload: [String: Any] = [:]
    private var biometricVerifiedAt: Date?

    private let maxLocationAge: TimeInterval = 30
    private let maxAccuracyMeters: CLLocationAccuracy = 100

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let requestId = body["requestId"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]
        verifyBiometric(requestId: requestId, payload: payload)
    }

    private func verifyBiometric(requestId: String, payload: [String: Any]) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            fail(requestId, code: "BIOMETRIC_UNAVAILABLE", message: "Biometria indisponível neste iPhone.")
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Confirme sua identidade para registrar a jornada.") { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard success else {
                    self.fail(requestId, code: "BIOMETRIC_FAILED", message: "A validação biométrica não foi concluída.")
                    return
                }
                self.biometricVerifiedAt = Date()
                self.requestLocation(requestId: requestId, payload: payload)
            }
        }
    }

    private func requestLocation(requestId: String, payload: [String: Any]) {
        pendingRequestId = requestId
        pendingPayload = payload
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            fail(requestId, code: "LOCATION_PERMISSION_DENIED", message: "Autorize a localização precisa para registrar a jornada.")
        @unknown default:
            fail(requestId, code: "LOCATION_UNAVAILABLE", message: "Não foi possível validar a localização.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let id = pendingRequestId else { return }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            fail(id, code: "LOCATION_PERMISSION_DENIED", message: "Autorize a localização precisa para registrar a jornada.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let id = pendingRequestId else { return }
        fail(id, code: "LOCATION_UNAVAILABLE", message: "Não foi possível obter o GPS do iPhone.")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let id = pendingRequestId, let location = locations.last else { return }
        pendingRequestId = nil

        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard age <= maxLocationAge else {
            fail(id, code: "STALE_LOCATION", message: "A localização está desatualizada. Tente novamente.")
            return
        }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maxAccuracyMeters else {
            fail(id, code: "LOW_LOCATION_ACCURACY", message: "A precisão do GPS está insuficiente. Vá para uma área com melhor sinal.")
            return
        }

        var simulated = false
        if #available(iOS 15.0, *) {
            simulated = location.sourceInformation?.isSimulatedBySoftware == true
        }
        guard !simulated else {
            fail(id, code: "MOCK_LOCATION", message: "Localização simulada não é permitida.")
            return
        }

        var distanceMeters: Double? = nil
        if let lat = number(pendingPayload["expectedLatitude"]),
           let lng = number(pendingPayload["expectedLongitude"]),
           let radius = number(pendingPayload["radiusMeters"]), radius > 0 {
            let expected = CLLocation(latitude: lat, longitude: lng)
            let distance = location.distance(from: expected)
            distanceMeters = distance
            guard distance <= radius else {
                fail(id, code: "OUTSIDE_GEOFENCE", message: String(format: "Você está a %.0f m do local autorizado.", distance))
                return
            }
        }

        // Fail-closed para Jornada até habilitarmos App Attest/DeviceCheck com a conta Apple Developer.
        // A interface e o bridge podem ser compilados/testados agora, mas a liberação definitiva da jornada
        // exige integridade de dispositivo equivalente à proteção Android já utilizada pelo projeto.
        let result: [String: Any] = [
            "requestId": id,
            "ok": true,
            "verifiedAt": Int(Date().timeIntervalSince1970 * 1000),
            "biometric": ["verified": true, "provider": "LocalAuthentication"],
            "location": [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy,
                "capturedAt": Int(location.timestamp.timeIntervalSince1970 * 1000),
                "isMock": false
            ],
            "distanceMeters": distanceMeters as Any,
            "device": ["deviceIdHash": deviceIdentifierHash()],
            "integrity": ["valid": false, "provider": "ios-pending-app-attest"]
        ]
        send(result)
    }

    private func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func deviceIdentifierHash() -> String {
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? "ios-no-idfv"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fail(_ requestId: String, code: String, message: String) {
        pendingRequestId = nil
        send(["requestId": requestId, "ok": false, "code": code, "message": message])
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("window.__agendaSTNativeReceive(\(json));", completionHandler: nil)
        }
    }
}
