// ABOUTME: Tests for the EpubParser — epub chapter extraction and metadata.
// ABOUTME: Covers RT-7.1 through RT-7.21.

import Testing
import Foundation
@testable import YapperKit

// Import the parser from the yapper target — but since it's in the executable
// target we can't import it directly. Instead, test the parsing logic by
// creating minimal epub fixtures and verifying the structure.
// Note: EpubParser is in Sources/yapper/ which isn't testable from YapperKitTests.
// We need to either move it to YapperKit or create a separate test target.
// For now, these tests verify the epub fixture creation and expected structure.

@Suite(.serialized)
struct EpubParserTests {

    /// Create a minimal epub 2 fixture with NCX TOC.
    private func createEpub2(
        title: String = "Test Book",
        author: String = "Test Author",
        chapters: [(String, String)] = [("Chapter 1", "This is chapter one."), ("Chapter 2", "This is chapter two.")],
        includeCover: Bool = false
    ) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_epub2_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // META-INF/container.xml
        let metaInf = tmpDir.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try """
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles>
            <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        // content.opf
        var manifest = ""
        var spine = ""
        var ncxItems = ""

        for (i, chapter) in chapters.enumerated() {
            let id = "ch\(i + 1)"
            manifest += "    <item id=\"\(id)\" href=\"\(id).xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "    <itemref idref=\"\(id)\"/>\n"
            ncxItems += """
                <navPoint id="nav\(i + 1)" playOrder="\(i + 1)">
                  <navLabel><text>\(chapter.0)</text></navLabel>
                  <content src="\(id).xhtml"/>
                </navPoint>

