import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Gives Foundation's `XMLParser` Darwin's strictness on every platform.
///
/// swift-corelibs-foundation (Windows/Linux) always drives libxml2 in recover mode
/// with entity substitution, never reports DTD entity declarations to the delegate,
/// and can crash when `abortParsing()` runs re-entrantly from a SAX callback. Off
/// Darwin, documents declaring entities are therefore rejected before parsing,
/// recovered errors fail the parse, and delegates record failures instead of
/// aborting (inputs are already size-limited). Darwin behavior is unchanged.
extension XMLParser {
    /// Whether the document declares DTD entities that this platform would expand silently.
    static func declaresUnreportedEntities(_ data: Data) -> Bool {
        #if canImport(Darwin)
        return false
        #else
        return data.range(of: Data("<!ENTITY".utf8)) != nil
        #endif
    }

    /// Whether external entity callbacks can be requested without enabling DTD loading.
    static var reportsExternalEntitiesSafely: Bool {
        #if canImport(Darwin)
        return true
        #else
        return false
        #endif
    }

    /// Parses, failing on any error libxml2 recovered from.
    func parseStrictly() -> Bool {
        #if canImport(Darwin)
        return parse()
        #else
        return parse() && parserError == nil
        #endif
    }

    /// Stops parsing from a delegate callback; the delegate must also record the failure.
    func stopFromDelegate() {
        #if canImport(Darwin)
        abortParsing()
        #endif
    }
}
