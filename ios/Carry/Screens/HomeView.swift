import SwiftUI
import UIKit

/// Status from the newest heartbeat, what this phone captured, Sync now, and where it all goes.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var location: LocationRecorder

    var body: some View {
        Screen("Carry", subtitle: "Everything your phone knows, on your agent's desk.") {
            switch model.container {
            case .resolving:
                StatusLine("Finding your iCloud folder…", color: Theme.ink2)
            case .unavailable:
                ICloudOffCard()
            case .ready(let place):
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    MacStatusCard(heartbeat: model.heartbeat, now: context.date)
                }
                Titled("Captured by this phone") {
                    captured
                    syncBlock
                }
                Titled("Where it goes") {
                    ICloudCard(location: place)
                }
                Note("Apple only lets Carry read Health while the phone is unlocked, so background sync is roughly hourly, not live.")
            }
        }
    }

    private var captured: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Card(padding: 0) {
                VStack(spacing: 0) {
                    captureRow(.health, detail: healthDetail(now: context.date))
                    Hairline(inset: 14)
                    captureRow(.location, detail: locationDetail(now: context.date))
                    Hairline(inset: 14)
                    captureRow(.inbox, detail: inboxDetail(now: context.date))
                }
            }
        }
    }

    private func captureRow(_ id: SourceID, detail: (String, Color)) -> some View {
        Row(id.title, detail: detail.0, detailColor: detail.1) { ChannelBadge(.app) }
            .opacity(model.sources.isEnabled(id) ? 1 : 0.55)
    }

    private func last(_ id: SourceID, now: Date) -> String? {
        model.lastCapture[id].map { "last " + RelativeTime.string(since: $0, now: now) }
    }

    private func healthDetail(now: Date) -> (String, Color) {
        guard model.sources.isEnabled(.health) else { return ("off", Theme.ink2) }
        guard model.health.hasAsked else { return ("access not asked yet · see Sources", Theme.warn) }
        return (statusJoin(["\(plural(model.today.health, "sample")) today", last(.health, now: now) ?? "nothing written yet"]), Theme.ink2)
    }

    private func locationDetail(now: Date) -> (String, Color) {
        guard model.sources.isEnabled(.location) else { return ("off", Theme.ink2) }
        guard location.isAuthorized else { return ("location \(location.authorizationLabel) · see Sources", Theme.warn) }
        return (statusJoin(["\(plural(model.today.visits, "visit")), \(plural(model.today.points, "point")) today",
                            last(.location, now: now) ?? "waiting for the first visit"]), Theme.ink2)
    }

    private func inboxDetail(now: Date) -> (String, Color) {
        guard model.sources.isEnabled(.inbox) else { return ("off", Theme.ink2) }
        guard let last = last(.inbox, now: now) else { return ("nothing shared yet · use the share sheet", Theme.ink2) }
        return (statusJoin(["\(plural(model.today.inbox, "item")) today", last]), Theme.ink2)
    }

    private var syncBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(model.isSyncing ? "Syncing…" : "Sync now") { Task { await model.syncNow() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isSyncing)
            if let line = model.syncLine {
                StatusLine(line, color: model.syncFailed ? Theme.warn : Theme.ink)
            }
        }
    }
}

/// `Mac read 12 min ago · 40 photos · 2 notes · Pro`, or the honest "No Mac has read this yet".
struct MacStatusCard: View {
    let heartbeat: Heartbeat?
    let now: Date
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            if let heartbeat {
                VStack(alignment: .leading, spacing: 6) {
                    StatusLine(Self.line(heartbeat, now: now), color: Theme.ok)
                    Text(Self.detail(heartbeat))
                        .font(.monoSmall)
                        .foregroundStyle(Theme.ink2)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    StatusLine("No Mac has read this yet", color: Theme.warn)
                    Button { openURL(Links.macInstall) } label: {
                        StatusLine("Install the CLI on your Mac → \(Links.siteLabel)", color: Theme.ink2)
                    }
                    .buttonStyle(.plain)
                    CodeLine(Links.cliInstall)
                }
            }
        }
    }

    static func line(_ heartbeat: Heartbeat, now: Date) -> String {
        var parts = ["Mac read " + (heartbeat.lastSyncDate.map { RelativeTime.string(since: $0, now: now) } ?? "at an unknown time")]
        let nouns: [(String, String)] = [("photos", "photo"), ("notes", "note"), ("screenshots", "screenshot"),
                                         ("voice_memos", "voice memo"), ("inbox", "inbox item")]
        for (key, noun) in nouns where parts.count < 4 {
            if let n = heartbeat.counts?[key], n > 0 { parts.append(plural(n, noun)) }
        }
        if heartbeat.pro == true { parts.append("Pro") }
        return statusJoin(parts)
    }

    static func detail(_ heartbeat: Heartbeat) -> String {
        var parts = [heartbeat.host]
        if let version = heartbeat.carryVersion { parts.append("carry \(version)") }
        if let digest = heartbeat.lastDigestDate { parts.append("digest \(digest)") }
        return statusJoin(parts)
    }
}

/// Where the files are, and that iCloud is the only transport.
struct ICloudCard: View {
    let location: ContainerLocation

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    StatusLine(location.isICloud ? Links.folderLabel : "App sandbox › CarryContainer", color: Theme.ink)
                    Spacer()
                    Text(location.isICloud ? "syncing" : "simulator")
                        .font(.monoSmall)
                        .foregroundStyle(location.isICloud ? Theme.ok : Theme.warn)
                }
                Text(location.isICloud
                     ? "Your iCloud carries this folder to your Mac, where carry reads it. Nothing else sees it."
                     : "iCloud is not available in this build, so files stay in the app sandbox and nothing syncs.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("On the Mac: \(Links.macContainerPath)")
                    .font(.monoSmall)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Release builds without a ubiquity container: say so plainly and show the fix.
struct ICloudOffCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                StatusLine("iCloud Drive is off for Carry", color: Theme.warn)
                Text("Carry has nowhere to write. Turn it on, then come back:")
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                Text("Settings › your name › iCloud › iCloud Drive › Carry")
                    .font(.mono)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
