"""Deterministic Word interoperability fixture; no Word installation required."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo
root = Path(__file__).resolve().parents[1]
ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
parts = {
 '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>',
 '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
 'word/_rels/document.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com" TargetMode="External"/></Relationships>',
 'word/styles.xml': f'''<w:styles xmlns:w="{ns}">
 <w:docDefaults><w:pPrDefault><w:pPr><w:spacing w:after="120"/></w:pPr></w:pPrDefault><w:rPrDefault><w:rPr><w:sz w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults>
 <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
 <w:style w:type="paragraph" w:styleId="Body"><w:name w:val="Indented body"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720" w:firstLine="720" w:right="360"/><w:spacing w:before="120" w:after="240" w:line="360" w:lineRule="auto"/><w:jc w:val="both"/></w:pPr><w:rPr><w:rFonts w:ascii="Georgia"/><w:sz w:val="32"/><w:b/></w:rPr></w:style>
 <w:style w:type="paragraph" w:styleId="Child"><w:basedOn w:val="Body"/><w:pPr><w:ind w:left="1440"/></w:pPr></w:style>
 <w:style w:type="character" w:styleId="Emphasis"><w:rPr><w:i/><w:color w:val="336699"/></w:rPr></w:style>
 </w:styles>''',
 'word/numbering.xml': f'''<w:numbering xmlns:w="{ns}"><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>''',
 'word/document.xml': f'''<w:document xmlns:w="{ns}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>
 <w:p><w:pPr><w:ind w:left="720" w:firstLine="720" w:right="360"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="AA3300"/><w:sz w:val="28"/></w:rPr><w:t>Direct first line. This paragraph should start one inch from the left edge of the text area and continue at half an inch when it wraps.</w:t></w:r></w:p>
 <w:p><w:pPr><w:pStyle w:val="Child"/></w:pPr><w:r><w:t>Inherited body. This paragraph uses its parent style for the first-line indent, font, spacing and alignment.</w:t></w:r></w:p>
 <w:p><w:pPr><w:pStyle w:val="Body"/><w:ind w:hanging="360"/></w:pPr><w:r><w:t>Hanging paragraph. The first line begins before subsequent lines, preserving its parent's left and right indents.</w:t></w:r></w:p>
 <w:p><w:pPr><w:pStyle w:val="Body"/><w:ind w:left="0" w:firstLine="0"/><w:spacing w:before="0" w:after="0"/><w:jc w:val="left"/></w:pPr><w:r><w:rPr><w:b w:val="0"/><w:rStyle w:val="Emphasis"/></w:rPr><w:t>Explicit zero overrides inherited values.</w:t></w:r></w:p>
 <w:p><w:pPr><w:ind w:firstLine="360"/><w:spacing w:line="400" w:lineRule="exact"/><w:tabs><w:tab w:val="right" w:pos="2880"/></w:tabs></w:pPr><w:r><w:t>Soft break 🙂</w:t><w:br/><w:t>Second line</w:t><w:tab/><w:t>Tabbed</w:t></w:r></w:p>
 <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Numbered item retains its list and hanging indent.</w:t></w:r></w:p>
 <w:tbl><w:tblPr><w:tblW w:w="8640" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="8640"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="8640" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:ind w:firstLine="240"/></w:pPr><w:r><w:t>Inside a table cell.</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
 <w:p><w:pPr><w:ind w:firstLine="600"/></w:pPr><w:hyperlink r:id="rId3"><w:r><w:t>After table link.</w:t></w:r></w:hyperlink></w:p>
 <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
 </w:body></w:document>'''
}
out = root / 'MongrelWordProcessor/Tests/Fixtures/WordFormatting.docx'
with ZipFile(out,'w') as archive:
 for name, value in parts.items():
  info = ZipInfo(name, (2026, 1, 1, 0, 0, 0))
  info.compress_type = ZIP_DEFLATED
  archive.writestr(info, value)
print(out)
