//
//  LumiAgentApp.swift
//  LumiAgent
//
//  Created by Lumi Agent on 2026-02-18.
//

import SwiftUI

@main
struct LumiAgentApp: App {
    // MARK: - Properties

    @StateObject private var appState = AppState()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    init() {
        // App initialization
        #if os(macOS)
        setupBundleIdentifier()
        #endif
    }

    #if os(macOS)
    private func setupBundleIdentifier() {
        // Check bundle identifier - critical for macOS system APIs
        let bundleID = Bundle.main.bundleIdentifier
        if bundleID == nil || bundleID?.isEmpty == true {
            print("⚠️ WARNING: Bundle identifier is not set!")
            print("⚠️ This will cause crashes when using screen control, keyboard/mouse events.")
            print("⚠️ Please set CFBundleIdentifier in your Info.plist or Xcode project settings.")
            print("⚠️ Recommended: com.lumiagent.app")
            
            // For development, you can try setting it via environment
            // Note: This doesn't always work and is not a proper solution
            if let envBundleID = ProcessInfo.processInfo.environment["PRODUCT_BUNDLE_IDENTIFIER"] {
                print("⚙️ Found bundle ID in environment: \(envBundleID)")
                // Unfortunately, we can't set Bundle.main.bundleIdentifier at runtime
                // You must configure it in your Xcode project or Info.plist
            }
        } else {
            print("✅ Bundle identifier: \(bundleID!)")
        }
    }
    #endif

    // MARK: - Body

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .commands {
            LumiAgentCommands(
                selectedSidebarItem: $appState.selectedSidebarItem,
                appState: appState
            )
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #else
        WindowGroup {
            #if os(iOS)
            iOSMainView()
                .environmentObject(appState)
            #else
            Text("LumiAgent is only available on macOS and iOS")
                .font(.title2)
                .foregroundStyle(.secondary)
            #endif
        }
        #endif
    }
}

// MARK: - Screen Capture

/// Tool names that visually change the screen — a screenshot is sent to the AI after these.
private let screenControlToolNames: Set<String> = [
    "open_application", "click_mouse", "scroll_mouse",
    "type_text", "press_key", "run_applescript", "take_screenshot"
]

#if os(macOS)
/// Captures a specific display and returns JPEG data for direct AI vision input.
/// `displayID` should be the CGDirectDisplayID of the target screen.
/// Runs synchronously — call from a background thread / Task.detached.
private func captureScreenAsJPEG(maxWidth: CGFloat = 1440, displayID: UInt32? = nil) -> Data? {
    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("lumi_vision_\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    // Target the specific display so multi-monitor setups don't composite all screens.
    if let id = displayID {
        proc.arguments = ["-x", "-D", "\(id)", tmpURL.path]
    } else {
        proc.arguments = ["-x", "-m", tmpURL.path]
    }
    guard (try? proc.run()) != nil else { return nil }
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }

    guard let src = CGImageSourceCreateWithURL(tmpURL as CFURL, nil),
          let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }

    let origW = CGFloat(cg.width), origH = CGFloat(cg.height)
    let scale = min(1.0, maxWidth / origW)
    let tw = Int(origW * scale), th = Int(origH * scale)

    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
    guard let scaled = ctx.makeImage() else { return nil }

    return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.82])
}

/// Captures the frontmost non-Lumi window and returns JPEG data.
/// Falls back to full-screen capture if the window ID cannot be determined.
/// Runs synchronously — call from a background thread / Task.detached.
private func captureWindowAsJPEG(maxWidth: CGFloat = 1440) -> Data? {
    // Find the frontmost window that isn't ours
    let myPID = ProcessInfo.processInfo.processIdentifier
    let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[CFString: Any]] ?? []

    var targetWindowID: CGWindowID?
    for info in windowList {
        guard let pid = info[kCGWindowOwnerPID] as? Int32,
              pid != myPID,
              let layer = info[kCGWindowLayer] as? Int,
              layer == 0, // normal window layer
              let wid = info[kCGWindowNumber] as? CGWindowID else { continue }
        targetWindowID = wid
        break
    }

    guard let windowID = targetWindowID else {
        // Fall back to full-screen capture
        return captureScreenAsJPEG(maxWidth: maxWidth)
    }

    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("lumi_window_\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = ["-x", "-l", "\(windowID)", tmpURL.path]
    guard (try? proc.run()) != nil else { return captureScreenAsJPEG(maxWidth: maxWidth) }
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return captureScreenAsJPEG(maxWidth: maxWidth) }

    guard let src = CGImageSourceCreateWithURL(tmpURL as CFURL, nil),
          let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        return captureScreenAsJPEG(maxWidth: maxWidth)
    }

    let origW = CGFloat(cg.width), origH = CGFloat(cg.height)
    let scale = min(1.0, maxWidth / origW)
    let tw = Int(origW * scale), th = Int(origH * scale)

    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
    guard let scaled = ctx.makeImage() else { return nil }

    return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.82])
}
#else
/// iOS version - screenshot capture not available on iOS
private func captureScreenAsJPEG(maxWidth: CGFloat = 1440, displayID: UInt32? = nil) -> Data? {
    // Screen capture is restricted on iOS for privacy reasons
    // This would require using the ReplayKit framework for in-app capture
    return nil
}
#endif

// MARK: - App State

