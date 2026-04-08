
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Foundation

enum AppMetadata {
    // Bump this value whenever shipping behavior/UI changes.
    static let version = "1.0.7"
}

@main
struct BADDADApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1320, minHeight: 820)
                .onAppear {
                    WindowCoordinator.registerMainWindowIfNeeded()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowCoordinator.registerMainWindowIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowCoordinator.bringMainWindowToFront()
        return true
    }
}

enum WindowCoordinator {
    private static weak var mainWindow: NSWindow?

    static func registerMainWindowIfNeeded() {
        DispatchQueue.main.async {
            let appWindows = NSApp.windows.filter { !($0 is NSPanel) }
            if mainWindow == nil {
                mainWindow = appWindows.first
            } else if let mainWindow = mainWindow, !mainWindow.isVisible {
                self.mainWindow = appWindows.first
            }
        }
    }

    static func collapseToSingleWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let appWindows = NSApp.windows.filter { !($0 is NSPanel) }

            if mainWindow == nil {
                mainWindow = appWindows.first
            }

            guard let mainWindow = mainWindow ?? appWindows.first else { return }

            for window in appWindows where window != mainWindow {
                window.close()
            }

            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    static func bringMainWindowToFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let mainWindow = mainWindow {
                mainWindow.makeKeyAndOrderFront(nil)
            } else if let first = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                self.mainWindow = first
                first.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - Incoming Payload Models

struct IncomingPayload: Codable {
    let jobs: [IncomingJob]
}

struct IncomingJob: Codable {
    let queue: String
    let print_side: String?
    let path: String
    let qty: Int
}

// MARK: - App Models

enum TopLevelQueue: String, CaseIterable, Identifiable {
    case blackFrontDesigns = "Black Front Designs"
    case blackBackDesigns = "Black Back Designs"
    case longSleeves = "Long Sleeves"
    case singlets = "Singlets"
    case dtf = "DTF"

    var id: String { rawValue }

    var hasSubmenu: Bool {
        switch self {
        case .blackBackDesigns, .longSleeves, .singlets:
            return true
        case .blackFrontDesigns, .dtf:
            return false
        }
    }
}

enum PrintSideFilter: String, CaseIterable, Identifiable {
    case front = "Front Print"
    case back = "Back Print"

    var id: String { rawValue }

    static func fromIncoming(_ raw: String?) -> PrintSideFilter? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "front":
            return .front
        case "back":
            return .back
        default:
            return nil
        }
    }
}

struct QueueDestination: Equatable {
    let topLevel: TopLevelQueue
    let submenu: PrintSideFilter?

    static func fromIncoming(queue: String, printSide: String?) -> QueueDestination? {
        switch queue.lowercased() {
        case "black_front":
            return QueueDestination(topLevel: .blackFrontDesigns, submenu: nil)
        case "black_back":
            guard let side = PrintSideFilter.fromIncoming(printSide) else { return nil }
            return QueueDestination(topLevel: .blackBackDesigns, submenu: side)
        case "long_sleeves":
            guard let side = PrintSideFilter.fromIncoming(printSide) else { return nil }
            return QueueDestination(topLevel: .longSleeves, submenu: side)
        case "singlets":
            guard let side = PrintSideFilter.fromIncoming(printSide) else { return nil }
            return QueueDestination(topLevel: .singlets, submenu: side)
        case "dtf", "white":
            return QueueDestination(topLevel: .dtf, submenu: nil)
        default:
            return nil
        }
    }
}

struct QueueKey: Hashable {
    let topLevel: TopLevelQueue
    let submenu: PrintSideFilter?
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
    var printSide: PrintSideFilter?

    init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        resolvedPath: String,
        localOverridePath: String? = nil,
        qty: Int,
        hasMissingFileError: Bool,
        errorMessage: String? = nil,
        printSide: PrintSideFilter? = nil
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.resolvedPath = resolvedPath
        self.localOverridePath = localOverridePath
        self.qty = qty
        self.hasMissingFileError = hasMissingFileError
        self.errorMessage = errorMessage
        self.printSide = printSide
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
    let printSide: PrintSideFilter?
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
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputText = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let details = [errorText, outputText]
                    .compactMap { text -> String? in
                        guard let text, !text.isEmpty else { return nil }
                        return text
                    }
                    .joined(separator: " | ")
                let normalizedMessage = normalizedFailureMessage(
                    from: details,
                    exitCode: process.terminationStatus,
                    scriptPath: scriptPath
                )

