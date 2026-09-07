import SwiftUI

/// Exactly one plan. Price from StoreKit 2; what stays free right next to it.
struct ProView: View {
    @ObservedObject var pro: ProStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        Screen("Pro") {
            Text("Pro turns pictures and audio into text your agent can read.")
                .font(.lede)
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Carry Pro").font(.sectionHead).foregroundStyle(Theme.ink)
                        Spacer()
                        StatusLine(pro.priceLine ?? "price from the App Store",
                                   color: pro.priceLine == nil ? Theme.ink2 : Theme.ink)
                    }
                    Hairline()
                    CheckLine("Text in screenshots and photos")
                    CheckLine("Words in voice memos and shared audio")
                    Text("Runs on your Mac. Nothing leaves it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                }
            }

            if pro.isSubscribed { subscribed } else { subscribe }

            if let message = pro.message {
                StatusLine(message, color: pro.messageIsError ? Theme.warn : Theme.ok)
            }
            if case .unavailable(let why) = pro.availability {
                StatusLine(why, color: Theme.warn)
            }

            Titled("What stays free") {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        CheckLine("Every source and every switch", color: Theme.ink2)
                        CheckLine("Health, Location and the share-sheet inbox", color: Theme.ink2)
                        CheckLine("The daily digest, search and MCP on your Mac", color: Theme.ink2)
                        CheckLine("The code, MIT", color: Theme.ink2)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Auto-renews monthly until cancelled in Settings › Apple Account › Subscriptions.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("Terms") { openURL(Links.terms) }
                    Button("Privacy") { openURL(Links.privacy) }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.ink2)
                .buttonStyle(.plain)
            }
        }
    }

    private var subscribe: some View {
        VStack(spacing: 4) {
            Button(pro.priceLine.map { "Subscribe · \($0)" } ?? "Subscribe") { Task { await pro.purchase() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(pro.busy || (pro.product == nil && !pro.isDemo))
            Button("Restore purchases") { Task { await pro.restore() } }
                .buttonStyle(QuietButtonStyle())
                .disabled(pro.busy)
        }
    }

    private var subscribed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    StatusLine(renewLine, color: Theme.ok)
                    if let at = pro.licenseWrittenAt {
                        StatusLine("license.json written \(TimeText.time(at)) · your Mac verifies it offline",
                                   color: Theme.ink2)
                    }
                }
            }
            Button("Manage subscription") { openURL(Links.manageSubscriptions) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var renewLine: String {
        guard let expiry = pro.expiresAt else { return "Pro is on" }
        return "Pro is on · \(pro.willRenew ? "renews" : "ends") \(TimeText.day(expiry))"
    }
}
