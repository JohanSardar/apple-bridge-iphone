import SwiftUI

struct SlideToApprove: View {
    let armed: Bool
    let armDelay: TimeInterval
    let busy: Bool
    let complete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var finished = false
    @State private var lastStep = 0
    @State private var armProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 60
    private let inset: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let knob = height - inset * 2
            let travel = max(1, proxy.size.width - knob - inset * 2)
            let progress = min(1, offset / travel)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(armed || busy ? Ink.primary : Ink.raised)
                Capsule()
                    .fill(Ink.inverse.opacity(0.14 * Double(progress)))
                    .frame(width: knob + inset * 2 + offset)
                label
                    .frame(maxWidth: .infinity)
                    .padding(.leading, busy ? 0 : knob * 0.6)
                    .padding(.trailing, busy ? knob * 0.9 : 0)
                    .opacity(busy ? 1 : Double(1 - progress * 1.6))
                knobView(size: knob)
                    .offset(x: inset + offset)
                    .gesture(drag(travel: travel))
            }
            .frame(height: height)
        }
        .frame(height: height)
        .animation(Motion.respecting(reduceMotion, Motion.standard), value: armed)
        .onAppear(perform: startArming)
        .onChange(of: armed) { _, now in
            if now { Haptics.soft() } else { startArming() }
        }
        .onChange(of: busy) { _, now in
            if !now { reset() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Approve")
        .accessibilityValue(busy ? "Waiting for Face ID" : armed ? "" : "Available in a moment")
        .accessibilityHint(armed ? "Slide right or double-tap to approve with Face ID" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard armed, !busy, !finished else { return }
            finished = true
            complete()
        }
    }

    @ViewBuilder
    private var label: some View {
        let text = busy ? "Confirm with Face ID" : armed ? "Slide to approve" : "Read it first"
        Text(text)
            .type(.headline)
            .foregroundStyle(armed || busy ? Ink.inverse : Ink.secondary)
            .contentTransition(.opacity)
            .animation(Motion.fade, value: text)
    }

    private func knobView(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(armed || busy ? Ink.inverse : Ink.canvas)
            if !armed && !busy {
                Circle()
                    .trim(from: 0, to: armProgress)
                    .stroke(Ink.primary.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(7)
            }
            if busy {
                ProgressView().tint(Ink.primary)
            } else {
                Image(systemName: finished ? "faceid" : "chevron.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Ink.primary.opacity(armed ? 1 : 0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: size, height: size)
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard armed, !busy, !finished else { return }
                offset = min(travel, max(0, value.translation.width))
                let step = Int((offset / travel) * 5)
                if step != lastStep {
                    if step > lastStep { Haptics.tick(0.3 + CGFloat(step) * 0.14) }
                    lastStep = step
                }
            }
            .onEnded { value in
                guard armed, !busy, !finished else { return }
                let projected = min(travel, max(0, value.predictedEndTranslation.width))
                if offset > travel * 0.82 || (projected >= travel && offset > travel * 0.5) {
                    finished = true
                    withAnimation(Motion.respecting(reduceMotion, Motion.snappy)) { offset = travel }
                    Haptics.thud()
                    complete()
                } else {
                    reset()
                }
            }
    }

    private func reset() {
        finished = false
        lastStep = 0
        withAnimation(Motion.respecting(reduceMotion, .spring(response: 0.42, dampingFraction: 0.72))) { offset = 0 }
    }

    private func startArming() {
        guard !armed else {
            armProgress = 1
            return
        }
        armProgress = 0
        withAnimation(.linear(duration: max(0.1, armDelay))) { armProgress = 1 }
    }
}
