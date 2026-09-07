import Foundation

/// Every link, command and path the app quotes. Edit here, nowhere else.
public enum Links {
    /// Public site.
    public static let site = URL(string: "https://carry-site.vercel.app")!
    /// The Mac CLI section of the site (install + `carry init`).
    public static let macInstall = URL(string: "https://carry-site.vercel.app/#top")!
    /// Source code, MIT.
    public static let source = URL(string: "https://github.com/tao-felix/carry")!
    public static let privacy = URL(string: "https://carry-site.vercel.app/#privacy")!
    public static let terms = URL(string: "https://carry-site.vercel.app/#pro")!
    public static let support = URL(string: "https://github.com/tao-felix/carry/issues")!
    /// Apple's subscription management page.
    public static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// Quoted commands and paths (keep in sync with `web/src/lib/links.ts`).
    public static let cliInstall = "uv tool install carry-context"
    public static let cliInit = "carry init"
    public static let contextDir = "~/.carry/context/"
    public static let macContainerPath = "~/Library/Mobile Documents/iCloud~app~carry~ios/Documents/"

    /// How the iCloud folder is named in the Files app.
    public static let folderLabel = "iCloud Drive › Carry"
    public static let siteLabel = "carry-site.vercel.app"
}
