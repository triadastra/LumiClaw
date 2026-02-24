//
//  QuickActionPanelController.swift
//  LumiAgent
//
//  A glass morphism Quick Actions panel (Ctrl+L) centered on screen.
//  On action click, displays agent reply in a glass bubble at upper right corner.
//

#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Quick Action Types

// MARK: - App Detection

func isIWorkApp() -> Bool {
    let iworkBundleIds = [
        "com.apple.iwork.pages",
        "com.apple.iwork.numbers",
        "com.apple.iwork.keynote",
        "com.apple.motionapp",
        "com.apple.finalcutpro",
        "com.apple.logicpro",
        "com.pixelmator.pixelmator-pro",
        "com.apple.compressor",
        "com.apple.mainstage",
    ]

    let workspace = NSWorkspace.shared
    if let frontmost = workspace.frontmostApplication {
        return iworkBundleIds.contains(frontmost.bundleIdentifier ?? "")
    }
    return false
}

enum QuickActionType: String, CaseIterable {
    case analyzePage
    case thinkAndWrite
    case writeNew

    var icon: String {
        switch self {
        case .analyzePage:   return "eye.fill"
        case .thinkAndWrite: return "pencil.line"
        case .writeNew:      return "doc.badge.plus"
        }
    }

    var label: String {
        switch self {
        case .analyzePage:   return "Analyze"
        case .thinkAndWrite: return "Write"
        case .writeNew:      return "New"
        }
    }

    var prompt: String {
        switch self {
        case .analyzePage:
            return "Describe what's on this screen"
        case .thinkAndWrite:
            return "Look at this screen, find the active text field, and write an appropriate response using type_text"
        case .writeNew:
            return "Look at this page and write appropriate new content using type_text"
        }
    }

    static var visibleCases: [QuickActionType] {
        // Only show "Write New" for iWork apps
        isIWorkApp() ? [.analyzePage, .thinkAndWrite, .writeNew] : [.analyzePage, .thinkAndWrite]
    }
}

// MARK: - Quick Action Panel Controller

final class QuickActionPanelController: NSObject {
    static let shared = QuickActionPanelController()

    private var panel: NSPanel?
    private var onAction: ((QuickActionType) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(onAction: @escaping (QuickActionType) -> Void) {
        guard panel == nil else { return }
        self.onAction = onAction
        createPanel()
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.onAction = nil
        }
    }

    func toggle(onAction: @escaping (QuickActionType) -> Void) {
        if isVisible {
            hide()
        } else {
            show(onAction: onAction)
        }
    }

    func triggerAction(_ type: QuickActionType) {
        onAction?(type)
        hide()
    }

    private func createPanel() {
        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 280

        let view = QuickActionPanelView(controller: self)
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(NSSize(width: panelWidth, height: panelHeight))

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isReleasedWhenClosed = false

        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let origin = NSPoint(
            x: sf.midX - panelWidth / 2,
            y: sf.midY - panelHeight / 2
        )
        p.setFrameOrigin(origin)
        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        panel = p
    }
}

// MARK: - Agent Reply Bubble Model

class AgentReplyBubbleModel: NSObject, ObservableObject {
    @Published var text: String = ""
}

// MARK: - Agent Reply Bubble Controller

final class AgentReplyBubbleController: NSObject {
    static let shared = AgentReplyBubbleController()

    private var panel: NSPanel?
    private var bubbleModel: AgentReplyBubbleModel?

    func show(initialText: String = "") {
        guard panel == nil else { return }
        createPanel(initialText: initialText)
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.bubbleModel = nil
        }
    }

    func updateText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.bubbleModel?.text = text
        }
    }

    private func createPanel(initialText: String) {
        let model = AgentReplyBubbleModel()
        model.text = initialText
        self.bubbleModel = model

        let bubbleView = AgentReplyBubbleView(model: model)
        let hosting = NSHostingView(rootView: bubbleView)
        hosting.setFrameSize(NSSize(width: 320, height: 200))

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 200)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isReleasedWhenClosed = false

        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        // Upper right corner, with padding
        let origin = NSPoint(
            x: sf.maxX - 320 - 16,
            y: sf.maxY - 200 - 16
        )
        p.setFrameOrigin(origin)
        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }

        panel = p
    }
}

// MARK: - Quick Action Panel View

struct QuickActionPanelView: View {
    let controller: QuickActionPanelController

    var body: some View {
        VStack(spacing: 0) {
            Text("Quick Actions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ForEach(Array(QuickActionType.visibleCases.enumerated()), id: \.element) { index, action in
                if index > 0 {
                    Divider().padding(.horizontal, 16)
                }
                QuickActionButton(action: action) {
                    controller.triggerAction(action)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(width: 320, height: 280)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct QuickActionButton: View {
    let action: QuickActionType
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: action.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isHovering ? .white : .accentColor)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isHovering ? Color.accentColor : Color.accentColor.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(action.prompt.prefix(45) + "...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
                    .padding(.horizontal, 8)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Agent Reply Bubble View

struct AgentReplyBubbleView: View {
    @ObservedObject var model: AgentReplyBubbleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Lumi Agent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: { AgentReplyBubbleController.shared.hide() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(model.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 320, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
#endif
