import SwiftUI
import AppKit

struct GameView: View {
    @ObservedObject var game: GameState
    @State private var showSplash = true
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BackgroundView(phaseProgress: phaseProgress)

                VStack(spacing: 8) {
                    HUDView(game: game)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    GeometryReader { bedGeo in
                        ZStack {
                            GardenBedView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            // Points & skill banner centered in garden bed
                            PointsBanner(points: game.points, skillLevel: game.skillLevel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .padding(.top, 30)

                            ForEach(game.veggies) { plot in
                                VegPlotView(plot: plot)
                                    .position(pointIn(size: bedGeo.size, pos: plot.position))
                                    .animation(.easeInOut(duration: 0.3), value: plot.growth)
                            }

                            ForEach(game.defenses) { defense in
                                if defense.isLine {
                                    LineDefenseView(defense: defense, size: bedGeo.size)
                                } else {
                                    DefenseView(defense: defense)
                                        .position(pointIn(size: bedGeo.size, pos: defense.center))
                                }
                            }

                            SnailTrailLayer(snails: game.snails, size: bedGeo.size)

                            ForEach(game.snails) { snail in
                                SnailView(snail: snail)
                                    .position(pointIn(size: bedGeo.size, pos: snail.position))
                                    .opacity(game.phase == .day && snail.alignment == .pest ? 0.45 : 1.0)
                                    .highPriorityGesture(
                                        TapGesture()
                                            .onEnded {
                                                game.removeSnail(snail.id)
                                            }
                                    )
                            }

                            if let hedgehog = game.hedgehog {
                                HedgehogView(heading: hedgehog.heading)
                                    .position(pointIn(size: bedGeo.size, pos: hedgehog.position))
                            }

                            if let start = dragStart, let current = dragCurrent, isLineDefenseSelected {
                                DragPreviewView(start: start, end: current, size: bedGeo.size, type: game.selectedDefense ?? .metalBars)
                            }
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let normalized = CGPoint(x: value.location.x / bedGeo.size.width,
                                                             y: value.location.y / bedGeo.size.height)
                                    if !game.snails.contains(where: { hypot($0.position.x - normalized.x, $0.position.y - normalized.y) < 0.06 }) {
                                        if isLineDefenseSelected, let start = dragStart {
                                            game.placeDefenseLine(from: start, to: normalized)
                                        } else {
                                            game.placeDefense(at: normalized)
                                        }
                                    }
                                    dragStart = nil
                                    dragCurrent = nil
                                }
                                .onChanged { value in
                                    guard isLineDefenseSelected else { return }
                                    let normalized = CGPoint(x: value.location.x / bedGeo.size.width,
                                                             y: value.location.y / bedGeo.size.height)
                                    if dragStart == nil {
                                        dragStart = normalized
                                    }
                                    dragCurrent = normalized
                                }
                        )
                    }
                    .padding(12)
                    .padding(.bottom, 40)

                    FooterView(game: game)
                        .padding(.bottom, 12)
                }

                SidePanelView(game: game)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 100)

                HStack {
                    Spacer()
                    CelestialView(game: game)
                        .frame(width: 200, height: 60)
                    Spacer()
                    HedgehogCageView(game: game)
                        .padding(.trailing, 18)
                }
                .padding(.top, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(10)
                }

                if isPaused {
                    PauseOverlayView(game: game)
                        .transition(.opacity)
                        .zIndex(11)
                }

                if isGameOver {
                    GameOverView(game: game, reason: gameOverReason)
                        .transition(.opacity)
                        .zIndex(12)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    withAnimation(.easeOut(duration: 0.8)) {
                        showSplash = false
                    }
                }
            }
        }
    }

    private var phaseProgress: Double {
        let day = game.dayDuration
        let night = game.nightDuration
        let total = day + night
        let offset = game.phase == .day ? 0 : day
        let t = min(max((game.phaseTime + offset) / total, 0), 1)
        let smooth = 0.5 - 0.5 * cos(t * 2 * .pi)
        return smooth
    }

    private func pointIn(size: CGSize, pos: CGPoint) -> CGPoint {
        CGPoint(x: pos.x * size.width, y: pos.y * size.height)
    }

    private var isLineDefenseSelected: Bool {
        if let selected = game.selectedDefense {
            return selected == .metalBars || selected == .razors
        }
        return false
    }

    private var isGameOver: Bool {
        !game.isRunning && !showSplash && (game.veggies.allSatisfy({ !$0.alive }) || game.points <= 0)
    }

    private var isPaused: Bool {
        !game.isRunning && !showSplash && !isGameOver
    }

    private var gameOverReason: String {
        if game.veggies.allSatisfy({ !$0.alive }) {
            return "The snails ate all your vegetables!"
        } else if game.points <= 0 {
            return "You ran out of points!"
        }
        return "Game Over"
    }
}

