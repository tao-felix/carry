import SwiftUI

/// Header, Full Disk Access, iPhone, Sources, Pro, footer. Paper background, serif section titles.
struct MainView: View {
    let model: AppModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderView(model: model)
                EngineCard(model: model)
                Titled("Full Disk Access") { FDACard(model: model) }
                Titled("iPhone") { PhoneCard(model: model) }
                Titled("Sources", note: sourcesNote) { SourcesCard(model: model) }
                Titled("Pro") { ProCard(model: model) }
                FooterView(model: model)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: MainWindowController.contentSize.width, height: MainWindowController.contentSize.height)
        .background(Theme.paper)
    }

    private var sourcesNote: String {
        if model.decidedOnPhone {
            return "Decided on the phone. The Carry iPhone app's sources.json wins; change them there."
        }
        return "Switch a source off and this Mac stops reading it. Once the iPhone app is installed, its choices win."
    }
}

// MARK: - Header

struct HeaderView: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Carry").font(.screenTitle).foregroundStyle(Theme.ink)
                StatusLine(model.statusLine.text, color: model.statusLine.color)
                Text("Read: the sources switched on below. Goes to: \(CarryHome.display)/context/ on this Mac. "
                     + "Seen by: the agents you point at it. Nobody else. There is no Carry server.")
                    .font(.small)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Button("Sync now") { Task { await model.sync(reason: "manual") } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isSyncing || model.cliPath == nil)
                .padding(.top, 8)
        }
    }
}

// MARK: - Engine (only when carry is missing or too old)

struct EngineCard: View {
    let model: AppModel

    var body: some View {
        switch model.engine {
        case .ready:
            EmptyView()
        case .missing:
            Titled("Install the engine") {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Carry for Mac drives the carry command line, and it is not installed yet.")
                            .font(.bodyText).foregroundStyle(Theme.ink)
                        CodeLine(CarryCLI.installCommand)
                        Text("Then run carry init once in a terminal. This window looks again every 5 seconds.")
                            .font(.small).foregroundStyle(Theme.ink2)
                        LinkText("Install notes on \(Links.siteLabel)", url: Links.site)
                    }
                }
            }
        case .outdated(let version):
            Titled("Update the engine") {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("carry \(version) is older than this app.").font(.bodyText).foregroundStyle(Theme.ink)
                        CodeLine(CarryCLI.upgradeCommand)
                    }
                }
            }
        case .failed(let message):
            Titled("The engine did not answer") {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusLine("carry status --json: \(message)", color: Theme.warn)
                        Text("Details in \(CarryHome.display)/logs/app.log.").font(.small).foregroundStyle(Theme.ink2)
                    }
                }
            }
        }
    }
}

// MARK: - Full Disk Access

struct FDACard: View {
    let model: AppModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if model.fdaGrantedForDisplay {
                    CheckLine("Granted · Carry reads \(FullDiskAccess.covers)")
                    Text("Every sync this app starts inherits it. Nothing to add to the list, no interpreter path.")
                        .font(.small).foregroundStyle(Theme.ink2)
                    if let blocked = model.status?.blocked, !blocked.isEmpty {
                        Note("The last sync ran outside this app and could not read \(blocked.joined(separator: ", ")). "
                             + "The next one from here will.")
                    }
                } else {
                    Text("Messages, Notes, Voice Memos, Calendar, Reminders, Safari and Screen Time sit in databases "
                         + "macOS keeps behind one switch. Carry reads them there; it never writes to them.")
                        .font(.bodyText).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Grant in System Settings") { model.grantFDA() }
                            .buttonStyle(PrimaryButtonStyle())
                        if model.fdaWaiting {
                            StatusLine("Waiting… Privacy & Security → Full Disk Access → Carry", color: Theme.warn)
                            Button("Stop") { model.stopWaitingForFDA() }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    Text("One switch, once. macOS doesn't let any app flip it for you.")
                        .font(.small).foregroundStyle(Theme.ink2)
                    Note("Without it: Photos, Screenshots, and everything from your iPhone still work.", color: Theme.ok)
                    if let blocked = model.status?.blocked, !blocked.isEmpty {
                        Note("The last sync could not read \(blocked.joined(separator: ", ")).")
                    }
                }
            }
        }
    }
}

// MARK: - iPhone

struct PhoneCard: View {
    let model: AppModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                if let phone = model.phoneForDisplay {
                    Text(phone.name ?? "iPhone").font(.bodyMedium).foregroundStyle(Theme.ink)
                    StatusLine(statusJoin(phoneParts(phone)), color: Theme.ink2)
                } else {
                    Text("No iPhone yet.").font(.bodyMedium).foregroundStyle(Theme.ink)
                    Text("Health, Location and the Share inbox reach this Mac only through the Carry iPhone app, "
                         + "by way of your iCloud Drive (folder Carry).")
                        .font(.small).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    LinkText("Get the iPhone app", url: Links.iosApp).padding(.top, 2)
                }
                if let heartbeat = model.heartbeatForDisplay {
                    StatusLine(heartbeatLine(heartbeat), color: Theme.ink2).padding(.top, 2)
                }
            }
        }
    }

    private func phoneParts(_ phone: PhoneInfo) -> [String] {
        var parts: [String] = []
        if let os = phone.os, !os.isEmpty { parts.append(os) }
        if let version = phone.appVersion, !version.isEmpty { parts.append("Carry \(version)") }
        if let wrote = RFC3339.parse(phone.updatedAt) { parts.append("last wrote \(TimeText.short(wrote))") }
        return parts
    }

    private func heartbeatLine(_ heartbeat: Heartbeat) -> String {
        var line = "Your iPhone sees this Mac as: \(heartbeat.host)"
        if let read = RFC3339.parse(heartbeat.lastSyncAt) { line += " · Mac read at \(TimeText.short(read))" }
        return line
    }
}

