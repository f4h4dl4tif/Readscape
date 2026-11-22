import CryptoKit
import Foundation
import SwiftUI

/// One-time "lifetime" license. Keys are signed offline with Tools/license_tool.swift and verified here
/// with the embedded public key — no account, no server, works offline forever.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    static let publicKey = "EoaSLQXJWvi2ELwSLKcdXEo1PJtXrEMD0835xgmj5Xw="
    static let purchaseURL = URL(string: "https://readscape.app/buy")!   // replace with your Gumroad / Lemon Squeezy / Paddle link
    static let freeBookLimit = 20
    static let freeMapLimit = 1

    @Published private(set) var licensee: String?
    var isLicensed: Bool { licensee != nil }

    private let defaultsKey = "licenseKey"

    init() {
        if let key = UserDefaults.standard.string(forKey: defaultsKey) { licensee = Self.verify(key) }
    }

    /// Returns nil on success, otherwise a user-facing error.
    func activate(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name = Self.verify(key) else { return "That license key isn't valid. Check that you pasted the whole key." }
        UserDefaults.standard.set(key, forKey: defaultsKey)
        licensee = name
        return nil
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        licensee = nil
    }

    func canAddBook(currentCount: Int) -> Bool { isLicensed || currentCount < Self.freeBookLimit }
    func canAddMap(currentCount: Int) -> Bool { isLicensed || currentCount < Self.freeMapLimit }

    static func verify(_ key: String) -> String? {
        guard key.hasPrefix("RS1-") else { return nil }
        let parts = key.dropFirst(4).split(separator: ".")
        guard parts.count == 2, let body = b64url(String(parts[0])), let sig = b64url(String(parts[1])),
              let pk = try? Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: publicKey)!),
              pk.isValidSignature(sig, for: body),
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: String] else { return nil }
        return obj["n"] ?? "Reader"
    }

    private static func b64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}

struct UpgradeView: View {
    @ObservedObject var license = LicenseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String?
    var reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text(license.isLicensed ? "Readscape Lifetime" : "Unlock Readscape").font(.title2.bold())
                    Text(license.isLicensed ? "Licensed to \(license.licensee ?? "")" : "One payment. Yours forever. No subscription.")
                        .foregroundStyle(.secondary)
                }
            }
            if let reason, !license.isLicensed {
                Label(reason, systemImage: "info.circle").foregroundStyle(.secondary)
            }
            if !license.isLicensed {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["Unlimited books, sessions and annotations", "Unlimited reading maps",
                             "All future 1.x updates", "Your data stays on your Mac"], id: \.self) {
                        Label($0, systemImage: "checkmark.circle.fill").symbolRenderingMode(.hierarchical)
                    }
                }
                Divider()
                Text("Already bought it? Paste your license key:").font(.callout)
                TextField("RS1-…", text: $key, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4).font(.system(.body, design: .monospaced))
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
            }
            HStack {
                if license.isLicensed {
                    Button("Deactivate on this Mac", role: .destructive) { license.deactivate() }
                } else {
                    Link("Buy Lifetime License…", destination: LicenseManager.purchaseURL)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if !license.isLicensed {
                    Button("Activate") { error = license.activate(key); if error == nil { dismiss() } }
                        .keyboardShortcut(.defaultAction).disabled(key.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