// MARK: - Tool Call Record

struct ToolCallRecord: Identifiable {
    let id: UUID
    let agentId: UUID
    let agentName: String
    let toolName: String
    let arguments: [String: String]
    let result: String
    let timestamp: Date
    let success: Bool

    init(agentId: UUID, agentName: String, toolName: String,
         arguments: [String: String], result: String, success: Bool) {
        self.id = UUID()
        self.agentId = agentId
        self.agentName = agentName
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.timestamp = Date()
        self.success = success
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var selectedSidebarItem: SidebarItem = .agents
    @Published var selectedAgentId: UUID?
    @Published var agents: [Agent] = []
    @Published var showingNewAgent = false
    @Published var showingSettings = false

    // MARK: - Agent Space
    @Published var conversations: [Conversation] = [] {
        didSet { saveConversations() }
    }
    @Published var selectedConversationId: UUID?

    // MARK: - Tool Call History
    @Published var toolCallHistory: [ToolCallRecord] = []
    @Published var selectedHistoryAgentId: UUID?

    // MARK: - Automations
    @Published var automations: [AutomationRule] = [] {
        didSet { saveAutomations() }
    }
    @Published var selectedAutomationId: UUID?

    // MARK: - Settings navigation (sidebar → detail pane)
    @Published var selectedSettingsSection: String? = "apiKeys"

    // MARK: - Health
    @Published var selectedHealthCategory: HealthCategory? = .activity

    // MARK: - Screen Control State
    /// True while the agent is actively running tools in Agent Mode.
    @Published var isAgentControllingScreen = false
    /// Counts concurrent screen-control agents so the flag clears only when all finish.
    private var screenControlCount = 0
    /// Stored Task handles so we can cancel them from the Stop button.
    private var screenControlTasks: [Task<Void, Never>] = []

    private let conversationsKey  = "lumiagent.conversations"
    private let automationsKey    = "lumiagent.automations"
    #if os(macOS)
    private var automationEngine: AutomationEngine?
    #endif

    init() {
        _ = DatabaseManager.shared
        loadAgents()
        loadConversations()
        loadAutomations()
        #if os(macOS)
        // Register ⌘L global hotkey after init completes
        DispatchQueue.main.async { [weak self] in
            self?.setupGlobalHotkey()
            self?.startAutomationEngine()
        }
        #endif
    }

    #if os(macOS)
    // MARK: - Global Hotkey

    private func setupGlobalHotkey() {
        // Use Carbon RegisterEventHotKey so the shortcut is truly intercepted
        // globally — it never reaches the frontmost app.
        // Default: ⌥⌘L (Option + Command + L). Override by calling
        // GlobalHotkeyManager.shared.register(keyCode:modifiers:) in AppDelegate.
        GlobalHotkeyManager.shared.onActivate = { [weak self] in
            self?.toggleCommandPalette()
        }
        GlobalHotkeyManager.shared.register()

        // Secondary: Ctrl+L — Quick Action Panel
        GlobalHotkeyManager.shared.onActivate2 = { [weak self] in
            self?.toggleQuickActionPanel()
        }
        GlobalHotkeyManager.shared.registerSecondary(
            keyCode: GlobalHotkeyManager.KeyCode.L,
            modifiers: GlobalHotkeyManager.Modifiers.control
        )
    }

    func toggleCommandPalette() {
        CommandPaletteController.shared.toggle(agents: agents) { [weak self] text, agentId in
            self?.sendCommandPaletteMessage(text: text, agentId: agentId)
        }
    }

    func toggleQuickActionPanel() {
        QuickActionPanelController.shared.toggle { [weak self] actionType in
            self?.sendQuickAction(type: actionType)
        }
    }

    func sendQuickAction(type: QuickActionType) {
        guard let targetAgent = agents.first else {
            print("⚠️ No agents available for quick action")
            return
        }

        // Show the corner reply bubble immediately
        DispatchQueue.main.async {
            AgentReplyBubbleController.shared.show(initialText: "Processing...")
        }

        // Run entirely in the background — no focus steal, no screen-control overlay.
        // The agent acts directly on the current page.
        Task {
            let jpeg: Data? = await Task.detached(priority: .userInitiated) {
                switch type {
                case .analyzePage:
                    return captureWindowAsJPEG(maxWidth: 1440)
                case .thinkAndWrite, .writeNew:
                    return captureScreenAsJPEG(maxWidth: 1440)
                }
            }.value

            // Detect active app and gather iWork context if applicable
            let (prompt, _) = await buildQuickActionPrompt(type: type)

            // Find or create DM (updates conversation list but doesn't navigate to it)
            let convId: UUID
            if let existing = conversations.first(where: { !$0.isGroup && $0.participantIds == [targetAgent.id] }) {
                convId = existing.id
            } else {
                let conv = Conversation(participantIds: [targetAgent.id])
                conversations.insert(conv, at: 0)
                convId = conv.id
            }

            guard let convIndex = conversations.firstIndex(where: { $0.id == convId }) else { return }

            let userMsg = SpaceMessage(role: .user, content: prompt, imageData: jpeg)
            conversations[convIndex].messages.append(userMsg)
            conversations[convIndex].updatedAt = Date()

            let history = conversations[convIndex].messages.filter { !$0.isStreaming }
            await streamResponse(from: targetAgent, in: convId,
                                 history: history, agentMode: true)
        }
    }

    /// Build smart prompt for Quick Action, detecting iWork apps and gathering context.
    private func buildQuickActionPrompt(type: QuickActionType) async -> (String, String?) {
        let activeApp = getActiveApplication()

        if isIWorkApp(bundleId: activeApp) {
            let (docInfo, docContent) = await getIWorkDocumentInfo()
            let iworkContext = buildIWorkContext(app: activeApp, docInfo: docInfo, docContent: docContent, actionType: type)
            let enhancedPrompt = type.prompt + "\n\n" + iworkContext
            return (enhancedPrompt, iworkContext)
        }

        return (type.prompt, nil)
    }

    /// Get the bundle identifier of the frontmost application.
    private func getActiveApplication() -> String {
        let workspace = NSWorkspace.shared
        if let frontmost = workspace.frontmostApplication {
            return frontmost.bundleIdentifier ?? ""
        }
        return ""
    }

    /// Check if a bundle ID is an iWork app.
    private func isIWorkApp(bundleId: String) -> Bool {
        let iworkBundleIds = [
            "com.apple.iWork.Pages",
            "com.apple.iWork.Numbers",
            "com.apple.iWork.Keynote",
            "com.apple.creativestudio.keynote",  // New Keynote
        ]
        return iworkBundleIds.contains(bundleId)
    }

    /// Get info and full text content from the active iWork document.
    private func getIWorkDocumentInfo() async -> (info: String, content: String) {
        let infoScript = """
        tell application "System Events"
            set frontmostApp to name of (first application process whose frontmost is true)
        end tell

        if frontmostApp contains "Pages" then
            tell application "Pages"
                if (count of documents) > 0 then
                    set activeDoc to document 1
                    set docName to name of activeDoc
                    return "Document: " & docName
                else
                    return "No active Pages document"
                end if
            end tell
        else if frontmostApp contains "Numbers" then
            tell application "Numbers"
                if (count of documents) > 0 then
                    set activeDoc to document 1
                    set docName to name of activeDoc
                    return "Spreadsheet: " & docName
                else
                    return "No active Numbers document"
                end if
            end tell
        else if frontmostApp contains "Keynote" then
            tell application "Keynote"
                if (count of presentations) > 0 then
                    set activePresentation to presentation 1
                    set docName to name of activePresentation
                    return "Presentation: " & docName
                else
                    return "No active Keynote presentation"
                end if
            end tell
        else
            return "Unknown iWork app"
        end if
        """

        let contentScript = """
        tell application "System Events"
            set frontmostApp to name of (first application process whose frontmost is true)
        end tell

        if frontmostApp contains "Pages" then
            tell application "Pages"
                if (count of documents) > 0 then
                    set activeDoc to document 1
                    set allText to text of activeDoc
                    return allText
                else
                    return "No content"
                end if
            end tell
        else if frontmostApp contains "Numbers" then
            tell application "Numbers"
                if (count of documents) > 0 then
                    set activeDoc to document 1
                    set allText to text of activeDoc
                    return allText
                else
                    return "No content"
                end if
            end tell
        else if frontmostApp contains "Keynote" then
            return "(Keynote presentations cannot be easily extracted as text)"
        else
            return "Unknown content"
        end if
        """

        var info = "Unknown"
        var content = ""

        do {
            info = try await ScreenControlTools.runAppleScript(script: infoScript)
            content = try await ScreenControlTools.runAppleScript(script: contentScript)
        } catch {
            info = "Could not get iWork document info"
            content = ""
        }

        return (info, content)
    }

    /// Build iWork-specific context message for the agent.
    private func buildIWorkContext(app: String, docInfo: String, docContent: String, actionType: QuickActionType) -> String {
        let appName = app.contains("Keynote") ? "Keynote" :
                     app.contains("Numbers") ? "Numbers" : "Pages"

        let contentSection = !docContent.isEmpty && docContent != "(Keynote presentations cannot be easily extracted as text)" && docContent != "No content"
            ? """

            ═══ DOCUMENT CONTENT ═══
            \(docContent.prefix(5000))
            \(docContent.count > 5000 ? "\n... (content truncated)" : "")
            """
            : ""

        switch actionType {
        case .analyzePage:
            return """
            You are working with \(appName). \(docInfo)

            ═══ TASK: PROOFREAD AND FIX ═══
            Review the entire document content below for:
            1. TYPOS and spelling errors
            2. GRAMMAR issues and awkward phrasing
            3. WEIRD or out-of-place words that don't fit
            4. FORMATTING inconsistencies
            5. CLARITY improvements

            If you find issues:
            - Use iwork_replace_text to fix typos and grammar
            - Use iwork_write_text to add clarifications or rephrase awkward sections
            - Suggest any other improvements
            \(contentSection)

            IMPORTANT: Be thorough and fix all issues you find.
            """

        case .thinkAndWrite:
            return """
            You are working with \(appName). \(docInfo)

            ═══ TASK: EDIT AND IMPROVE ═══
            Review the document content and:
            1. Identify any typos, grammar errors, or unclear passages
            2. Fix them using the iWork tools
            3. Suggest improvements to clarity and flow
            4. Use iwork_replace_text, iwork_write_text, or iwork_insert_after_anchor as needed

            TOOLS AVAILABLE:
            - iwork_replace_text: Find and fix specific text
            - iwork_write_text: Add or rewrite content
            - iwork_insert_after_anchor: Insert text after a specific location
            \(contentSection)

            Be proactive and fix issues directly without asking for permission.
            """

        case .writeNew:
            return """
            You are working with \(appName). \(docInfo)

            ═══ TASK: REVIEW AND ENHANCE ═══
            Read the current content and:
            1. Check for any spelling, grammar, or clarity issues
            2. Identify opportunities to enhance or expand the content
            3. Use the iWork tools to make improvements:
               - iwork_replace_text: Fix errors and improve wording
               - iwork_write_text: Add new content
               - iwork_insert_after_anchor: Insert content at specific locations

            Make it the best version possible.
            \(contentSection)

            Fix all issues you find automatically.
            """
        }
    }
    #endif

    /// Routes a command-palette submission into the normal agent-mode send path.
    func sendCommandPaletteMessage(text: String, agentId: UUID?) {
        let targetId = agentId ?? agents.first?.id
        guard let targetId, agents.contains(where: { $0.id == targetId }) else { return }

        // Find or create a DM with the target agent, then send in agent mode
        let conv = createDM(agentId: targetId)
        sendMessage(text, in: conv.id, agentMode: true)

        // Bring our window to front so the user sees the response
        #if os(macOS)
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }

    // MARK: - Automation management

    #if os(macOS)
    private func startAutomationEngine() {
        automationEngine = AutomationEngine { [weak self] rule in
            self?.fireAutomation(rule)
        }
        automationEngine?.update(rules: automations)
    }
    #endif

    func createAutomation() {
        let rule = AutomationRule(agentId: agents.first?.id)
        automations.insert(rule, at: 0)
        selectedAutomationId = rule.id
    }

    func runAutomation(id: UUID) {
        guard let rule = automations.first(where: { $0.id == id }) else { return }
        #if os(macOS)
        automationEngine?.runManually(rule)
        #endif
    }

    private func fireAutomation(_ rule: AutomationRule) {
        guard rule.isEnabled, let agentId = rule.agentId else { return }
        let prompt = rule.notes.isEmpty
            ? "Execute the automation titled: \"\(rule.title)\""
            : "Execute this automation task:\n\n\(rule.notes)"
        sendCommandPaletteMessage(text: prompt, agentId: agentId)
        // Record last-run timestamp
        if let idx = automations.firstIndex(where: { $0.id == rule.id }) {
            automations[idx].lastRunAt = Date()
        }
    }

    private func loadAutomations() {
        guard let data = UserDefaults.standard.data(forKey: automationsKey),
              let saved = try? JSONDecoder().decode([AutomationRule].self, from: data) else { return }
        automations = saved
    }

    private func saveAutomations() {
        guard let data = try? JSONEncoder().encode(automations) else { return }
        UserDefaults.standard.set(data, forKey: automationsKey)
    }

    func recordToolCall(agentId: UUID, agentName: String, toolName: String,
                        arguments: [String: String], result: String) {
        let success = !result.hasPrefix("Error:") && !result.hasPrefix("Tool not found:")
        toolCallHistory.insert(
            ToolCallRecord(agentId: agentId, agentName: agentName, toolName: toolName,
                           arguments: arguments, result: result, success: success),
            at: 0
        )
    }

    /// Called by the Stop button on the floating overlay.
    func stopAgentControl() {
        screenControlTasks.forEach { $0.cancel() }
        screenControlTasks.removeAll()
        screenControlCount = 0
        isAgentControllingScreen = false
    }

    // MARK: - Agent persistence

    private func loadAgents() {
        Task {
            let repo = AgentRepository()
            do {
                self.agents = try await repo.getAll()
            } catch {
                print("Error loading agents: \(error)")
            }
        }
    }

    func updateAgent(_ agent: Agent) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        }
        Task {
            let repo = AgentRepository()
            try? await repo.update(agent)
        }
    }

    func deleteAgent(id: UUID) {
        agents.removeAll { $0.id == id }
        if selectedAgentId == id { selectedAgentId = nil }
        Task {
            let repo = AgentRepository()
            try? await repo.delete(id: id)
        }
    }

    /// Apply an agent's self-modification request. Returns a human-readable result string.
    func applySelfUpdate(_ args: [String: String], agentId: UUID) -> String {
        guard let idx = agents.firstIndex(where: { $0.id == agentId }) else {
            return "Error: agent not found."
        }
        var updated = agents[idx]
        var changes: [String] = []

        if let name = args["name"], !name.isEmpty {
            updated.name = name
            changes.append("name → \"\(name)\"")
        }
        if let prompt = args["system_prompt"] {
            updated.configuration.systemPrompt = prompt.isEmpty ? nil : prompt
            changes.append("system prompt updated")
        }
        if let model = args["model"], !model.isEmpty {
            updated.configuration.model = model
            changes.append("model → \(model)")
        }
        if let tempStr = args["temperature"], let temp = Double(tempStr) {
            updated.configuration.temperature = max(0, min(2, temp))
            changes.append("temperature → \(temp)")
        }

        guard !changes.isEmpty else { return "No changes requested." }
        updated.updatedAt = Date()
        updateAgent(updated)
        return "Configuration updated: \(changes.joined(separator: ", "))."
    }

    // MARK: - Conversation management

    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let saved = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
        conversations = saved
    }

    private func saveConversations() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        UserDefaults.standard.set(data, forKey: conversationsKey)
    }

    @discardableResult
    func createDM(agentId: UUID) -> Conversation {
        // Reuse existing DM if one exists
        if let existing = conversations.first(where: { !$0.isGroup && $0.participantIds == [agentId] }) {
            selectedConversationId = existing.id
            selectedSidebarItem = .agentSpace
            return existing
        }
        let conv = Conversation(participantIds: [agentId])
        conversations.insert(conv, at: 0)
        selectedConversationId = conv.id
        selectedSidebarItem = .agentSpace
        return conv
    }

    @discardableResult
    func createGroup(agentIds: [UUID], title: String?) -> Conversation {
        let conv = Conversation(title: title, participantIds: agentIds)
        conversations.insert(conv, at: 0)
        selectedConversationId = conv.id
        selectedSidebarItem = .agentSpace
        return conv
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationId == id { selectedConversationId = nil }
    }

    // MARK: - Messaging

    func sendMessage(_ text: String, in conversationId: UUID, agentMode: Bool = false, desktopControlEnabled: Bool = false) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        let userMsg = SpaceMessage(role: .user, content: text)
        conversations[index].messages.append(userMsg)
        conversations[index].updatedAt = Date()

        let conv = conversations[index]
        let participants = agents.filter { conv.participantIds.contains($0.id) }

        // All participants are peers — no lead agent.
        // @mentioned agents respond; unaddressed messages go to every participant.
        // Agents go one at a time: the second agent sees the first's completed output
        // before starting, so they build on each other rather than acting in parallel.
        let mentioned = participants.filter { text.contains("@\($0.name)") }
        let targets: [Agent] = mentioned.isEmpty ? participants : mentioned

        let task = Task { [weak self] in
            guard let self else { return }
            for agent in targets {
                guard !Task.isCancelled else { break }
                // Re-snapshot history before each turn so every agent sees
                // everything the previous agent wrote.
                let freshHistory = conversations
                    .first(where: { $0.id == conversationId })?
                    .messages.filter { !$0.isStreaming } ?? []
                await streamResponse(from: agent, in: conversationId,
                                     history: freshHistory, agentMode: agentMode, desktopControlEnabled: desktopControlEnabled)
            }
        }
        screenControlTasks.append(task)
    }

    private func streamResponse(from agent: Agent, in conversationId: UUID, history: [SpaceMessage], agentMode: Bool = false, desktopControlEnabled: Bool = false, delegationDepth: Int = 0) async {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        // Only raise the screen-control flag when a screen tool is actually called,
        // not at the start of every agent-mode response.
        var didRaiseScreenControl = false
        defer {
            if didRaiseScreenControl {
                screenControlCount = max(0, screenControlCount - 1)
                if screenControlCount == 0 {
                    isAgentControllingScreen = false
                    screenControlTasks.removeAll { $0.isCancelled }
                }
            }
        }

        let placeholderId = UUID()
        conversations[index].messages.append(SpaceMessage(
            id: placeholderId, role: .agent, content: "",
            agentId: agent.id, isStreaming: true
        ))

        // Build AI message history.
        // In a group chat, other agents' messages are injected as user-role turns
        // prefixed with their name so this agent knows who said what.
        let convParticipants = agents.filter { conversations[index].participantIds.contains($0.id) }
        let isGroup = convParticipants.count > 1
        var aiMessages: [AIMessage] = history.compactMap { msg in
            if msg.role == .user {
                return AIMessage(role: .user, content: msg.content, imageData: msg.imageData)
            } else if let senderId = msg.agentId {
                if senderId == agent.id {
                    // Own previous message → assistant role
                    return AIMessage(role: .assistant, content: msg.content)
                } else if isGroup {
                    // Another agent in the group → inject as user turn with name prefix
                    let senderName = agents.first { $0.id == senderId }?.name ?? "Agent"
                    return AIMessage(role: .user, content: "[\(senderName)]: \(msg.content)")
                }
            }
            return nil
        }

        let repo = AIProviderRepository()
        // In Agent Mode, give the agent access to every registered tool so it
        // can complete multi-step tasks (search → reason → write, etc.) without
        // the user having to pre-enable individual tools.
        // Outside Agent Mode, respect the agent's explicit enabledTools list.
        // If desktopControlEnabled is false, exclude desktop control tools (mouse, keyboard, open_app).
        var tools: [AITool]
        #if os(macOS)
        if agentMode {
            if desktopControlEnabled {
                tools = ToolRegistry.shared.getToolsForAI() // all tools
            } else {
                // Allow screenshot and AppleScript but not mouse/keyboard/app control
                tools = ToolRegistry.shared.getToolsForAIWithoutDesktopControl()
            }
        } else {
            tools = ToolRegistry.shared.getToolsForAI(enabledNames: agent.configuration.enabledTools)
        }
        if !tools.contains(where: { $0.name == "update_self" }),
           let selfTool = ToolRegistry.shared.getTool(named: "update_self") {
            tools.append(selfTool.toAITool())
        }
        #else
        tools = []
        #endif

        // In a group chat, prepend context so each agent knows who else is present
        let effectiveSystemPrompt: String? = {
            var parts: [String] = []
            if agentMode {
                let modeDescription = desktopControlEnabled
                    ? "You have FULL autonomous control of the user's Mac — file system, web, shell, apps, and screen."
                    : "You have access to file system, web, shell, AppleScript, and screenshots. Desktop control (mouse, keyboard, app launching) is DISABLED."

                parts.append("""
                You are in Agent Mode. \(modeDescription)

                ═══ MULTI-STEP TASK EXECUTION ═══
                For any task that requires multiple steps (research → reason → write, open app → interact → verify, etc.):
                  1. PLAN silently: identify every step needed to fully complete the task.
                  2. EXECUTE each step immediately using the appropriate tool — do NOT narrate future steps, just do them.
                  3. CHAIN results: use the output of one tool as input to the next tool call.
                  4. ONLY give a final text response when EVERY step is 100% complete.
                  5. NEVER stop mid-task and ask the user to continue or do anything manually.

                EXAMPLE — "search for X, then write a report on the Desktop":
                  Step 1 → call web_search("X")
                  Step 2 → call web_search again for more detail if needed
                  Step 3 → call write_file(path: "/Users/<user>/Desktop/report.txt", content: <full report>)
                  Step 4 → respond: "Done — report saved to your Desktop."

                EXAMPLE — "open Safari and go to apple.com":
                  Step 1 → call open_application("Safari")
                  Step 2 → call run_applescript to navigate to the URL
                  Step 3 → call take_screenshot to verify
                  Step 4 → respond with result.

                ═══ TOOL SELECTION GUIDE ═══
                • Research / web data   → web_search, fetch_url
                • Files on disk         → write_file, read_file, list_directory, create_directory
                • Shell / automation    → execute_command, run_applescript
                • Open apps / URLs      → open_application, open_url
                • Screen interaction    → get_screen_info, click_mouse, type_text, press_key, take_screenshot
                • Memory across turns   → memory_save, memory_read

                ═══ SCREEN CONTROL ═══
                • Screen origin is top-left (0,0). Coordinates are logical pixels (1:1 with screenshot).
                • When you receive a screenshot, look at the image carefully and read the EXACT pixel
                  position of the element — do NOT approximate or guess. State the pixel coords before clicking.

                PRIORITY ORDER for UI interaction:
                  1. run_applescript — interact by element name, no coordinates needed (most reliable)
                  2. JavaScript via AppleScript — for web browsers (never misses, not affected by zoom)
                  3. click_mouse — pixel click, last resort only

                AppleScript — native app UI:
                    tell application "AppName" to activate
                    delay 0.8
                    tell application "System Events"
                        tell process "AppName"
                            click button "Button Name" of window 1
                            set value of text field 1 of window 1 to "text"
                            key code 36  -- Return
                        end tell
                    end tell

                JavaScript via AppleScript — web browsers (ALWAYS prefer this over click_mouse in browsers):
                    -- Click a tab / link by text or selector:
                    tell application "Google Chrome"
                        tell active tab of front window
                            execute javascript "document.querySelector('a[href*=\"/images\"]').click()"
                        end tell
                    end tell
                    -- Or navigate directly (most reliable):
                    tell application "Google Chrome"
                        set URL of active tab of front window to "https://www.bing.com/images/search?q=cats"
                    end tell
                    -- Safari equivalent: execute javascript / set URL of current tab of front window

                ═══ WHEN AN ACTION FAILS ═══
                If a click or action doesn't produce the expected result:
                  1. NEVER repeat the identical click at "slightly adjusted" coordinates — that rarely works.
                  2. NEVER tell the user to click manually — try a different method instead.
                  3. For browser clicks that failed → switch to JavaScript or navigate by URL directly.
                  4. For native app clicks that failed → switch to System Events AppleScript by element name.
                  5. If still failing after 2 attempts → take_screenshot, re-read the full UI, pick a completely
                     different approach (e.g. keyboard shortcut, menu item, URL navigation).
                  6. Only after exhausting ALL automated approaches may you report that the action failed.

                ═══ ABSOLUTE RULES ═══
                1. NEVER tell the user to "manually" do anything — not clicking, typing, or any interaction.
                2. NEVER stop after one tool call and ask what to do next — keep executing until the full task is done.
                3. NEVER leave a task half-finished. If a step fails, try an alternative approach.
                4. Desktop path: use execute_command("echo $HOME") to get the user's home, then write to $HOME/Desktop/.
                """)

                if !desktopControlEnabled {
                    parts.append("""
                    ⚠️ DESKTOP CONTROL RESTRICTION ⚠️
                    The following tools are NOT available:
                    • click_mouse, scroll_mouse, move_mouse — no mouse control
                    • type_text, press_key — no keyboard input
                    • open_application — cannot launch apps

                    AVAILABLE ALTERNATIVES:
                    • take_screenshot — view the screen
                    • run_applescript — execute AppleScript for automation
                    • execute_command — run shell commands
                    • write_file, read_file — file operations
                    • web_search, fetch_url — web access

                    Use AppleScript (run_applescript) with System Events for sophisticated automation instead of mouse/keyboard clicks.
                    """)
                }
            }
            if isGroup {
                let others = convParticipants.filter { $0.id != agent.id }
                if !others.isEmpty {
                    let peerList = others.map { other -> String in
                        let role = other.configuration.systemPrompt
                            .flatMap { $0.isEmpty ? nil : String($0.prefix(120)) }
                            ?? "General assistant"
                        return "• \(other.name): \(role)"
                    }.joined(separator: "\n")
                    parts.append("""
                    You are \(agent.name). You are in a multi-agent group conversation. There is no leader — all agents are equal peers.

                    ═══ PARTICIPANTS ═══
                    \(peerList)
                    • You: \(agent.name)

                    Other agents' messages appear prefixed with [AgentName]: in the conversation.

                    ═══ HOW TO COLLABORATE ═══
                    Agents take turns — one completes their work fully, then hands off.
                    • READ FIRST: Before acting, read all previous messages to understand what has already been done.
                      Never duplicate or redo work a peer has already completed.
                    • ACT, DON'T OVERLAP: Do your part of the task using tools, then hand off cleanly.
                      Don't start something another agent is already doing or has just finished.
                    • HAND OFF with @AgentName: <clear instruction of what's left> — they will pick up exactly where you stopped.
                      Hand off to ONE agent at a time. Avoid mentioning multiple agents in one message unless
                      they truly need to act at the same time (which is rare).
                    • CONTINUE FREELY: After receiving a handoff, act on it. Then hand back or forward as needed.
                      The conversation can go back-and-forth as many times as the task requires.
                    • USE TOOLS at any point: search, write files, run code, control the screen, etc.
                    • FINISH: When everything is truly done, end your message with [eof].

                    ═══ SILENCE PROTOCOL ═══
                    • Not your turn, or nothing meaningful to add → respond with exactly: [eof] (hidden from user).
                    • Spoke your piece and want to hand off → say what you need, then end with [eof].
                    • Near exchange limit (20) → just finish the task yourself instead of delegating further.
                    """)
                }
            }
            if let base = agent.configuration.systemPrompt, !base.isEmpty { parts.append(base) }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }()

        func updatePlaceholder(_ text: String) {
            if let ci = conversations.firstIndex(where: { $0.id == conversationId }),
               let mi = conversations[ci].messages.firstIndex(where: { $0.id == placeholderId }) {
                conversations[ci].messages[mi].content = text
            }
            // Also update the corner reply bubble if it's showing (for quick actions)
            DispatchQueue.main.async {
                AgentReplyBubbleController.shared.updateText(text)
            }
        }

        do {
            if tools.isEmpty {
                // No tools — stream normally
                let stream = try await repo.sendMessageStream(
                    provider: agent.configuration.provider,
                    model: agent.configuration.model,
                    messages: aiMessages,
                    systemPrompt: effectiveSystemPrompt,
                    temperature: agent.configuration.temperature,
                    maxTokens: agent.configuration.maxTokens
                )
                var accumulated = ""
                for try await chunk in stream {
                    if let content = chunk.content, !content.isEmpty {
                        accumulated += content
                        updatePlaceholder(accumulated)
                    }
                }
            } else {
                // Has tools — run a non-streaming tool execution loop
                var iteration = 0
                let maxIterations = agentMode ? 30 : 10
                var finalContent = ""
                while iteration < maxIterations {
                    iteration += 1

                    // Respect cancellation (Stop button)
                    if Task.isCancelled {
                        updatePlaceholder(finalContent.isEmpty ? "Stopped." : finalContent)
                        break
                    }

                    let response = try await repo.sendMessage(
                        provider: agent.configuration.provider,
                        model: agent.configuration.model,
                        messages: aiMessages,
                        systemPrompt: effectiveSystemPrompt,
                        tools: tools,
                        temperature: agent.configuration.temperature,
                        maxTokens: agent.configuration.maxTokens
                    )

                    aiMessages.append(AIMessage(
                        role: .assistant,
                        content: response.content ?? "",
                        toolCalls: response.toolCalls
                    ))

                    if let content = response.content, !content.isEmpty {
                        finalContent += (finalContent.isEmpty ? "" : "\n\n") + content
                        updatePlaceholder(finalContent)
                    }

                    guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else { break }

                    // Show which tools are running (appended so prior content stays visible)
                    let names = toolCalls.map { $0.name }.joined(separator: ", ")
                    finalContent += (finalContent.isEmpty ? "" : "\n\n") + "Running: \(names)…"
                    updatePlaceholder(finalContent)

                    // Track whether this batch touched the screen
                    var touchedScreen = false

                    for toolCall in toolCalls {
                        if Task.isCancelled { break }

                        let result: String
                        // Stream tool call to reply bubble
                        DispatchQueue.main.async {
                            AgentReplyBubbleController.shared.addToolCall(toolCall.name, args: toolCall.arguments)
                        }

                        #if os(macOS)
                        if toolCall.name == "update_self" {
                            result = applySelfUpdate(toolCall.arguments, agentId: agent.id)
                        } else if let tool = ToolRegistry.shared.getTool(named: toolCall.name) {
                            do { result = try await tool.handler(toolCall.arguments) }
                            catch { result = "Error: \(error.localizedDescription)" }
                        } else {
                            result = "Tool not found: \(toolCall.name)"
                        }
                        #else
                        result = "Tools not available on this platform"
                        #endif
                        recordToolCall(agentId: agent.id, agentName: agent.name,
                                       toolName: toolCall.name, arguments: toolCall.arguments,
                                       result: result)
                        aiMessages.append(AIMessage(role: .tool, content: result, toolCallId: toolCall.id))

                        if screenControlToolNames.contains(toolCall.name) {
                            touchedScreen = true
                            // Raise the overlay the first time a screen tool fires
                            if agentMode && !didRaiseScreenControl {
                                didRaiseScreenControl = true
                                screenControlCount += 1
                                isAgentControllingScreen = true
                            }
                        }
                    }

                    // ── Post-action screenshot → AI vision ───────────────────
                    // After any screen-touching tool, capture the main display and
                    // send the raw screenshot to the model. Vision-capable models
                    // (GPT-4o, Claude, Gemini) read the image and decide what to
                    // click / type next without any intermediate parsing.
                    #if os(macOS)
                    if agentMode && touchedScreen && !Task.isCancelled {
                        // Give the UI time to settle before capturing
                        try? await Task.sleep(nanoseconds: 900_000_000) // 0.9 s

                        finalContent += (finalContent.isEmpty ? "" : "\n\n") + "📸 Capturing screen…"
                        updatePlaceholder(finalContent)

                        let (screen, displayID) = await MainActor.run { () -> (CGRect, UInt32) in
                            let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
                            let id = (NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                                .map { UInt32($0.uint32Value) } ?? CGMainDisplayID()
                            return (frame, id)
                        }
                        let screenW = Int(screen.width), screenH = Int(screen.height)
                        let jpeg = await Task.detached(priority: .userInitiated) {
                            captureScreenAsJPEG(maxWidth: 1440, displayID: displayID)
                        }.value
                        if let data = jpeg {
                            aiMessages.append(AIMessage(
                                role: .user,
                                content: "Here is the current screen state after your last actions. " +
                                         "Resolution: \(screenW)×\(screenH) logical px — coordinates are 1:1, " +
                                         "top-left origin (0,0). Use pixel positions from this image directly " +
                                         "with click_mouse — no scaling needed. " +
                                         "Identify every visible UI element and decide what to do next. " +
                                         "Tip: run_applescript can interact with UI elements by name " +
                                         "(click buttons, fill fields, choose menu items) without needing " +
                                         "pixel coordinates — prefer it when the app supports it.",
                                imageData: data
                            ))
                        }
                    }
                    #endif
                }
                if finalContent.isEmpty { updatePlaceholder("(no response)") }
            }
        } catch {
            updatePlaceholder("Error: \(error.localizedDescription)")
        }

        // Mark streaming done
        if let ci = conversations.firstIndex(where: { $0.id == conversationId }),
           let mi = conversations[ci].messages.firstIndex(where: { $0.id == placeholderId }) {
            conversations[ci].messages[mi].isStreaming = false
        }
        if let ci = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[ci].updatedAt = Date()
        }

        // ── [eof] silence handling ────────────────────────────────────────────
        // Agents respond with [eof] (alone or at the end) to pass silently.
        // Strip the marker; if nothing meaningful remains, remove the message.
        if isGroup,
           let ci = conversations.firstIndex(where: { $0.id == conversationId }),
           let mi = conversations[ci].messages.firstIndex(where: { $0.id == placeholderId }) {
            let raw = conversations[ci].messages[mi].content
            let cleaned = raw
                .replacingOccurrences(of: "[eof]", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                // Complete silent pass — remove placeholder, nothing to delegate
                conversations[ci].messages.remove(at: mi)
                return
            } else if cleaned != raw {
                conversations[ci].messages[mi].content = cleaned
            }
        }

        // ── Agent-to-agent delegation ─────────────────────────────────────────
        // After this agent's message is final, scan it for @mentions of peers.
        // Delegates run ONE AT A TIME: each one finishes completely before the next
        // starts, so every agent sees the prior agent's completed work in history.
        // Capped at depth 20 to prevent infinite loops.
        if isGroup && delegationDepth < 20 && !Task.isCancelled,
           let ci = conversations.firstIndex(where: { $0.id == conversationId }),
           let mi = conversations[ci].messages.firstIndex(where: { $0.id == placeholderId }) {
            let agentResponse = conversations[ci].messages[mi].content
            let delegatedAgents = convParticipants.filter { other in
                other.id != agent.id &&
                agentResponse.range(of: "@\(other.name)", options: .caseInsensitive) != nil
            }
            if !delegatedAgents.isEmpty {
                // Sequential: await each delegate in order.
                // Re-snapshot history before each one so it sees all prior output.
                for target in delegatedAgents {
                    guard !Task.isCancelled else { break }
                    let freshHistory = conversations
                        .first(where: { $0.id == conversationId })?
                        .messages.filter { !$0.isStreaming } ?? []
                    await streamResponse(
                        from: target,
                        in: conversationId,
                        history: freshHistory,
                        agentMode: agentMode,
                        delegationDepth: delegationDepth + 1
                    )
                }
            }
        }
    }
}

// MARK: - Sidebar Item

enum SidebarItem: String, CaseIterable, Identifiable {
    case agents     = "Agents"
    case agentSpace = "Agent Space"
    case health     = "Health"
    case history    = "History"
    case automation = "Automations"
    case settings   = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agents:     return "cpu"
        case .agentSpace: return "bubble.left.and.bubble.right.fill"
        case .health:     return "heart.fill"
        case .history:    return "clock.arrow.circlepath"
        case .automation: return "bolt.horizontal"
        case .settings:   return "gear"
        }
    }
}
