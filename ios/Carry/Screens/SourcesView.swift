import SwiftUI
import UIKit

/// The control surface (DATA-CONTRACT §3). Every change is written to `sources.json`, debounced 1 s.
struct SourcesView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var location: LocationRecorder
    @State private var askHealth = false
    @State private var askLocation = false

    var body: some View {
        Screen("Sources",
               subtitle: "What your Mac reads. Switch one off and the Mac reader skips it.") {
            Titled("Already on your Mac via iCloud",
                   note: "These already sync to your Mac. This switch tells the Mac reader whether to read them.") {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(SourceID.icloudSources.enumerated()), id: \.element) { index, id in
                            if index > 0 { Hairline(inset: 14) }
                            SourceRow(id: id, enabled: model.sources.isEnabled(id)) { model.setSource(id, enabled: $0) }
                        }
                    }
                }
            }

            Titled("Only Carry can capture") {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        SourceRow(id: .health, enabled: model.sources.isEnabled(.health)) { on in
                            if on, !model.health.hasAsked { askHealth = true } else { model.setSource(.health, enabled: on) }
                        }
                        if model.sources.isEnabled(.health) { healthTypes }
                        Hairline(inset: 14)
                        SourceRow(id: .location, enabled: model.sources.isEnabled(.location)) { on in
                            if on, !location.hasAsked { askLocation = true } else { model.setSource(.location, enabled: on) }
                        }
                        if model.sources.isEnabled(.location) { locationStatus }
                        Hairline(inset: 14)
                        SourceRow(id: .inbox, enabled: model.sources.isEnabled(.inbox)) { model.setSource(.inbox, enabled: $0) }
                    }
                }
            }

            Titled("Processing", note: "Takes effect with Pro, on your Mac. Nothing is processed on the phone.") {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ToggleRow("Read text in images", detail: "OCR on screenshots and photos",
                                  isOn: model.sources.processing.ocr) { model.setProcessing(ocr: $0) }
                        Hairline(inset: 14)
                        ToggleRow("Transcribe audio", detail: "Voice memos and shared audio become text",
                                  isOn: model.sources.processing.transcribe) { model.setProcessing(transcribe: $0) }
                    }
                }
            }

            TimelineView(.periodic(from: .now, by: 30)) { context in
                StatusLine(model.sourcesSaveLine(now: context.date), color: Theme.ink2)
            }
        }
        .alert("Allow Health access", isPresented: $askHealth) {
            Button("Continue") { Task { await model.requestHealthAccess() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("iOS will ask which Health types Carry may read. They go to your iCloud Drive and then your Mac; there is no Carry server.")
        }
        .alert("Allow location access", isPresented: $askLocation) {
            Button("Continue") { model.requestLocationAccess() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("iOS will ask for your location. Choose “Always” so Carry can record visits while the app is closed.")
        }
    }

    private var healthTypes: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(HealthType.allCases) { type in
                    let on = model.sources.healthTypes.contains(type)
                    Chip(type.title, isOn: on, color: Theme.tangerine) { model.setHealthType(type, enabled: !on) }
                }
            }
            if model.health.hasAsked {
                StatusLine("Access asked · reads only while the phone is unlocked", color: Theme.ink2)
            } else {
                Button { askHealth = true } label: {
                    StatusLine("Health access not asked yet · tap to allow", color: Theme.warn)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var locationStatus: some View {
        Group {
            if location.authorization == .denied || location.authorization == .restricted {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    StatusLine("Location \(location.authorizationLabel)", color: Theme.warn)
                }
                .buttonStyle(.plain)
            } else if location.needsAttention {
                Button { model.requestLocationAccess() } label: {
                    StatusLine("Location \(location.authorizationLabel) · tap to allow Always", color: Theme.warn)
                }
                .buttonStyle(.plain)
            } else {
                StatusLine("Location: Always · visits, and one point per 10 min", color: Theme.ink2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}

/// Source card row: name, what is read, channel badge, toggle. Off rows fade to 55%, never disappear.
struct SourceRow: View {
    let id: SourceID
    let enabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(id.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                    ChannelBadge(id.channel)
                }
                Text(id.reads)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(id.title, isOn: Binding(get: { enabled }, set: onToggle))
                .labelsHidden()
                .tint(Theme.color(for: id.channel))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(enabled ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: enabled)
    }
}

struct ToggleRow: View {
    let title: String
    let detail: String
    let isOn: Bool
    let onToggle: (Bool) -> Void

    init(_ title: String, detail: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        self.title = title
        self.detail = detail
        self.isOn = isOn
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: Binding(get: { isOn }, set: onToggle))
                .labelsHidden()
                .tint(Theme.tangerine)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(isOn ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
