
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Foundation

@main
struct BADDADApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1280, minHeight: 780)
        }
    }
}

// MARK: - Incoming Payload Models

struct IncomingPayload: Codable {
    let jobs: [IncomingJob]
}

struct IncomingJob: Codable {
    let queue: String
    let path: String
    let qty: Int
}

// MARK: - App Models

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

struct PrintJob: Identifiable, Equatable {
    let id: UUID
    var name: String
    var relativePath: String
    var resolvedPath: String
    var localOverridePath: String?
    var qty: Int
    var hasMissingFileError: Bool
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        resolvedPath: String,
        localOverridePath: String? = nil,
        qty: Int,
        hasMissingFileError: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.resolvedPath = resolvedPath
        self.localOverridePath = localOverridePath
        self.qty = qty
        self.hasMissingFileError = hasMissingFileError
        self.errorMessage = errorMessage
    }

    var activePath: String {
        localOverridePath ?? resolvedPath
    }
}

struct CompletedJob: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let qty: Int
    let wasSkipped: Bool
}

struct QueueState {
    var inQueue: [PrintJob]
    var completed: [CompletedJob]
    var currentlyPrinting: PrintJob?
    var isPrintingStarted: Bool
}

// MARK: - Print Automation

enum PrintAutomation {
    static func runPythonPrint(for filePath: String) -> Result<Void, Error> {
        let scriptPath = pythonScriptPath()

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return .failure(
                NSError(
                    domain: "PrintAutomation",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not find automated_print.py at \(scriptPath)"]
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

    private static func pythonScriptPath() -> String {
        if let bundled = Bundle.main.path(forResource: "automated_print", ofType: "py") {
            return bundled
        }

        return "\(FileManager.default.currentDirectoryPath)/automated_print.py"
    }
}

// MARK: - Path Resolver

enum PathResolver {
    static func detectBasePath() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/Library/CloudStorage/GoogleDrive-ricky@oceanspiritclothing.com.au/Shared drives/",
            "\(home)/Library/CloudStorage/GoogleDrive-brian@oceanspiritclothing.com.au/Shared drives/"
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }

        return nil
    }

    static func resolveFullPath(basePath: String, relativePath: String) -> String {
        let cleanedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let cleanedRelative = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        return "\(cleanedBase)/\(cleanedRelative)"
    }
}

// MARK: - Root

struct RootView: View {
    @State private var selectedQueue: QueueName = .blackFront
    @State private var showSettings = false
    @State private var importStatusMessage: String?
    @State private var showQtyConfirmation = false
    @State private var pendingQtyConfirmationJob: PrintJob?
    @State private var showClearQueueModal = false

    @State private var queues: [QueueName: QueueState] = {
        var states: [QueueName: QueueState] = [:]
        for queue in QueueName.allCases {
            states[queue] = QueueState(
                inQueue: [],
                completed: [],
                currentlyPrinting: nil,
                isPrintingStarted: false
            )
        }
        return states
    }()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(
                    selectedQueue: selectedQueue,
                    showClearQueueModal: $showClearQueueModal
                )

                Divider()

