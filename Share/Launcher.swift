import SwiftUI
import AppKit

@MainActor final class ShareLauncher: ObservableObject {
    @Published var active = false
    @Published var external = false
    @Published var reason = ""
    @Published var starting = false
    @Published var failure = ""
    private var target = ShareFiles.host
    private var helper: Process?
    init() {
        if let path = ShareFiles.json("host.json")?["path"] as? String {
            target = URL(fileURLWithPath:path)
        }
        reason = ShareFiles.compatibility(target) ?? ""
        refresh()
    }
    func refresh() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier:ShareFiles.appleBundle)
            .first { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == target.resolvingSymlinksInPath().standardizedFileURL.path }
        let pid = ShareFiles.json("session.json")?["pid"] as? Int32
        let managed = running != nil && running?.processIdentifier == pid
        let independent = running != nil && !managed
        if active != managed { active = managed }
        if external != independent { external = independent }
        if managed && starting { starting = false }
    }
    func locate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath:"/Applications")
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let issue = ShareFiles.compatibility(url) { failure = issue; return }
        target = url
        do { try ShareFiles.save(["path":url.path],"host.json"); failure = ""; reason = ""; refresh() }
        catch { failure = error.localizedDescription }
    }
    func launch() {
        reason = ShareFiles.compatibility(target) ?? ""
        refresh()
        guard !external, !active, !starting, reason.isEmpty else { return }
        let p = Process()
        p.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ThemeSession")
        p.arguments = [target.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self, self.helper === proc else { return }
                if self.starting { self.failure = "启动未完成。请确认 Antigravity 已完全退出，再试一次。" }
                self.starting = false; self.helper = nil; self.refresh()
            }
        }
        do { try p.run(); helper = p; starting = true; failure = "" }
        catch { failure = error.localizedDescription }
    }
}