private struct GameOverView: View {
    @ObservedObject var game: GameState
    let reason: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Game Over")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(reason)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    Text("Days Survived: \(game.dayCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                }
                .padding(.vertical, 10)

                HStack(spacing: 20) {
                    Button {
                        game.resetGame()
                        game.isRunning = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Try Again")
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                            Text("Quit")
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}

private struct PauseOverlayView: View {
    @ObservedObject var game: GameState

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("⏸ Paused")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Day \(game.dayCount)  •  \(game.phase.rawValue)time")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                Button {
                    game.togglePause()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Happy 26th Birthday, Tjitske!")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Welcome to the Vegetable Bed")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
}

private struct HUDView: View {
    @ObservedObject var game: GameState

    var body: some View {
        HStack {
            DigitalClockView(timeText: timeText)
                .frame(width: 36, height: 20)
                .padding(.trailing, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Vegetable Bed Defense")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Day \(game.dayCount)  •  \(game.phase.rawValue)time")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.3)))
    }

    private var timeText: String {
        let dayHours = 12.0
        let nightHours = 12.0
        let hourOffset = game.phase == .day ? 7.0 : 19.0
        let duration = game.phase == .day ? game.dayDuration : game.nightDuration
        let progress = min(max(game.phaseTime / duration, 0), 1)
        let rawHour = hourOffset + progress * (game.phase == .day ? dayHours : nightHours)
        let hour24 = rawHour >= 24 ? rawHour - 24 : rawHour
        let hour = Int(hour24)
        let minutes = Int((hour24 - Double(hour)) * 60)
        return String(format: "%02d:%02d", hour, minutes)
    }
}

private struct DigitalClockView: View {
    let timeText: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.2))
            Text(timeText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

private struct FooterView: View {
    @ObservedObject var game: GameState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button(game.isRunning ? "Pause" : "Resume") {
                    game.togglePause()
                }
                Button("Reset Garden") {
                    game.resetGame()
                    game.isRunning = true
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                Spacer()
                Text(game.message.isEmpty ? "Tip: Click snails to shoo them away!" : game.message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                ForEach(DefenseType.allCases, id: \.self) { type in
                    Button {
                        game.selectDefense(type)
                    } label: {
                        HStack(spacing: 6) {
                            DefenseBadge(type: type, isSelected: game.selectedDefense == type)
                            Text("\(type.displayName) \(type.cost)pt")
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(game.selectedDefense == type ? Color.blue : Color.gray.opacity(0.5))
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(game.skillLevel < type.requiredSkill)
                    .opacity(game.skillLevel < type.requiredSkill ? 0.5 : 1.0)
                }
                Spacer()
                Text("Build during the day • Click to place")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct BackgroundView: View {
    let phaseProgress: Double

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [
                    blend(Color(red: 0.72, green: 0.9, blue: 1.0), Color(red: 0.06, green: 0.08, blue: 0.2), t: phaseProgress),
                    blend(Color(red: 0.93, green: 0.98, blue: 0.92), Color(red: 0.1, green: 0.18, blue: 0.3), t: phaseProgress)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            SunGlowView()
                .opacity(1.0 - phaseProgress)
            StarsView()
                .opacity(phaseProgress)
        }
    }

    private func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        let t = min(max(t, 0), 1)
        let ca = NSColor(a)
        let cb = NSColor(b)
        let r = ca.redComponent + (cb.redComponent - ca.redComponent) * t
        let g = ca.greenComponent + (cb.greenComponent - ca.greenComponent) * t
        let bl = ca.blueComponent + (cb.blueComponent - ca.blueComponent) * t
        return Color(red: r, green: g, blue: bl)
    }
}

private struct SunGlowView: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(gradient: Gradient(colors: [Color.yellow.opacity(0.5), Color.clear]), center: .center, startRadius: 0, endRadius: 260)
            )
            .frame(width: 380, height: 380)
            .offset(x: -200, y: -200)
    }
}

private struct StarsView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<28, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 2.5, height: 2.5)
                        .position(x: CGFloat((index * 37) % Int(geo.size.width)),
                                  y: CGFloat((index * 71) % Int(geo.size.height * 0.5)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct GardenBedView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.55, green: 0.33, blue: 0.18), Color(red: 0.4, green: 0.24, blue: 0.14)]), startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color(red: 0.73, green: 0.5, blue: 0.3), lineWidth: 6)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
    }
}

