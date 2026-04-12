# Homebrew formula for Mac Doctor
# To use: brew tap mahii6991/tap && brew install mac-doctor
#
# To publish, create a repo named "homebrew-tap" under your GitHub account
# and place this file at Formula/mac-doctor.rb in that repo.

class MacDoctor < Formula
  desc "Single-command macOS performance diagnostics — find exactly why your Mac is slow"
  homepage "https://github.com/mahii6991/mac-doctor"
  url "https://github.com/mahii6991/mac-doctor/archive/refs/tags/v2.1.0.tar.gz"
  # sha256 "UPDATE_THIS_AFTER_TAGGING_RELEASE"
  license "MIT"
  version "2.1.0"

  # No dependencies — mac-doctor uses only built-in macOS tools

  def install
    bin.install "mac-doctor.sh" => "mac-doctor"

    # Install LaunchAgent support files
    (share/"mac-doctor").install "packaging/launchd/mac-doctor-notify.sh"
    chmod 0755, share/"mac-doctor/mac-doctor-notify.sh"
  end

  def caveats
    <<~EOS
      Mac Doctor is installed. Run it with:
        mac-doctor              # standard scan
        mac-doctor --fix        # scan + fix issues interactively
        mac-doctor --html       # save HTML report to Desktop

      Optional: set up a weekly scan with macOS notifications:
        brew services start mac-doctor
    EOS
  end

  service do
    run [opt_share/"mac-doctor/mac-doctor-notify.sh"]
    run_type :cron
    cron "0 10 * * 0"
    log_path var/"log/mac-doctor.log"
    error_log_path var/"log/mac-doctor.log"
  end

  test do
    assert_match "Mac Doctor", shell_output("#{bin}/mac-doctor --help")
  end
end
