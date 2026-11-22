import CryptoKit
import Foundation

// Readscape license tool (keep this and the private key OFF any public repo / never ship it).
//
//   swift Tools/license_tool.swift keygen                 -> creates Tools/keys/private.key, prints the public key
//   swift Tools/license_tool.swift issue "Jane Reader" [order-id]   -> prints a license key for that buyer
//
// Keys are Ed25519 signatures over a small JSON payload, verified offline by the app.

let args = CommandLine.arguments.dropFirst()
let keyURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("keys/private.key")

func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

switch args.first {
case "keygen":
    if FileManager.default.fileExists(atPath: keyURL.path) {
        print("A private key already exists at \(keyURL.path). Delete it first if you really want a new one (old licenses would stop working).")
        exit(1)
    }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try key.rawRepresentation.base64EncodedString().write(to: keyURL, atomically: true, encoding: .utf8)
    print("Private key saved to \(keyURL.path)")
    print("Public key (paste into Sources/License.swift):")
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "issue":
    guard let name = args.dropFirst().first else { print("usage: issue \"Buyer Name\" [order-id]"); exit(1) }
    let order = args.dropFirst(2).first ?? UUID().uuidString.prefix(8).lowercased()
    let raw = try String(contentsOf: keyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: raw)!)
    let payload: [String: String] = ["n": name, "o": String(order), "e": "lifetime", "d": ISO8601DateFormatter().string(from: Date())]
    let body = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys)
    let sig = try key.signature(for: body)
    print("RS1-" + b64url(body) + "." + b64url(sig))
default:
    print("usage: license_tool.swift keygen | issue \"Buyer Name\" [order-id]")
}
