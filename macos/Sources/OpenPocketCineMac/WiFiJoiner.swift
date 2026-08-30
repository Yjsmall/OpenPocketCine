import CoreWLAN
import Darwin
import Foundation
import Network
import OpenPocketViewCore
import os

/// macOS twin of the iOS `WiFiJoiner`. iOS uses `NEHotspotConfiguration`, which
/// does not exist on Mac, so the join path is CoreWLAN: scan for the camera's
/// SoftAP and `associate` with the credentials read over BLE. This only works
/// for a non-sandboxed, non-App-Store build (this target). Reading the current
/// SSID requires Location Services approval on macOS 14+; when it is denied we
/// fall back to path probing so a manual join in the Wi-Fi menu still works.
///
/// The camera is an internet-less AP at `192.168.2.1`; there is no cellular
/// default route on Mac, but a home Wi-Fi / Ethernet can still own the default
/// path, so the same interface pinning rules as iOS apply (DatalinkDriver).
enum WiFiJoiner {
    enum JoinError: LocalizedError {
        case failed(String)
        case pathNotReady
        case stillOnOtherBody(String)
        case noInterface
        case ssidNotFound(String)
        var errorDescription: String? {
            switch self {
            case .failed(let s): s
            case .pathNotReady: "camera Wi-Fi joined but 192.168.2.x never appeared"
            case .stillOnOtherBody(let ssid):
                "couldn't switch from \(ssid) — tap Connect again"
            case .noInterface: "no Wi-Fi interface on this Mac"
            case .ssidNotFound(let ssid):
                "didn't find \(ssid) — join it manually in the Wi-Fi menu, then retry"
            }
        }
    }

