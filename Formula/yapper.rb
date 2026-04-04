class Yapper < Formula
  desc "Fast, Apple Silicon-native text-to-speech CLI and Swift library"
  homepage "https://github.com/tigger04/yapper"
  url "https://github.com/tigger04/yapper/releases/download/v0.8.1/yapper-macos-arm64.tar.gz"
  sha256 "ae97ebd0fac75dd28fd2b14e6c97182c76a047fb3ad506df00fd7c5de76df827"
  license "Apache-2.0"
  version "0.8.1"

  depends_on :macos
  depends_on arch: :arm64
  depends_on "ffmpeg"

  resource "model" do
    url "https://github.com/tigger04/yapper/releases/download/models-v1/kokoro-v1_0.safetensors"
    sha256 "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8"
  end

  resource "voices" do
    url "https://github.com/tigger04/yapper/releases/download/models-v1/voices.tar.gz"
    sha256 "bf273cf082639010bc5e94a5ff19f62c69aa4ded7a0651dc8a3c6d19e855b459"
  end

  def install
    # Prebuilt ad-hoc signed binary and its Swift resource bundles go into libexec;
    # a thin wrapper script in bin/ execs the real binary so Bundle.main lookups
    # resolve relative to libexec (where the .bundle directories live).
    libexec.install "yapper"
    libexec.install Dir["*.bundle"]

    (bin/"yapper").write <<~SH
      #!/bin/bash
      exec "#{libexec}/yapper" "$@"
    SH
    (bin/"yapper").chmod 0755

    (share/"yapper/models").mkpath
    (share/"yapper/voices").mkpath

    resource("model").stage do
      (share/"yapper/models").install "kokoro-v1_0.safetensors"
    end

    resource("voices").stage do
      (share/"yapper/voices").install Dir["*.safetensors"]
    end
  end

  def caveats
    <<~EOS
      Yapper ships as a prebuilt Apple Silicon binary, Developer ID signed
      with hardened runtime and notarised by Apple.

      Model weights and English voices are downloaded automatically at install
      time from the tigger04/yapper models-v1 release (Apache 2.0, redistributed
      from hexgrad/Kokoro-82M). They live in:
        #{share}/yapper/models
        #{share}/yapper/voices

      Try it:
        yapper speak "Hello, world"
        yapper voices
    EOS
  end

  test do
    assert_match "0.8.1", shell_output("#{bin}/yapper --version")
  end
end
