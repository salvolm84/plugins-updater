import SwiftUI

/// Minimal block-level Markdown renderer for GitHub release notes; inline styling uses AttributedString.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
        case let .listItem(marker, text, indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary).monospacedDigit()
                Text(inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case let .quote(text):
            Text(inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.tertiary).frame(width: 3) }
        case let .code(text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case let .paragraph(text):
            Text(inline(text)).fixedSize(horizontal: false, vertical: true)
        case .rule:
            Divider()
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

enum MarkdownBlock {
    case heading(Int, String)
    case listItem(marker: String, text: String, indent: Int)
    case quote(String)
    case code(String)
    case paragraph(String)
    case rule

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        for raw in source.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil }
                else { flushParagraph(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }

            let indent = raw.prefix { $0 == " " || $0 == "\t" }.count / 2
            if line.isEmpty {
                flushParagraph()
            } else if let (level, text) = ReleaseNotes.heading(line) {
                flushParagraph(); blocks.append(.heading(level, text))
            } else if ["---", "***", "___"].contains(line) {
                flushParagraph(); blocks.append(.rule)
            } else if line.hasPrefix("> ") || line == ">" {
                flushParagraph(); blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
                flushParagraph(); blocks.append(.listItem(marker: "•", text: String(line.dropFirst(2)), indent: indent))
            } else if let range = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                flushParagraph()
                blocks.append(.listItem(marker: String(line[range]).trimmingCharacters(in: .whitespaces), text: String(line[range.upperBound...]), indent: indent))
            } else if paragraph.isEmpty, case let .listItem(marker, text, i)? = blocks.last, indent > 0 {
                // Continuation line of the previous list item.
                blocks[blocks.count - 1] = .listItem(marker: marker, text: text + " " + line, indent: i)
            } else {
                paragraph.append(line)
            }
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }
}
