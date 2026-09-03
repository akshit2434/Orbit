import AppKit
import SwiftUI

enum OrbitState: Equatable {
    case idle
    case listening
    case thinking
    case working

    var accent: Color {
        switch self {
        case .idle: Color(red: 0.36, green: 0.47, blue: 0.98)
        case .listening: Color(red: 0.22, green: 0.42, blue: 0.95)
        case .thinking: Color(red: 0.50, green: 0.30, blue: 0.90)
        case .working: Color(red: 0.39, green: 0.35, blue: 0.86)
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .idle: Color(red: 0.20, green: 0.68, blue: 0.95)
        case .listening: Color(red: 0.25, green: 0.68, blue: 0.88)
        case .thinking: Color(red: 0.88, green: 0.28, blue: 0.67)
        case .working: Color(red: 0.55, green: 0.33, blue: 0.90)
        }
    }

    var energy: Double {
        switch self {
        case .idle: 0.42
        case .listening: 0.84
        case .thinking: 1.08
        case .working: 0.68
        }
    }

    var breathAmplitude: Double {
        switch self {
        case .idle: 0.024
        case .listening: 0.034
        case .thinking: 0.072
        case .working: 0.048
        }
    }
}

struct OrbitOverlayView: View {
    @ObservedObject var model: OrbitPanelModel
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch model.mode {
            case .orb:
                ZStack(alignment: .trailing) {
                    historyButton
                    surface
                        .frame(width: 56, height: 56)
                }
                .transition(.blurReplace.combined(with: .opacity))
            case .voice:
                ZStack(alignment: .trailing) {
                    historyButton
                    surface
                        .frame(width: 190, height: 44)
                }
                .transition(.blurReplace.combined(with: .opacity))
                if model.isMockVoice {
                    TextField("mock transcript", text: $model.debugText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(width: 190)
                        .onSubmit {
                            model.send()
                        }
                        .accessibilityLabel("Mock transcript inject")
                }
            case .thinking:
                HStack(alignment: .center, spacing: 8) {
                    thinkingBubble
                    surface
                        .frame(width: 56, height: 56)
                }
                .transition(.blurReplace.combined(with: .opacity))
            case .output:
                HStack(alignment: .center, spacing: 8) {
                    outputBubble
                    surface
                        .frame(width: 56, height: 56)
                }
                .transition(.blurReplace.combined(with: .opacity))
            case .card, .history:
                cardView
                    .transition(.blurReplace.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 12)
        .preferredColorScheme(.light)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.46), value: model.mode)
        .animation(.easeInOut(duration: 0.46), value: model.state)
        .animation(.easeInOut(duration: 0.46), value: model.hintText)
        .animation(.easeInOut(duration: 0.46), value: model.streamText)
        .animation(.easeInOut(duration: 0.46), value: model.store.turns.count)
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    model.drag(to: value.translation)
                }
                .onEnded { _ in
                    model.endDrag()
                }
        )
        .allowsWindowActivationEvents()
    }

    private var thinkingBubble: some View {
        ZStack(alignment: .topLeading) {
            Text(model.hintText ?? "Thinking…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.4), lineWidth: 0.6)
                }
                .frame(maxWidth: 170, alignment: .leading)
                .padding(.leading, 20)
                .transition(.blurReplace.combined(with: .opacity))
            Button {
                model.closeChat()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .focusable(false)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close chat")
        }
        .frame(maxWidth: 190, alignment: .trailing)
    }

    private var outputBubble: some View {
        ZStack(alignment: .topLeading) {
            Button {
                model.expandToCard()
            } label: {
                Text(model.streamText.isEmpty ? (model.hintText ?? "Thinking…") : model.streamText)
                    .font(.system(size: 10))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                    .frame(maxWidth: 170, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Expand to card")
            .padding(.leading, 20)
            .transition(.blurReplace.combined(with: .opacity))
            Button {
                model.closeChat()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .focusable(false)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close chat")
        }
        .frame(maxWidth: 190, alignment: .trailing)
    }

    private var cardView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                timerLabel
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(model.streamText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .regular))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focusable(false)
                .accessibilityLabel("Copy reply")
                Button {
                    model.closeChat()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focusable(false)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close chat")
            }
            ScrollView {
                Text(model.streamText.isEmpty ? (model.hintText ?? "Thinking…") : model.streamText)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Orbit reply")
            }
            .frame(maxHeight: 140)
            .scrollIndicators(.hidden)
            cardInputRow
                .frame(maxWidth: 280, alignment: .trailing)
            if let selected = model.selectedTurn {
                Button {
                    model.selectedTurn = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focusable(false)
                .accessibilityLabel("Back to history")
                Text(selected.reply)
                    .font(.system(size: 10))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                    .frame(maxWidth: 280, alignment: .leading)
                    .accessibilityLabel("Past reply")
            } else if !model.store.turns.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.store.turns.enumerated()), id: \.offset) { _, turn in
                            Button {
                                model.selectedTurn = turn
                            } label: {
                                Text(turn.transcript)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    .frame(maxWidth: 280, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .accessibilityLabel("Reread turn")
                        }
                    }
                }
                .frame(maxHeight: 90)
                .scrollIndicators(.hidden)
            }
            HStack {
                Spacer()
                surface
                    .frame(width: 56, height: 56)
            }
        }
        .padding(12)
        .frame(width: 296, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.4), lineWidth: 0.6)
        }
    }

    private var timerLabel: some View {
        Group {
            if let start = model.workStart {
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    Text(workedString(elapsed: context.date.timeIntervalSince(start)))
                }
            } else {
                Text(workedString(elapsed: 0))
            }
        }
    }

    private var historyButton: some View {
        Button {
            model.openHistory()
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .regular))
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.4), lineWidth: 0.6)
                }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel("Show history")
        .opacity(isHovered && !model.isExpanded ? 1 : 0)
        .scaleEffect(isHovered && !model.isExpanded ? 1 : 0.8)
        .offset(x: isHovered && !model.isExpanded ? -56 : 0)
        .allowsHitTesting(isHovered && !model.isExpanded)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .animation(.smooth(duration: 0.22), value: model.isExpanded)
    }

    private var historyCard: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let selected = model.selectedTurn {
                Button {
                    model.selectedTurn = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focusable(false)
                .accessibilityLabel("Back to history")
                Text(selected.transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 170, alignment: .trailing)
                    .lineLimit(2)
                Text(selected.reply)
                    .font(.system(size: 10))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                    .frame(maxWidth: 190, alignment: .trailing)
                    .accessibilityLabel("Past reply")
            } else {
                if model.store.turns.isEmpty {
                    Text("No turns yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 170, alignment: .trailing)
                        .accessibilityLabel("Empty history")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .trailing, spacing: 4) {
                            ForEach(Array(model.store.turns.enumerated()), id: \.offset) { _, turn in
                                Button {
                                    model.selectedTurn = turn
                                } label: {
                                    Text(turn.transcript)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                        .frame(maxWidth: 170, alignment: .trailing)
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .accessibilityLabel("Reread turn")
                            }
                        }
                    }
                    .frame(maxHeight: 110)
                    .scrollIndicators(.hidden)
                }
            }
            cardInputRow
        }
    }

    private var cardInputRow: some View {
        HStack(spacing: 6) {
            TextField("Ask…", text: $model.debugText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
                .onSubmit {
                    model.send()
                }
                .accessibilityLabel("Ask Orbit")
            Button {
                model.activate()
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .focusable(false)
            .accessibilityLabel("Voice input")
        }
        .frame(maxWidth: 170, alignment: .trailing)
    }

    private var surface: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    model.state.secondaryAccent.opacity(0.68),
                                    model.state.accent.opacity(0.82)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.52), lineWidth: 0.7)
                }
                .shadow(color: model.state.accent.opacity(0.2), radius: 6, y: 3)
                .opacity(model.isExpanded ? 1 : 0)

            streamingControls
                .opacity(model.isExpanded ? 1 : 0)
                .allowsHitTesting(model.isExpanded)

            MotionOrb(state: model.state, size: 30) {
                model.activate()
            }
            .frame(width: 56, height: 56)
            .opacity(model.isExpanded ? 0 : 1)
            .scaleEffect(model.isExpanded ? 0.78 : 1)
            .allowsHitTesting(!model.isExpanded)
        }
        .animation(.smooth(duration: 0.22), value: model.isExpanded)
    }

    private var streamingControls: some View {
        ZStack {
            StreamingWaveform(monitor: model.microphone)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .opacity(isHovered ? 0.2 : 1)

            HStack(spacing: 10) {
                Button {
                    model.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OrbitActionButtonStyle())
                .focusable(false)
                .focusEffectDisabled()
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel")

                Button {
                    model.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OrbitActionButtonStyle(isProminent: true, accent: model.state.accent))
                .focusable(false)
                .focusEffectDisabled()
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Send")
            }
            .opacity(isHovered ? 1 : 0)
            .scaleEffect(isHovered ? 1 : 0.95)
            .allowsHitTesting(isHovered)
        }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

private struct MotionOrb: View {
    let state: OrbitState
    let size: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let pulse = 1 + sin(time * state.energy) * state.breathAmplitude

                ZStack {
                    Circle()
                        .fill(state.accent.opacity(0.14))
                        .frame(width: size * 1.32, height: size * 1.32)
                        .blur(radius: size * 0.15)

                    OrbFluid(state: state, time: time)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.88), lineWidth: 0.7)
                        }
                        .shadow(color: state.accent.opacity(0.22), radius: size * 0.14)
                }
                .scaleEffect(isHovered ? 1.075 : pulse)
                .animation(.spring(response: 0.18, dampingFraction: 0.84), value: isHovered)
                .animation(.easeInOut(duration: 0.46), value: state)
            }
            .frame(width: 56, height: 56)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .contentShape(Circle())
        .onHover { isHovered = $0 }
        .accessibilityElement()
        .accessibilityLabel("Activate Orbit")
    }
}

