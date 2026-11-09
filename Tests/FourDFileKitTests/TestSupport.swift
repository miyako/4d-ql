import Foundation
import XCTest
import FourDFileKit

extension AnalyzerRegistry {
    /// The default registry with forms analyzed for macOS, the platform the
    /// existing reference expectations were measured on.
    static let macOSReference = AnalyzerRegistry(AnalyzerRegistry.default.analyzers.map {
        $0 is FormFileAnalyzer ? FormFileAnalyzer(platform: .macOS) : $0
    })
}

extension XCTestCase {
    /// Creates a symbolic link, skipping the test where the host refuses to
    /// (Windows requires Developer Mode or SeCreateSymbolicLinkPrivilege).
    func createSymbolicLink(at link: URL, to destination: URL) throws {
        do {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        } catch {
            #if os(Windows)
            throw XCTSkip("symbolic links are unavailable on this Windows host: \(error)")
            #else
            throw error
            #endif
        }
    }

    /// Skips pixel assertions whose expected values were measured with the
    /// macOS system fonts and therefore only hold on a macOS host.
    func requireMacOSFontMetrics() throws {
        #if !os(macOS)
        throw XCTSkip("expected text metrics were measured with macOS system fonts")
        #endif
    }
}
