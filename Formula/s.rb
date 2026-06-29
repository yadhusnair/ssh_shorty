# This file is auto-updated by .github/workflows/release.yml on each tagged release.
# The live formula lives at: https://github.com/yadhusnair/homebrew-ssh_shorty

class S < Formula
  desc "Fleet SSH management CLI — connect, broadcast, and monitor remote devices by nickname"
  homepage "https://github.com/yadhusnair/ssh_shorty"
  url "https://github.com/yadhusnair/ssh_shorty/archive/refs/tags/v20260637.tar.gz"
  sha256 "" # filled in by release workflow
  license "MIT"
  version "20260637"

  def install
    bin.install "s"
    bash_completion.install "completion.bash" => "s"
    zsh_completion.install "completion.zsh" => "_s"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/s --help")
  end
end
