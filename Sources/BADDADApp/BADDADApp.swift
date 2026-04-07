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
        case "black_front":
            return .blackFront
        case "black_back":
            return .blackBack
        case "singlets_front":
            return .singletsFront
        case "singlets_back":
            return .singletsBack
        case "long_sleeve_front":
            return .longSleeveFront
        case "long_sleeve_back":
            return .longSleeveBack
        case "dtf", "white":
            return .dtf
        default:
            return nil
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
    static func runPythonPrint(for filePath: String) -> Result<Void, String> {
        let scriptPath = pythonScriptPath()

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return .failure("Could not find automated_print.py at \(scriptPath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath, filePath]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            return .success(())
        } catch {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            return .failure(stderrText.isEmpty ? error.localizedDescription : stderrText)
        }
    }

    private static func pythonScriptPath() -> String {
        let currentDirectory = FileManager.default.currentDirectoryPath
        return "\(currentDirectory)/automated_print.py"
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
            let payload = try JSONDecoder().decode(IncomingPayload.self, from: jsonData)
            importJobs(payload.jobs)
        } catch {
            importStatusMessage = "Failed to decode payload JSON."
        }
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
                errorMessage: exists ? nil : "File not found"
            )

            var state = queues[queue] ?? QueueState(
                inQueue: [],
                completed: [],
                currentlyPrinting: nil,
                isPrintingStarted: false
            )
            state.inQueue.append(job)
            queues[queue] = state
            importedCount += 1
        }

        importStatusMessage = "Imported \(importedCount) job(s)\(skippedCount > 0 ? " • Skipped \(skippedCount)" : "")."
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

// MARK: - Top Bar

struct TopBar: View {
    let selectedQueue: QueueName
    @Binding var showClearQueueModal: Bool

    var body: some View {
        ZStack {
            Text("Printing Production Manager")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.labelPrimary)

            HStack {
                LogoView()
                Spacer()

                Button("Clear Queue") {
                    showClearQueueModal = true
                }
                .buttonStyle(SecondaryButtonStyle(fixedWidth: 110))
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 16)
        .background(AppTheme.windowBackground)
    }
}

struct LogoView: View {
    private var logoImage: NSImage? {
        if let url = Bundle.module.url(forResource: "productionmanagerlogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }

    var body: some View {
        ZStack {
            if let logoImage {
                Image(nsImage: logoImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 128, height: 52)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.controlBackground)
                    .frame(width: 128, height: 52)
                    .overlay(
                        Text("PM")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.labelSecondary)
                    )
            }
        }
        .frame(width: 128, height: 52)
    }
}

// MARK: - Clear Queue Modal

struct ClearQueueModal: View {
    let queueName: String
    let onClearAll: () -> Void
    let onClearThisQueue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Clear Queue")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppTheme.labelPrimary)

