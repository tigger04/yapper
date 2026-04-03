// ABOUTME: Tests that the package structure is correct — YapperKit is importable.
// ABOUTME: Covers RT-1.1 and RT-1.2.

import Testing
@testable import YapperKit

// RT-1.1: YapperKit module is importable in test code
@Test("RT-1.1: YapperKit module is importable")
func test_yapperkit_module_importable_RT1_1() {
    // If this file compiles, YapperKit is importable.
    // Verify a public type is accessible as a smoke test.
    let voice = Voice(name: "af_heart")
    #expect(voice != nil)
}

// RT-1.2: yapper binary responds to --version with a version string and exits 0
@Test("RT-1.2: version string is defined")
func test_version_string_defined_RT1_2() throws {
    // Verify the version constant is accessible and non-empty.
    // Full CLI --version test is OT-1.1 (invokes build system).
    let version = YapperKit.version
    #expect(!version.isEmpty)
    #expect(version.contains("."))
}