private struct VegPlotView: View {
    let plot: VegPlot

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.18, green: 0.12, blue: 0.08).opacity(0.6))
                .frame(width: 90, height: 90)

            VStack(spacing: 4) {
                VegIconView(type: plot.type, growth: plot.growth, alive: plot.alive)
                Text(plot.type.displayName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(plot.alive ? 0.9 : 0.4))
            }
        }
        .opacity(plot.alive ? 1.0 : 0.4)
    }
}

private struct VegIconView: View {
    let type: VegType
    let growth: Double
    let alive: Bool

    var body: some View {
        let scale = 0.5 + growth * 0.7
        ZStack {
            switch type {
            case .carrot:
                CarrotShape()
                    .fill(type.baseColor)
                    .frame(width: 42, height: 42)
                    .overlay(
                        LeavesShape()
                            .fill(Color.green)
                            .frame(width: 26, height: 26)
                            .offset(y: -20)
                    )
            case .tomato:
                Circle()
                    .fill(type.baseColor)
                    .frame(width: 38, height: 38)
                    .overlay(
                        StarLeaf()
                            .fill(Color.green)
                            .frame(width: 22, height: 22)
                            .offset(y: -12)
                    )
            case .pumpkin:
                ZStack {
                    Circle().fill(type.baseColor)
                    Circle().fill(Color.orange.opacity(0.8)).scaleEffect(x: 0.65, y: 1.0)
                    Circle().fill(Color.orange.opacity(0.8)).scaleEffect(x: 0.4, y: 1.0)
                }
                .frame(width: 42, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green)
                        .frame(width: 6, height: 12)
                        .offset(y: -22)
                )
            case .salad:
                ZStack {
                    Circle().fill(type.baseColor.opacity(0.8))
                    Circle().fill(type.baseColor).scaleEffect(0.75)
                    Circle().fill(type.baseColor.opacity(0.9)).scaleEffect(0.5)
                }
                .frame(width: 40, height: 40)
            }
        }
        .overlay(BiteMarks(level: 1.0 - growth))
        .compositingGroup()
        .scaleEffect(scale)
        .opacity(alive ? 1.0 : 0.4)
        .animation(.interpolatingSpring(mass: 1.0, stiffness: 100, damping: 14, initialVelocity: 0), value: growth)
    }
}

private struct BiteMarks: View {
    let level: Double

    var body: some View {
        let strength = min(max(level, 0), 1)
        return ZStack {
            Circle()
                .frame(width: 18, height: 18)
                .offset(x: 10, y: -10)
            Circle()
                .frame(width: 14, height: 14)
                .offset(x: -12, y: -6)
            Circle()
                .frame(width: 12, height: 12)
                .offset(x: 6, y: 12)
        }
        .foregroundColor(.white)
        .opacity(strength)
        .blendMode(.destinationOut)
    }
}

private struct SnailView: View {
    let snail: Snail

