import Foundation
import UIKit

/// What `manifest.json` (§2) says about this phone and build.
enum DeviceInfo {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// `iPhone17,1`; the simulator reports the device it emulates.
    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    static func manifest() -> Manifest {
        Manifest(appVersion: appVersion,
                 device: .init(name: UIDevice.current.name, model: model,
                               os: "iOS " + UIDevice.current.systemVersion))
    }
}
