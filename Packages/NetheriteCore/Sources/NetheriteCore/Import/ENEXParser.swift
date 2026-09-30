import Foundation

/// One note read from an Evernote `.enex` export.
public struct ENEXNote: Sendable {
    public struct Resource: Sendable { public var data: Data; public var mime: String; public var fileName: String }
    public var title = ""
    public var content = ""
    public var created: Date?
    public var updated: Date?
    public var tags: [String] = []
    public var sourceURL: String?
    public var author: String?
    public var resources: [Resource] = []
}

public final class ENEXParser: NSObject, XMLParserDelegate {
    private var notes: [ENEXNote] = []
    private var note: ENEXNote?
    private var resource: ENEXNote.Resource?
    private var text = ""

    public static func parse(_ data: Data) -> [ENEXNote] {
        let d = ENEXParser()
        let p = XMLParser(data: data)
        p.shouldResolveExternalEntities = false   // .enex declares a DTD; never fetch it
        p.delegate = d
        p.parse()
        return d.notes
    }

    nonisolated(unsafe) static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    public func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "note": note = ENEXNote()
        case "resource": resource = ENEXNote.Resource(data: Data(), mime: "", fileName: "")
        default: break
        }
    }

    public func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    public func parser(_ p: XMLParser, foundCDATA d: Data) { text += String(decoding: d, as: UTF8.self) }

    public func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if resource != nil {
            switch name {
            case "data": resource?.data = Data(base64Encoded: value, options: .ignoreUnknownCharacters) ?? Data()
            case "mime": resource?.mime = value
            case "file-name": resource?.fileName = value
            case "resource": if let r = resource { note?.resources.append(r) }; resource = nil
            default: break
            }
        } else {
            switch name {
            case "title": note?.title = value
            case "content": note?.content = text
            case "created": note?.created = Self.dateFormatter.date(from: value)
            case "updated": note?.updated = Self.dateFormatter.date(from: value)
            case "tag": if !value.isEmpty { note?.tags.append(value) }
            case "source-url": note?.sourceURL = value.isEmpty ? nil : value
            case "author": note?.author = value.isEmpty ? nil : value
            case "note": if let n = note { notes.append(n) }; note = nil
            default: break
            }
        }
        text = ""
    }
}
