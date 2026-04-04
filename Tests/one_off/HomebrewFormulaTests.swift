// ABOUTME: Static structural tests for Formula/yapper.rb and release scripts.
// ABOUTME: Covers OT-11.2, OT-11.4, OT-11.5, OT-11.7, OT-11.8 — see issue #11.

import Testing
import Foundation

@Suite("Issue #11 Homebrew formula structure")
struct HomebrewFormulaTests {

    private static let projectRoot: URL = {
        // Tests run from the project root; use the current working directory
        // and walk up until we find Package.swift.
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        // Fall back to known location; test will fail loudly if wrong.
        return URL(fileURLWithPath: "/Users/tigger/code/tigoss/yapper")
    }()

    private static func read(_ relativePath: String) throws -> String {
        let url = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // OT-11.2: Formula references a specific git tag (not HEAD)
    @Test("OT-11.2: Formula URL points to a tagged release")
    func formulaReferencesTaggedRelease() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("/archive/refs/tags/v"),
                "Formula url must reference a tagged release (tags/vX.Y.Z)")
        #expect(!formula.contains("archive/refs/heads/"),
                "Formula must not reference a branch HEAD")
    }

    // OT-11.4: Formula declares ffmpeg runtime dependency
    @Test("OT-11.4: Formula declares ffmpeg dependency")
    func formulaDeclaresFfmpeg() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("depends_on \"ffmpeg\""))
        #expect(formula.contains("depends_on :macos"))
        #expect(formula.contains("depends_on arch: :arm64"))
    }

    // OT-11.5: Formula includes caveats explaining Xcode/Metal Toolchain + model download
    @Test("OT-11.5: Formula caveats mention Xcode, Metal Toolchain, model download")
    func formulaIncludesCaveats() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("def caveats"))
        #expect(formula.range(of: #"Xcode"#, options: .caseInsensitive) != nil)
        #expect(formula.range(of: #"Metal"#, options: .caseInsensitive) != nil)
        #expect(formula.range(of: #"model"#, options: .caseInsensitive) != nil)
    }

    // Structural check: formula declares model + voices resources
    @Test("OT-11.9: Formula declares model and voices resources")
    func formulaDeclaresResources() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("resource \"model\""))
        #expect(formula.contains("resource \"voices\""))
        #expect(formula.contains("kokoro-v1_0.safetensors"))
        #expect(formula.contains("voices.tar.gz"))
        #expect(formula.contains("models-v1"))
    }

    // Structural check: install block uses xcodebuild and stages share/yapper
    @Test("OT-11.10: Formula install block builds with xcodebuild and stages data dirs")
    func formulaInstallBlockCorrect() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("xcodebuild"))
        #expect(formula.contains("share/\"yapper/models\""))
        #expect(formula.contains("share/\"yapper/voices\""))
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

    // OT-11.8: release.sh updates formula SHA256 + URL and mirrors to tap
    @Test("OT-11.8: release.sh updates formula SHA256/URL and mirrors to tap")
    func releaseScriptUpdatesFormula() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("SOURCE_SHA256"),
                "release.sh must compute source tarball SHA256")
        #expect(script.contains("Formula/yapper.rb"),
                "release.sh must write Formula/yapper.rb")
        #expect(script.contains("tigger04/homebrew-tap"),
                "release.sh must push formula to the tap repo")
    }

    // Companion: release-models.sh handles English voice filtering and upload
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

    // Makefile wiring
    @Test("OT-11.12: Makefile exposes release and release-models targets")
    func makefileExposesReleaseTargets() throws {
        let makefile = try Self.read("Makefile")
        #expect(makefile.contains("release-models:"))
        #expect(makefile.contains("release:"))
        #expect(makefile.contains("scripts/release-models.sh"))
        #expect(makefile.contains("scripts/release.sh"))
    }
}