    var body: some View {
        let wiggle = CGFloat(sin(snail.wobblePhase) * 3.0)
        let angle = Angle(radians: snail.heading + .pi)
        ZStack {
            switch snail.type {
            case .garden:
                GardenSnailBody()
            case .shell:
                ShellSnailBody()
            case .speedy:
                SpeedySnailBody()
            case .slug:
                SlugBody()
            case .helper:
                HelperSnailBody()
            }
        }
        .frame(width: 60, height: 44)
        .contentShape(Rectangle())
        .rotationEffect(angle)
        .offset(x: wiggle)
        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}

private struct SnailTrailLayer: View {
    let snails: [Snail]
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(snails) { snail in
                if snail.trail.count > 1 {
                    SnailTrailPath(trail: snail.trail, size: size)
                        .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    SnailTrailPath(trail: snail.trail, size: size)
                        .stroke(Color.white.opacity(0.18), lineWidth: 4)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SnailTrailPath: Shape {
    let trail: [CGPoint]
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = trail.first else { return path }
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in trail.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        return path
    }
}

private struct HedgehogView: View {
    let heading: Double

    var body: some View {
        HedgehogArt(animate: true)
            .rotationEffect(.radians(heading))
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

private struct HedgehogCageView: View {
    @ObservedObject var game: GameState

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if game.hedgehogState == .sleeping {
                Button {
                    game.releaseHedgehog()
                } label: {
                    HStack(spacing: 10) {
                        HedgehogCageArt()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hedgehog House")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            if game.isHedgehogActiveHours {
                                Text("\(game.hedgehogCost) points • Wake it up")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Sleeps until 17:00")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(game.points < game.hedgehogCost || !game.isHedgehogActiveHours)
            } else {
                HStack(spacing: 8) {
                    HedgehogArt(scale: 0.6, animate: true)
                    Text("Hedgehog active")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
            }
        }
    }
}

private struct HedgehogArt: View {
    var scale: CGFloat = 1.0
    var animate: Bool = false
    @State private var legPhase: Bool = false

    var body: some View {
        ZStack {
            // Legs
            HStack(spacing: 6 * scale) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.18, green: 0.12, blue: 0.08))
                    .frame(width: 6 * scale, height: 10 * scale)
                    .offset(y: animate && legPhase ? 1.5 * scale : 0)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.18, green: 0.12, blue: 0.08))
                    .frame(width: 6 * scale, height: 10 * scale)
                    .offset(y: animate && !legPhase ? 1.5 * scale : 0)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.18, green: 0.12, blue: 0.08))
                    .frame(width: 6 * scale, height: 10 * scale)
                    .offset(y: animate && legPhase ? 1.5 * scale : 0)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.18, green: 0.12, blue: 0.08))
                    .frame(width: 6 * scale, height: 10 * scale)
                    .offset(y: animate && !legPhase ? 1.5 * scale : 0)
            }
            .offset(y: 14 * scale)

            // Body base
            Ellipse()
                .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.33, green: 0.22, blue: 0.16),
                                              Color(red: 0.5, green: 0.38, blue: 0.26)]),
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 76 * scale, height: 42 * scale)

            // Belly
            Ellipse()
                .fill(Color(red: 0.9, green: 0.78, blue: 0.64))
                .frame(width: 36 * scale, height: 22 * scale)
                .offset(x: 18 * scale, y: 2 * scale)

            // Snout
            Ellipse()
                .fill(Color(red: 0.86, green: 0.72, blue: 0.56))
                .frame(width: 16 * scale, height: 10 * scale)
                .offset(x: 34 * scale, y: 2 * scale)

            // Eye + nose
            Circle()
                .fill(Color.black)
                .frame(width: 5 * scale, height: 5 * scale)
                .offset(x: 20 * scale, y: -6 * scale)
            Circle()
                .fill(Color.black)
                .frame(width: 6 * scale, height: 6 * scale)
                .offset(x: 42 * scale, y: 4 * scale)

            // Ear
            Circle()
                .fill(Color(red: 0.4, green: 0.28, blue: 0.2))
                .frame(width: 8 * scale, height: 8 * scale)
                .offset(x: 6 * scale, y: -14 * scale)

            // Spines
            ForEach(0..<22, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.18, green: 0.12, blue: 0.08))
                    .frame(width: 2 * scale, height: 20 * scale)
                    .offset(x: -10 * scale, y: -12 * scale)
                    .rotationEffect(.degrees(Double(index) * 8 - 88))
            }
            ForEach(0..<8, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.25, green: 0.17, blue: 0.1))
                    .frame(width: 2 * scale, height: 14 * scale)
                    .offset(x: -22 * scale, y: -4 * scale)
                    .rotationEffect(.degrees(Double(index) * 9 - 60))
            }
        }
        .onAppear {
            guard animate else { return }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                legPhase.toggle()
            }
        }
    }
}