    private static let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "wifi")

    /// Leave the other Osmo SoftAP and join `ssid`. Pocket and Nano share
    /// `192.168.2.1`, so a leftover camera DHCP address is not a stop — apply
    /// the target join and let the Mac switch.
    static func joinCameraAP(
        ssid: String,
        passphrase: String,
        wpa3: Bool,
        knownOtherSSIDs: [String],
        persist: Bool = false
    ) async throws {
        var kick = Set(knownOtherSSIDs.filter { !$0.isEmpty && $0 != ssid })
        leave(ssids: Array(kick))

        var lastForeign: String?
        for attempt in 1...CameraSoftAPSwitch.maxJoinAttempts {
            try Task.checkCancellation()
            if let foreign = CameraSoftAPSwitch.ssidToKick(
                currentSSID: currentSSID(), target: ssid)
            {
                log.info(
                    "wifi: kick \(foreign, privacy: .public) then join \(ssid, privacy: .public) #\(attempt)"
                )
                leave(ssid: foreign)
                kick.insert(foreign)
                lastForeign = foreign
            }
            leave(ssids: Array(kick))
            try await join(ssid: ssid, passphrase: passphrase, wpa3: wpa3, persist: persist)
            try await waitUntilCameraPathReady()
            let now = currentSSID()
            if CameraSoftAPSwitch.isOnTarget(currentSSID: now, target: ssid) {
                log.info(
                    "wifi: on \(ssid, privacy: .public) (current=\(now ?? "nil", privacy: .public)) #\(attempt)"
                )
                return
            }
            lastForeign = now
            log.info(
                "wifi: still on \(now ?? "?", privacy: .public) after join \(ssid, privacy: .public) — retry"
            )
            if let now { leave(ssid: now) }
        }
        throw JoinError.stillOnOtherBody(lastForeign ?? "other camera")
    }

    /// Current SSID via CoreWLAN. Needs Location Services approval on macOS 14+
    /// (System Settings → Privacy & Security → Location Services → this app);
    /// without it this returns nil and join cannot verify the SSID — the path
    /// probe below still proves the camera network is up.
    static func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    static func join(
        ssid: String,
        passphrase: String,
        wpa3: Bool,
        persist: Bool = false
    ) async throws {
        // The path is the truth: a manual join (or a previous attempt) that
        // already yields `192.168.2.x` needs no association at all.
        if isCameraPathReady() { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try associateBlocking(ssid: ssid, passphrase: passphrase)
                    c.resume()
                } catch {
                    c.resume(throwing: error)
                }
            }
        }
    }

    /// CoreWLAN scan + associate. Blocks for seconds; call off the main actor.
    /// `persist` is accepted for signature parity with iOS; macOS keeps joins in
    /// the user's preferred-network list only when the user asks the system to.
    private static func associateBlocking(ssid: String, passphrase: String) throws {
        guard let interface = CWWiFiClient.shared().interface() else {
            throw JoinError.noInterface
        }
        // Already associated with the target (manual join): CoreWLAN errors on
        // re-association — treat it as the success it is.
        if currentSSID() == ssid { return }
        guard let data = ssid.data(using: .utf8),
            let network = (try? interface.scanForNetworks(withSSID: data))?
                .max(by: { $0.rssiValue < $1.rssiValue })
        else {
            // Scan can miss while the AP channel-hops. If the camera path is
            // already up, trust it — the datalink only needs 192.168.2.x.
            if isCameraPathReady() { return }
            throw JoinError.ssidNotFound(ssid)
        }
        do {
            try interface.associate(to: network, password: passphrase)
        } catch {
            // macOS may error while the system still switches (and always
            // errors on the already-associated case). Give DHCP a beat; the
            // path probe decides, not the associate result.
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if isCameraPathReady() { return }
                Thread.sleep(forTimeInterval: 0.2)
            }
            throw JoinError.failed(
                "\(error.localizedDescription) — join \(ssid) manually in the Wi-Fi menu, then press Connect again"
            )
        }
    }

    /// True when this Mac has a DHCP address on the camera AP.
    static func isCameraPathReady() -> Bool {
        CameraSoftAP.isPathReady(localIPv4s: ipv4Addresses())
    }

    /// Block until `192.168.2.2…254` exists. Second connect returns immediately.
    static func waitUntilCameraPathReady(timeout: TimeInterval = 15) async throws {
        if isCameraPathReady() { return }
        log.info("wifi: waiting for 192.168.2.x (first join / DHCP)")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if isCameraPathReady() {
                try await Task.sleep(for: .milliseconds(200))
                if isCameraPathReady() {
                    log.info(
                        "wifi: camera path ready (\(ipv4Addresses().filter(CameraSoftAP.isAssociatedIPv4).joined(separator: ","), privacy: .public))"
                    )
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw JoinError.pathNotReady
    }

    static func leave(ssid: String) {
        // macOS has no per-SSID configuration removal; disassociate only when we
        // are actually sitting on that network. Preferred-network cleanup is a
        // System Settings task for the operator.
        if currentSSID() == ssid {
            CWWiFiClient.shared().interface()?.disassociate()
        }
    }

    static func leave(ssids: [String]) {
        for ssid in Set(ssids) where !ssid.isEmpty {
            leave(ssid: ssid)
        }
    }

    static func ipv4Addresses() -> [String] {
        interfaceAddresses().map(\.ipv4)
    }

    static func cameraLocalIPv4() -> String? {
        CameraSoftAP.cameraLocalIPv4(in: interfaceAddresses())
    }

    static func cameraInterfaceNames() -> [String] {
        CameraSoftAP.cameraInterfaceNames(in: interfaceAddresses())
    }

    static func interfaceAddresses() -> [CameraSoftAP.InterfaceAddress] {
        var addrs: [CameraSoftAP.InterfaceAddress] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(first) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            guard let sa = ifa.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let ok = getnameinfo(
                sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST)
            if ok == 0 {
                addrs.append(
                    .init(
                        name: String(cString: ifa.pointee.ifa_name),
                        ipv4: String(cString: host)))
            }
        }
        return addrs
    }

    /// NWInterface that owns `192.168.2.2…254`. Nil if the SoftAP is not in the
    /// default path — caller still binds `requiredLocalEndpoint` to that IPv4.
    static func resolveCameraInterface(timeout: TimeInterval = 2) async -> NWInterface? {
        let names = Set(cameraInterfaceNames())
        guard !names.isEmpty else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<NWInterface?, Never>) in
            let monitor = NWPathMonitor()
            let q = DispatchQueue(label: "opv.macos.wifi.camera-if")
            var resumed = false
            let finish: @Sendable (NWInterface?) -> Void = { iface in
                guard !resumed else { return }
                resumed = true
                monitor.cancel()
                cont.resume(returning: iface)
            }
            monitor.pathUpdateHandler = { path in
                if let iface = path.availableInterfaces.first(where: { names.contains($0.name) }) {
                    finish(iface)
                }
            }
            monitor.start(queue: q)
            q.asyncAfter(deadline: .now() + timeout) {
                let iface = monitor.currentPath.availableInterfaces.first {
                    names.contains($0.name)
                }
                finish(iface)
            }
        }
    }
}
