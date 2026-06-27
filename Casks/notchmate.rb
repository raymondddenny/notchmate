cask "notchmate" do
  version "0.1.7"
  sha256 "a1abf653678e329c3dae49133849ddd8c62e1b5a78e9c144c6a495f3c9b5437a"

  url "https://github.com/raymondddenny/notchmate/releases/download/v#{version}/notchmate-#{version}.dmg",
      verified: "github.com/raymondddenny/notchmate/"
  name "notchmate"
  desc "Notch companion app for macOS (media, Claude sessions, timer, HUDs)"
  homepage "https://github.com/raymondddenny/notchmate"

  depends_on macos: :sonoma

  app "notchmate.app"

  # Ad-hoc signed: drop quarantine so Gatekeeper does not block launch.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/notchmate.app"]
  end

  zap trash: [
    "~/Library/Preferences/com.notchmate.app.plist",
    "~/.notchmate",
  ]
end