private struct HedgehogCageArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.78, green: 0.64, blue: 0.46),
                                              Color(red: 0.62, green: 0.48, blue: 0.34)]),
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 60, height: 44)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                .frame(width: 52, height: 36)
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 3, height: 28)
                    .offset(x: CGFloat(index) * 10 - 15)
            }
            Text("zzz")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .offset(x: 14, y: -14)
        }
    }
}

private struct DefenseView: View {
    let defense: Defense

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 46, height: 46)
            switch defense.type {
            case .metalBars:
                MetalBarsIcon()
            case .highVoltage:
                HighVoltageIcon()
            case .razors:
                RazorIcon()
            }
        }
        .overlay(
            Text("\(defense.durability)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .offset(y: 18)
        )
    }
}

private struct LineDefenseView: View {
    let defense: Defense
    let size: CGSize

    var body: some View {
        ZStack {
            let startPt = CGPoint(x: defense.start.x * size.width, y: defense.start.y * size.height)
            let endPt = CGPoint(x: defense.end.x * size.width, y: defense.end.y * size.height)
            let vector = CGVector(dx: endPt.x - startPt.x, dy: endPt.y - startPt.y)
            let length = max(1, hypot(vector.dx, vector.dy))
            let normal = CGVector(dx: -(vector.dy / length), dy: vector.dx / length)

            // Main line
            LineSegmentShape(from: startPt, to: endPt)
                .stroke(defense.type == .razors ? Color.red.opacity(0.7) : Color.gray.opacity(0.7),
                        lineWidth: defense.type == .metalBars ? 8 : 4)

            // Cross bars or spikes
            if defense.type == .metalBars {
                ForEach(0..<max(1, Int(length / 18) + 1), id: \.self) { i in
                    let t = CGFloat(i) / CGFloat(max(1, Int(length / 18)))
                    let px = startPt.x + vector.dx * t
                    let py = startPt.y + vector.dy * t
                    LineSegmentShape(
                        from: CGPoint(x: px + normal.dx * 8, y: py + normal.dy * 8),
                        to: CGPoint(x: px - normal.dx * 8, y: py - normal.dy * 8)
                    )
                    .stroke(Color.gray, lineWidth: 4)
                }
            } else if defense.type == .razors {
                ForEach(0..<max(1, Int(length / 14) + 1), id: \.self) { i in
                    let t = CGFloat(i) / CGFloat(max(1, Int(length / 14)))
                    let px = startPt.x + vector.dx * t
                    let py = startPt.y + vector.dy * t
                    LineSegmentShape(
                        from: CGPoint(x: px - normal.dx * 2, y: py - normal.dy * 2),
                        to: CGPoint(x: px + normal.dx * 8, y: py + normal.dy * 8)
                    )
                    .stroke(Color.white.opacity(0.8), lineWidth: 2)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LineSegmentShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

private struct DragPreviewView: View {
    let start: CGPoint
    let end: CGPoint
    let size: CGSize
    let type: DefenseType

    var body: some View {
        LineSegmentShape(
            from: CGPoint(x: start.x * size.width, y: start.y * size.height),
            to: CGPoint(x: end.x * size.width, y: end.y * size.height)
        )
        .stroke(type == .razors ? Color.red.opacity(0.6) : Color.gray.opacity(0.7), lineWidth: 6)
        .allowsHitTesting(false)
    }
}

private struct DefenseBadge: View {
    let type: DefenseType
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.65))
                .frame(width: 22, height: 22)
            switch type {
            case .metalBars: MetalBarsIcon(scale: 0.7)
            case .highVoltage: HighVoltageIcon(scale: 0.7)
            case .razors: RazorIcon(scale: 0.7)
            }
        }
    }
}

private struct MetalBarsIcon: View {
    var scale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 3 * scale) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray)
                    .frame(width: 4 * scale, height: 20 * scale)
            }
        }
    }
}