                return .failure(
                    NSError(
                        domain: "PrintAutomation",
                        code: Int(process.terminationStatus),
                        userInfo: [
                            NSLocalizedDescriptionKey: normalizedMessage
                        ]
                    )
                )
            }

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func pythonScriptPath() -> String {
        if let bundled = Bundle.main.path(forResource: "automated_print", ofType: "py"),
           FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let appResourcesPath = executableURL
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents
            .appendingPathComponent("Resources")
            .appendingPathComponent("automated_print.py")
            .path
        if FileManager.default.fileExists(atPath: appResourcesPath) {
            return appResourcesPath
        }
        return "\(FileManager.default.currentDirectoryPath)/automated_print.py"
    }

    private static func normalizedFailureMessage(from details: String, exitCode: Int32, scriptPath: String) -> String {
        let lowered = details.lowercased()
        if lowered.contains("not allowed to send keystrokes")
            || lowered.contains("osascript is not allowed")
            || lowered.contains("system events got an error") {
            return "macOS blocked keyboard automation for the printer helper. Enable Accessibility permission for the app running this tool (Terminal or BADDAD Print Manager) in System Settings → Privacy & Security → Accessibility, then retry. If it was already enabled, remove/re-add the app entry or run 'tccutil reset Accessibility'. Script path: \(scriptPath). Raw error: \(details)"
        }
        if lowered.contains("not authorised to send apple events") {
            return "macOS blocked Apple Events automation for the printer helper. In System Settings → Privacy & Security → Automation, allow the app running this tool (Terminal or BADDAD Print Manager) to control Brother GTX File Viewer/System Events. Script path: \(scriptPath). Raw error: \(details)"
        }

        if details.isEmpty {
            return "Print helper exited with code \(exitCode). Script path: \(scriptPath)."
        }

        return "Script path: \(scriptPath). \(details)"
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

// MARK: - Preview Resolver

enum PreviewResolver {
    private static let supportedExtensions = ["png", "PNG", "jpg", "JPG", "jpeg", "JPEG", "webp", "WEBP"]

    static func resolvePreviewPath(for job: PrintJob, queueType: TopLevelQueue) -> String? {
        let fileURL = URL(fileURLWithPath: job.activePath)
        let folderURL = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent

        switch queueType {
        case .dtf:
            if let generic = findFirstExistingFile(in: folderURL, baseNames: ["preview"], exts: supportedExtensions) {
                return generic
            }

            if let specific = findFirstExistingFile(in: folderURL, baseNames: ["\(baseName)-preview"], exts: supportedExtensions) {
                return specific
            }

            return nil

        case .blackFrontDesigns, .blackBackDesigns, .longSleeves, .singlets:
            var currentFolder = folderURL

            for _ in 0...2 {
                let sideSpecificBaseNames = sideSpecificBaseNames(for: job.printSide, queueType: queueType)
                if let sideSpecific = findFirstExistingFile(in: currentFolder, baseNames: sideSpecificBaseNames, exts: supportedExtensions) {
                    return sideSpecific
                }

                if let generic = findFirstExistingFile(in: currentFolder, baseNames: ["preview"], exts: supportedExtensions) {
                    return generic
                }

                currentFolder.deleteLastPathComponent()
            }

            return nil
        }
    }

    private static func sideSpecificBaseNames(for printSide: PrintSideFilter?, queueType: TopLevelQueue) -> [String] {
        switch printSide {
        case .front:
            return ["preview-front"]
        case .back:
            return ["preview-back"]
        case .none:
            if queueType == .blackFrontDesigns {
                return ["preview-front"]
            }
            return []
        }
    }

    private static func findFirstExistingFile(in folder: URL, baseNames: [String], exts: [String]) -> String? {
        for baseName in baseNames {
            for ext in exts {
                let path = folder.appendingPathComponent("\(baseName).\(ext)").path
                if FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }
}

// MARK: - Shared App Model

final class AppModel: ObservableObject {
    @Published var selectedTopLevelQueue: TopLevelQueue = .blackFrontDesigns
    @Published var selectedPrintSideByQueue: [TopLevelQueue: PrintSideFilter] = [
        .blackBackDesigns: .front,
        .longSleeves: .front,
        .singlets: .front
    ]

    @Published var showSettings = false
    @Published var importStatusMessage: String?
    @Published var showQtyConfirmation = false
    @Published var pendingQtyConfirmationJob: PrintJob?
    @Published var showClearQueueModal = false
    @Published var queues: [QueueKey: QueueState] = AppModel.makeInitialQueues()

    static func makeInitialQueues() -> [QueueKey: QueueState] {
        var states: [QueueKey: QueueState] = [:]

        for topLevel in TopLevelQueue.allCases {
            if topLevel.hasSubmenu {
                states[QueueKey(topLevel: topLevel, submenu: .front)] = QueueState(
                    inQueue: [],
                    completed: [],
                    currentlyPrinting: nil,
                    isPrintingStarted: false
                )
                states[QueueKey(topLevel: topLevel, submenu: .back)] = QueueState(
                    inQueue: [],
                    completed: [],
                    currentlyPrinting: nil,
                    isPrintingStarted: false
                )
            } else {
                states[QueueKey(topLevel: topLevel, submenu: nil)] = QueueState(
                    inQueue: [],
                    completed: [],
                    currentlyPrinting: nil,
                    isPrintingStarted: false
                )
            }
        }

        return states
    }

    var activeQueueKey: QueueKey {
        if selectedTopLevelQueue.hasSubmenu {
            let side = selectedPrintSideByQueue[selectedTopLevelQueue] ?? .front
            return QueueKey(topLevel: selectedTopLevelQueue, submenu: side)
        } else {
            return QueueKey(topLevel: selectedTopLevelQueue, submenu: nil)
        }
    }

    var activeQueueDisplayName: String {
        if let submenu = activeQueueKey.submenu {
            return "\(activeQueueKey.topLevel.rawValue) — \(submenu.rawValue)"
        }
        return activeQueueKey.topLevel.rawValue
    }

    func clearSelectedQueue() {
        queues[activeQueueKey] = QueueState(
            inQueue: [],
            completed: [],
            currentlyPrinting: nil,
            isPrintingStarted: false
        )
    }

    func clearAllQueues() {
        for key in queues.keys {
            queues[key] = QueueState(
                inQueue: [],
                completed: [],
                currentlyPrinting: nil,
                isPrintingStarted: false
            )
        }
    }

    func confirmQtyCompletion(for job: PrintJob) {
        guard let queueKey = queues.first(where: { $0.value.currentlyPrinting?.id == job.id })?.key else { return }
        var state = queues[queueKey]!

        state.completed.append(
            CompletedJob(name: job.name, qty: job.qty, wasSkipped: false, printSide: job.printSide)
        )
        state.currentlyPrinting = nil
        state.isPrintingStarted = false

        if !state.inQueue.isEmpty {
            let nextJob = state.inQueue.removeFirst()
            state.currentlyPrinting = nextJob

            let result = PrintAutomation.runPythonPrint(for: nextJob.activePath)

            switch result {
            case .success:
                state.isPrintingStarted = true
                importStatusMessage = "Print started for \(nextJob.name)"
            case .failure(let error):
                state.isPrintingStarted = false
                importStatusMessage = "Failed to start print: \(error.localizedDescription)"
            }
        }

        queues[queueKey] = state
        pendingQtyConfirmationJob = nil
    }

    func handleIncomingURL(_ url: URL) {
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
        var firstDestination: QueueDestination?

        for incoming in incomingJobs {
            guard let destination = QueueDestination.fromIncoming(queue: incoming.queue, printSide: incoming.print_side) else {
                skippedCount += 1
                continue
            }

            if firstDestination == nil {
                firstDestination = destination
            }

            let key = QueueKey(topLevel: destination.topLevel, submenu: destination.submenu)
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
                errorMessage: exists ? nil : "File not found",
                printSide: destination.submenu
            )

            var state = queues[key] ?? QueueState(
                inQueue: [],
                completed: [],
                currentlyPrinting: nil,
                isPrintingStarted: false
            )

            state.inQueue.append(job)

            queues[key] = state
            importedCount += 1
        }

        if let firstDestination {
            selectedTopLevelQueue = firstDestination.topLevel
            if let submenu = firstDestination.submenu {
                selectedPrintSideByQueue[firstDestination.topLevel] = submenu
            }
        }

        importStatusMessage = "Imported \(importedCount) job(s)\(skippedCount > 0 ? " • Skipped \(skippedCount)" : "")"
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            mainContent
            clearQueueOverlay
        }
        .onOpenURL { url in
            model.handleIncomingURL(url)
            WindowCoordinator.bringMainWindowToFront()
            WindowCoordinator.collapseToSingleWindow()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            TopBar(showClearQueueModal: $model.showClearQueueModal)
            Divider()
            statusBanner
            MainLayout()
        }
        .background(AppTheme.contentBackground)
        .sheet(isPresented: $model.showSettings) {
            SettingsView(
                showSettings: $model.showSettings,
                resolvedBasePath: PathResolver.detectBasePath()
            )
        }
        .alert("Did you print the correct QTY?", isPresented: $model.showQtyConfirmation, presenting: model.pendingQtyConfirmationJob) { job in
            Button("No", role: .cancel) {}
            Button("Yes") {
                model.confirmQtyCompletion(for: job)
            }
        } message: { job in
            Text("\(job.name) — Qty: \(job.qty)")
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let importStatusMessage = model.importStatusMessage, !importStatusMessage.isEmpty {
            HStack {
                Text(importStatusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.labelPrimary)
                    .textSelection(.enabled)
                Spacer()

                Button("Copy") {
                    copyToClipboard(importStatusMessage)
                }
                .buttonStyle(SecondaryButtonStyle(fixedWidth: 64))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.controlBackground)
        }
    }

    @ViewBuilder
    private var clearQueueOverlay: some View {
        if model.showClearQueueModal {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            ClearQueueModal(
                queueName: model.activeQueueDisplayName,
                onClearAll: {
                    model.clearAllQueues()
                    model.showClearQueueModal = false
                },
                onClearThisQueue: {
                    model.clearSelectedQueue()
                    model.showClearQueueModal = false
                },
                onCancel: {
                    model.showClearQueueModal = false
                }
            )
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Top Bar

struct TopBar: View {
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
        if let url = Bundle.main.url(forResource: "productionmanagerlogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

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
        .frame(width: 380)
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
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Sidebar()
                .frame(width: 250)

            VStack(spacing: 12) {
                QueuePanel(title: "In Queue", jobs: currentState.inQueue)
                CompletedPanel(title: "Completed", jobs: currentState.completed)
            }

            CurrentPrintingPanel(
                queueTitle: currentQueueDisplayName,
                queueType: activeQueueKey.topLevel,
                queueState: bindingForSelectedQueue(),
                showQtyConfirmation: $model.showQtyConfirmation,
                pendingQtyConfirmationJob: $model.pendingQtyConfirmationJob,
                setImportStatusMessage: { message in
                    model.importStatusMessage = message
                }
            )
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(AppTheme.contentBackground)
    }

    private var activeQueueKey: QueueKey {
        model.activeQueueKey
    }

    private var currentQueueDisplayName: String {
        model.activeQueueDisplayName
    }

    private var currentState: QueueState {
        model.queues[activeQueueKey] ?? QueueState(
            inQueue: [],
            completed: [],
            currentlyPrinting: nil,
            isPrintingStarted: false
        )
    }

    private func bindingForSelectedQueue() -> Binding<QueueState> {
        let key = activeQueueKey

        return Binding(
            get: {
                model.queues[key] ?? QueueState(
                    inQueue: [],
                    completed: [],
                    currentlyPrinting: nil,
                    isPrintingStarted: false
                )
            },
            set: { newValue in
                model.queues[key] = newValue
            }
        )
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            queuesHeader
            queueButtons
            Spacer()
            footerSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(AppTheme.sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var queuesHeader: some View {
        Text("QUEUES")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(AppTheme.labelTertiary)
            .tracking(0.5)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
    }

    private var queueButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(TopLevelQueue.allCases) { queue in
                QueueMenuSection(queue: queue)
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            Divider()
                .overlay(AppTheme.separator)

            Button {
                model.showSettings = true
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
        }
    }
}

struct QueueMenuSection: View {
    @EnvironmentObject private var model: AppModel
    let queue: TopLevelQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            topLevelButton
            submenuButtons
        }
    }

    private var topLevelButton: some View {
        Button {
            model.selectedTopLevelQueue = queue
        } label: {
            HStack {
                Text(queue.rawValue)
                    .font(.system(size: 13))
                    .foregroundColor(topLevelTextColor)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(topLevelBackgroundColor)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var submenuButtons: some View {
        if queue.hasSubmenu {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(PrintSideFilter.allCases) { side in
                    submenuButton(for: side)
                }
            }
        }
    }

    private func submenuButton(for side: PrintSideFilter) -> some View {
        Button {
            model.selectedTopLevelQueue = queue
            model.selectedPrintSideByQueue[queue] = side
        } label: {
            HStack {
                Text(side.rawValue)
                    .font(.system(size: 12))
                    .foregroundColor(submenuTextColor(for: side))
                Spacer()
            }
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(submenuBackgroundColor(for: side))
            )
        }
        .buttonStyle(.plain)
    }

    private var topLevelTextColor: Color {
        model.selectedTopLevelQueue == queue ? AppTheme.labelPrimary : AppTheme.labelSecondary
    }

    private var topLevelBackgroundColor: Color {
        model.selectedTopLevelQueue == queue ? AppTheme.controlBackground : .clear
    }

    private func submenuTextColor(for side: PrintSideFilter) -> Color {
        (model.selectedTopLevelQueue == queue && model.selectedPrintSideByQueue[queue] == side) ? AppTheme.labelPrimary : AppTheme.labelSecondary
    }

    private func submenuBackgroundColor(for side: PrintSideFilter) -> Color {
        (model.selectedTopLevelQueue == queue && model.selectedPrintSideByQueue[queue] == side) ? AppTheme.controlBackground.opacity(0.85) : .clear
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
    let queueTitle: String
    let queueType: TopLevelQueue
    @Binding var queueState: QueueState
    @Binding var showQtyConfirmation: Bool
    @Binding var pendingQtyConfirmationJob: PrintJob?
    let setImportStatusMessage: (String) -> Void

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Currently Printing")

                VStack(alignment: .leading, spacing: 24) {
                    headerInfo
                    previewBox
                    locateFileSection
                    Spacer()
                    actionSection
                }
                .padding(24)
            }
        }
    }

    private var headerInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(currentJobName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(AppTheme.labelPrimary)

            Text("\(queueTitle) • Qty: \(currentQty)")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.labelSecondary)

            if currentHasFileError {
                Text("Missing file")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
        }
    }

    private var previewBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.controlBackground)

            if let previewImagePath = currentPreviewImagePath,
               let image = NSImage(contentsOfFile: previewImagePath) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            } else {
                Text("Design Preview")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.labelTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }

    @ViewBuilder
    private var locateFileSection: some View {
        if currentHasFileError {
            Button("Locate File") {
                locateFileForCurrentJob()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if queueState.currentlyPrinting != nil || !queueState.inQueue.isEmpty {
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

    private var currentJob: PrintJob? {
        queueState.currentlyPrinting
    }

    private var currentJobName: String {
        currentJob?.name ?? "Nothing in queue"
    }

    private var currentQty: Int {
        currentJob?.qty ?? 0
    }

    private var currentHasFileError: Bool {
        currentJob?.hasMissingFileError ?? false
    }

    private var currentPreviewImagePath: String? {
        guard let job = currentJob else { return nil }
        return PreviewResolver.resolvePreviewPath(for: job, queueType: queueType)
    }

    private func startPrinting() {
        if queueState.currentlyPrinting == nil, !queueState.inQueue.isEmpty {
            queueState.currentlyPrinting = queueState.inQueue.removeFirst()
        }

        guard let current = queueState.currentlyPrinting else { return }

        let result = PrintAutomation.runPythonPrint(for: current.activePath)

        switch result {
        case .success:
            queueState.isPrintingStarted = true
            setImportStatusMessage("Print started for \(current.name)")
        case .failure(let error):
            queueState.isPrintingStarted = false
            setImportStatusMessage("Failed to start print: \(error.localizedDescription)")
        }
    }

    private func skipCurrent() {
        guard let current = queueState.currentlyPrinting else { return }

        queueState.completed.append(
            CompletedJob(name: current.name, qty: current.qty, wasSkipped: true, printSide: current.printSide)
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
                CompletedJob(name: current.name, qty: current.qty, wasSkipped: false, printSide: current.printSide)
            )

            queueState.currentlyPrinting = nil
            queueState.isPrintingStarted = false

            if !queueState.inQueue.isEmpty {
                let nextJob = queueState.inQueue.removeFirst()
                queueState.currentlyPrinting = nextJob

                let result = PrintAutomation.runPythonPrint(for: nextJob.activePath)

                switch result {
                case .success:
                    queueState.isPrintingStarted = true
                    setImportStatusMessage("Print started for \(nextJob.name)")
                case .failure(let error):
                    queueState.isPrintingStarted = false
                    setImportStatusMessage("Failed to start print: \(error.localizedDescription)")
                }
            }
        }
    }

    private func locateFileForCurrentJob() {
        guard var job = currentJob else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if let type = UTType(filenameExtension: "arxp") {
            panel.allowedContentTypes = [type]
        }

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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings — Version \(AppMetadata.version)")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AppTheme.labelPrimary)
                }

                Spacer()

                Text("v\(AppMetadata.version)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.labelPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.controlBackground)
                    )

                Button("Close") {
                    showSettings = false
                }
                .buttonStyle(SecondaryButtonStyle(fixedWidth: 88))
            }
            .padding(20)

            Divider()
                .overlay(AppTheme.separator)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("App Version:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.labelPrimary)
                    Text(AppMetadata.version)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(AppTheme.labelPrimary)
                        .textSelection(.enabled)
                }

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
