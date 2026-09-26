import AppKit

let app = NSApplication.shared
let delegado = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegado
app.setActivationPolicy(.accessory)
app.run()
