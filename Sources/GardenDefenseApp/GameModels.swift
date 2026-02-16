import Foundation
import SwiftUI

enum GamePhase: String {
    case day = "Day"
    case night = "Night"
}

enum VegType: String, CaseIterable {
    case carrot
    case tomato
    case pumpkin
    case salad

    var displayName: String {
        switch self {
        case .carrot: return "Carrot"
        case .tomato: return "Tomato"
        case .pumpkin: return "Pumpkin"
        case .salad: return "Salad"
        }
    }

    var baseColor: Color {
        switch self {
        case .carrot: return Color.orange
        case .tomato: return Color.red
        case .pumpkin: return Color(red: 0.96, green: 0.55, blue: 0.12)
        case .salad: return Color.green
        }
    }
}

struct VegPlot: Identifiable {
    let id = UUID()
    let type: VegType
    var growth: Double
    var alive: Bool
    var position: CGPoint
}

struct Snail: Identifiable {
    let id = UUID()
    var position: CGPoint
    var speed: Double
    var type: SnailType
    var alignment: CritterAlignment
    var wobblePhase: Double
    var creepPhase: Double
    var trail: [CGPoint]
    var heading: Double
}

enum CritterAlignment: String {
    case pest
    case helper
}

enum DefenseType: String, CaseIterable {
    case metalBars
    case highVoltage
    case razors

    var displayName: String {
        switch self {
        case .metalBars: return "Metal Bars"
        case .highVoltage: return "High Voltage"
        case .razors: return "Razors"
        }
    }

    var cost: Int {
        switch self {
        case .metalBars: return 12
        case .highVoltage: return 20
        case .razors: return 28
        }
    }

    var requiredSkill: Int {
        switch self {
        case .metalBars: return 1
        case .highVoltage: return 2
        case .razors: return 3
        }
    }

    var durability: Int {
        switch self {
        case .metalBars: return 3
        case .highVoltage: return 2
        case .razors: return 2
        }
    }
}

struct Defense: Identifiable {
    let id = UUID()
    let type: DefenseType
    var start: CGPoint
    var end: CGPoint
    var durability: Int

    var center: CGPoint {
        CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
    }

    var isLine: Bool {
        switch type {
        case .metalBars, .razors:
            return true
        case .highVoltage:
            return false
        }
    }
}

struct Hedgehog: Identifiable {
    let id = UUID()
    var position: CGPoint
    var speed: Double
    var activeTime: Double
    var wanderPhase: Double
    var heading: Double
}

enum HedgehogState: String {
    case sleeping
    case active
    case returningHome
}

enum SnailType: CaseIterable {
    case garden
    case shell
    case speedy
    case slug
    case helper

    var speedRange: ClosedRange<Double> {
        switch self {
        case .garden: return 0.08...0.11
        case .shell: return 0.06...0.09
        case .speedy: return 0.12...0.16
        case .slug: return 0.09...0.13
        case .helper: return 0.11...0.15
        }
    }
}

// Sound callback type for game events
typealias SoundCallback = (GameSoundEvent) -> Void

enum GameSoundEvent {
    case snailMove
    case snailKilled
    case snailZapped
    case hedgehogMove
    case hedgehogEat
    case defensePlaced
    case cropEaten
    case nightFalls
    case morningComes
    case gameOver
}

final class GameState: ObservableObject {
    @Published var phase: GamePhase = .day
    @Published var phaseTime: Double = 0
    @Published var dayCount: Int = 1
    @Published var points: Int = 0
    @Published var skillXP: Int = 0
    @Published var pestPressure: Double = 0
    @Published var veggies: [VegPlot] = []
    @Published var snails: [Snail] = []
    @Published var defenses: [Defense] = []
    @Published var hedgehog: Hedgehog?
    @Published var hedgehogState: HedgehogState = .sleeping
    @Published var selectedDefense: DefenseType? = .metalBars
    @Published var isRunning: Bool = true
    @Published var message: String = ""

    private var lastUpdate = Date()
    private var timer: Timer?
    private var spawnCooldown: Double = 0
    private var pointsAccumulator: Double = 0
    private var announcedCropLoss: Set<VegType> = []
    private var scoutAccumulator: Double = 0
    