private struct HighVoltageIcon: View {
    var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.yellow)
                .frame(width: 24 * scale, height: 20 * scale)
            Image(systemName: "bolt.fill")
                .font(.system(size: 12 * scale, weight: .bold))
                .foregroundColor(.orange)
        }
    }
}

private struct RazorIcon: View {
    var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.7))
                .frame(width: 20 * scale, height: 20 * scale)
            ForEach(0..<6, id: \.self) { index in
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2 * scale, height: 10 * scale)
                    .offset(y: -10 * scale)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
    }
}

private struct GardenSnailBody: View {
    var body: some View {
        ZStack {
            SnailBodyBase(colorA: Color(red: 0.72, green: 0.84, blue: 0.88),
                          colorB: Color(red: 0.6, green: 0.78, blue: 0.84))
            SnailShellBase(shellColor: Color(red: 0.88, green: 0.69, blue: 0.44),
                           spiralColor: Color(red: 0.62, green: 0.44, blue: 0.28))
            SnailEyes()
        }
    }
}

private struct ShellSnailBody: View {
    var body: some View {
        ZStack {
            SnailBodyBase(colorA: Color(red: 0.66, green: 0.8, blue: 0.82),
                          colorB: Color(red: 0.56, green: 0.74, blue: 0.78))
            SnailShellBase(shellColor: Color(red: 0.93, green: 0.79, blue: 0.55),
                           spiralColor: Color(red: 0.7, green: 0.52, blue: 0.32))
                .offset(x: 2)
            SnailHouse()
            SnailEyes()
        }
    }
}

private struct SpeedySnailBody: View {
    var body: some View {
        ZStack {
            SnailBodyBase(colorA: Color(red: 0.64, green: 0.84, blue: 0.72),
                          colorB: Color(red: 0.56, green: 0.78, blue: 0.66))
            SnailShellBase(shellColor: Color(red: 0.9, green: 0.67, blue: 0.4),
                           spiralColor: Color(red: 0.62, green: 0.42, blue: 0.26))
            SnailEyes()
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 22, height: 6)
                .offset(x: -18, y: 8)
        }
    }
}

private struct SlugBody: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.58, green: 0.34, blue: 0.46), Color(red: 0.42, green: 0.24, blue: 0.36)]),
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 56, height: 18)
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 44, height: 8)
                .offset(y: -3)
            HStack(spacing: 6) {
                Circle().fill(Color.white.opacity(0.5)).frame(width: 3, height: 3)
                Circle().fill(Color.white.opacity(0.4)).frame(width: 2, height: 2)
                Circle().fill(Color.white.opacity(0.35)).frame(width: 2, height: 2)
            }
            .offset(x: -6, y: 4)
            SnailEyes()
        }
    }
}

