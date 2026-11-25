import Foundation
import Darwin

private typealias Object = [String: Any]
private enum Failure: Error { case disconnected, invalid, timeout }
private final class PrivatePipe {
    let input: FileHandle
    let output: FileHandle
    var buffered = Data()
    var nextID = 0
    init(_ send: Int32, _ receive: Int32) {
        output = FileHandle(fileDescriptor: send, closeOnDealloc: true)
        input = FileHandle(fileDescriptor: receive, closeOnDealloc: true)
    }
    func call(_ method: String, _ params: Object = [:], session: String? = nil) throws -> Object {
        nextID += 1
        var request: Object = ["id": nextID, "method": method, "params": params]
        if let session { request["sessionId"] = session }
        var encoded = try JSONSerialization.data(withJSONObject: request)
        encoded.append(0)
        try output.write(contentsOf: encoded)
        let deadline = ProcessInfo.processInfo.systemUptime + 6
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let end = buffered.firstIndex(of: 0) {
                let message = buffered[..<end]
                buffered = Data(buffered[buffered.index(after: end)...])
                guard let object = try JSONSerialization.jsonObject(with: message) as? Object, object["id"] as? Int == nextID else { continue }
                guard let result = object["result"] as? Object else { throw Failure.invalid }
                return result
            }
            guard wait_readable(input.fileDescriptor, 500) > 0 else { continue }
            let bytes = input.availableData
            guard !bytes.isEmpty else { throw Failure.disconnected }
            buffered.append(bytes)
        }
        throw Failure.timeout
    }
}

private func commandOutput(_ path: String, _ args: [String]) -> String {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath:path); p.arguments = args
    p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: bytes, as: UTF8.self)
}

// Only allow pages served by the language server owned by this Antigravity process.
private func localPorts(host: URL, pid: Int32) -> Set<Int> {
    let children = commandOutput("/usr/bin/pgrep", ["-P",String(pid),"-x","language_server"])
    let server = host.appendingPathComponent("Contents/Resources/bin/language_server").path
    var ports = Set<Int>()
    for value in children.split(whereSeparator: \.isWhitespace) {
        guard let child = Int32(value), child_is_server(child, server) != 0 else { continue }
        let sockets = commandOutput("/usr/sbin/lsof", ["-nP","-a","-p",String(child),"-iTCP","-sTCP:LISTEN","-Fn"])
        for line in sockets.split(separator:"\n") where line.hasPrefix("n127.0.0.1:") {
            if let port = Int(line.dropFirst("n127.0.0.1:".count)) { ports.insert(port) }
        }
    }
    return ports
}
private func eligible(_ raw: Any?, _ ports: Set<Int>) -> Bool {
    guard let text = raw as? String, let url = URL(string:text), url.scheme == "https", url.host == "127.0.0.1", let port = url.port else { return false }
    return ports.contains(port)
}

private struct ThemeEntry: Decodable { let id, image, accent: String }
private struct Styles {
    let template: String
    func css(_ id: String) throws -> String {
        if id == ShareFiles.native { return "" }
        let themes = try JSONDecoder().decode([ThemeEntry].self, from: Data(contentsOf:ShareFiles.library.appendingPathComponent("catalog.json")))
        guard let theme = themes.first(where: { $0.id == id }),
              id.range(of: "^[a-z0-9-]+$",options:.regularExpression) != nil,
              theme.accent.range(of:"^#[0-9a-fA-F]{6}$",options:.regularExpression) != nil,
              ["background.png","background.jpg","background.webp"].contains(theme.image) else { throw Failure.invalid }
        let file = ShareFiles.library.appendingPathComponent(id).appendingPathComponent(theme.image)
        let data = try Data(contentsOf:file)
        let type = ["jpg":"jpeg","webp":"webp","png":"png"][file.pathExtension]!
        var css = template.replacingOccurrences(of:"__ARTWORK__",with:"data:image/"+type+";base64,"+data.base64EncodedString())
        if id != "crayon-shin-chan" {
            css = css.replacingOccurrences(of:"#cd2316",with:theme.accent)
                .replacingOccurrences(of:"#b01e13",with:"color-mix(in srgb, "+theme.accent+" 70%, black)")
                .replacingOccurrences(of:"#ffa79b",with:"color-mix(in srgb, "+theme.accent+" 65%, white)")
        }
        if id.hasPrefix("snow-night-homeward") {
            let alpha = id.hasSuffix("atmosphere") ? ".81" : id.hasSuffix("readable") ? ".97" : ".9"
            css += "\nbody.theme-dark { --shin-reading: rgba(12,25,46,"+alpha+"); --shin-rail: rgba(8,18,36,.76); --shin-veil: rgba(8,16,34,.28); }"
        }
        return css
    }
}