    // Sound callback
    var onSound: SoundCallback?
    var onGameOver: (() -> Void)?
    
    private func playSound(_ event: GameSoundEvent) {
        onSound?(event)
    }

    let dayDuration: Double = 18
    let nightDuration: Double = 18
    let maxSnails = 8
    let maxDefenses = 10
    let hedgehogCost = 35

    var skillLevel: Int {
        max(1, 1 + skillXP / 10)
    }

    init() {
        resetGame()
        startTimer()
    }

    func resetGame() {
        phase = .day
        phaseTime = 0
        dayCount = 1
        points = 20  // Start with some points
        skillXP = 0
        pestPressure = 0
        snails = []
        defenses = []
        hedgehog = nil
        hedgehogState = .sleeping
        message = ""
        veggies = GameState.makeGarden()
        pointsAccumulator = 0
        announcedCropLoss = []
        scoutAccumulator = 0
        lastUpdate = Date()
    }

    func togglePause() {
        isRunning.toggle()
        message = isRunning ? "" : "Paused"
    }

    func removeSnail(_ snailID: UUID) {
        guard let critter = snails.first(where: { $0.id == snailID }) else { return }
        if critter.alignment == .helper {
            message = "🤦 Oops! You squished your own leopard slug! -10 pts"
            snails.removeAll { $0.id == snailID }
            points = max(0, points - 10)
            playSound(.snailKilled)
            return
        }
        snails.removeAll { $0.id == snailID }
        points += 3
        skillXP += 1
        playSound(.snailKilled)
    }

    func selectDefense(_ type: DefenseType) {
        selectedDefense = type
    }

    func placeDefense(at normalizedPoint: CGPoint) {
        guard let type = selectedDefense else { return }
        guard phase == .day else {
            message = "Build defenses during the day."
            return
        }
        guard type == .highVoltage else {
            message = "Drag to place \(type.displayName)."
            return
        }
        guard skillLevel >= type.requiredSkill else {
            message = "Need Skill \(type.requiredSkill) for \(type.displayName)."
            return
        }
        guard points >= type.cost else {
            message = "Not enough points for \(type.displayName)."
            return
        }
        guard defenses.count < maxDefenses else {
            message = "No more space for defenses."
            return
        }

        points -= type.cost
        defenses.append(Defense(type: type, start: normalizedPoint, end: normalizedPoint, durability: type.durability))
        message = "\(type.displayName) placed!"
        playSound(.defensePlaced)
    }

    func placeDefenseLine(from start: CGPoint, to end: CGPoint) {
        guard let type = selectedDefense else { return }
        guard phase == .day else {
            message = "Build defenses during the day."
            return
        }
        guard type != .highVoltage else {
            message = "Click to place \(type.displayName)."
            return
        }
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length >= 0.08 else {
            message = "Drag a longer line for \(type.displayName)."
            return
        }
        guard skillLevel >= type.requiredSkill else {
            message = "Need Skill \(type.requiredSkill) for \(type.displayName)."
            return
        }
        guard points >= type.cost else {
            message = "Not enough points for \(type.displayName)."
            return
        }
        guard defenses.count < maxDefenses else {
            message = "No more space for defenses."
            return
        }

        points -= type.cost
        defenses.append(Defense(type: type, start: start, end: end, durability: type.durability))
        message = "\(type.displayName) placed!"
        playSound(.defensePlaced)
    }

    // Calculate current game hour (0-24)
    var currentHour: Double {
        let dayHours = 12.0
        let nightHours = 12.0
        let hourOffset = phase == .day ? 7.0 : 19.0
        let duration = phase == .day ? dayDuration : nightDuration
        let progress = min(max(phaseTime / duration, 0), 1)
        let rawHour = hourOffset + progress * (phase == .day ? dayHours : nightHours)
        return rawHour >= 24 ? rawHour - 24 : rawHour
    }
    
    // Hedgehog is only active 17:00 - 23:00
    var isHedgehogActiveHours: Bool {
        currentHour >= 17.0 && currentHour < 23.0
    }
    
