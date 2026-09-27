import Foundation
import IOKit.pwr_mgt

/// Aserción de energía de macOS (lo mismo que usa `caffeinate`): impide el reposo del sistema pero deja
/// que la pantalla se apague. Se suelta sola si la app se cierra.
final class Vigilia {
    private let tipo: String
    private let motivo: String
    private var id: IOPMAssertionID = 0
    private(set) var activa = false

    /// tipo: kIOPMAssertionTypePreventSystemSleep (solo con cargador, como `caffeinate -s`).
    init(tipo: String, motivo: String) {
        self.tipo = tipo
        self.motivo = motivo
    }

    func poner(_ si: Bool) {
        guard si != activa else { return }
        if si {
            activa = IOPMAssertionCreateWithName(tipo as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 motivo as CFString, &id) == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(id)
            activa = false
        }
    }
}
