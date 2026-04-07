
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
        let scriptPath = resolvedPythonScriptPath()

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return .failure(
                NSError(
                    domain: "PrintAutomation",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing automated_print.py at \(scriptPath)"]
                )
            )
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

    private static func resolvedPythonScriptPath() -> String {
        if let bundled = Bundle.main.path(forResource: "automated_print", ofType: "py") {
            return bundled
        }

        return "\(FileManager.default.currentDirectoryPath)/automated_print.py"
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
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Queues")
                    .font(.headline)
                    .padding(.bottom, 8)

                ForEach(QueueName.allCases) { queue in
                    Button {
                        selectedQueue = queue
                    } label: {
                        HStack {
                            Text(queue.rawValue)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedQueue == queue
                                ? Color.gray.opacity(0.20)
                                : Color.clear
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .frame(width: 220)
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Printing Production Manager")
                    .font(.title)

                if let msg = message {
                    Text(msg)
                        .font(.subheadline)
                }

                Text("Selected Queue: \(selectedQueue.rawValue)")
                    .font(.headline)

                if let current = queues[selectedQueue]?.currentlyPrinting {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Currently Printing")
                            .font(.headline)

                        Text("Name: \(current.name)")
                        Text("Qty: \(current.qty)")

                        if current.hasError {
                            Text("Warning: file path does not currently exist")
                                .foregroundColor(.red)
                        }

                        Button("Start Printing") {
                            let result = PrintAutomation.runPythonPrint(for: current.activePath)

                            switch result {
                            case .success:
                                message = "Print started"
                            case .failure(let error):
                                message = error.localizedDescription
                            }
                        }
                    }
                } else {
                    Text("No job selected")
                }

                Divider()

                Text("In Queue")
                    .font(.headline)

                if let jobs = queues[selectedQueue]?.inQueue, !jobs.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(jobs) { job in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(job.name)
                                        Text("Qty: \(job.qty)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if job.hasError {
                                        Text("Missing File")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(10)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(8)
                            }
                        }
                    }
                } else {
                    Text("No jobs in queue")
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
        .onOpenURL { url in
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "baddadqueue" else {
            message = "Ignored URL: unsupported scheme"
            return
        }

        guard url.host?.lowercased() == "load" else {
            message = "Ignored URL: unsupported action"
            return
        }

        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value,
            let decoded = payload.removingPercentEncoding,
            let data = decoded.data(using: .utf8)
        else {
            message = "Invalid payload"
            return
        }

        do {
            let incoming = try JSONDecoder().decode(IncomingPayload.self, from: data)

            for job in incoming.jobs {
                guard let queue = QueueName.fromIncoming(job.queue) else {
                    continue
                }

                let exists = FileManager.default.fileExists(atPath: job.path)

                let printJob = PrintJob(
                    name: URL(fileURLWithPath: job.path).lastPathComponent,
                    path: job.path,
                    qty: max(job.qty, 1),
                    hasError: !exists
                )

                queues[queue]?.inQueue.append(printJob)

                if queues[queue]?.currentlyPrinting == nil {
                    queues[queue]?.currentlyPrinting = printJob
                }
            }

            message = "Jobs loaded"
        } catch {
            message = "Decode failed: \(error.localizedDescription)"
        }
    }
}