private struct PageState {
    let session: String
    var loader = "", sheet = "", revision = ""
}
private final class Session {
    let pipe: PrivatePipe, styles: Styles
    var pages: [String:PageState] = [:]
    var lastAck = "", cachedID = "", cachedCSS = ""
    init(_ pipe: PrivatePipe, _ styles: Styles) { self.pipe = pipe; self.styles = styles }
    func tick(_ ports: Set<Int>) throws {
        let selection = ShareFiles.json("selection.json")
        let id = selection?["id"] as? String ?? "crayon-shin-chan"
        let revision = selection?["revision"] as? String ?? "initial"
        let targets = try pipe.call("Target.getTargets",["filter":[["type":"page"],["exclude":true]]])["targetInfos"] as? [Object] ?? []
        let hubs = targets.filter { eligible($0["url"], ports) }
        let keys = Set(hubs.compactMap { $0["targetId"] as? String })
        for key in Array(pages.keys) where !keys.contains(key) {
            if let removed = pages.removeValue(forKey:key) {
                _ = try? pipe.call("Target.detachFromTarget",["sessionId":removed.session])
            }
        }
        var confirmed = false
        for hub in hubs {
            guard let key = hub["targetId"] as? String else { continue }
            if pages[key] == nil {
                guard let session = try pipe.call("Target.attachToTarget",["targetId":key,"flatten":true])["sessionId"] as? String else { continue }
                pages[key] = PageState(session:session)
            }
            guard var state = pages[key] else { continue }
            do {
                let tree = try pipe.call("Page.getFrameTree", session:state.session)["frameTree"] as? Object
                guard let frame = tree?["frame"] as? Object, eligible(frame["url"],ports),
                      let loader = frame["loaderId"] as? String, let frameID = frame["id"] as? String else { continue }
                if state.loader != loader || state.sheet.isEmpty {
                    _ = try pipe.call("DOM.enable",session:state.session)
                    _ = try pipe.call("CSS.enable",session:state.session)
                    guard let sheet = try pipe.call("CSS.createStyleSheet",["frameId":frameID],session:state.session)["styleSheetId"] as? String else { continue }
                    state = PageState(session:state.session,loader:loader,sheet:sheet,revision:"")
                }
                if state.revision != revision {
                    if cachedID != id { cachedCSS = try styles.css(id); cachedID = id }
                    _ = try pipe.call("CSS.setStyleSheetText",["styleSheetId":state.sheet,"text":cachedCSS],session:state.session)
                    state.revision = revision
                }
                pages[key] = state
                confirmed = true
            } catch {
                _ = try? pipe.call("Target.detachFromTarget",["sessionId":state.session])
                pages.removeValue(forKey:key)
            }
        }
        if confirmed && lastAck != revision {
            let current = ShareFiles.json("selection.json")?["revision"] as? String ?? "initial"
            guard current == revision else { return }
            var recent = ShareFiles.json("applied.json")?["recent"] as? [String] ?? []
            if id != ShareFiles.native { recent = [id]+recent.filter { $0 != id } }
            try ShareFiles.save(["id":id,"revision":revision,"recent":recent],"applied.json")
            lastAck = revision
        }
    }
}

@main struct SkinSession {
    static func main() {
        guard CommandLine.arguments.count == 2 else { return }
        let host = URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
        guard ShareFiles.compatibility(host) == nil else { return }
        let lockFile = ShareFiles.root.appendingPathComponent("session.lock")
        let lock = open(lockFile.path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { close(lock) }
        signal(SIGPIPE,SIG_IGN)
        let resources = URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        do {
            let styles = Styles(template:try String(contentsOf:resources.appendingPathComponent("skin-template.css"),encoding:.utf8))
            var send: Int32 = -1, receive: Int32 = -1
            let pid = start_skin_host(host.appendingPathComponent("Contents/MacOS/Antigravity").path,&send,&receive)
            guard pid > 0 else { throw Failure.disconnected }
            let status = ShareFiles.root.appendingPathComponent("session.json")
            defer { try? FileManager.default.removeItem(at:status) }
            let pipe = PrivatePipe(send,receive), session = Session(pipe,styles)
            try? ShareFiles.save(["pid":Int(pid)],"session.json")
            var ports: Set<Int> = [], lastPorts = -100.0
            while waitpid(pid,nil,WNOHANG) == 0 {
                autoreleasepool {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now-lastPorts > (ports.isEmpty ? 2 : 20) { ports = localPorts(host:host,pid:pid); lastPorts = now }
                    if !ports.isEmpty { try? session.tick(ports) }
                }
                Thread.sleep(forTimeInterval:0.65)
            }
        } catch { try? ShareFiles.save(["error":"换肤启动失败，请重新打开皮肤库。"],"session.json") }
    }
}