// MARK: - Sources

struct SourcesCard: View {
    let model: AppModel

    var body: some View {
        Card(padding: 0) {
            let rows = model.sources
            if rows.isEmpty {
                Text(model.cliPath == nil ? "The twelve sources appear once carry is installed."
                                          : "Reading sources…")
                    .font(.small).foregroundStyle(Theme.ink2)
                    .padding(14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        SourceRowView(row: row, disabled: model.decidedOnPhone || model.cliPath == nil) { on in
                            model.setSource(row.name, enabled: on)
                        }
                        if index < rows.count - 1 { Hairline(inset: 14) }
                    }
                }
                if let note = model.sourceNote {
                    Hairline()
                    Note(note).padding(.horizontal, 14).padding(.vertical, 8)
                }
            }
        }
    }
}

struct SourceRowView: View {
    let row: SourceRow
    let disabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(row.label).font(.bodyMedium).foregroundStyle(Theme.ink)
                    ChannelBadge(row.channel)
                }
                if let error = row.error, !error.isEmpty {
                    Text(error).font(.small).foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(itemsText).font(.mono).foregroundStyle(Theme.ink2)
            Toggle("", isOn: Binding(get: { row.enabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(PillToggleStyle(color: Theme.color(for: row.channel)))
                .disabled(disabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .opacity(row.enabled ? 1 : 0.55)
    }

    private var itemsText: String {
        guard let items = row.items else { return "" }
        return row.enabled || items > 0 ? plural(items, "item") : ""
    }
}

// MARK: - Pro

struct ProCard: View {
    let model: AppModel

    var body: some View {
        let pro = model.status?.pro
        let active = pro?.active == true
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(active ? "Pro is on" : "Pro is off").font(.lede).foregroundStyle(Theme.ink)
                    if let reason = pro?.reason, !reason.isEmpty {
                        StatusLine(reason, color: Theme.ink2)
                    }
                }
                Text("Pro turns pictures and audio into text your agent can read.")
                    .font(.bodyText).foregroundStyle(Theme.ink)
                Text("Screenshot and photo OCR, voice memo and inbox transcription, all on this Mac. Everything else is free.")
                    .font(.small).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !active, let pending = model.status?.pendingTotal, pending > 0 {
                    Note("\(plural(pending, "picture or recording", "pictures and recordings")) waiting for Pro to become text.")
                }
                if !active {
                    HStack(spacing: 6) {
                        LinkText("Subscribe in the iPhone app", url: Links.pro)
                        Text("· the license reaches this Mac through your iCloud Drive.")
                            .font(.small).foregroundStyle(Theme.ink2)
                    }
                }
            }
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Hairline()
            HStack(spacing: 18) {
                Button("Open context folder") { model.openContextFolder() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Toggle(isOn: Binding(get: { model.runAtLogin }, set: { model.setRunAtLogin($0) })) {
                    Text("Run at login").font(.small).foregroundStyle(Theme.ink)
                }
                .toggleStyle(PillToggleStyle(color: Theme.moss))
                HStack(spacing: 5) {
                    Text("Sync every").font(.small).foregroundStyle(Theme.ink).padding(.trailing, 3)
                    ForEach(AppModel.scheduleChoices, id: \.self) { minutes in
                        Chip("\(minutes)", isOn: minutes == model.scheduleMinutes) { model.scheduleMinutes = minutes }
                    }
                    Text("min").font(.small).foregroundStyle(Theme.ink).padding(.leading, 3)
                }
            }
            if model.loginItemStatus == .requiresApproval {
                HStack(spacing: 8) {
                    Note("Run at login needs your approval in System Settings → General → Login Items.")
                    Button("Open") { model.openLoginItemsSettings() }.buttonStyle(QuietButtonStyle())
                }
            } else if let error = model.loginItemError {
                Note("Run at login: \(error)")
            }
            StatusLine("Runs carry sync every \(model.scheduleMinutes) min while awake, at launch and after wake.",
                       color: Theme.ink2)
            HStack(spacing: 16) {
                StatusLine(versionLine, color: Theme.ink2)
                Spacer()
                LinkText(Links.siteLabel, url: Links.site)
                LinkText("GitHub", url: Links.source)
            }
        }
    }

    private var versionLine: String {
        var parts = ["Carry \(AppModel.appVersion)"]
        if let cli = model.cliVersion { parts.append("carry \(cli)") }
        parts.append("\(CarryHome.display)/logs/app.log")
        return statusJoin(parts)
    }
}
