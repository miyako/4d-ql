import Foundation
import FourDFileKit
import FourDRender

struct CommandError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct FormCommand {
    var input: String?
    var output: String?
    var json = false
    var languages: [String] = []
    var options = FormRenderOptions()

    init(_ arguments: [String]) throws {
        var index = 0
        var positionalOnly = false
        func value(_ flag: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw CommandError(message: "\(flag) requires a value.") }
            return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            if positionalOnly || !argument.hasPrefix("-") {
                guard input == nil else { throw CommandError(message: "Provide exactly one form per invocation.") }
                input = argument
            } else {
                switch argument {
                case "--": positionalOnly = true
                case "--json": json = true
                case "--html": json = false
                case "--output", "-o": output = try value(argument)
                case "--language":
                    let language = try value(argument)
                    guard !language.isEmpty else { throw CommandError(message: "--language must not be empty.") }
                    languages.append(language)
                case "--theme":
                    let name = try value(argument)
                    switch name {
                    case "classic-light": options.initialTheme = .classicLight
                    case "classic-dark": options.initialTheme = .classicDark
                    case "glass-light": options.initialTheme = .glassLight
                    case "glass-dark": options.initialTheme = .glassDark
                    default: throw CommandError(message: "Unknown theme: \(name).")
                    }
                case "--page":
                    let number = try value(argument)
                    guard let page = Int(number), page >= 0 else { throw CommandError(message: "--page must be a nonnegative integer.") }
                    options.initialPage = page
                default: throw CommandError(message: "Unknown option: \(argument).")
                }
            }
            index += 1
        }
        guard input != nil else { throw CommandError(message: "Provide a .4DForm path.") }
    }

    func run() throws {
        guard let input else { throw CommandError(message: "Provide a .4DForm path.") }
        let url = URL(fileURLWithPath: input)
        let destination = output.map { URL(fileURLWithPath: $0) }
        if let destination, destination.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath() {
            throw CommandError(message: "The output must not replace the input form.")
        }
        let result = try FormRenderer().render(url: url,
            preferredLanguages: languages.isEmpty ? Locale.preferredLanguages : languages, options: options)
        for notice in result.document.notices {
            FileHandle.standardError.write(Data(("warning: \(notice)\n").utf8))
        }
        let data = json ? try result.document.jsonData() : Data(result.html.utf8)
        if let destination { try data.write(to: destination, options: .atomic) }
        else {
            try FileHandle.standardOutput.write(contentsOf: data)
            try FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
        }
    }
}

let usage = """
usage: fourdform [--html | --json] [--output path] [--theme theme] [--page N]
                [--language BCP47 ...] [--] form.4DForm
themes: classic-light, classic-dark, glass-light, glass-dark
HTML is self-contained; JSON exports macOS reference styles (schema version 1).
No 4D, Quick Look host or project-method execution is required.
"""

let arguments = Array(CommandLine.arguments.dropFirst())
func message(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription { return description }
    return String(describing: error)
}
if arguments == ["--help"] || arguments == ["-h"] {
    print(usage)
    exit(0)
}
let command: FormCommand
do { command = try FormCommand(arguments) }
catch {
    FileHandle.standardError.write(Data(("error: \(message(error))\n\(usage)\n").utf8))
    exit(2)
}
do { try command.run() }
catch {
    FileHandle.standardError.write(Data(("error: \(message(error))\n").utf8))
    exit(1)
}
