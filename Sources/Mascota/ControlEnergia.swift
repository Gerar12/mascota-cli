import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import MascotaCore

/// Mantiene la Mac despierta mientras trabajan (automático) o siempre (manual); los dos SOLO con cargador
/// (macOS ignora PreventSystemSleep con batería). La pantalla sí se apaga.
@MainActor
final class ControlEnergia {
    private let vigiliaTrabajo = Vigilia(tipo: kIOPMAssertionTypePreventSystemSleep,
                                         motivo: "Mascota: Claude o Codex están trabajando")
    private let vigiliaSiempre = Vigilia(tipo: kIOPMAssertionTypePreventSystemSleep,
                                         motivo: "Mascota: mantener despierta siempre")
    private var ultimaVezTrabajando: Date?
    private var ultimoCargador: Bool?
    /// Se llama cuando se conecta o desconecta el cargador (para refrescar el menú abierto).
    var alCambiarCargador: ((Bool) -> Void)?

    var mientrasTrabajan: Bool {
        get { UserDefaults.standard.object(forKey: "energia.trabajo") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "energia.trabajo") }
    }
    var siempre: Bool {
        get { UserDefaults.standard.bool(forKey: "energia.siempre") }
        set { UserDefaults.standard.set(newValue, forKey: "energia.siempre") }
    }

    /// ¿La Mac está conectada al cargador? Se consulta en cada sondeo: cambia en tiempo real.
    var conCargador: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let fuente = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        return fuente == kIOPMACPowerKey
    }

    func actualizar(_ sesiones: [Sesion], ahora: Date) {
        let trabajando = Energia.hayTrabajo(sesiones, ahora: ahora)
        if trabajando { ultimaVezTrabajando = ahora }
        let cargador = conCargador
        if cargador != ultimoCargador {
            ultimoCargador = cargador
            alCambiarCargador?(cargador)
        }
        vigiliaTrabajo.poner(Energia.activa(preferencia: mientrasTrabajan, conCargador: cargador)
            && Energia.mantenerDespierta(trabajando: trabajando, ultimaVezTrabajando: ultimaVezTrabajando, ahora: ahora))
        vigiliaSiempre.poner(Energia.activa(preferencia: siempre, conCargador: cargador))
    }
}
