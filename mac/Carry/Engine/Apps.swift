import Foundation

/// Friendly names for bundle identifiers seen in Screen Time and in share-sheet items (apps.py).
/// Kept identical to the CLI so both write the same digest line; no NSWorkspace lookup on purpose.
enum Apps {
    static let friendly: [String: String] = [
        "com.anthropic.claudefordesktop": "Claude", "com.anthropic.claude": "Claude", "com.tencent.xinWeChat": "WeChat",
        "com.tencent.xin": "WeChat", "md.obsidian": "Obsidian", "com.google.Chrome": "Chrome", "com.google.chrome.ios": "Chrome",
        "com.apple.Safari": "Safari", "com.apple.mobilesafari": "Safari", "com.apple.mail": "Mail", "com.apple.mobilemail": "Mail",
        "com.apple.Notes": "Notes", "com.apple.mobilenotes": "Notes", "com.microsoft.VSCode": "VS Code",
        "com.todesktop.230313mzl4w4u92": "Cursor", "com.apple.Terminal": "Terminal", "com.googlecode.iterm2": "iTerm",
        "com.tinyspeck.slackmacgap": "Slack", "com.tinyspeck.chatlyio": "Slack", "com.apple.MobileSMS": "Messages",
        "com.apple.finder": "Finder", "com.apple.iCal": "Calendar", "com.apple.mobilecal": "Calendar", "us.zoom.xos": "Zoom",
        "com.figma.Desktop": "Figma", "com.apple.Music": "Music", "com.spotify.client": "Spotify", "com.apple.Photos": "Photos",
        "com.apple.mobileslideshow": "Photos", "com.apple.dt.Xcode": "Xcode", "com.electron.lark": "Lark",
        "com.bytedance.macos.feishu": "Feishu", "com.larksuite.ios": "Lark", "com.bytedance.ios.feishu": "Feishu", "notion.id": "Notion",
        "com.linear": "Linear", "com.atebits.Tweetie2": "X", "com.xingin.discover": "Xiaohongshu", "com.burbn.instagram": "Instagram",
        "ph.telegra.Telegraph": "Telegram", "net.whatsapp.WhatsApp": "WhatsApp", "com.zhiliaoapp.musically": "TikTok",
        "com.ss.iphone.ugc.Aweme": "Douyin", "com.linkedin.LinkedIn": "LinkedIn", "com.apple.reminders": "Reminders",
        "com.apple.VoiceMemos": "Voice Memos", "com.openai.chat": "ChatGPT", "com.readdle.smartemail": "Spark",
        "com.apple.mobilephone": "Phone", "com.zhihu.ios": "Zhihu", "com.alibaba.DingTalkMac": "DingTalk",
    ]

    /// `app_name(bundle)`
    static func name(_ bundle: String?) -> String {
        guard let bundle, !bundle.isEmpty else { return "" }
        if let known = friendly[bundle] { return known }
        let tail = bundle.split(separator: ".", omittingEmptySubsequences: false).last.map(String.init) ?? bundle
        guard let first = tail.unicodeScalars.first else { return bundle }
        return String(first).uppercased() + Py.dropFirst(tail, 1)
    }
}