                if let importStatusMessage, !importStatusMessage.isEmpty {
                    HStack {
                        Text(importStatusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.labelPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.controlBackground)
                }

                MainLayout(
                    selectedQueue: $selectedQueue,
                    showSettings: $showSettings,
                    queues: $queues,
                    showQtyConfirmation: $showQtyConfirmation,
                    pendingQtyConfirmationJob: $pendingQtyConfirmationJob,
                    setImportStatusMessage: { message in
                        importStatusMessage = message
                    }
                )
            }
            .background(AppTheme.contentBackground)
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    showSettings: $showSettings,
                    resolvedBasePath: PathResolver.detectBasePath()
                )
            }
            .alert("Did you print the correct QTY?", isPresented: $showQtyConfirmation, presenting: pendingQtyConfirmationJob) { job in
                Button("No", role: .cancel) {}
                Button("Yes") {
                    confirmQtyCompletion(for: job)
                }
            } message: { job in
                Text("\(job.name) — Qty: \(job.qty)")
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }

            if showClearQueueModal {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()

                ClearQueueModal(
                    queueName: selectedQueue.rawValue,
                    onClearAll: {
                        clearAllQueues()
                        showClearQueueModal = false
                    },
                    onClearThisQueue: {
                        clearSelectedQueue()
                        showClearQueueModal = false
                    },
                    onCancel: {
                        showClearQueueModal = false
                    }
                )
            }
        }
    }

    private func clearSelectedQueue() {
        var state = queues[selectedQueue] ?? QueueState(
            inQueue: [],
            completed: [],
            currentlyPrinting: nil,
            isPrintingStarted: false
        )
        state.inQueue.removeAll()
        state.completed.removeAll()
        state.currentlyPrinting = nil
        state.isPrintingStarted = false
        queues[selectedQueue] = state
    }

    private func clearAllQueues() {
        for queue in QueueName.allCases {
            queues[queue] = QueueState(
                inQueue: [],
                completed: [],
                currentlyPrinting: nil,
                isPrintingStarted: false
            )
        }
    }

    private func confirmQtyCompletion(for job: PrintJob) {
        guard let queue = QueueName.allCases.first(where: { queues[$0]?.currentlyPrinting?.id == job.id }) else { return }
        var state = queues[queue]!
        state.completed.append(
            CompletedJob(name: job.name, qty: job.qty, wasSkipped: false)
        )
        state.currentlyPrinting = nil
        state.isPrintingStarted = false
        queues[queue] = state
        pendingQtyConfirmationJob = nil
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "baddadqueue" else {
            importStatusMessage = "Ignored URL: unsupported scheme."
            return
        }

        guard url.host?.lowercased() == "load" else {
            importStatusMessage = "Ignored URL: unsupported action."
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payloadItem = components.queryItems?.first(where: { $0.name == "payload" }),
              let rawPayload = payloadItem.value else {
            importStatusMessage = "Failed to load queue: missing payload."
            return
        }

        let decodedPayloadString = rawPayload.removingPercentEncoding ?? rawPayload

        guard let jsonData = decodedPayloadString.data(using: .utf8) else {
            importStatusMessage = "Failed to load queue: payload was not valid UTF-8."
            return
        }

        do {
            let jobs = try decodeIncomingJobs(from: jsonData)
            importJobs(jobs)
        } catch {
            importStatusMessage = "Decode failed: \(error.localizedDescription)"
        }
    }

    private func decodeIncomingJobs(from data: Data) throws -> [IncomingJob] {
        let decoder = JSONDecoder()

        if let payload = try? decoder.decode(IncomingPayload.self, from: data) {
            return payload.jobs
        }

        if let jobs = try? decoder.decode([IncomingJob].self, from: data) {
            return jobs
        }

        throw NSError(
            domain: "PayloadDecode",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Payload must be either {\"jobs\":[...]} or a bare [...] array."]
        )
    }

    private func importJobs(_ incomingJobs: [IncomingJob]) {
        guard let basePath = PathResolver.detectBasePath() else {
            importStatusMessage = "No Google Drive base path found for Ricky or Brian."
            return
        }

        var importedCount = 0
        var skippedCount = 0

        for incoming in incomingJobs {
            guard let queue = QueueName.fromIncoming(incoming.queue) else {
                skippedCount += 1
                continue
            }

            let relativePath = incoming.path
            let resolvedPath = PathResolver.resolveFullPath(basePath: basePath, relativePath: relativePath)
            let exists = FileManager.default.fileExists(atPath: resolvedPath)

            let displayName = URL(fileURLWithPath: relativePath)
                .deletingPathExtension()
                .lastPathComponent

            let job = PrintJob(
                name: displayName,
                relativePath: relativePath,
                resolvedPath: resolvedPath,
                qty: max(incoming.qty, 1),
                hasMissingFileError: !exists,
                errorMessage: exists ? nil : "File not found
