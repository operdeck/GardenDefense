import SwiftUI
import AVFoundation

// Sound types for the game
enum GameSound: String, CaseIterable {
    case birthday = "birthday"
    case slime = "slime"
    case squeak = "squeak"
    case footsteps = "footsteps"
    case zap = "zap"
    case build = "build"
    case crunch = "crunch"
    case night = "night"
    case morning = "morning"
    case shriek = "shriek"
    
    var fileExtension: String {
        return "aiff"  // All sounds are now AIFF
    }
    
    var volume: Float {
        switch self {
        case .birthday: return 0.7
        case .slime: return 0.15  // Soft ambient
        case .squeak: return 0.6  // High-pitched squeak for snail kills
        case .footsteps: return 0.25  // Subtle click-click
        case .zap: return 0.5  // Electric zap
        case .build: return 0.5
        case .crunch: return 0.45
        case .night: return 0.3
        case .morning: return 0.4
        case .shriek: return 0.4  // Short sharp shriek for snail kills
        }
    }
    
    var cooldown: Double {
        switch self {
        case .slime: return 0.8  // Don't spam slime sounds
        case .footsteps: return 0.3
        case .squeak: return 0.15
        default: return 0.0
        }
    }
}

// Sound manager with multiple audio players for overlapping sounds
class SoundManager {
    static let shared = SoundManager()
    
    private var players: [GameSound: AVAudioPlayer] = [:]
    private var ambientPlayer: AVAudioPlayer?
    private var lastPlayTime: [GameSound: Date] = [:]
    
    private init() {
        preloadSounds()
    }
    
    private func preloadSounds() {
        for sound in GameSound.allCases {
            if let url = Bundle.module.url(forResource: sound.rawValue, withExtension: sound.fileExtension) {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    players[sound] = player
                } catch {
                    print("⚠️ Could not load \(sound.rawValue).\(sound.fileExtension): \(error.localizedDescription)")
                }
            } else {
                print("⚠️ Could not find \(sound.rawValue).\(sound.fileExtension) in bundle")
            }
        }
    }
    
    func play(_ sound: GameSound) {
        // Check cooldown
        if sound.cooldown > 0 {
            if let lastTime = lastPlayTime[sound] {
                if Date().timeIntervalSince(lastTime) < sound.cooldown {
                    return  // Still in cooldown
                }
            }
            lastPlayTime[sound] = Date()
        }
        
        guard let player = players[sound] else { return }
        
        // Create a new player for overlapping sounds
        if player.isPlaying && sound.cooldown == 0 {
            if let url = Bundle.module.url(forResource: sound.rawValue, withExtension: sound.fileExtension),
               let newPlayer = try? AVAudioPlayer(contentsOf: url) {
                newPlayer.volume = sound.volume
                newPlayer.play()
                return
            }
        }
        
        player.volume = sound.volume
        player.currentTime = 0
        player.play()
    }
    
    // Convenience methods
    func playBirthday() { play(.birthday) }
    func playSlime() { play(.slime) }
    func playSqueak() { play(.squeak) }
    func playFootsteps() { play(.footsteps) }
    func playZap() { play(.zap) }
    func playBuild() { play(.build) }
    func playCrunch() { play(.crunch) }
    func playNight() { play(.night) }
    func playMorning() { play(.morning) }
    
    // Map game events to sounds
    func handleGameSound(_ event: GameSoundEvent) {
        switch event {
        case .snailMove:
            play(.slime)
        case .snailKilled:
            play(.shriek)
        case .snailZapped:
            play(.zap)
        case .hedgehogMove:
            play(.footsteps)
        case .hedgehogEat:
            play(.crunch)
        case .defensePlaced:
            play(.build)
        case .cropEaten:
            play(.crunch)
        case .nightFalls:
            play(.night)
        case .morningComes:
            play(.morning)
        case .gameOver:
            play(.squeak)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct GardenDefenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var game = GameState()
    @StateObject private var leaderboard = LeaderboardManager()
    @State private var playerName: String = ""
    @State private var isAnonymous: Bool = false
    @State private var showNameEntry: Bool = true
    @State private var showLeaderboard: Bool = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                GameView(game: game)
                    .frame(minWidth: 900, minHeight: 650)

                if showNameEntry {
                    NameEntryView(
                        leaderboard: leaderboard,
                        playerName: $playerName,
                        isAnonymous: $isAnonymous,
                        onStart: {
                            showNameEntry = false
                            game.resetGame()
                            game.isRunning = true
                        }
                    )
                    .zIndex(20)
                }

                if showLeaderboard {
                    LeaderboardView(leaderboard: leaderboard, onDismiss: {
                        showLeaderboard = false
                    })
                    .zIndex(21)
                }
            }
            .frame(minWidth: 900, minHeight: 650)
            .onAppear {
                game.isRunning = false  // Don't start until name is entered
                // Connect game sound events to SoundManager
                game.onSound = { event in
                    SoundManager.shared.handleGameSound(event)
                }
                // Connect game over callback for leaderboard
                game.onGameOver = {
                    if !self.isAnonymous && !self.playerName.isEmpty {
                        self.leaderboard.addEntry(
                            name: self.playerName,
                            points: self.game.points,
                            skillLevel: self.game.skillLevel,
                            daysSurvived: self.game.dayCount
                        )
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.showLeaderboard = true
                    }
                }
                // Play happy birthday sound on startup
                SoundManager.shared.playBirthday()
            }
        }
    }
}
