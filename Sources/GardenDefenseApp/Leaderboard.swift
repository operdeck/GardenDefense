import Foundation
import SwiftUI

// MARK: - Leaderboard Data

struct LeaderboardEntry: Codable, Identifiable {
    let id: UUID
    let name: String
    let points: Int
    let skillLevel: Int
    let daysSurvived: Int
    let date: Date

    init(name: String, points: Int, skillLevel: Int, daysSurvived: Int) {
        self.id = UUID()
        self.name = name
        self.points = points
        self.skillLevel = skillLevel
        self.daysSurvived = daysSurvived
        self.date = Date()
    }
}

// MARK: - Leaderboard Manager

class LeaderboardManager: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var previousNames: [String] = []

    private let fileName = "garden_defense_leaderboard.json"

    init() {
        load()
    }

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("GardenDefense")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent(fileName)
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LeaderboardEntry].self, from: data) else {
            entries = []
            previousNames = []
            return
        }
        entries = decoded.sorted { $0.daysSurvived > $1.daysSurvived || ($0.daysSurvived == $1.daysSurvived && $0.points > $1.points) }
        previousNames = Array(Set(entries.map { $0.name })).sorted()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL)
    }

    func addEntry(name: String, points: Int, skillLevel: Int, daysSurvived: Int) {
        let entry = LeaderboardEntry(name: name, points: points, skillLevel: skillLevel, daysSurvived: daysSurvived)
        entries.append(entry)
        entries.sort { $0.daysSurvived > $1.daysSurvived || ($0.daysSurvived == $1.daysSurvived && $0.points > $1.points) }
        // Keep top 50
        if entries.count > 50 {
            entries = Array(entries.prefix(50))
        }
        if !previousNames.contains(name) {
            previousNames.append(name)
            previousNames.sort()
        }
        save()
    }
}

// MARK: - Name Entry View

struct NameEntryView: View {
    @ObservedObject var leaderboard: LeaderboardManager
    @Binding var playerName: String
    @Binding var isAnonymous: Bool
    let onStart: () -> Void

    @State private var typedName: String = ""

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("🌱 Garden Defense 🌱")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Enter your name for the leaderboard")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                // Name input
                TextField("Your name...", text: $typedName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 250)
                    .font(.system(size: 16, design: .rounded))

                // Previous players
                if !leaderboard.previousNames.isEmpty {
                    VStack(spacing: 8) {
                        Text("Or pick a returning gardener:")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))

                        HStack(spacing: 8) {
                            ForEach(leaderboard.previousNames.prefix(6), id: \.self) { name in
                                Button(name) {
                                    typedName = name
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(typedName == name ? Color.green.opacity(0.6) : Color.white.opacity(0.15))
                                )
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                    }
                }

                HStack(spacing: 16) {
                    // Start with name
                    Button {
                        playerName = typedName.trimmingCharacters(in: .whitespaces)
                        isAnonymous = false
                        onStart()
                    } label: {
                        HStack(spacing: 8) {
                            Text("🥕")
                            Text("Start Game")
                        }
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(typedName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(typedName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)

                    // Anonymous
                    Button {
                        playerName = ""
                        isAnonymous = true
                        onStart()
                    } label: {
                        HStack(spacing: 8) {
                            Text("🐌")
                            Text("Play Anonymous")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.4))
                        .foregroundColor(.white.opacity(0.8))
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Show leaderboard button if there are entries
                if !leaderboard.entries.isEmpty {
                    Button("🏆 View Leaderboard") {
                        // Toggle inline leaderboard
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.yellow.opacity(0.8))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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

// MARK: - Leaderboard View

struct LeaderboardView: View {
    @ObservedObject var leaderboard: LeaderboardManager
    let onDismiss: () -> Void

    private let veggieEmojis = ["🥕", "🍅", "🎃", "🥬", "🌽", "🥒", "🍆", "🌶️"]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header with vegetable decoration
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        Text(veggieEmojis[i])
                            .font(.system(size: 20))
                    }
                    Text("🏆 Leaderboard 🏆")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                    ForEach(4..<8, id: \.self) { i in
                        Text(veggieEmojis[i])
                            .font(.system(size: 20))
                    }
                }

                // Column headers
                HStack {
                    Text("#")
                        .frame(width: 30)
                    Text("Gardener")
                        .frame(width: 140, alignment: .leading)
                    Text("Days")
                        .frame(width: 50)
                    Text("Points")
                        .frame(width: 60)
                    Text("Skill")
                        .frame(width: 50)
                    Text("Date")
                        .frame(width: 80)
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

                // Entries
                ScrollView {
                    VStack(spacing: 4) {
                        if leaderboard.entries.isEmpty {
                            Text("No entries yet — be the first gardener! 🌱")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.top, 20)
                        } else {
                            ForEach(Array(leaderboard.entries.prefix(20).enumerated()), id: \.element.id) { index, entry in
                                LeaderboardRowView(rank: index + 1, entry: entry, veggie: veggieEmojis[index % veggieEmojis.count])
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)

                // Bottom veggie border
                HStack(spacing: 8) {
                    ForEach(0..<10, id: \.self) { i in
                        Text(veggieEmojis[i % veggieEmojis.count])
                            .font(.system(size: 14))
                            .opacity(0.5)
                    }
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Close")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.1, green: 0.12, blue: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color(red: 0.4, green: 0.55, blue: 0.3), lineWidth: 2)
                    )
            )
            .frame(maxWidth: 600)
        }
    }
}

private struct LeaderboardRowView: View {
    let rank: Int
    let entry: LeaderboardEntry
    let veggie: String

    var body: some View {
        HStack {
            Text(rank <= 3 ? ["🥇", "🥈", "🥉"][rank - 1] : "\(rank)")
                .frame(width: 30)
                .font(.system(size: rank <= 3 ? 16 : 12, weight: .bold, design: .rounded))
            HStack(spacing: 4) {
                Text(veggie)
                    .font(.system(size: 12))
                Text(entry.name)
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)
            Text("\(entry.daysSurvived)")
                .frame(width: 50)
                .foregroundColor(.yellow)
            Text("\(entry.points)")
                .frame(width: 60)
            Text("\(entry.skillLevel)")
                .frame(width: 50)
            Text(shortDate(entry.date))
                .frame(width: 80)
                .foregroundColor(.white.opacity(0.5))
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundColor(.white.opacity(0.85))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rank <= 3 ? Color.yellow.opacity(0.08) : Color.white.opacity(0.03))
        )
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        return formatter.string(from: date)
    }
}