            Text("Choose what to clear.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.labelSecondary)

            VStack(spacing: 12) {
                Button("All Queues") {
                    onClearAll()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("This Queue (\(queueName))") {
                    onClearThisQueue()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(AppTheme.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Main Layout

struct MainLayout: View {
    @Binding var selectedQueue: QueueName
    @Binding var showSettings: Bool
    @Binding var queues: [QueueName: QueueState]
    @Binding var showQtyConfirmation: Bool
    @Binding var pendingQtyConfirmationJob: PrintJob?
    let setImportStatusMessage: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Sidebar(
                selectedQueue: $selectedQueue,
                showSettings: $showSettings
            )
            .frame(width: 224)

            VStack(spacing: 12) {
                QueuePanel(
                    title: "In Queue",
                    jobs: currentState.inQueue
                )

                CompletedPanel(
                    title: "Completed",
                    jobs: currentState.completed
                )
            }

            CurrentPrintingPanel(
                queueName: selectedQueue,
                queueState: bindingForSelectedQueue(),
                showQtyConfirmation: $showQtyConfirmation,
                pendingQtyConfirmationJob: $pendingQtyConfirmationJob,
                setImportStatusMessage: setImportStatusMessage
            )
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(AppTheme.contentBackground)
    }

    private var currentState: QueueState {
        queues[selectedQueue] ?? QueueState(
            inQueue: [],
            completed: [],
            currentlyPrinting: nil,
            isPrintingStarted: false
        )
    }

    private func bindingForSelectedQueue() -> Binding<QueueState> {
        Binding(
            get: {
                queues[selectedQueue] ?? QueueState(
                    inQueue: [],
                    completed: [],
                    currentlyPrinting: nil,
                    isPrintingStarted: false
                )
            },
            set: { newValue in
                queues[selectedQueue] = newValue
            }
        )
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Binding var selectedQueue: QueueName
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("QUEUES")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.labelTertiary)
                .tracking(0.5)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            ForEach(QueueName.allCases) { queue in
                Button {
                    selectedQueue = queue
                } label: {
                    HStack {
                        Text(queue.rawValue)
                            .font(.system(size: 13))
                            .foregroundColor(
                                selectedQueue == queue
                                ? AppTheme.labelPrimary
                                : AppTheme.labelSecondary
                            )
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedQueue == queue ? AppTheme.controlBackground : .clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Divider()
                .overlay(AppTheme.separator)

            Button {
                showSettings = true
            } label: {
                HStack {
                    Text("Settings")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.labelPrimary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.controlBackground)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(AppTheme.sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Queue Panels

struct QueuePanel: View {
    let title: String
    let jobs: [PrintJob]

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: title)

                ScrollView {
                    VStack(spacing: 0) {
                        if jobs.isEmpty {
                            EmptyStateRow(text: "No items")
                        } else {
                            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                                QueueRow(job: job, showDivider: index < jobs.count - 1)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CompletedPanel: View {
    let title: String
    let jobs: [CompletedJob]

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: title)

                ScrollView {
                    VStack(spacing: 0) {
                        if jobs.isEmpty {
                            EmptyStateRow(text: "No completed items")
                        } else {
                            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                                CompletedRow(job: job, showDivider: index < jobs.count - 1)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Current Printing Panel

struct CurrentPrintingPanel: View {
    let queueName: QueueName
    @Binding var queueState: QueueState
    @Binding var showQtyConfirmation: Bool
    @Binding var pendingQtyConfirmationJob: PrintJob?
    let setImportStatusMessage: (String) -> Void

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Currently Printing")

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentJobName)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(AppTheme.labelPrimary)

                        Text("\(queueName.rawValue) • Qty: \(currentQty)")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.labelSecondary)
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.controlBackground)

                        Text("Design Preview")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.labelTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)

                    if currentHasFileError {
                        Button("Locate File") {
                            locateFileForCurrentJob()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Spacer()

                    if currentOrNextJob != nil {
                        if !queueState.isPrintingStarted {
                            if currentHasFileError {
                                Button("Start Printing") {}
                                    .buttonStyle(DisabledButtonStyle())
                                    .disabled(true)
                            } else {
                                Button("Start Printing") {
                                    startPrinting()
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        } else {
                            HStack(spacing: 12) {
                                Button("Skip") {
                                    skipCurrent()
                                }
                                .buttonStyle(SecondaryButtonStyle())

                                Button("Done") {
                                    doneCurrent()
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                    } else {
                        Button("Start Printing") {}
                            .buttonStyle(DisabledButtonStyle())
                    }
                }
                .padding(24)
            }
        }
    }

    private var currentOrNextJob: PrintJob? {
        queueState.currentlyPrinting ?? queueState.inQueue.first
    }

    private var currentJobName: String {
        currentOrNextJob?.name ?? "Nothing in queue"
    }

    private var currentQty: Int {
        currentOrNextJob?.qty ?? 0
    }

    private var currentHasFileError: Bool {
        currentOrNextJob?.hasMissingFileError ?? false
    }

    private func startPrinting() {
        if queueState.currentlyPrinting == nil, !queueState.inQueue.isEmpty {
            queueState.currentlyPrinting = queueState.inQueue.removeFirst()
        }

        guard let current = queueState.currentlyPrinting else {
            return
        }

        let result = PrintAutomation.runPythonPrint(for: current.activePath)

        switch result {
        case .success:
            queueState.isPrintingStarted = true
            setImportStatusMessage("Print started for \(current.name)")
        case .failure(let errorMessage):
            queueState.isPrintingStarted = false
            setImportStatusMessage("Failed to start print: \(errorMessage)")
        }
    }

    private func skipCurrent() {
        guard let current = queueState.currentlyPrinting else { return }
        queueState.completed.append(
            CompletedJob(name: current.name, qty: current.qty, wasSkipped: true)
        )
        queueState.currentlyPrinting = nil
        queueState.isPrintingStarted = false
    }

    private func doneCurrent() {
        guard let current = queueState.currentlyPrinting else { return }

        if current.qty > 1 {
            pendingQtyConfirmationJob = current
            showQtyConfirmation = true
        } else {
            queueState.completed.append(
                CompletedJob(name: current.name, qty: current.qty, wasSkipped: false)
            )
            queueState.currentlyPrinting = nil
            queueState.isPrintingStarted = false
        }
    }

    private func locateFileForCurrentJob() {
        guard var job = currentOrNextJob else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "arxp")].compactMap { $0 }

        if panel.runModal() == .OK, let url = panel.url {
            job.localOverridePath = url.path
            job.hasMissingFileError = false
            job.errorMessage = nil

            if queueState.currentlyPrinting?.id == job.id {
                queueState.currentlyPrinting = job
            } else if let index = queueState.inQueue.firstIndex(where: { $0.id == job.id }) {
                queueState.inQueue[index] = job
            }
        }
    }
}

// MARK: - Reusable Views

struct PanelCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(AppTheme.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

struct PanelHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.labelPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .overlay(AppTheme.separator)
        }
    }
}

struct QueueRow: View {
    let job: PrintJob
    let showDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.labelPrimary)

                    Text("Qty: \(job.qty)")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.labelSecondary)
                }

                Spacer()

                if job.hasMissingFileError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(job.hasMissingFileError ? Color.red.opacity(0.15) : Color.clear)

            if showDivider {
                Divider()
                    .overlay(AppTheme.separator)
            }
        }
    }
}

struct CompletedRow: View {
    let job: CompletedJob
    let showDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.labelPrimary)

                    Text("Qty: \(job.qty)")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.labelSecondary)
                }

                Spacer()

                Text(job.wasSkipped ? "✕" : "✓")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(job.wasSkipped ? .red : .green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Divider()
                    .overlay(AppTheme.separator)
            }
        }
    }
}

struct EmptyStateRow: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.labelTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SettingsView: View {
    @Binding var showSettings: Bool
    let resolvedBasePath: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(AppTheme.labelPrimary)

                Spacer()

                Button("Close") {
                    showSettings = false
                }
                .buttonStyle(SecondaryButtonStyle(fixedWidth: 88))
            }
            .padding(20)

            Divider()
                .overlay(AppTheme.separator)

            VStack(alignment: .leading, spacing: 12) {
                Text("Detected Base Path")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.labelPrimary)

                Text(resolvedBasePath ?? "No valid Google Drive path found")
                    .font(.system(size: 12))
                    .foregroundColor(resolvedBasePath == nil ? .red : AppTheme.labelSecondary)

                Spacer()
            }
            .padding(20)
        }
        .frame(width: 520, height: 320)
        .background(AppTheme.windowBackground)
    }
}