    // Time for hedgehog to go home (23:00 or later, before midnight)
    var shouldHedgehogGoHome: Bool {
        currentHour >= 23.0 || currentHour < 7.0
    }
    
    func releaseHedgehog() {
        guard hedgehogState == .sleeping else {
            message = "The hedgehog is already out!"
            return
        }
        guard isHedgehogActiveHours else {
            message = "🦔 Hedgehog only wakes up between 17:00 and 23:00"
            return
        }
        guard points >= hedgehogCost else {
            message = "Not enough points for a hedgehog."
            return
        }
        points -= hedgehogCost
        hedgehog = Hedgehog(position: CGPoint(x: 0.85, y: 0.1),
                            speed: 0.16,
                            activeTime: 999,  // Stays active until 23:00
                            wanderPhase: Double.random(in: 0...Double.pi * 2),
                            heading: 0)
        hedgehogState = .active
        message = "🦔 Hedgehog is awake!"
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard isRunning else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastUpdate)
        lastUpdate = now

        phaseTime += dt
        if phase == .day {
            updateDay(dt: dt)
            if phaseTime >= dayDuration {
                phase = .night
                phaseTime = 0
                spawnCooldown = 0
                message = "Night falls... protect the veggies!"
                scoutAccumulator = 0
                playSound(.nightFalls)
            }
        } else {
            updateNight(dt: dt)
            if phaseTime >= nightDuration {
                phase = .day
                phaseTime = 0
                dayCount += 1
                points += 10
                message = "Morning! The garden survived the night."
                playSound(.morningComes)
            }
        }

        checkCropLossAnnouncements()

        // Game over: all crops eaten
        if veggies.allSatisfy({ !$0.alive }) {
            message = "🐌 The snails ate all your veggies! Game Over."
            isRunning = false
            playSound(.gameOver)
            onGameOver?()
        }

