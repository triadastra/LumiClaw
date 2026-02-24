//
//  iOSMainView.swift
//  LumiAgent
//
//  iOS-specific main interface
//  ✅ ALL TYPE ERRORS FIXED FOR iOS
//

#if os(iOS)
import SwiftUI

struct iOSMainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Agents Tab
            NavigationStack {
                iOSAgentListView()
                    .navigationTitle("Agents")
            }
            .tabItem {
                Label("Agents", systemImage: "cpu")
            }
            .tag(0)
            
            // Chat Tab
            NavigationStack {
                iOSConversationsView()
                    .navigationTitle("Conversations")
            }
            .tabItem {
                Label("Chat", systemImage: "message.fill")
            }
            .tag(1)
            
            // Settings Tab
            NavigationStack {
                iOSSettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
    }
}

// MARK: - iOS Agent List

struct iOSAgentListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingNewAgent = false
    
    var body: some View {
        List {
            ForEach(appState.agents) { agent in
                NavigationLink {
                    iOSAgentDetailView(agent: agent)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(agent.name)
                            .font(.headline)
                        Text(agent.configuration.model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .toolbar {
            Button {
                showingNewAgent = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingNewAgent) {
            iOSNewAgentView()
        }
        .overlay {
            if appState.agents.isEmpty {
                ContentUnavailableView(
                    "No Agents",
                    systemImage: "cpu",
                    description: Text("Create your first AI agent to get started")
                )
            }
        }
    }
}

// MARK: - iOS Agent Detail

struct iOSAgentDetailView: View {
    let agent: Agent
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            Section("Configuration") {
                LabeledContent("Provider", value: agent.configuration.provider.rawValue)
                LabeledContent("Model", value: agent.configuration.model)
                // ✅ FIX #1: Convert Double to String for LabeledContent
                LabeledContent("Temperature", value: String(format: "%.1f", agent.configuration.temperature))
            }
            
            Section("System Prompt") {
                if let prompt = agent.configuration.systemPrompt {
                    Text(prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No system prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Text("⚠️ Tool execution is only available on macOS")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("To use tools like file operations, terminal commands, and system automation, please use LumiAgent on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Tools")
            }
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - iOS Conversations

struct iOSConversationsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingNewConversation = false
    
    var body: some View {
        List {
            ForEach(appState.conversations) { conversation in
                NavigationLink {
                    iOSChatView(conversationId: conversation.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        // ✅ FIX #2: Unwrap optional String with ??
                        Text(conversation.title ?? "Conversation")
                            .font(.headline)
                        if let lastMessage = conversation.messages.last {
                            Text(lastMessage.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .toolbar {
            Button {
                showingNewConversation = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingNewConversation) {
            iOSNewConversationView()
        }
        .overlay {
            if appState.conversations.isEmpty {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "message",
                    description: Text("Start a new conversation with your agents")
                )
            }
        }
    }
}

// MARK: - iOS Chat View

struct iOSChatView: View {
    let conversationId: UUID
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    
    var conversation: Conversation? {
        appState.conversations.first { $0.id == conversationId }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let conv = conversation {
                        ForEach(conv.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Input
            HStack(spacing: 12) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.isEmpty ? .secondary : .blue)
                }
                .disabled(inputText.isEmpty)
            }
            .padding()
        }
        .navigationTitle(conversation?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        appState.sendMessage(inputText, in: conversationId, agentMode: false)
        inputText = ""
    }
}

struct MessageBubble: View {
    let message: SpaceMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    // ✅ FIX #3: Use Color(uiColor:) for iOS UIColor conversion
                    .background(message.role == .user ? Color.blue : Color(uiColor: .systemGray5))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                if message.isStreaming {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            if message.role != .user {
                Spacer()
            }
        }
    }
}

// MARK: - iOS Settings

struct iOSSettingsView: View {
    var body: some View {
        List {
            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Platform", value: "iOS")
            }
            
            Section("Limitations") {
                Text("⚠️ iOS Version Limitations")
                    .font(.headline)
                Text("The iOS version of LumiAgent provides chat functionality only. Advanced features like tool execution, file operations, terminal commands, and system automation require the macOS version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let url = URL(string: "https://lumiagent.com") {
                Link(destination: url) {
                    Label("Learn More", systemImage: "safari")
                }
            }
        }
    }
}

// MARK: - iOS New Agent View

struct iOSNewAgentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var provider: AIProvider = .openai
    @State private var model = "gpt-4o"
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Agent Name", text: $name)
                
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                
                TextField("Model", text: $model)
            }
            .navigationTitle("New Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createAgent()
                        dismiss()
                    }
                    .disabled(name.isEmpty || model.isEmpty)
                }
            }
        }
    }
    
    private func createAgent() {
        let agent = Agent(
            name: name,
            configuration: AgentConfiguration(
                provider: provider,
                model: model
            )
        )
        appState.agents.append(agent)
    }
}

// MARK: - iOS New Conversation View

struct iOSNewConversationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedAgentIds: Set<UUID> = []
    @State private var title = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title (optional)", text: $title)
                
                Section("Select Agents") {
                    ForEach(appState.agents) { agent in
                        Toggle(agent.name, isOn: Binding(
                            get: { selectedAgentIds.contains(agent.id) },
                            set: { isOn in
                                if isOn {
                                    selectedAgentIds.insert(agent.id)
                                } else {
                                    selectedAgentIds.remove(agent.id)
                                }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createConversation()
                        dismiss()
                    }
                    .disabled(selectedAgentIds.isEmpty)
                }
            }
        }
    }
    
    private func createConversation() {
        let agentIds = Array(selectedAgentIds)
        if agentIds.count == 1 {
            _ = appState.createDM(agentId: agentIds[0])
        } else {
            _ = appState.createGroup(
                agentIds: agentIds,
                title: title.isEmpty ? nil : title
            )
        }
    }
}

#endif
