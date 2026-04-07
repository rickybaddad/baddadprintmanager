
import SwiftUI
import AppKit
import Foundation

@main
struct BADDADApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1200, minHeight: 750)
        }
    }
}

// MARK: - Models

struct IncomingPayload: Codable {
    let jobs: [IncomingJob]
}

struct IncomingJob: Codable {
    let queue: String
    let path: String
    let qty: Int
}

enum QueueName: String, CaseIterable, Identifiable {
    case blackFront = "Black Front"
    case blackBack = "Black Back"
    case singletsFront = "Singlets Front"
    case singletsBack = "Singlets Back"
    case longSleeveFront = "Long Sleeve Front"
    case longSleeveBack = "Long Sleeve Back"
    case dtf = "DTF"

    var id: String { rawValue }

    static func fromIncoming(_ raw: String) -> QueueName? {
        switch raw.lowercased() {
        case "black_front": return .blackFront
        case "black_back": return .blackBack
        case "singlets_front": return .singletsFront
        case "singlets_back": return .singletsBack
        case "long_sleeve_front": return .longSleeveFront
        case "long_sleeve_back": return .longSleeveBack
        case "dtf", "white": return .dtf
        default: return nil
        }
    }
}

struct PrintJob: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let qty: Int
    let hasError: Bool

    var activePath: String { path }
}

struct QueueState {
    var inQueue: [PrintJob] = []
    var currentlyPrinting: PrintJob?
}

// MARK: - Python Automation

enum PrintAutomation {
    static func runPythonPrint(for filePath: String) -> Result<Void, Error> {
        let scriptPath = "\(FileManager.default.currentDirectoryPath)/automated_print.py"

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return .failure(NSError(domain: "PrintAutomation", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing automated_print.py"
            ]))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath, filePath]

        do {
            try process.run()
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - UI

struct RootView: View {
    @State private var queues: [QueueName: QueueState] = {
        var dict: [QueueName: QueueState] = [:]
        QueueName.allCases.forEach { dict[$0] = QueueState() }
        return dict
    }()

    @State private var selectedQueue: QueueName = .blackFront
    @State private var message: String?

    var body: some View {
        HStack {
            List(QueueName.allCases, selection: $selectedQueue) {
                Text($0.rawValue)
            }
            .frame(width: 220)

            VStack {
                Text("Printing Production Manager")
                    .font(.title)

                if let msg = message {
                    Text(msg)
                }

                if let current = queues[selectedQueue]?.currentlyPrinting {
                    Text("Printing: \(current.name) (Qty: \(current.qty))")

                    Button("Start Printing") {
                        let result = PrintAutomation.runPythonPrint(for: current.activePath)

                        switch result {
                        case .success:
                            message = "Print started"
                        case .failure(let error):
                            message = error.localizedDescription
                        }
                    }
                } else {
                    Text("No job selected")
                }
            }
        }
        .onOpenURL { url in
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value,
              let decoded = payload.removingPercentEncoding,
              let data = decoded.data(using: .utf8) else {
            message = "Invalid payload"
            return
        }

        do {
            let incoming = try JSONDecoder().decode(IncomingPayload.self, from: data)

            for job in incoming.jobs {
                if let queue = QueueName.fromIncoming(job.queue) {
                    let printJob = PrintJob(
                        name: URL(fileURLWithPath: job.path).lastPathComponent,
                        path: job.path,
                        qty: job.qty,
                        hasError: !FileManager.default.fileExists(atPath: job.path)
                    )

                    queues[queue]?.inQueue.append(printJob)

                    if queues[queue]?.currentlyPrinting == nil {
                        queues[queue]?.currentlyPrinting = printJob
                    }
                }
            }

            message = "Jobs loaded"
        } catch {
            message = "Decode failed"
        }
    }
}
