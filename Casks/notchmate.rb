cask "notchmate" do
  version "0.1.3"
  sha256 "1a393bfb27ed1c31cd47dddda852b1dcbb653f2498f3c6300aa1f6c60d8e56aa"

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