private struct HelperSnailBody: View {
    var body: some View {
        ZStack {
            // Leopard slug - long elongated body, no shell
            // Tapered body shape
            Capsule()
                .fill(LinearGradient(gradient: Gradient(colors: [
                        Color(red: 0.72, green: 0.65, blue: 0.52),
                        Color(red: 0.68, green: 0.60, blue: 0.48),
                        Color(red: 0.62, green: 0.55, blue: 0.42)
                    ]),
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: 56, height: 16)

            // Lighter belly/underside
            Capsule()
                .fill(Color(red: 0.78, green: 0.72, blue: 0.60).opacity(0.5))
                .frame(width: 48, height: 8)
                .offset(y: 3)

            // Mantle (raised area behind head)
            Ellipse()
                .fill(Color(red: 0.70, green: 0.62, blue: 0.50))
                .frame(width: 18, height: 14)
                .offset(x: -12, y: -1)

            // Leopard spots - scattered dark blotches
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(Color(red: 0.2, green: 0.18, blue: 0.14).opacity(0.7))
                    .frame(
                        width: CGFloat([3.5, 2.5, 3, 2, 3.5, 2.5, 3, 2, 2.5, 3, 2, 3.5][index]),
                        height: CGFloat([3.5, 2.5, 3, 2, 3.5, 2.5, 3, 2, 2.5, 3, 2, 3.5][index])
                    )
                    .offset(
                        x: CGFloat([-20, -14, -8, -2, 4, 10, 16, 22, -16, -6, 8, 18][index]),
                        y: CGFloat([-3, 2, -4, 3, -2, 4, -3, 1, 4, -1, 2, -4][index])
                    )
            }

            // Tentacles (two pairs - longer upper, shorter lower)
            // Upper tentacles (eye stalks) - orangish like the photo
            VStack(spacing: 0) {
                Circle()
                    .fill(Color(red: 0.2, green: 0.15, blue: 0.1))
                    .frame(width: 3, height: 3)
                Rectangle()
                    .fill(Color(red: 0.8, green: 0.55, blue: 0.35))
                    .frame(width: 1.5, height: 10)
            }
            .offset(x: -24, y: -12)
            .rotationEffect(.degrees(-15))

            VStack(spacing: 0) {
                Circle()
                    .fill(Color(red: 0.2, green: 0.15, blue: 0.1))
                    .frame(width: 3, height: 3)
                Rectangle()
                    .fill(Color(red: 0.8, green: 0.55, blue: 0.35))
                    .frame(width: 1.5, height: 10)
            }
            .offset(x: -20, y: -12)
            .rotationEffect(.degrees(5))

            // Lower tentacles (shorter, sensing)
            Rectangle()
                .fill(Color(red: 0.8, green: 0.55, blue: 0.35))
                .frame(width: 1, height: 5)
                .offset(x: -26, y: -4)
                .rotationEffect(.degrees(-25))
            Rectangle()
                .fill(Color(red: 0.8, green: 0.55, blue: 0.35))
                .frame(width: 1, height: 5)
                .offset(x: -23, y: -4)
                .rotationEffect(.degrees(-5))
        }
    }
}

private struct SnailEyes: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 2, height: 10)
            Circle()
                .fill(Color.black)
                .frame(width: 4, height: 4)
        }
        .offset(x: -12, y: -12)
    }
}

private struct SnailBodyBase: View {
    let colorA: Color
    let colorB: Color

    var body: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(gradient: Gradient(colors: [colorA, colorB]), startPoint: .leading, endPoint: .trailing))
                .frame(width: 50, height: 26)
                .offset(x: -6)
            Ellipse()
                .fill(Color.white.opacity(0.12))
                .frame(width: 30, height: 8)
                .offset(x: -10, y: -6)
        }
    }
}

private struct SnailShellBase: View {
    let shellColor: Color
    let spiralColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(gradient: Gradient(colors: [shellColor, shellColor.opacity(0.7)]),
                                     center: .center, startRadius: 2, endRadius: 16))
                .frame(width: 26, height: 26)
                .offset(x: 10)
            SpiralShape()
                .stroke(spiralColor, lineWidth: 2)
                .frame(width: 18, height: 18)
                .offset(x: 10)
        }
    }
}

private struct SnailHouse: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(red: 0.88, green: 0.76, blue: 0.52))
            .frame(width: 30, height: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(red: 0.7, green: 0.56, blue: 0.38), lineWidth: 2)
            )
            .offset(x: 12, y: -10)
    }
}

private struct SpiralShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let turns = 2.2
        let maxRadius = min(rect.width, rect.height) / 2
        var t: CGFloat = 0
        let step: CGFloat = 0.12
        var first = true
        while t <= CGFloat(turns * 2 * .pi) {
            let radius = maxRadius * (t / CGFloat(turns * 2 * .pi))
            let x = center.x + cos(t) * radius
            let y = center.y + sin(t) * radius
            if first {
                path.move(to: CGPoint(x: x, y: y))
                first = false
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
            t += step
        }
        return path
    }
}

