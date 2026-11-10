import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct XMLFileNode: Codable {
    public let name: String
    public let attributes: [String: String]
    public var children: [XMLFileNode] = []
    public var text: String = ""
}

final class BoundedXMLDocument: NSObject, XMLParserDelegate {
    var root: XMLFileNode?
    var failure: String?
    private var stack: [XMLFileNode] = []
    private var elementCount = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard failure == nil else { return }
        elementCount += 1
        guard elementCount <= 20_000, stack.count < 32 else {
            failure = "XML exceeds the element or nesting limit"
            parser.stopFromDelegate()
            return
        }
        stack.append(XMLFileNode(name: elementName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if failure == nil, !stack.isEmpty { stack[stack.count - 1].text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if failure == nil, !stack.isEmpty { stack[stack.count - 1].text += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let node = stack.popLast() else { return }
        if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        rejectEntity(parser)
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        rejectEntity(parser)
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        rejectEntity(parser)
        return nil
    }

    private func rejectEntity(_ parser: XMLParser) {
        failure = "custom XML entities are not supported"
        parser.stopFromDelegate()
    }
}
