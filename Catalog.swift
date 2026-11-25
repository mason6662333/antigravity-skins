import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct Theme: Codable, Identifiable {
    let id: String
    var name, image, accent: String
    // Host loaders consume immutable image IDs. The gallery keeps one editable card per original.
    var owner: String?
    var artwork: String?
    var deleted: Bool?
}
struct Selection: Codable, Equatable { let id, revision: String }
struct Applied: Codable, Equatable { let id, revision: String; let recent: [String] }
enum Shelf: String, CaseIterable { case all = "全部", recent = "最近用过", trash = "已删除" }
enum LibraryFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor final class Library: ObservableObject {
    static let first = "crayon-shin-chan"
    #if SHARE
    let root = ShareFiles.root
    @Published var applied = Applied(id: "", revision: "", recent: [])
    #else
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Antigravity Skins")
    @Published var applied = Applied(id: first, revision: "initial", recent: [first])
    #endif
    @Published private(set) var records: [Theme] = []
    @Published var selection = Selection(id: first, revision: "initial")
    @Published var error = ""
    private let fm = FileManager.default
    private var previews: [String:NSImage] = [:]
    var folder: URL { root.appendingPathComponent("Library") }
    var catalog: URL { folder.appendingPathComponent("catalog.json") }
    init() {
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: folder.path) {
                let temp = root.appendingPathComponent(".catalog-"+UUID().uuidString)
                defer { try? fm.removeItem(at: temp) }
                try fm.copyItem(at: Bundle.main.resourceURL!.appendingPathComponent("Library"), to: temp)
                try fm.moveItem(at: temp, to: folder)
            }
            records = try read()
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    private func read() throws -> [Theme] { try JSONDecoder().decode([Theme].self, from: Data(contentsOf: catalog)) }
    private func change(_ edit: (inout [Theme]) throws -> Void) throws {
        let fd = open(root.appendingPathComponent("catalog.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw LibraryFailure.message("无法打开皮肤库。") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw LibraryFailure.message("皮肤库正忙，请重试。") }
        var next = try read()
        try edit(&next)
        try JSONEncoder().encode(next).write(to: catalog, options: .atomic)
        records = next
    }
    func canonical(_ id: String) -> String { records.first { $0.id == id }?.owner ?? id }
    func asset(_ theme: Theme) -> Theme { records.first { $0.id == theme.artwork } ?? theme }
    func name(_ id: String) -> String { records.first { $0.id == canonical(id) }?.name ?? id }
    func preview(_ theme: Theme) -> NSImage? {
        let key = asset(theme).id
        if previews[key] == nil { previews[key] = NSImage(contentsOf: folder.appendingPathComponent(key).appendingPathComponent("preview.jpg")) }
        return previews[key]
    }
    func list(_ shelf: Shelf, _ query: String) -> [Theme] {
        let items = records.filter { $0.owner == nil && ($0.deleted == true) == (shelf == .trash) }
        let result: [Theme]
        if shelf == .recent {
            var seen = Set<String>()
            result = applied.recent.map(canonical).compactMap { id in
                guard seen.insert(id).inserted else { return nil }
                return items.first { $0.id == id }
            }
        } else {
            result = items.sorted { a,b in
                if a.id == Self.first || b.id == Self.first { return a.id == Self.first && b.id != Self.first }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? result : result.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }
    func refresh() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: root.appendingPathComponent("selection.json")),
           let next = try? decoder.decode(Selection.self, from: data), selection != next { selection = next }
        if let data = try? Data(contentsOf: root.appendingPathComponent("applied.json")),
           let next = try? decoder.decode(Applied.self, from: data), applied != next { applied = next }
    }
    func chooseID(_ id: String) {
        do {
            let next = Selection(id: id, revision: UUID().uuidString)
            try JSONEncoder().encode(next).write(to: root.appendingPathComponent("selection.json"), options: .atomic)
            selection = next
            error = ""
        } catch { self.error = error.localizedDescription }
    }
    func choose(_ theme: Theme) { chooseID(asset(theme).id) }
    var pending: Bool { selection.revision != applied.revision || selection.id != applied.id }
    func protected(_ theme: Theme) -> Bool {
        theme.id == canonical(selection.id) || theme.id == canonical(applied.id)
    }
    func setDeleted(_ theme: Theme, _ deleted: Bool) throws {
        refresh()
        if deleted && protected(theme) { throw LibraryFailure.message("这款皮肤正在使用或等待应用。请先切换到另一款。") }
        try change { items in
            guard let index = items.firstIndex(where: { $0.id == theme.id }) else { throw LibraryFailure.message("皮肤已变更，请重新打开。") }
            items[index].deleted = deleted
        }
    }
    @discardableResult func save(_ theme: Theme?, name: String, accent: String, replacement: URL?) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64 else { throw LibraryFailure.message("名称请填写 1 到 64 个字符。") }
        guard accent.range(of:"^#[a-fA-F0-9]{6}$",options:.regularExpression) != nil else { throw LibraryFailure.message("请选择有效的强调色。") }
        let id = theme?.id ?? "custom-"+UUID().uuidString.lowercased()
        let previous = theme.map(asset)
        let newAsset = replacement != nil || previous?.accent.lowercased() != accent.lowercased()
        var created: URL?
        do {
            try change { rows in
                if let theme, !rows.contains(where: { $0.id == id && $0.artwork == theme.artwork && $0.deleted != true }) {
                    throw LibraryFailure.message("这款皮肤已变更，请重新打开。")
                }
                let index = rows.firstIndex(where: { $0.id == id })
                if !newAsset, let index { rows[index].name = name; return }
                var key = theme == nil ? id : id+"-"+UUID().uuidString.lowercased()
                // Existing hosts distinguish these palettes by the last segment of the asset ID.
                if theme != nil && id.hasPrefix("snow-night-homeward-"), let mode = id.split(separator:"-").last {
                    key += "-" + mode
                }
                let target = folder.appendingPathComponent(key)
                try fm.createDirectory(at: target, withIntermediateDirectories: false)
                created = target
                let image: String
                if let replacement {
                    image = "background.jpg"
                    try Self.writeWallpaper(replacement, to:target)
                } else if let previous {
                    image = previous.image
                    for file in [image,"preview.jpg"] {
                        let source = folder.appendingPathComponent(previous.id).appendingPathComponent(file)
                        let destination = target.appendingPathComponent(file)
                        do { try fm.linkItem(at:source,to:destination) }
                        catch { try fm.copyItem(at:source,to:destination) }
                    }
                } else { throw LibraryFailure.message("请先选择一张壁纸。") }
                rows.append(Theme(id:key,name:name,image:image,accent:accent,owner:theme == nil ? nil : id))
                if let index { rows[index].name = name; rows[index].artwork = key }
            }
        } catch {
            if let created { try? fm.removeItem(at: created) }
            throw error
        }
        if theme != nil && canonical(selection.id) == id && newAsset, let updated = records.first(where: { $0.id == id }) { choose(updated) }
        return id
    }
    static func thumbnail(_ url: URL, size: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source,0,[
            kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:size
        ] as CFDictionary)
    }
    private static func writeWallpaper(_ url: URL, to folder: URL) throws {
        for (name,limit) in [("background.jpg",4096),("preview.jpg",640)] {
            guard let bitmap = thumbnail(url,size:limit),
                  let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL,UTType.jpeg.identifier as CFString,1,nil) else {
                throw LibraryFailure.message("无法读取这张图片，请选择 JPG、PNG、HEIC 或 WebP。")
            }
            CGImageDestinationAddImage(dest,bitmap,[kCGImageDestinationLossyCompressionQuality:0.94] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw LibraryFailure.message("壁纸保存失败。") }
        }
    }
}
