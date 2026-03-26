# This formula belongs in a Homebrew tap repository, not in the CodexBar repo itself.
#
# Setup instructions:
#   1. Create a GitHub repo named "homebrew-codexbar" under your account (rubenfb23).
#   2. Copy this file to: Formula/codexbar-linux.rb inside that repo.
#   3. Update `version`, `sha256` fields after each release.
#
# Users install with:
#   brew tap rubenfb23/codexbar
#   brew install codexbar-linux
#
# After a new GitHub release is published on rubenfb23/CodexBar:
#   1. Download the .sha256 sidecar files from the release assets.
#   2. Update the `sha256` values below.
#   3. Bump `version` to match the release tag (strip the "linux-v" prefix).
#   4. Commit and push the updated formula to the tap repo.

class CodexbarLinux < Formula
  desc "AI coding usage tracker — GTK4 tray app for Linux"
  homepage "https://github.com/rubenfb23/CodexBar"
  license "MIT"
  version "0.1.0"

  on_linux do
    on_intel do
      url "https://github.com/rubenfb23/CodexBar/releases/download/linux-v#{version}/CodexBarLinux-linux-v#{version}-linux-x86_64.tar.gz"
      sha256 "REPLACE_WITH_SHA256_FROM_RELEASE_ASSET_sha256_SIDECAR"
    end

    on_arm do
      url "https://github.com/rubenfb23/CodexBar/releases/download/linux-v#{version}/CodexBarLinux-linux-v#{version}-linux-aarch64.tar.gz"
      sha256 "REPLACE_WITH_SHA256_FROM_RELEASE_ASSET_sha256_SIDECAR"
    end
  end

  # GTK4 runtime libraries that CodexBarLinux links against dynamically.
  depends_on "gtk4"
  depends_on "libadwaita"
  depends_on "libx11"

  # patchelf is only needed during install to fix the binary RPATH.
  depends_on "patchelf" => :build

  # CodexBarLinux is a Linux-only GTK4 app.
  depends_on :linux

  def install
    # The pre-built binary was stripped of its RPATH at packaging time so it
    # can be relocated to any Homebrew prefix.  Re-apply it here pointing at
    # the Homebrew lib directory where gtk4 / libadwaita / libx11 are installed.
    system "patchelf", "--set-rpath", "#{HOMEBREW_PREFIX}/lib", "CodexBarLinux"

    bin.install "CodexBarCLI"
    bin.install "CodexBarLinux"

    # Convenience lowercase symlinks that match the install-script names.
    bin.install_symlink "CodexBarCLI" => "codexbar"
    bin.install_symlink "CodexBarLinux" => "codexbar-linux"
  end

  def caveats
    <<~EOS
      CodexBarLinux requires the AppIndicator GNOME Shell extension for the
      system tray icon:
        https://extensions.gnome.org/extension/615/appindicator-support/

      Launch the app:
        codexbar-linux

      Configure provider API tokens in the Preferences window (right-click the
      tray icon → Preferences → Providers), or edit directly:
        ~/.codexbar/config.json

      To fetch a GitHub OAuth token for the Copilot provider:
        gh auth token
    EOS
  end

  test do
    # CodexBarLinux requires a display, so only test the headless CLI.
    assert_match version.to_s, shell_output("#{bin}/CodexBarCLI --version 2>&1", 0)
  end
end
