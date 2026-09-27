import Darwin

/// Consultas al sistema sin lanzar programas externos (antes se usaba `ps` cada 2 s: era lo que más CPU gastaba).
enum ProcesosSistema {
    /// ¿Hay algún proceso `codex` con terminal? El servicio de fondo de Codex no tiene (tdev = NODEV).
    static func hayCodexConTerminal() -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var tamano = 0
        guard sysctl(&mib, 4, nil, &tamano, nil, 0) == 0, tamano > 0 else { return false }
        let cantidad = tamano / MemoryLayout<kinfo_proc>.stride + 16      // margen por procesos nuevos
        var procesos = [kinfo_proc](repeating: kinfo_proc(), count: cantidad)
        tamano = cantidad * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procesos, &tamano, nil, 0) == 0 else { return false }
        for p in procesos.prefix(tamano / MemoryLayout<kinfo_proc>.stride) {
            let nombre = withUnsafeBytes(of: p.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if nombre == "codex", p.kp_eproc.e_tdev != -1 { return true }     // -1 = NODEV: sin terminal
        }
        return false
    }

    /// Memoria real que usa la app (la misma cifra que «Physical footprint» de vmmap), en MB.
    static func memoriaMB() -> Double {
        var info = task_vm_info_data_t()
        var cuenta = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cuenta)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &cuenta)
            }
        }
        return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