private struct OrbFluid: View {
    let state: OrbitState
    let time: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let drift = diameter * 0.14

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [state.accent, state.secondaryAccent, Color.white.opacity(0.88)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: diameter * 0.84
                        )
                    )

                Circle()
                    .fill(state.secondaryAccent.opacity(0.72))
                    .frame(width: diameter * 0.7, height: diameter * 0.7)
                    .blur(radius: diameter * 0.13)
                    .offset(
                        x: cos(time * state.energy * 0.72) * drift,
                        y: sin(time * state.energy * 0.94) * drift
                    )
                    .blendMode(.screen)

                Circle()
                    .fill(.white.opacity(0.42))
                    .frame(width: diameter * 0.28, height: diameter * 0.28)
                    .blur(radius: diameter * 0.06)
                    .offset(x: -diameter * 0.18, y: -diameter * 0.2)
            }
        }
        .drawingGroup()
    }
}

private struct StreamingWaveform: View {
    @ObservedObject var monitor: MicrophoneMonitor

    var body: some View {
        ZStack {
            bars
                .blur(radius: 2.4)
                .opacity(0.62)
                .mask(edgeBlurMask)

            bars
                .mask(edgeFadeMask)
        }
        .accessibilityLabel("Live microphone waveform")
    }

    private var bars: some View {
        GeometryReader { proxy in
            let availableHeight = proxy.size.height
            let count = monitor.levels.count

            HStack(spacing: 2.2) {
                ForEach(Array(monitor.levels.enumerated()), id: \.offset) { index, level in
                    let progress = Double(index) / Double(max(1, count - 1))
                    let centerLens = 0.5 + 0.82 * pow(sin(progress * .pi), 1.7)
                    let height = max(2, availableHeight * min(level * 1.65, 1) * centerLens)

                    Capsule()
                        .fill(.white.opacity(0.7 + 0.28 * centerLens / 1.32))
                        .frame(width: 2.6, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.46), location: 0.1),
                .init(color: .white, location: 0.24),
                .init(color: .white, location: 0.76),
                .init(color: .white.opacity(0.46), location: 0.9),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var edgeBlurMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .clear, location: 0.3),
                .init(color: .clear, location: 0.7),
                .init(color: .white, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct OrbitActionButtonStyle: ButtonStyle {
    var isProminent = false
    var accent = Color.black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? accent : .white.opacity(0.94))
            .background(
                isProminent
                    ? Color.white.opacity(configuration.isPressed ? 0.76 : 0.94)
                    : Color.white.opacity(configuration.isPressed ? 0.12 : 0.2),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(.white.opacity(isProminent ? 0.32 : 0.2), lineWidth: 0.7)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}