private struct SidePanelView: View {
    @ObservedObject var game: GameState

    private var pestCount: Int {
        game.snails.filter { $0.alignment == .pest }.count
    }

    private var helperCount: Int {
        game.snails.filter { $0.alignment == .helper }.count
    }

    private var forecastCount: Int {
        Int(3 + game.pestPressure * 10)
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("Night Watch")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            HStack(spacing: 6) {
                Circle().fill(Color(red: 0.84, green: 0.64, blue: 0.36)).frame(width: 8, height: 8)
                Text(game.phase == .day ? "Pests: \(forecastCount)" : "Pests: \(pestCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }

            HStack(spacing: 6) {
                Circle().stroke(Color.white.opacity(0.8), lineWidth: 2).frame(width: 8, height: 8)
                Text("Helpers: \(helperCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }

            Text("🐆 Spotted slugs are friends — don't squish! 😅")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
    }
}

private struct PointsBanner: View {
    let points: Int
    let skillLevel: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("💰 \(points) pts")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0))
            Text("⭐ Skill \(skillLevel)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.3)))
    }
}

private struct CarrotShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct LeavesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.midX - 4, y: rect.minY, width: 8, height: rect.height), cornerSize: CGSize(width: 4, height: 4))
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.midY - 4, width: rect.width, height: 8), cornerSize: CGSize(width: 4, height: 4))
        return path
    }
}

private struct StarLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let points = 5
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<points {
            let angle = Double(i) * (2 * Double.pi / Double(points)) - Double.pi / 2
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct CelestialView: View {
    @ObservedObject var game: GameState

    var body: some View {
        let progress = celestialProgress
        let sunAngle = Double.pi * progress
        let moonAngle = Double.pi * progress

        ZStack {
            // Sky arc background
            Ellipse()
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
                .frame(width: 180, height: 50)

            // Sun - visible during day
            ZStack {
                // Sun glow
                Circle()
                    .fill(RadialGradient(gradient: Gradient(colors: [Color.yellow.opacity(0.6), Color.orange.opacity(0.3), Color.clear]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 20
                    ))
                    .frame(width: 40, height: 40)

                // Sun body
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [Color.yellow, Color.orange]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 24, height: 24)

                // Sun rays
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.yellow.opacity(0.8))
                        .frame(width: 2, height: 6)
                        .offset(y: -18)
                        .rotationEffect(.degrees(Double(index) * 45))
                }
            }
            .offset(
                x: cos(sunAngle) * 80,
                y: -sin(sunAngle) * 22
            )
            .opacity(game.phase == .day ? 1.0 : 0.0)

            // Moon - visible during night
            ZStack {
                // Moon glow
                Circle()
                    .fill(RadialGradient(gradient: Gradient(colors: [Color.white.opacity(0.4), Color.blue.opacity(0.1), Color.clear]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 18
                    ))
                    .frame(width: 36, height: 36)

                // Moon body (crescent effect)
                ZStack {
                    Circle()
                        .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.95, green: 0.95, blue: 0.88), Color(red: 0.85, green: 0.85, blue: 0.78)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 20, height: 20)

                    // Crescent shadow
                    Circle()
                        .fill(Color(red: 0.1, green: 0.15, blue: 0.25))
                        .frame(width: 16, height: 16)
                        .offset(x: 6, y: -2)
                }

                // Moon craters
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 4, height: 4)
                    .offset(x: -4, y: 2)
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 3, height: 3)
                    .offset(x: 2, y: -4)
            }
            .offset(
                x: cos(moonAngle) * 80,
                y: -sin(moonAngle) * 22
            )
            .opacity(game.phase == .night ? 1.0 : 0.0)

            // Horizon line
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 180, height: 1)
                .offset(y: 8)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.3)))
    }

    private var celestialProgress: Double {
        let duration = game.phase == .day ? game.dayDuration : game.nightDuration
        let progress = min(max(game.phaseTime / duration, 0), 1)
        return progress
    }
}
