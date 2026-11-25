import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EditorRequest: Identifiable {
    let id = UUID()
    let theme: Theme?
}

struct SkinEditor: View {
    @ObservedObject var library: Library
    let theme: Theme?
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var accent: Color
    @State private var replacement: URL?
    @State private var preview: NSImage?
    @State private var message = ""
    @State private var choosing = false

    init(library: Library, theme: Theme?, onSave: @escaping (String) -> Void) {
        self.library = library; self.theme = theme; self.onSave = onSave
        _name = State(initialValue: theme?.name ?? "")
        let hex = theme.map { library.asset($0).accent } ?? "#48b8a7"
        let bits = UInt32(hex.dropFirst(),radix:16) ?? 0x48b8a7
        _accent = State(initialValue: Color(.sRGB,red:Double(bits >> 16)/255,green:Double((bits >> 8) & 255)/255,blue:Double(bits & 255)/255))
        _preview = State(initialValue: theme.flatMap { t in
            let a = library.asset(t)
            let file = library.folder.appendingPathComponent(a.id).appendingPathComponent(a.image)
            return Library.thumbnail(file,size:1200).map { NSImage(cgImage:$0,size:.zero) }
        })
    }
    private func setPhoto(_ url: URL) {
        guard let image = Library.thumbnail(url,size:1000) else { message = "无法读取图片，请选择其他文件。"; return }
        preview = NSImage(cgImage:image,size:.zero); replacement = url
        if name.isEmpty { name = String(url.deletingPathExtension().lastPathComponent.prefix(64)) }
        message = ""
    }
    private func save() {
        do {
            let rgb = NSColor(accent).usingColorSpace(.sRGB) ?? .systemTeal
            let hex = String(format:"#%02x%02x%02x",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
            let id = try library.save(theme,name:name,accent:hex,replacement:replacement)
            onSave(id); dismiss()
        } catch { message = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:17) {
            Text(theme == nil ? "添加皮肤" : "编辑皮肤").font(.title2.bold())
            ZStack(alignment:.bottomTrailing) {
                Color(white:0.15)
                    .overlay {
                        if let preview { Image(nsImage:preview).resizable().scaledToFit() }
                        else { Image(systemName:"photo").font(.largeTitle).foregroundStyle(.secondary) }
                    }
                Button(replacement == nil && theme == nil ? "选择壁纸…" : "更换壁纸…") { choosing = true }.padding(12)
            }.frame(height:206).clipShape(RoundedRectangle(cornerRadius:11))
            HStack(spacing:18) {
                VStack(alignment:.leading,spacing:6) {
                    Text("皮肤名称").font(.callout)
                    TextField("输入名称",text:$name).textFieldStyle(.roundedBorder).accessibilityLabel("皮肤名称")
                }
                VStack(alignment:.leading,spacing:6) {
                    Text("强调色").font(.callout)
                    ColorPicker("强调色",selection:$accent,supportsOpacity:false).labelsHidden().frame(height:23)
                }
            }
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.orange) }
            Divider()
            HStack {
                if let theme {
                    Button("移到已删除",role:.destructive) {
                        do { try library.setDeleted(theme,true); dismiss() } catch { message = error.localizedDescription }
                    }.disabled(library.protected(theme))
                    if library.protected(theme) { Text("切换皮肤后可删除").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || (theme == nil && replacement == nil))
            }
        }.padding(23).frame(width:494)
        .fileImporter(isPresented:$choosing,allowedContentTypes:[.png,.jpeg,.heic,.webP]) { result in
            switch result {
            case .success(let url): setPhoto(url)
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription }
            }
        }
    }
}