// MARK: - Theme

enum AppTheme {
    static let windowBackground = Color(red: 30/255, green: 30/255, blue: 30/255)
    static let contentBackground = Color(red: 20/255, green: 20/255, blue: 20/255)
    static let controlBackground = Color(red: 42/255, green: 42/255, blue: 42/255)
    static let sidebarBackground = Color(red: 25/255, green: 25/255, blue: 25/255)

    static let labelPrimary = Color(red: 245/255, green: 245/255, blue: 247/255)
    static let labelSecondary = Color(red: 152/255, green: 152/255, blue: 157/255)
    static let labelTertiary = Color(red: 134/255, green: 134/255, blue: 139/255)

    static let accentBlue = Color(red: 0/255, green: 122/255, blue: 1)
    static let accentBlueHover = Color(red: 0/255, green: 102/255, blue: 214/255)

    static let separator = Color(red: 42/255, green: 42/255, blue: 42/255)
    static let border = Color(red: 42/255, green: 42/255, blue: 42/255)
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.accentBlueHover : AppTheme.accentBlue)
            )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var fixedWidth: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(AppTheme.labelPrimary)
            .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
            .frame(width: fixedWidth)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.controlBackground.opacity(configuration.isPressed ? 0.8 : 1.0))
            )
    }
}

struct DisabledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(AppTheme.labelTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.controlBackground.opacity(0.6))
            )
    }
}