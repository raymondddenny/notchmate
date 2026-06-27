cask "notchmate" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # placeholder; CI overwrites on first release

  url "https://github.com/raymondddenny/notchmate/releases/download/v#{version}/notchmate-#{version}.dmg",
      verified: "github.com/raymondddenny/notchmate/"
  name "notchmate"
  desc "Notch companion app for macOS (media, Claude sessions, timer, HUDs)"
  homepage "https://github.com/raymondddenny/notchmate"

  depends_on macos: ">= :sonoma"

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
