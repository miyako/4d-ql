import Foundation
import FourDFileKit

private let quickReportUsage = """
usage: fourdql qr-convert (--to-json | --to-4qr) [input [output]]
       fourdql qr-convert (--to-json | --to-4qr) [-i input] [-o output]

Omitted paths or '-' use stdin/stdout. File output is replaced atomically.
JSON retains opaque formula, picture, printer and unknown data as base64.
"""

private struct QuickReportUsageError: Error, CustomStringConvertible {
    let description: String
}

func runQuickReportCommand(_ arguments: [String]) -> Int32 {
    do {
        var toJSON: Bool?
        var input: String?
        var output: String?
        var positional: [String] = []
        var index = 0
        var literalPaths = false
        while index < arguments.count {
            let argument = arguments[index]
            if literalPaths {
                positional.append(argument)
            } else {
                switch argument {
                case "-h", "--help":
                    print(quickReportUsage)
                    return 0
                case "--":
                    literalPaths = true
                case "--to-json", "--to-4qr":
                    guard toJSON == nil else {
                        throw QuickReportUsageError(description: "specify exactly one conversion direction")
                    }
                    toJSON = argument == "--to-json"
                case "-i", "--input", "-o", "--output":
                    index += 1
                    guard index < arguments.count else {
                        throw QuickReportUsageError(description: "\(argument) requires a path")
                    }
                    if argument == "-i" || argument == "--input" {
                        guard input == nil else { throw QuickReportUsageError(description: "duplicate input path") }
                        input = arguments[index]
                    } else {
                        guard output == nil else { throw QuickReportUsageError(description: "duplicate output path") }
                        output = arguments[index]
                    }
                default:
                    guard !argument.hasPrefix("-") || argument == "-" else {
                        throw QuickReportUsageError(description: "unknown option \(argument)")
                    }
                    positional.append(argument)
                }
            }
            index += 1
        }
        guard let toJSON else { throw QuickReportUsageError(description: "conversion direction is required") }
        guard positional.count <= 2, positional.isEmpty || (input == nil && output == nil) else {
            throw QuickReportUsageError(description: "use either positional paths or -i/-o, not both")
        }
        if !positional.isEmpty { input = positional[0] }
        if positional.count == 2 { output = positional[1] }

        let limit = toJSON ? QuickReportConverter.binaryLimit : QuickReportConverter.jsonLimit
        let bytes: Data
        if let input, input != "-" {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: input))
            defer { handle.closeFile() }
            bytes = try readQuickReportInput(handle, limit: limit)
        } else {
            bytes = try readQuickReportInput(.standardInput, limit: limit)
        }
        let converted = try toJSON ? QuickReportConverter.json(from: bytes) : QuickReportConverter.binary(from: bytes)
        if let output, output != "-" {
            try converted.write(to: URL(fileURLWithPath: output), options: .atomic)
        } else {
            try FileHandle.standardOutput.write(contentsOf: converted)
        }
        return 0
    } catch let error as QuickReportUsageError {
        FileHandle.standardError.write(Data("qr-convert: \(error)\n\(quickReportUsage)\n".utf8))
        return 2
    } catch {
        FileHandle.standardError.write(Data("qr-convert: \(error)\n".utf8))
        return 1
    }
}

private func readQuickReportInput(_ handle: FileHandle, limit: Int) throws -> Data {
    var data = Data()
    while let bytes = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)), !bytes.isEmpty {
        data.append(bytes)
        guard data.count <= limit else {
            throw QuickReportError.invalid("input exceeds the \(limit / (1024 * 1024)) MiB conversion limit.")
        }
    }
    return data
}
