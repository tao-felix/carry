import SwiftUI

/// What was shared, an optional one-line note, one button.
struct ShareSheetView: View {
    @ObservedObject var model: ShareModel
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Send to my agent")
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: model.cancel) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.ink2)
                        .frame(width: 30, height: 30)
                        .background(Theme.paper2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }

            switch model.phase {
            case .loading:
                StatusLine("Reading what you shared…", color: Theme.ink2)
            case .failed(let why):
                StatusLine(why, color: Theme.warn)
                Button("Close", action: model.cancel).buttonStyle(SecondaryButtonStyle())
            case .ready, .sending, .sent:
                if let preview = model.preview { PreviewCard(preview: preview) }
                TextField("Add a note (optional)", text: $model.note)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .background(Theme.paper2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(noteFocused ? Theme.ink2 : Theme.line, lineWidth: 1))
                    .focused($noteFocused)
                    .submitLabel(.send)
                    .onSubmit(model.send)
                    .disabled(model.phase != .ready)
                Button(buttonTitle, action: model.send)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.phase != .ready)
                StatusLine(footer, color: model.phase == .sent ? Theme.ok : Theme.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.paper.ignoresSafeArea())
        .animation(.easeOut(duration: 0.15), value: model.phase)
    }

    private var buttonTitle: String {
        switch model.phase {
        case .sending: return "Sending…"
        case .sent: return "Sent"
        default: return "Send to my agent"
        }
    }

    private var footer: String {
        model.phase == .sent
            ? "Saved to \(Links.folderLabel) › inbox. Your Mac reads it on its next sync."
            : "Goes to \(Links.folderLabel) › inbox, then your Mac. No Carry server."
    }
}

struct PreviewCard: View {
    let preview: ShareModel.Preview

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.paper)
                        if let thumbnail = preview.thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFill()
                        } else {
                            Image(systemName: preview.icon).font(.title3).foregroundStyle(Theme.tangerine)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preview.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                        Text(preview.subtitle)
                            .font(.mono)
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if let excerpt = preview.excerpt {
                    Text(excerpt).font(.footnote).foregroundStyle(Theme.ink2).lineLimit(3)
                }
            }
        }
    }
}