        // Game over: points reach zero
        if points <= 0 && isRunning {
            points = 0
            message = "💀 You ran out of points! Game Over."
            isRunning = false
            playSound(.gameOver)
            onGameOver?()
        }
    }

    private func updateDay(dt: Double) {
        pestPressure = min(1.0, pestPressure + dt * 0.02)  // Slower pest buildup
        // Point accumulation - about 1.5 points per second
        pointsAccumulator += dt * 1.5
        if pointsAccumulator >= 1.0 {
            let earned = Int(pointsAccumulator)
            points += earned
            pointsAccumulator -= Double(earned)
        }

        scoutAccumulator += dt * (0.6 + pestPressure * 1.8)
        if scoutAccumulator >= 1.0 {
            let gained = Int(scoutAccumulator)
            for _ in 0..<gained {
                if snails.filter({ $0.alignment == .pest }).count < maxSnails {
                    snails.append(GameState.spawnPestScout())
                }
            }
            scoutAccumulator -= Double(gained)
        }

        // Crops regrow during the day - this also heals bite marks visually
        for index in veggies.indices {
            if veggies[index].alive {
                veggies[index].growth = min(1.0, veggies[index].growth + dt * 0.06)
            }
        }

        updateHedgehog(dt: dt)
    }

    private func updateNight(dt: Double) {
        spawnCooldown -= dt
        if spawnCooldown <= 0, snails.count < maxSnails {
            let pressureFactor = 1.0 - min(0.6, pestPressure * 0.5)
            spawnCooldown = 3.0 * pressureFactor + 1.0  // Slower spawning
            snails.append(GameState.spawnCritter(allowHelper: true))
        }

        for index in snails.indices {
            guard let target = nearestTargetPoint(for: snails[index]) else { continue }
            let dir = CGVector(dx: target.x - snails[index].position.x, dy: target.y - snails[index].position.y)
            let dist = max(0.001, hypot(dir.dx, dir.dy))
            let creep = 0.25 + 0.75 * max(0.0, sin(snails[index].creepPhase))
            let step = snails[index].speed * creep * dt
            let nx = snails[index].position.x + dir.dx / dist * step
            let ny = snails[index].position.y + dir.dy / dist * step
            snails[index].position = CGPoint(x: nx, y: ny)
            snails[index].wobblePhase += dt * (snails[index].type == .speedy ? 6.0 : 4.0)
            snails[index].creepPhase += dt * 2.2
            snails[index].heading = atan2(dir.dy, dir.dx)
            updateTrail(for: index)
            // Snail movement sound (will be rate-limited by SoundManager cooldown)
            playSound(.snailMove)
        }

        updateHedgehog(dt: dt)

        var defensesToRemove: [UUID] = []
        var snailsToRemove: [UUID] = []
        for index in snails.indices {
            var snail = snails[index]
            if snail.alignment == .helper {
                if let targetIndex = nearestPestIndex(to: snail.position) {
                    let target = snails[targetIndex]
                    let dist = hypot(target.position.x - snail.position.x, target.position.y - snail.position.y)
                    if dist < 0.05 {
                        snailsToRemove.append(target.id)
                        points += 4
                        skillXP += 1
                    }
                }
            }

            if let defenseIndex = nearestDefenseIndex(to: snail.position) {
                let defense = defenses[defenseIndex]
                let dist = defenseDistance(defense, to: snail.position)
                if dist < 0.06 {
                    switch defense.type {
                    case .metalBars:
                        let angle = snail.heading + Double.pi
                        snail.position = CGPoint(x: snail.position.x + cos(angle) * 0.06,
                                                 y: snail.position.y + sin(angle) * 0.06)
                        snail.heading = angle
                        snails[index] = snail
                        continue
                    case .highVoltage, .razors:
                        snailsToRemove.append(snail.id)
                        var updated = defense
                        updated.durability -= 1
                        if updated.durability <= 0 {
                            defensesToRemove.append(defense.id)
                        } else {
                            defenses[defenseIndex] = updated
                        }
                        points += 3
                        skillXP += 1
                        playSound(.snailZapped)
                        continue
                    }
                }
            }

            // Only pests eat veggies
            guard snail.alignment == .pest else { continue }

            if let targetIndex = nearestVegIndex(to: snail.position) {
                let target = veggies[targetIndex]
                let dist = hypot(target.position.x - snail.position.x, target.position.y - snail.position.y)
                if dist < 0.05 {
                    var updated = target
                    updated.growth = max(0, updated.growth - 0.45)
                    if updated.growth <= 0.1 {
                        updated.alive = false
                    }
                    veggies[targetIndex] = updated
                    snailsToRemove.append(snail.id)
                    // Point penalty for letting snails eat crops
                    points = max(0, points - 5)
                    playSound(.cropEaten)
                }
            }
        }
        if !snailsToRemove.isEmpty {
            snails.removeAll { snailsToRemove.contains($0.id) }
        }
        if !defensesToRemove.isEmpty {
            defenses.removeAll { defensesToRemove.contains($0.id) }
        }
        pestPressure = max(0, pestPressure - dt * 0.05)
    }

    private func checkCropLossAnnouncements() {
        for type in VegType.allCases {
            if announcedCropLoss.contains(type) { continue }
            let anyAlive = veggies.contains { $0.type == type && $0.alive }
            if !anyAlive {
                announcedCropLoss.insert(type)
                message = "All the \(type.displayName.lowercased()) are gone!"
            }
        }
    }

    private func nearestVeg(to point: CGPoint) -> VegPlot? {
        veggies
            .filter { $0.alive }
            .min(by: { hypot($0.position.x - point.x, $0.position.y - point.y) < hypot($1.position.x - point.x, $1.position.y - point.y) })
    }

    private func nearestTargetPoint(for critter: Snail) -> CGPoint? {
        switch critter.alignment {
        case .pest:
            return nearestVeg(to: critter.position)?.position
        case .helper:
            if let index = nearestPestIndex(to: critter.position) {
                return snails[index].position
            }
            return nil
        }
    }

    private func nearestVegIndex(to point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDist = Double.greatestFiniteMagnitude
        for index in veggies.indices where veggies[index].alive {
            let dist = hypot(veggies[index].position.x - point.x, veggies[index].position.y - point.y)
            if dist < bestDist {
                bestDist = dist
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func nearestPestIndex(to point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDist = Double.greatestFiniteMagnitude
        for index in snails.indices where snails[index].alignment == .pest {
            let dist = hypot(snails[index].position.x - point.x, snails[index].position.y - point.y)
            if dist < bestDist {
                bestDist = dist
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func nearestDefenseIndex(to point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDist = Double.greatestFiniteMagnitude
        for index in defenses.indices {
            let dist = defenseDistance(defenses[index], to: point)
            if dist < bestDist {
                bestDist = dist
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func defenseDistance(_ defense: Defense, to point: CGPoint) -> Double {
        if !defense.isLine {
            return hypot(defense.center.x - point.x, defense.center.y - point.y)
        }
        let ax = defense.start.x
        let ay = defense.start.y
        let bx = defense.end.x
        let by = defense.end.y
        let px = point.x
        let py = point.y
        let abx = bx - ax
        let aby = by - ay
        let apx = px - ax
        let apy = py - ay
        let abLen2 = abx * abx + aby * aby
        let t = abLen2 > 0 ? max(0, min(1, (apx * abx + apy * aby) / abLen2)) : 0
        let cx = ax + abx * t
        let cy = ay + aby * t
        return hypot(px - cx, py - cy)
    }

    private static func makeGarden() -> [VegPlot] {
        var plots: [VegPlot] = []
        // 3 rows x 4 columns, centered within the garden bed
        // Positions are now relative to the garden bed GeometryReader
        let cols = 4
        let rows = 3
        // Use full garden bed space with margins for visual padding
        let xMargin = 0.12
        let yMargin = 0.15
        let xEnd = 0.88
        let yEnd = 0.85
        let xSpacing = (xEnd - xMargin) / Double(cols - 1)
        let ySpacing = (yEnd - yMargin) / Double(rows - 1)

        var positions: [CGPoint] = []
        for row in 0..<rows {
            for col in 0..<cols {
                let x = xMargin + Double(col) * xSpacing
                let y = yMargin + Double(row) * ySpacing
                positions.append(CGPoint(x: x, y: y))
            }
        }

        // Assign vegetable types: each column gets one type
        let vegTypes = VegType.allCases
        for (index, pos) in positions.enumerated() {
            let col = index % cols
            let type = vegTypes[col % vegTypes.count]
            plots.append(VegPlot(type: type, growth: Double.random(in: 0.45...0.75), alive: true, position: pos))
        }
        return plots
    }

    private static func spawnCritter(allowHelper: Bool) -> Snail {
        let edge = Int.random(in: 0..<4)
        let pos: CGPoint
        switch edge {
        case 0: pos = CGPoint(x: Double.random(in: 0.05...0.95), y: -0.08)
        case 1: pos = CGPoint(x: Double.random(in: 0.05...0.95), y: 1.08)
        case 2: pos = CGPoint(x: -0.08, y: Double.random(in: 0.05...0.95))
        default: pos = CGPoint(x: 1.08, y: Double.random(in: 0.05...0.95))
        }

        let isHelper = allowHelper && Double.random(in: 0...1) < 0.10
        let type: SnailType = isHelper ? .helper : (SnailType.allCases.filter { $0 != .helper }.randomElement() ?? .garden)
        let speed = Double.random(in: type.speedRange)
        let alignment: CritterAlignment = isHelper ? .helper : .pest
        return Snail(position: pos,
                     speed: speed,
                     type: type,
                     alignment: alignment,
                     wobblePhase: Double.random(in: 0...Double.pi * 2),
                     creepPhase: Double.random(in: 0...Double.pi * 2),
                     trail: [],
                     heading: Double.random(in: 0...(Double.pi * 2)))
    }

    private static func spawnPestScout() -> Snail {
        let pos = randomBedPosition()
        let type: SnailType = Bool.random() ? .garden : .slug
        let speed = Double.random(in: type.speedRange)
        return Snail(position: pos,
                     speed: speed * 0.6,
                     type: type,
                     alignment: .pest,
                     wobblePhase: Double.random(in: 0...Double.pi * 2),
                     creepPhase: Double.random(in: 0...Double.pi * 2),
                     trail: [],
                     heading: Double.random(in: 0...(Double.pi * 2)))
    }

    private static func randomBedPosition() -> CGPoint {
        let around = Double.random(in: 0...1) < 0.35
        let x = around ? Double.random(in: 0.05...0.95) : Double.random(in: 0.12...0.88)
        let y = around ? Double.random(in: 0.12...0.92) : Double.random(in: 0.2...0.88)
        return CGPoint(x: x, y: y)
    }

    private func updateTrail(for index: Int) {
        var trail = snails[index].trail
        let pos = snails[index].position
        if let last = trail.last {
            let dist = hypot(pos.x - last.x, pos.y - last.y)
            if dist < 0.012 { return }
        }
        trail.append(pos)
        if trail.count > 18 {
            trail.removeFirst(trail.count - 18)
        }
        snails[index].trail = trail
    }

    private func nearestSnailIndex(to point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDist = Double.greatestFiniteMagnitude
        for index in snails.indices {
            let dist = hypot(snails[index].position.x - point.x, snails[index].position.y - point.y)
            if dist < bestDist {
                bestDist = dist
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func updateHedgehog(dt: Double) {
        guard var hog = hedgehog else { return }
        if let targetIndex = nearestSnailIndex(to: hog.position) {
            let target = snails[targetIndex]
            let dir = CGVector(dx: target.position.x - hog.position.x, dy: target.position.y - hog.position.y)
            let dist = max(0.001, hypot(dir.dx, dir.dy))
            let step = hog.speed * dt
            let nx = hog.position.x + dir.dx / dist * step
            let ny = hog.position.y + dir.dy / dist * step
            hog.position = CGPoint(x: nx, y: ny)
            hog.heading = atan2(dir.dy, dir.dx)

            if dist < 0.06 {
                snails.removeAll { $0.id == target.id }
                points += 4
                skillXP += 1
                playSound(.hedgehogEat)
            }
            playSound(.hedgehogMove)
        } else {
            // Wander smoothly in the garden area
            hog.wanderPhase += dt * 0.8
            let targetX = 0.5 + cos(hog.wanderPhase) * 0.2
            let targetY = 0.5 + sin(hog.wanderPhase * 0.7) * 0.15
            
            // Move toward target smoothly
            let dir = CGVector(dx: targetX - hog.position.x, dy: targetY - hog.position.y)
            let dist = hypot(dir.dx, dir.dy)
            if dist > 0.01 {
                let step = hog.speed * 0.5 * dt
                let nx = hog.position.x + dir.dx / dist * step
                let ny = hog.position.y + dir.dy / dist * step
                hog.position = CGPoint(x: nx, y: ny)
                hog.heading = atan2(dir.dy, dir.dx)
            }
        }

        // Hedgehog goes home at 23:00
        if shouldHedgehogGoHome && hedgehogState == .active {
            hedgehogState = .returningHome
            message = "🦔 Hedgehog is heading home..."
        }
        
        // When returning home, move toward the house
        if hedgehogState == .returningHome {
            let homePos = CGPoint(x: 0.92, y: 0.08)  // Near the house UI
            let dir = CGVector(dx: homePos.x - hog.position.x, dy: homePos.y - hog.position.y)
            let dist = hypot(dir.dx, dir.dy)
            
            if dist < 0.05 {
                // Arrived home
                hedgehog = nil
                hedgehogState = .sleeping
                message = "🦔 Hedgehog is back in its house"
            } else {
                // Move toward home
                let step = hog.speed * 1.5 * dt  // Move faster when going home
                let nx = hog.position.x + dir.dx / dist * step
                let ny = hog.position.y + dir.dy / dist * step
                hog.position = CGPoint(x: nx, y: ny)
                hog.heading = atan2(dir.dy, dir.dx)
                hedgehog = hog
                playSound(.hedgehogMove)
            }
        } else {
            hedgehog = hog
        }
    }
}
