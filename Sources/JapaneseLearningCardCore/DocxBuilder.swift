import Foundation

/// Builds a minimal OOXML `.docx` archive containing a Japanese essay with
/// inline ruby (furigana) annotations.
///
/// The generated document follows the Office Open XML Flat OPC structure:
///   _rels/.rels
///   [Content_Types].xml
///   word/_rels/document.xml.rels
///   word/document.xml
public enum DocxBuilder {

    // MARK: - Public API

    /// Assembles a complete `.docx` `Data` blob ready to be written to disk.
    public static func buildDocx(
        title: String,
        titleRuby: [RubySegment]?,
        theme: String,
        paragraphs: [ArticleParagraph]
    ) -> Data {
        let docXML = buildDocumentXML(
            title: title,
            titleRuby: titleRuby,
            theme: theme,
            paragraphs: paragraphs
        )

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        // An empty document relationships file is required for full OOXML conformance.
        let wordRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        </Relationships>
        """

        let entries: [DocxZipWriter.Entry] = [
            DocxZipWriter.Entry(name: "_rels/.rels",                    data: Data(rootRels.utf8)),
            DocxZipWriter.Entry(name: "[Content_Types].xml",            data: Data(contentTypes.utf8)),
            DocxZipWriter.Entry(name: "word/_rels/document.xml.rels",   data: Data(wordRels.utf8)),
            DocxZipWriter.Entry(name: "word/document.xml",              data: Data(docXML.utf8)),
        ]
        return DocxZipWriter.write(entries: entries)
    }

    // MARK: - XML building (internal for unit tests)

    static func buildDocumentXML(
        title: String,
        titleRuby: [RubySegment]?,
        theme: String,
        paragraphs: [ArticleParagraph]
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
        """

        // ── Title paragraph ──────────────────────────────────────────────────
        xml += """
            <w:p>
              <w:pPr>
                <w:jc w:val="center"/>
                <w:spacing w:after="240"/>
              </w:pPr>
        """
        let usableTitleRuby = RubySupport.validated(titleRuby, for: title)
        if !usableTitleRuby.isEmpty {
            for segment in usableTitleRuby {
                xml += buildRunXML(segment: segment, baseSize: 36, rubySize: 18, bold: true)
            }
        } else {
            xml += """
              <w:r>
                <w:rPr>
                  <w:sz w:val="36"/>
                  <w:szCs w:val="36"/>
                  <w:b/>
                </w:rPr>
                <w:t xml:space="preserve">\(escapeXML(title))</w:t>
              </w:r>
            """
        }
        xml += "</w:p>"

        // ── Theme subtitle ────────────────────────────────────────────────────
        xml += """
            <w:p>
              <w:pPr>
                <w:jc w:val="center"/>
                <w:spacing w:after="480"/>
              </w:pPr>
              <w:r>
                <w:rPr>
                  <w:sz w:val="20"/>
                  <w:color w:val="666666"/>
                </w:rPr>
                <w:t xml:space="preserve">主題：\(escapeXML(theme))</w:t>
              </w:r>
            </w:p>
        """

        // ── Body paragraphs ───────────────────────────────────────────────────
        for para in paragraphs {
            xml += """
                <w:p>
                  <w:pPr>
                    <w:spacing w:before="240" w:after="120" w:line="360" w:lineRule="auto"/>
                  </w:pPr>
            """
            // Fall back to plain text when ruby data is absent or mismatched.
            let usableRuby = RubySupport.validated(para.ruby, for: para.japanese)
            if !usableRuby.isEmpty {
                for segment in usableRuby {
                    xml += buildRunXML(segment: segment, baseSize: 24, rubySize: 12)
                }
            } else {
                xml += buildRunXML(segment: RubySegment(base: para.japanese), baseSize: 24, rubySize: 12)
            }
            xml += "</w:p>"

            // Crawled articles have no translation – skip empty translation paragraphs.
            if !para.translation.trimmingCharacters(in: .whitespaces).isEmpty {
                xml += """
                    <w:p>
                      <w:pPr>
                        <w:spacing w:before="60" w:after="240"/>
                      </w:pPr>
                      <w:r>
                        <w:rPr>
                          <w:sz w:val="20"/>
                          <w:color w:val="555555"/>
                        </w:rPr>
                        <w:t xml:space="preserve">\(escapeXML(para.translation))</w:t>
                      </w:r>
                    </w:p>
                """
            }
        }

        xml += """
          </w:body>
        </w:document>
        """
        return xml
    }

