class Yapper < Formula
  desc "Fast, Apple Silicon-native text-to-speech CLI and Swift library"
  homepage "https://github.com/tigger04/yapper"
  url "https://github.com/tigger04/yapper/archive/refs/tags/v0.7.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "Apache-2.0"

  depends_on :macos
  depends_on arch: :arm64
  depends_on "ffmpeg"

  resource "model" do
    url "https://github.com/tigger04/yapper/releases/download/models-v1/kokoro-v1_0.safetensors"
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  end

  resource "voices" do
    url "https://github.com/tigger04/yapper/releases/download/models-v1/voices.tar.gz"
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  end

  def install
    system "xcodebuild", "build",
           "-scheme", "yapper",
           "-destination", "platform=OS X",
           "-configuration", "Release",
           "-derivedDataPath", buildpath/".xcode"

    built = Dir["#{buildpath}/.xcode/Build/Products/Release/yapper"].first
    odie "yapper binary not found after build" unless built
    bin.install built

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
      Yapper builds from source and requires:
        - Xcode command-line tools (for xcodebuild)
        - The Metal Toolchain component of Xcode (for MLX shader compilation)

      Model weights and English voices are downloaded automatically at install time
      from the tigger04/yapper models-v1 release (Apache 2.0, redistributed from
      hexgrad/Kokoro-82M). They live in:
        #{share}/yapper/models
        #{share}/yapper/voices

      Try it:
        yapper speak "Hello, world"
        yapper voices
    EOS
  end

  test do
    assert_match "0.7.0", shell_output("#{bin}/yapper --version")
  end
end
