import SwiftUI
import UIKit

/// Version, the folder, links, and the one destructive action.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false

    var body: some View {
        Screen("Settings") {
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Row("Carry for iPhone", detail: "\(DeviceInfo.appVersion) (\(DeviceInfo.build)) · data contract schema 1")
                    Hairline(inset: 14)
                    Text("No Carry server. Your iCloud carries it. Your Mac reads it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                        .padding(14)
                }
            }

            Titled("Folder") {
                Card(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        LinkRow("Open the Carry folder", detail: folderDetail) { openFolder() }
                            .disabled(!(model.containerLocation?.isICloud ?? false))
                            .opacity((model.containerLocation?.isICloud ?? false) ? 1 : 0.55)
                        Hairline(inset: 14)
                        Text("On your Mac: \(Links.macContainerPath)")
                            .font(.monoSmall)
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                    }
                }
            }

            Titled("Links") {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        LinkRow(Links.siteLabel) { openURL(Links.site) }
                        Hairline(inset: 14)
                        LinkRow("Install the Mac CLI", detail: Links.cliInstall) { openURL(Links.macInstall) }
                        Hairline(inset: 14)
                        LinkRow("Source code · MIT") { openURL(Links.source) }
                        Hairline(inset: 14)
                        LinkRow("Privacy") { openURL(Links.privacy) }
                        Hairline(inset: 14)
                        LinkRow("Support", detail: Links.support.absoluteString.replacingOccurrences(of: "mailto:", with: "")) {
                            openURL(Links.support)
                        }
                    }
                }
            }

            Titled("Data") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Delete everything Carry wrote") { confirmDelete = true }
                        .buttonStyle(SecondaryButtonStyle(tint: Theme.tangerine))
                        .disabled(model.store == nil)
                    if let at = model.deletedAt {
                        StatusLine("Deleted · \(TimeText.time(at))", color: Theme.ink2)
                    }
                    Text("Removes the health, location, inbox and license files from \(Links.folderLabel). Your switches stay. Your Mac's own store is untouched.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .confirmationDialog("Delete everything Carry wrote?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete files", role: .destructive) { Task { await model.deleteEverything() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every file in \(Links.folderLabel) goes away on this phone and, once iCloud syncs, on your Mac. This cannot be undone.")
        }
    }

    private var folderDetail: String {
        guard let location = model.containerLocation else { return "not available" }
        return location.isICloud ? "\(Links.folderLabel) · Files app" : "simulator · no iCloud in this build"
    }

    /// The Files app opens `shareddocuments://<path>` for a public ubiquity container.
    private func openFolder() {
        guard let location = model.containerLocation, location.isICloud,
              let path = location.documents.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "shareddocuments://" + path) else { return }
        UIApplication.shared.open(url)
    }
}
