import Foundation
import Security

/// Pro on this Mac: active or not, and why. Mirrors `ProStatus` in pro.py.
struct ProState {
    let active: Bool
    let reason: String
    var expiresAt: String? = nil
    var environment: String? = nil
    var source: String = "none"
}

/// The single paid plan. A StoreKit 2 signed transaction (JWS) written by the iOS app to license.json,
/// verified offline against Apple Root CA G3. Nothing here talks to a server (pro.py).
enum License {
    static let graceSeconds: Double = 3 * 24 * 3600
    static let overrideKey = "CarryProOverride"
    private static let legacyOverrideKey = "CARRY_PRO"

    /// Apple Root CA - G3 (cli/src/carry/assets/AppleRootCA-G3.pem).
    static let appleRootPEM = """
    -----BEGIN CERTIFICATE-----
    MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
    QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
    IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
    MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
    b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
    aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
    AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
    TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
    IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
    MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
    MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
    at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
    6BgD56KyKA==
    -----END CERTIFICATE-----
    """

    static var appleRoot: SecCertificate? {
        let body = appleRootPEM.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: body) else { return nil }
        return SecCertificateCreateWithData(nil, der as CFData)
    }

    private static func b64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    /// `verify_jws(jws)`
    static func verifyJWS(_ jws: String) -> ProState {
        let parts = jws.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let headerData = b64url(String(parts[0])), let payloadData = b64url(String(parts[1])),
              let sig = b64url(String(parts[2])), let header = JSON.parse(headerData), let payload = JSON.parse(payloadData) else {
            return ProState(active: false, reason: "license.json is not a valid JWS")
        }
        guard header["alg"]?.string == "ES256", let x5c = header["x5c"]?.array, !x5c.isEmpty else {
            return ProState(active: false, reason: "unexpected JWS header")
        }
        var chain: [SecCertificate] = []
        for c in x5c {
            guard let s = c.string, let der = Data(base64Encoded: s), let cert = SecCertificateCreateWithData(nil, der as CFData) else {
                return ProState(active: false, reason: "bad certificate chain")
            }
            chain.append(cert)
        }
        guard let root = appleRoot, chainLeadsToAppleRoot(chain, root: root, at: payload["signedDate"]?.double) else {
            return ProState(active: false, reason: "certificate chain does not lead to Apple Root CA G3")
        }
        guard let key = SecCertificateCopyKey(chain[0]), sig.count == 64,
              verifyES256(key: key, message: Data("\(parts[0]).\(parts[1])".utf8), rawSignature: sig) else {
            return ProState(active: false, reason: "signature does not verify")
        }
        let productID = payload["productId"]?.string ?? ""
        guard CarryPaths.proProductIDs.contains(productID) else {
            return ProState(active: false, reason: "license is for \(payload["productId"]?.pyStr ?? "None"), not Carry Pro")
        }
        if payload["revocationDate"]?.truthy == true {
            return ProState(active: false, reason: "license was revoked")
        }
        let environment = payload["environment"]?.string
        if let expMs = payload["expiresDate"]?.double, expMs != 0 {
            if expMs / 1000 + graceSeconds < Date().timeIntervalSince1970 {
                return ProState(active: false, reason: "license expired", expiresAt: msISO(expMs), environment: environment, source: "phone")
            }
            return ProState(active: true, reason: "verified StoreKit transaction", expiresAt: msISO(expMs), environment: environment, source: "phone")
        }
        return ProState(active: true, reason: "verified StoreKit transaction", expiresAt: nil, environment: environment, source: "phone")
    }

    /// The x5c chain must end at (or be issued by) the embedded Apple Root CA G3 and each link must be
    /// directly issued by the next. SecTrust does that with the root as the only anchor; the verify date is the
    /// transaction's signedDate so an old but genuine transaction still checks out.
    private static func chainLeadsToAppleRoot(_ chain: [SecCertificate], root: SecCertificate, at signedMs: Double?) -> Bool {
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess, let trust else { return false }
        SecTrustSetAnchorCertificates(trust, [root] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetNetworkFetchAllowed(trust, false)
        if let signedMs, signedMs > 0 { SecTrustSetVerifyDate(trust, Date(timeIntervalSince1970: signedMs / 1000) as CFDate) }
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }

    /// ES256 over `header.payload`; the JWS carries r||s, Security wants DER.
    private static func verifyES256(key: SecKey, message: Data, rawSignature: Data) -> Bool {
        func derInteger(_ bytes: Data) -> Data {
            var b = [UInt8](bytes)
            while b.count > 1, b[0] == 0 { b.removeFirst() }
            if let first = b.first, first & 0x80 != 0 { b.insert(0, at: 0) }
            return Data([0x02, UInt8(b.count)] + b)
        }
        let r = derInteger(rawSignature.prefix(32)), s = derInteger(rawSignature.suffix(32))
        let der = Data([0x30, UInt8(r.count + s.count)]) + r + s
        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(key, .ecdsaSignatureMessageX962SHA256, message as CFData, der as CFData, &error)
    }

    private static func msISO(_ ms: Double) -> String {
        PyTime.iso(Date(timeIntervalSince1970: ms / 1000))
    }

    /// The developer override: defaults key `CarryProOverride` (the old string key `CARRY_PRO` migrates once),
    /// or `CARRY_PRO=1` in the environment.
    static var overrideOn: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: overrideKey) == nil, defaults.string(forKey: legacyOverrideKey) == "1" {
            defaults.set(true, forKey: overrideKey)
            defaults.removeObject(forKey: legacyOverrideKey)
        }
        if defaults.bool(forKey: overrideKey) { return true }
        return ProcessInfo.processInfo.environment["CARRY_PRO"] == "1"
    }

    /// `status()`
    static func status() -> ProState {
        if overrideOn {
            return ProState(active: true, reason: "CARRY_PRO=1 (developer override)", source: "env")
        }
        let p = CarryPaths.container.appendingPathComponent("license.json")
        guard FileManager.default.fileExists(atPath: p.path) else {
            return ProState(active: false, reason: "no license.json in the Carry folder yet")
        }
        guard let data = try? Data(contentsOf: p), let json = JSON.parse(data) else {
            return ProState(active: false, reason: "license.json unreadable")
        }
        guard let jws = json["jws"]?.string, !jws.isEmpty else {
            return ProState(active: false, reason: "license.json has no jws")
        }
        return verifyJWS(jws)
    }

    static func isPro() -> Bool { status().active }
}