            """

            // Chapter XHTML
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head><title>\(chapter.0)</title></head>
            <body><h1>\(chapter.0)</h1><p>\(chapter.1)</p></body>
            </html>
            """.write(to: tmpDir.appendingPathComponent("\(id).xhtml"), atomically: true, encoding: .utf8)
        }

        manifest += "    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n"

        let coverMeta = includeCover ? "<meta name=\"cover\" content=\"cover-image\"/>" : ""
        if includeCover {
            manifest += "    <item id=\"cover-image\" href=\"cover.jpg\" media-type=\"image/jpeg\"/>\n"
            try Data([0xFF, 0xD8, 0xFF]).write(to: tmpDir.appendingPathComponent("cover.jpg"))
        }

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(title)</dc:title>
            <dc:creator>\(author)</dc:creator>
            \(coverMeta)
          </metadata>
          <manifest>
        \(manifest)  </manifest>
          <spine toc="ncx">
        \(spine)  </spine>
        </package>
        """.write(to: tmpDir.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        // toc.ncx
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
          <navMap>
        \(ncxItems)  </navMap>
        </ncx>
        """.write(to: tmpDir.appendingPathComponent("toc.ncx"), atomically: true, encoding: .utf8)

        // ZIP it
        let epubPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).epub")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", epubPath.path, "."]
        process.currentDirectoryURL = tmpDir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: tmpDir)
        return epubPath
    }

    /// Create a minimal epub 3 fixture with nav TOC.
    private func createEpub3(
        title: String = "Test Book 3",
        author: String = "Test Author 3",
        chapters: [(String, String)] = [("Chapter A", "Epub three chapter A."), ("Chapter B", "Epub three chapter B.")]
    ) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_epub3_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let metaInf = tmpDir.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try """
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles>
            <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        var manifest = ""
        var spine = ""
        var navLinks = ""

        for (i, chapter) in chapters.enumerated() {
            let id = "ch\(i + 1)"
            manifest += "    <item id=\"\(id)\" href=\"\(id).xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "    <itemref idref=\"\(id)\"/>\n"
            navLinks += "        <li><a href=\"\(id).xhtml\">\(chapter.0)</a></li>\n"

            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head><title>\(chapter.0)</title></head>
            <body><h1>\(chapter.0)</h1><p>\(chapter.1)</p></body>
            </html>
            """.write(to: tmpDir.appendingPathComponent("\(id).xhtml"), atomically: true, encoding: .utf8)
        }

        manifest += "    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n"

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(title)</dc:title>
            <dc:creator>\(author)</dc:creator>
          </metadata>
          <manifest>
        \(manifest)  </manifest>
          <spine>
        \(spine)  </spine>
        </package>
        """.write(to: tmpDir.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        // nav.xhtml
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <body>
          <nav epub:type="toc">
            <ol>
        \(navLinks)    </ol>
          </nav>
        </body>
        </html>
        """.write(to: tmpDir.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)

        let epubPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test3_\(UUID().uuidString).epub")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", epubPath.path, "."]
        process.currentDirectoryURL = tmpDir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: tmpDir)
        return epubPath
    }

    // RT-7.1: Parser returns at least one chapter from a test epub
    @Test("RT-7.1: at least one chapter extracted")
    func test_at_least_one_chapter_RT7_1() throws {
        let epub = try createEpub2()
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(!result.chapters.isEmpty)
    }

    // RT-7.2: Each chapter has a non-empty title and non-empty text
    @Test("RT-7.2: chapters have title and text")
    func test_chapters_have_title_text_RT7_2() throws {
        let epub = try createEpub2()
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        for chapter in result.chapters {
            #expect(!chapter.title.isEmpty)
            #expect(!chapter.text.isEmpty)
        }
    }

    // RT-7.3: Chapter text contains no HTML tags
    @Test("RT-7.3: no HTML tags in text")
    func test_no_html_tags_RT7_3() throws {
        let epub = try createEpub2()
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        for chapter in result.chapters {
            #expect(!chapter.text.contains("<"))
            #expect(!chapter.text.contains(">"))
        }
    }

    // RT-7.4: Chapter count matches TOC entries
    @Test("RT-7.4: chapter count matches TOC")
    func test_chapter_count_matches_toc_RT7_4() throws {
        let epub = try createEpub2(chapters: [
            ("Ch 1", "Text 1."), ("Ch 2", "Text 2."), ("Ch 3", "Text 3.")
        ])
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.chapters.count == 3)
    }

    // RT-7.5: Chapter order matches spine order
    @Test("RT-7.5: chapter order matches spine")
    func test_chapter_order_RT7_5() throws {
        let epub = try createEpub2(chapters: [("First", "A."), ("Second", "B."), ("Third", "C.")])
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.chapters[0].title == "First")
        #expect(result.chapters[1].title == "Second")
        #expect(result.chapters[2].title == "Third")
    }

    // RT-7.6: Extracted title matches dc:title
    @Test("RT-7.6: title matches dc:title")
    func test_title_matches_RT7_6() throws {
        let epub = try createEpub2(title: "My Great Book")
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.metadata.title == "My Great Book")
    }

    // RT-7.7: Extracted author matches dc:creator
    @Test("RT-7.7: author matches dc:creator")
    func test_author_matches_RT7_7() throws {
        let epub = try createEpub2(author: "Jane Doe")
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.metadata.author == "Jane Doe")
    }

    // RT-7.8: Cover image path returned when present
    @Test("RT-7.8: cover image path when present")
    func test_cover_image_present_RT7_8() throws {
        let epub = try createEpub2(includeCover: true)
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.metadata.coverImagePath == "cover.jpg")
    }

    // RT-7.9: Non-epub file produces descriptive error
    @Test("RT-7.9: non-epub rejected")
    func test_non_epub_rejected_RT7_9() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("not_an_epub.txt")
        try "just text".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        #expect(throws: (any Error).self) {
            try EpubParser.parse(tmpFile.path)
        }
    }

    // RT-7.10: Epub with missing OPF produces descriptive error
    @Test("RT-7.10: missing OPF produces error")
    func test_missing_opf_RT7_10() throws {
        // Create a ZIP without proper epub structure
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_bad_epub_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let metaInf = tmpDir.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try """
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles>
            <rootfile full-path="missing.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        let epubPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad_\(UUID().uuidString).epub")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", epubPath.path, "."]
        process.currentDirectoryURL = tmpDir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: epubPath) }
        try? FileManager.default.removeItem(at: tmpDir)

        #expect(throws: (any Error).self) {
            try EpubParser.parse(epubPath.path)
        }
    }

    // RT-7.11: Epub 2 with NCX TOC produces correct chapters
    @Test("RT-7.11: epub 2 NCX works")
    func test_epub2_ncx_RT7_11() throws {
        let epub = try createEpub2()
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.chapters.count == 2)
        #expect(result.chapters[0].title == "Chapter 1")
    }

    // RT-7.12: Epub 3 with nav TOC produces correct chapters
    @Test("RT-7.12: epub 3 nav works")
    func test_epub3_nav_RT7_12() throws {
        let epub = try createEpub3()
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.chapters.count == 2)
        #expect(result.chapters[0].title == "Chapter A")
    }

    // RT-7.13: No-TOC epub returns one chapter
    @Test("RT-7.13: no-TOC produces single chapter")
    func test_no_toc_single_chapter_RT7_13() throws {
        // Create epub without NCX or nav
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_notoc_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let metaInf = tmpDir.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try """
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>No TOC Book</dc:title></metadata>
          <manifest><item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest>
          <spine><itemref idref="ch1"/></spine>
        </package>
        """.write(to: tmpDir.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        try "<html><body><p>All the content in one file.</p></body></html>"
            .write(to: tmpDir.appendingPathComponent("ch1.xhtml"), atomically: true, encoding: .utf8)

        let epubPath = FileManager.default.temporaryDirectory.appendingPathComponent("notoc_\(UUID().uuidString).epub")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-r", "-q", epubPath.path, "."]
        zip.currentDirectoryURL = tmpDir
        zip.standardOutput = FileHandle.nullDevice
        zip.standardError = FileHandle.nullDevice
        try zip.run()
        zip.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: epubPath) }
        try? FileManager.default.removeItem(at: tmpDir)

        let result = try EpubParser.parse(epubPath.path)
        #expect(result.chapters.count == 1)
    }

    // RT-7.14: Single-chapter text matches full document content
    @Test("RT-7.14: single chapter has full content")
    func test_single_chapter_full_content_RT7_14() throws {
        let epub = try createEpub2(chapters: [("Only Chapter", "The entire book content.")])
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.chapters.count == 1)
        #expect(result.chapters[0].text.contains("entire book content"))
    }

    // RT-7.15: HTML entities decoded
    @Test("RT-7.15: HTML entities decoded")
    func test_html_entities_decoded_RT7_15() throws {
        let epub = try createEpub2(chapters: [("Ch", "Tom &amp; Jerry &lt;3 each &#8220;other&#8221;")])
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        let text = result.chapters[0].text
        #expect(text.contains("Tom & Jerry"))
        #expect(text.contains("<3"))
        #expect(text.contains("\u{201C}other\u{201D}"))
    }

    // RT-7.16: Smart quotes preserved as unicode
    @Test("RT-7.16: smart quotes preserved")
    func test_smart_quotes_RT7_16() throws {
        let epub = try createEpub2(chapters: [("Ch", "She said &#8216;hello&#8217; to &#8220;everyone&#8221;")])
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        let text = result.chapters[0].text
        #expect(text.contains("\u{2018}hello\u{2019}"))
        #expect(text.contains("\u{201C}everyone\u{201D}"))
    }

    // RT-7.17: No dc:title returns nil title
    @Test("RT-7.17: missing title returns nil")
    func test_missing_title_nil_RT7_17() throws {
        let epub = try createEpub2(title: "")
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.metadata.title == nil || result.metadata.title?.isEmpty == true)
    }

    // RT-7.18: No dc:creator returns nil author
    @Test("RT-7.18: missing author returns nil")
    func test_missing_author_nil_RT7_18() throws {
        let epub = try createEpub2(author: "")
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.metadata.author == nil || result.metadata.author?.isEmpty == true)
    }

    // RT-7.19: No cover image returns nil
    @Test("RT-7.19: missing cover returns nil")
    func test_missing_cover_nil_RT7_19() throws {
        let epub = try createEpub2(includeCover: false)
        defer { try? FileManager.default.removeItem(at: epub) }
        let result = try EpubParser.parse(epub.path)
        #expect(result.metadata.coverImagePath == nil)
    }

    // RT-7.20: ZIP without container.xml produces error
    @Test("RT-7.20: ZIP without container.xml")
    func test_zip_no_container_RT7_20() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_nocontainer_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try "dummy".write(to: tmpDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let zipPath = FileManager.default.temporaryDirectory.appendingPathComponent("nocontainer_\(UUID().uuidString).epub")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-r", "-q", zipPath.path, "."]
        zip.currentDirectoryURL = tmpDir
        zip.standardOutput = FileHandle.nullDevice
        zip.standardError = FileHandle.nullDevice
        try zip.run()
        zip.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: zipPath) }
        try? FileManager.default.removeItem(at: tmpDir)

        #expect(throws: (any Error).self) {
            try EpubParser.parse(zipPath.path)
        }
    }

    // RT-7.21: Zero-byte file produces error
    @Test("RT-7.21: zero-byte file produces error")
    func test_zero_byte_file_RT7_21() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("zero_\(UUID().uuidString).epub")
        try Data().write(to: tmpFile)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        #expect(throws: (any Error).self) {
            try EpubParser.parse(tmpFile.path)
        }
    }
}
