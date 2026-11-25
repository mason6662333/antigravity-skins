import AppKit
import Security

enum ShareFiles {
    static let fm = FileManager.default
    static let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Antigravity Skins Share", isDirectory: true)
    static let library = root.appendingPathComponent("Library", isDirectory: true)
    static let native = "original"
    static let appleBundle = "com.google.antigravity"
    static var host: URL {
        let system = URL(fileURLWithPath: "/Applications/Antigravity.app", isDirectory: true)
        let personal = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Antigravity.app")
        return fm.fileExists(atPath: system.path) ? system : personal
    }
    static func compatibility(_ url: URL) -> String? {
        guard let b = Bundle(url: url), b.bundleIdentifier == appleBundle else { return "请先将官方 Antigravity 安装到“应用程序”。" }
        let binary = url.appendingPathComponent("Contents/MacOS/Antigravity").path
        let server = url.appendingPathComponent("Contents/Resources/bin/language_server").path
        guard fm.isExecutableFile(atPath: binary), fm.isExecutableFile(atPath: server) else {
            return "所选 Antigravity 缺少必需组件，请重新安装官方版本。"
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and identifier \"com.google.antigravity\" and certificate leaf[subject.OU] = \"EQHXZ8M8AV\""
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let code = code, SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else {
            return "请使用 Google 签名的原版 Antigravity。已定制的客户端请沿用原换肤方式。"
        }
        return nil
    }
    static func json(_ name: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func save(_ object: [String: Any], _ name: String) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: root.appendingPathComponent(name), options: .atomic)
    }
}
