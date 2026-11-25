import SwiftUI
import AppKit

struct Gallery: View {
    @StateObject private var library = Library()
    #if SHARE
    @StateObject private var launcher = ShareLauncher()
    #endif
    @State private var shelf: Shelf = .all
    @State private var query = ""
    @State private var page = 0
    @State private var editor: EditorRequest?
    @State private var hover: String?
    private let perPage = 6
    private let timer = Timer.publish(every:0.65,on:.main,in:.common).autoconnect()
    private var shown: [Theme] { library.list(shelf,query) }
    private var pages: Int { max(1,(shown.count + perPage - 1)/perPage) }
    private var current: Int { min(page,pages-1) }
    private var selectionName: String {
        library.selection.id == "original" ? "原版外观" : library.name(library.selection.id)
    }
    private var status: String {
        #if SHARE
        if !launcher.reason.isEmpty { return launcher.reason }
        if launcher.external { return "请先退出 Antigravity，再从这里启动。" }
        if launcher.starting { return "正在打开 Antigravity…" }
        if !launcher.active { return "已选择 · " + selectionName }
        #endif
        return (library.pending ? "等待应用 · " : "当前使用 · ") + selectionName
    }
    private func showSaved(_ id: String) {
        if shelf != .all { shelf = .all }
        if !query.isEmpty { query = "" }
        // Allow filter-reset handlers to finish before revealing the saved card.
        DispatchQueue.main.async {
            if let i = library.list(.all,"").firstIndex(where: { $0.id == id }) { page = i/perPage }
        }
    }
    private var header: some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:6) {
                Text("皮肤库").font(.system(size:29,weight:.semibold))
                HStack(spacing:6) {
                    Circle().fill(library.pending ? Color.orange : Color.mint).frame(width:7,height:7)
                    Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            #if SHARE
            if !launcher.active {
                Button("带皮肤启动") { launcher.launch() }.disabled(launcher.external || launcher.starting || !launcher.reason.isEmpty)
            }
            Menu {
                Button("使用原版外观") { library.chooseID(ShareFiles.native) }
                Button("选择 Antigravity…") { launcher.locate() }.disabled(launcher.active || launcher.starting)
            } label: { Image(systemName:"ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("启动选项")
            #endif
            Button { editor = EditorRequest(theme:nil) } label: {
                Label("添加皮肤",systemImage:"plus").padding(.horizontal,3)
            }.controlSize(.large)
        }
    }
    private var filters: some View {
        HStack {
            Picker("皮肤分类",selection:$shelf) {
                ForEach(Shelf.allCases,id:\.self) { value in Text(value.rawValue).tag(value) }
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            HStack(spacing:6) {
                Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索皮肤",text:$query).textFieldStyle(.plain).accessibilityLabel("搜索皮肤")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName:"xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
            }.padding(.horizontal,9).frame(width:170,height:28)
                .background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:7))
        }
    }
    private func card(_ theme: Theme) -> some View {
        let deleted = shelf == .trash
        let chosen = library.canonical(library.selection.id) == theme.id && !deleted
        return VStack(alignment:.leading,spacing:0) {
            Button {
                if !deleted { library.choose(theme) }
            } label: {
                Color.clear.aspectRatio(2.08,contentMode:.fit)
                    .overlay {
                        if let image = library.preview(theme) { Image(nsImage:image).resizable().scaledToFill() }
                    }.clipped().contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(deleted).accessibilityLabel("应用"+theme.name)
            HStack(spacing:7) {
                if chosen { Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.mint).accessibilityHidden(true) }
                Button(theme.name) { if !deleted { library.choose(theme) } }
                    .buttonStyle(.plain).font(.system(size:14,weight:.medium)).lineLimit(1)
                    .disabled(deleted).help(theme.name)
                Spacer(minLength:2)
                Button {
                    if deleted {
                        do { try library.setDeleted(theme,false) } catch { library.error = error.localizedDescription }
                    } else { editor = EditorRequest(theme:theme) }
                } label: {
                    Image(systemName:deleted ? "arrow.uturn.backward" : "pencil").frame(width:28,height:28)
                }.buttonStyle(.borderless).accessibilityLabel((deleted ? "恢复" : "编辑")+theme.name)
                    .help(deleted ? "恢复到皮肤库" : "编辑皮肤")
            }.padding(.leading,12).padding(.trailing,6).frame(height:40)
        }.background(Color(white:hover == theme.id ? 0.19 : 0.145))
            .clipShape(RoundedRectangle(cornerRadius:11))
            .overlay { RoundedRectangle(cornerRadius:11).strokeBorder(chosen ? Color.mint : .white.opacity(0.12),lineWidth:chosen ? 2 : 1).allowsHitTesting(false) }
            .onHover { hover = $0 ? theme.id : nil }
    }
    private var footer: some View {
        HStack(spacing:10) {
            Text(shown.isEmpty ? "共 0 款" : "第 \(current*perPage+1)–\(min((current+1)*perPage,shown.count)) 款，共 \(shown.count) 款")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button { page = max(0,current-1) } label: { Image(systemName:"chevron.left") }
                .disabled(current == 0).accessibilityLabel("上一页")
            Text("\(current+1) / \(pages)").font(.callout.monospacedDigit())
            Button { page = min(pages-1,current+1) } label: { Image(systemName:"chevron.right") }
                .disabled(current == pages-1).accessibilityLabel("下一页")
        }.padding(.horizontal,24).frame(height:46)
    }
    var body: some View {
        VStack(spacing:0) {
            VStack(spacing:18) { header; filters }.padding(.horizontal,24).padding(.top,15).padding(.bottom,15)
            Divider()
            if !library.error.isEmpty { Text(library.error).font(.callout).foregroundStyle(.orange).padding(6) }
            #if SHARE
            if !launcher.failure.isEmpty { Text(launcher.failure).font(.callout).foregroundStyle(.orange).padding(6) }
            #endif
            GeometryReader { geometry in
                if shown.isEmpty {
                    VStack(spacing:12) {
                        Image(systemName:!query.isEmpty ? "magnifyingglass" : shelf == .trash ? "trash" : "clock").font(.title).foregroundStyle(.secondary)
                        Text(!query.isEmpty ? "没有匹配的皮肤" : shelf == .trash ? "没有已删除的皮肤" : "还没有使用记录")
                        if !query.isEmpty { Button("清除搜索") { query = "" } }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:16),count:geometry.size.width >= 740 ? 3 : 2),spacing:16) {
                            ForEach(Array(shown.dropFirst(current*perPage).prefix(perPage))) { theme in card(theme) }
                        }.padding(.horizontal,24).padding(.vertical,18)
                    }.id("\(shelf.rawValue)-\(current)")
                }
            }
            Divider(); footer
        }.frame(minWidth:680,minHeight:460)
            .background(Color(red:0.086,green:0.09,blue:0.099))
            .preferredColorScheme(.dark)
            .onChange(of:shelf) { page = 0 }
            .onChange(of:query) { page = 0 }
            .onChange(of:pages) { _, total in page = min(page,total-1) }
            .sheet(item:$editor) { request in SkinEditor(library:library,theme:request.theme,onSave:showSaved) }
            .onReceive(timer) { _ in
                library.refresh()
                #if SHARE
                launcher.refresh()
                #endif
            }
    }
}
@main struct SkinGallery: App {
    var body: some Scene {
        Window("Antigravity Skins",id:"gallery") { Gallery() }.defaultSize(width:910,height:615)
    }
}
