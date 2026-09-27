import AppKit
import MascotaCore
import UserNotifications

/// Notificación de macOS cuando una sesión del usuario pide permiso; al tocarla lleva a su terminal.
final class Avisador: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// Recibe la clave "cli-sesión" de la notificación tocada.
    var alTocar: (@MainActor (String) -> Void)?

    func pedirPermiso() {
        let centro = UNUserNotificationCenter.current()
        centro.delegate = self
        centro.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func avisar(_ s: Sesion, imagen: CGImage? = nil) {
        let contenido = UNMutableNotificationContent()
        contenido.title = "\(s.nombreCLI) necesita tu permiso"
        contenido.body = "\(s.project) · clic para ir a su terminal"
        let clave = "\(s.cli)-\(s.session)"
        contenido.userInfo = ["clave": clave]
        if let imagen, let adjunto = Self.adjunto(imagen, nombre: clave) { contenido.attachments = [adjunto] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: clave, content: contenido, trigger: nil))
    }

    /// La mascota pidiendo permiso, como imagen de la notificación (macOS la copia a su almacén).
    private static func adjunto(_ imagen: CGImage, nombre: String) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mascota-\(nombre)-\(UUID().uuidString).png")
        let rep = NSBitmapImageRep(cgImage: imagen)
        guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "mascota", url: url)
    }

    /// Ya no espera permiso: quita su notificación.
    func retirar(_ claves: [String]) {
        guard !claves.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: claves)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let clave = response.notification.request.content.userInfo["clave"] as? String {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.alTocar?(clave) } }
        }
        completionHandler()
    }
}
