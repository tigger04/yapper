// ABOUTME: Static structural tests for Formula/yapper.rb and release scripts.
// ABOUTME: Covers OT-11.7, 11.8, 11.11, 11.12, 11.13–11.18 — see issue #11.
//
// Removed tests (IDs preserved per TESTING.md §"Never renumber"):
//   🚫 OT-11.2  — Formula referenced a tagged source release (now points at
//                 a binary tarball). Superseded by OT-11.14.
//   🚫 OT-11.4  — Formula declared Xcode/Metal deps. No longer applicable:
//                 prebuilt binary needs no Xcode. Superseded by OT-11.17.
//   🚫 OT-11.5  — Formula caveats mentioned Xcode/Metal. Superseded by
//                 prebuilt-binary caveat text.
//   🚫 OT-11.9  — Formula declared resource "model" + "voices" AND a xcodebuild
//                 install block. Split into OT-11.15 (model/voices only) and
//                 OT-11.16 (no build step).
//   🚫 OT-11.10 — Formula install block used xcodebuild. Replaced by OT-11.16.

import Testing
import Foundation

@Suite("Issue #11 Homebrew formula structure")
struct HomebrewFormulaTests {

    private static let projectRoot: URL = {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "/Users/tigger/code/tigoss/yapper")
    }()

    private static func read(_ relativePath: String) throws -> String {
        let url = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // OT-11.7: release.sh performs tag + version bump
    @Test("OT-11.7: release.sh bumps version and creates tag")
    func releaseScriptTagsAndBumps() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("git -C \"${PROJECT_ROOT}\" tag -a \"${TAG}\""),
                "release.sh must create an annotated git tag")
        #expect(script.contains("bump_version"),
                "release.sh must bump version")
        #expect(script.contains("Version.swift"),
                "release.sh must update Version.swift")
    }

    // OT-11.8: release.sh writes Formula and mirrors to tap
    @Test("OT-11.8: release.sh writes Formula and mirrors to tap")
    func releaseScriptUpdatesFormula() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("Formula/yapper.rb"),
                "release.sh must write Formula/yapper.rb")
        #expect(script.contains("tigger04/homebrew-tap"),
                "release.sh must push formula to the tap repo")
    }

    // OT-11.11: release-models.sh filters English voices and uploads
    @Test("OT-11.11: release-models.sh filters English voices and uploads to models-v1")
    func releaseModelsScriptStructure() throws {
        let script = try Self.read("scripts/release-models.sh")
        #expect(script.contains("models-v1"))
        #expect(script.contains("a[fm]_*.safetensors"))
        #expect(script.contains("b[fm]_*.safetensors"))
        #expect(script.contains("voices.tar.gz"))
        #expect(script.contains("kokoro-v1_0.safetensors"))
        #expect(script.contains("gh release"))
    }

    // OT-11.12: Makefile wiring
    @Test("OT-11.12: Makefile exposes release and release-models targets")
    func makefileExposesReleaseTargets() throws {
        let makefile = try Self.read("Makefile")
        #expect(makefile.contains("release-models:"))
        #expect(makefile.contains("release:"))
        #expect(makefile.contains("scripts/release-models.sh"))
        #expect(makefile.contains("scripts/release.sh"))
    }

    // OT-11.13: release.sh builds, signs, tars, and uploads the binary
    @Test("OT-11.13: release.sh builds, signs, tars, and uploads the binary")
    func releaseScriptBuildsAndPackagesBinary() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("xcodebuild build"),
                "release.sh must build the release binary with xcodebuild")
        #expect(script.contains("codesign --force --sign -"),
                "release.sh must ad-hoc sign the binary")
        #expect(script.contains("tar -czf"),
                "release.sh must tar the binary + bundles")
        #expect(script.contains("gh release create"),
                "release.sh must create the GH release")
        #expect(script.contains("yapper-macos-arm64.tar.gz"),
                "release.sh must name the asset yapper-macos-arm64.tar.gz")
    }

    // OT-11.14: Formula main url targets the code release tag's binary asset
    @Test("OT-11.14: Formula url targets the code release binary asset")
    func formulaUrlTargetsBinaryAsset() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("yapper-macos-arm64.tar.gz"),
                "Formula url must reference the binary tarball asset")
        #expect(formula.range(of: #"releases/download/v\d+\.\d+\.\d+/yapper-macos-arm64\.tar\.gz"#,
                              options: .regularExpression) != nil,
                "Formula url must use a tagged code release (vX.Y.Z), not HEAD")
    }

    // OT-11.15: Formula declares model and voices resources
    @Test("OT-11.15: Formula declares model and voices resources")
    func formulaDeclaresResources() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("resource \"model\""))
        #expect(formula.contains("resource \"voices\""))
        #expect(formula.contains("kokoro-v1_0.safetensors"))
        #expect(formula.contains("voices.tar.gz"))
        #expect(formula.contains("models-v1"))
    }

    // OT-11.16: Formula install block has no build step
    @Test("OT-11.16: Formula install block has no xcodebuild or swift build")
    func formulaInstallBlockHasNoBuildStep() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(!formula.contains("xcodebuild"),
                "Formula must not invoke xcodebuild")
        #expect(!formula.contains("\"swift\""),
                "Formula must not invoke swift build/package resolve")
        #expect(formula.contains("libexec.install \"yapper\""),
                "Formula must install the prebuilt binary into libexec")
        #expect(formula.contains("libexec.install Dir[\"*.bundle\"]"),
                "Formula must install resource bundles alongside the binary")
    }

    // OT-11.17: Formula declares runtime dependency on ffmpeg only
    @Test("OT-11.17: Formula declares ffmpeg runtime dep and no Xcode dep")
    func formulaDeclaresRuntimeDepsOnly() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("depends_on \"ffmpeg\""))
        #expect(formula.contains("depends_on :macos"))
        #expect(formula.contains("depends_on arch: :arm64"))
        #expect(!formula.contains("depends_on :xcode"),
                "Prebuilt binary formula must not require Xcode")
    }

    // OT-11.18: release.sh runs codesign with hardened runtime before packaging
    @Test("OT-11.18: release.sh codesigns binary with hardened runtime")
    func releaseScriptCodesignsWithHardenedRuntime() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("codesign --force --sign - --options runtime"),
                "release.sh must ad-hoc sign with hardened runtime")
        #expect(script.contains("codesign --verify"),
                "release.sh must verify the signature after signing")
    }
}
