import SwiftUI

/// First screen: the tagline, the three-line privacy block, one button.
struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Carry")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 28)
                    Text("Everything your phone knows, on your agent's desk.")
                        .font(.system(size: 36, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    PrivacyBlock()
                    StatusLine("No Carry server. Your iCloud carries it. Your Mac reads it.", color: Theme.ink2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 0) {
                Hairline()
                Button("Choose what Carry covers", action: onContinue)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(20)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// Read / Goes to / Seen by. The same three lines as the site and `carry init`.
struct PrivacyBlock: View {
    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                row("Read", Text("the sources you switch on."))
                Hairline()
                row("Goes to", Text("your iCloud Drive (folder ") + Text("Carry").font(.mono) + Text("), then your Mac."))
                Hairline()
                row("Seen by", Text("the agents you point at ") + Text(Links.contextDir).font(.mono)
                    + Text(". Nobody else. There is no Carry server."))
            }
        }
    }

    private func row(_ key: String, _ value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Theme.ink)
                .frame(width: 84, alignment: .leading)
            value
                .font(.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
