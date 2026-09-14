import ClipChumCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Callbacks the settings screen needs from the app.
struct SettingsActions {
    var clearHistory: () -> Void
    var storageSummary: () -> String
    var openStorageFolder: () -> Void
}

struct SettingsView: View {
    @Bindable var store: SettingsStore
    let actions: SettingsActions

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var accessibilityTrusted = PasteService.isAccessibilityTrusted(prompt: false)
    @State private var manualBundleID = ""
    @State private var confirmClear = false
    @State private var storageSummary = ""

    var body: some View {
        Form {
            historySection
            recordSection
            storageSection
            appsSection
            shortcutsSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 560)
        .onAppear { storageSummary = actions.storageSummary() }
        .alert("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) {
                actions.clearHistory()
                storageSummary = actions.storageSummary()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned clips are kept. Stored image and file copies that no clip references are deleted.")
        }
    }

    // MARK: - Sections

    private var historySection: some View {
        Section("History") {
            Stepper(value: $store.settings.showCount, in: 1...200) {
                LabeledContent("Show when opened", value: "last \(store.settings.showCount) clips")
            }
            Stepper(value: $store.settings.maxItems, in: 10...100_000, step: stepFor(store.settings.maxItems)) {
                LabeledContent("Keep at most", value: "\(store.settings.maxItems) clips")
            }
            Text("Search always covers every kept clip. Pinned clips never count toward the limit.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var recordSection: some View {
        Section("Record these kinds") {
            ForEach(ClipKind.allCases, id: \.self) { kind in
                Toggle(isOn: kindBinding(kind)) {
                    Label(kind.displayName, systemImage: kind.symbolName)
                }
            }
            Text("Clips marked as concealed or transient by password managers are always ignored.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var storageSection: some View {
        Section("Storage") {
            Toggle("Keep full image data", isOn: $store.settings.storeImageData)
            if store.settings.storeImageData {
                Stepper(value: $store.settings.imageCapMB, in: 1...500, step: 5) {
                    LabeledContent("Skip images larger than", value: "\(store.settings.imageCapMB) MB")
                }
            }
            Toggle("Copy file contents into ClipChum (dereference)", isOn: $store.settings.dereferenceFiles)
            if store.settings.dereferenceFiles {
                Stepper(value: $store.settings.fileCapMB, in: 1...2000, step: 10) {
                    LabeledContent("Skip files larger than", value: "\(store.settings.fileCapMB) MB")
                }
            }
            Text("Files are always kept as references (path plus a bookmark that follows renames and moves). Dereferencing additionally stores a copy so the clip works after the original is deleted. Single regular files only.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("On disk", value: storageSummary)
            HStack {
                Button("Open Storage Folder") { actions.openStorageFolder() }
                Button("Clear History…", role: .destructive) { confirmClear = true }
            }
        }
    }

    private var appsSection: some View {
        Section("Ignore copies from these apps") {
            if store.settings.excludedApps.isEmpty {
                Text("No apps excluded.").foregroundStyle(.secondary)
            }
            ForEach(store.settings.excludedApps, id: \.self) { id in
                HStack {
                    if let icon = AppInfo.icon(for: id) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(AppInfo.name(for: id))
                    Text(id).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.settings.excludedApps.removeAll { $0 == id }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Menu("Add Running App") {
                    ForEach(AppInfo.runningApps(), id: \.bundleID) { app in
                        Button(app.name) { addExcluded(app.bundleID) }
                    }
                }
                .fixedSize()
                TextField("or bundle identifier, e.g. com.apple.Terminal", text: $manualBundleID)
                    .onSubmit { addExcluded(manualBundleID); manualBundleID = "" }
                Button("Add") { addExcluded(manualBundleID); manualBundleID = "" }
                    .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var shortcutsSection: some View {
        Section("Shortcut and pasting") {
            KeyboardShortcuts.Recorder("Open ClipChum", name: .togglePanel)
            Toggle("Paste into the active app after choosing a clip", isOn: $store.settings.pasteDirectly)
            HStack {
                Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(accessibilityTrusted ? .green : .orange)
                Text(accessibilityTrusted
                     ? "Accessibility access granted."
                     : "Pasting directly needs Accessibility access. Without it, choosing a clip only copies it.")
                    .font(.caption)
                Spacer()
                if !accessibilityTrusted {
                    Button("Grant…") {
                        _ = PasteService.isAccessibilityTrusted(prompt: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            accessibilityTrusted = PasteService.isAccessibilityTrusted(prompt: false)
                        }
                    }
                }
            }
            Stepper(value: $store.settings.pollInterval, in: 0.1...2, step: 0.1) {
                LabeledContent("Check clipboard every", value: String(format: "%.1f s", store.settings.pollInterval))
            }
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
        }
    }

    // MARK: - Helpers

    private func kindBinding(_ kind: ClipKind) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledKinds.contains(kind) },
            set: { on in
                if on { store.settings.enabledKinds.insert(kind) } else { store.settings.enabledKinds.remove(kind) }
            }
        )
    }

    private func stepFor(_ value: Int) -> Int {
        value >= 1000 ? 500 : (value >= 200 ? 100 : 10)
    }

    private func addExcluded(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !store.settings.excludedApps.contains(trimmed) else { return }
        store.settings.excludedApps.append(trimmed)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
            if SMAppService.mainApp.status == .requiresApproval {
                loginError = "Approve ClipChum under System Settings → General → Login Items."
            }
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