    /// Returns a `<w:ruby>` element (or a plain `<w:r>` when `segment.ruby` is
    /// empty) suitable for direct insertion into a `<w:p>` paragraph element.
    ///
    /// **Important:** `<w:ruby>` is a direct child of `<w:p>` in OOXML — it must
    /// NOT be wrapped inside a `<w:r>`.
    static func buildRunXML(
        segment: RubySegment,
        baseSize: Int,
        rubySize: Int,
        bold: Bool = false
    ) -> String {
        let text = escapeXML(segment.base)
        let boldTag = bold ? "<w:b/>" : ""

        guard !segment.ruby.isEmpty else {
            // Plain run — no annotation.
            return """
                  <w:r>
                    <w:rPr>
                      <w:sz w:val="\(baseSize)"/>
                      <w:szCs w:val="\(baseSize)"/>
                      \(boldTag)
                    </w:rPr>
                    <w:t xml:space="preserve">\(text)</w:t>
                  </w:r>
            """
        }

        let escapedRuby = escapeXML(segment.ruby)
        // hpsRaise positions the ruby text above the base-text baseline.
        // Typical Word value: approximately (baseSize − 2) half-points.
        let hpsRaise = max(baseSize - 2, rubySize)
        return """
              <w:ruby>
                <w:rubyPr>
                  <w:rubyAlign w:val="center"/>
                  <w:hps w:val="\(rubySize)"/>
                  <w:hpsRaise w:val="\(hpsRaise)"/>
                  <w:hpsBaseText w:val="\(baseSize)"/>
                  <w:lid w:val="ja-JP"/>
                </w:rubyPr>
                <w:rt>
                  <w:r>
                    <w:rPr>
                      <w:sz w:val="\(rubySize)"/>
                      <w:szCs w:val="\(rubySize)"/>
                    </w:rPr>
                    <w:t xml:space="preserve">\(escapedRuby)</w:t>
                  </w:r>
                </w:rt>
                <w:rubyBase>
                  <w:r>
                    <w:rPr>
                      <w:sz w:val="\(baseSize)"/>
                      <w:szCs w:val="\(baseSize)"/>
                      \(boldTag)
                    </w:rPr>
                    <w:t xml:space="preserve">\(text)</w:t>
                  </w:r>
                </w:rubyBase>
              </w:ruby>
        """
    }

    static func escapeXML(_ string: String) -> String {
        var s = string
        s = s.replacingOccurrences(of: "&",  with: "&amp;")
        s = s.replacingOccurrences(of: "<",  with: "&lt;")
        s = s.replacingOccurrences(of: ">",  with: "&gt;")
        s = s.replacingOccurrences(of: "\"", with: "&quot;")
        s = s.replacingOccurrences(of: "'",  with: "&apos;")
        return s
    }
}

// MARK: - Minimal stored-mode ZIP writer

/// Writes a ZIP archive with all entries stored (compression method 0).
enum DocxZipWriter {
    struct Entry {
        let name: String
        let data: Data
    }

    static func write(entries: [Entry]) -> Data {
        var zip = Data()
        var offsets = [String: Int]()

        for entry in entries {
            offsets[entry.name] = zip.count
            let nameBytes = Data(entry.name.utf8)
            let crc  = DocxCRC32.calculate(entry.data)
            let size = UInt32(entry.data.count)

            // Local file header
            zip += [0x50, 0x4b, 0x03, 0x04]   // signature
            zip += [10, 0]                      // version needed
            zip += [0, 0]                       // flags
            zip += [0, 0]                       // compression: stored
            zip += [0, 0, 0, 0]                 // mod time / date (zero)
            writeUInt32(crc,  into: &zip)
            writeUInt32(size, into: &zip)       // compressed size
            writeUInt32(size, into: &zip)       // uncompressed size
            writeUInt16(UInt16(nameBytes.count), into: &zip)
            zip += [0, 0]                       // extra field length
            zip += nameBytes
            zip += entry.data
        }

        let cdOffset = UInt32(zip.count)

        // Central directory
        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            let crc  = DocxCRC32.calculate(entry.data)
            let size = UInt32(entry.data.count)
            let off  = UInt32(offsets[entry.name] ?? 0)

            zip += [0x50, 0x4b, 0x01, 0x02]
            zip += [20, 0]                      // version made by
            zip += [10, 0]                      // version needed
            zip += [0, 0]                       // flags
            zip += [0, 0]                       // compression
            zip += [0, 0, 0, 0]                 // mod time / date
            writeUInt32(crc,  into: &zip)
            writeUInt32(size, into: &zip)
            writeUInt32(size, into: &zip)
            writeUInt16(UInt16(nameBytes.count), into: &zip)
            zip += [0, 0]                       // extra length
            zip += [0, 0]                       // comment length
            zip += [0, 0]                       // disk start
            zip += [0, 0]                       // internal attrs
            zip += [0, 0, 0, 0]                 // external attrs
            writeUInt32(off, into: &zip)
            zip += nameBytes
        }

        let cdSize   = UInt32(zip.count) - cdOffset
        let numFiles = UInt16(entries.count)

        // End of central directory record
        zip += [0x50, 0x4b, 0x05, 0x06]
        zip += [0, 0]                           // disk number
        zip += [0, 0]                           // disk with CD start
        writeUInt16(numFiles, into: &zip)
        writeUInt16(numFiles, into: &zip)
        writeUInt32(cdSize,   into: &zip)
        writeUInt32(cdOffset, into: &zip)
        zip += [0, 0]                           // comment length

        return zip
    }

    private static func writeUInt16(_ value: UInt16, into data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data += $0 }
    }

    private static func writeUInt32(_ value: UInt32, into data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data += $0 }
    }
}

// MARK: - CRC-32

enum DocxCRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1
            }
            return c
        }
    }()

    static func calculate(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}
