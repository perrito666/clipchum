import ClipChumCore
import SwiftUI

struct ClipListView: View {
    @Bindable var model: ClipListModel
    @FocusState private var searchFocused: Bool

    static let size = CGSize(width: 440, height: 500)

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onChange(of: model.focusToken, initial: true) { _, _ in
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clips", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        if model.items.isEmpty {
            ContentUnavailableView {
                Label(model.isSearching ? "No matches" : "Nothing copied yet",
                      systemImage: model.isSearching ? "magnifyingglass" : "clipboard")
            } description: {
                Text(model.isSearching ? "Try a different search." : "Copy something and it will show up here.")
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, clip in
                            ClipRowView(clip: clip, isSelected: index == model.selectedIndex, now: model.now)
                                .id(clip.id)
                                .contentShape(Rectangle())
                                .onTapGesture { model.activate(clip) }
                                .contextMenu { contextMenu(for: clip) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selectedIndex) { _, idx in
                    if model.items.indices.contains(idx) {
                        proxy.scrollTo(model.items[idx].id, anchor: nil)
                    }
                }
            }
        }
    }

    @ViewBuilder private func contextMenu(for clip: Clip) -> some View {
        Button("Copy") { model.activate(clip) }
        Button(clip.pinned ? "Unpin" : "Pin") { model.togglePin(clip) }
        if clip.kind == .fileRef {
            Button("Reveal in Finder") { model.revealInFinder(clip) }
        }
        if clip.kind == .url {
            Button("Open Link") { model.openURL(clip) }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(clip) }
    }

    private var footer: some View {
        HStack {
            Text(model.status ?? model.footerText)
                .font(.caption)
                .foregroundStyle(model.status == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            Button { model.onOpenSettings?() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
