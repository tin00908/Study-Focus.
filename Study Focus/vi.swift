import Foundation
import SwiftUI
import Combine
import OSLog

protocol StudyDataStore {
    func load() -> StudentData?
    func save(_ data: StudentData) throws
}

struct UserDefaultsStudyDataStore: StudyDataStore {
    private let key = "tin.student.data.v1" // v1 contains the local-only student profile.
    private let logger = Logger(subsystem: "com.tin.app", category: "persistence")

    func load() -> StudentData? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(StudentData.self, from: data)
        } catch {
            logger.error("Saved student data could not be decoded: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ data: StudentData) throws {
        let encoded = try JSONEncoder().encode(data)
        UserDefaults.standard.set(encoded, forKey: key)
    }
}

@MainActor
final class StudyViewModel: ObservableObject {
    @Published private(set) var assignments: [Assignment]
    @Published private(set) var events: [CalendarEvent]
    @Published private(set) var focusSessions: [FocusSession]
    @Published private(set) var readingPagesToday: Int
    @Published private(set) var streak: Int
    @Published var theme: AppTheme { didSet { persist() } }
    let accent: Color = .indigo

    private let repository: StudyDataStore
    private let calendar: Calendar
    private let logger = Logger(subsystem: "com.tin.app", category: "study-state")

    init(repository: StudyDataStore = UserDefaultsStudyDataStore(), calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
        let data = repository.load() ?? Self.seedData(calendar: calendar)
        assignments = data.assignments
        events = data.events
        focusSessions = data.focusSessions
        readingPagesToday = data.readingPagesToday
        streak = 0
        theme = data.theme
        streak = calculateStreak()
    }

    var openTasks: [Assignment] { assignments.filter { !$0.done } }
    var todayEvents: [CalendarEvent] {
        events
            .filter { calendar.isDateInToday($0.date) }
            .sorted { $0.date < $1.date }
    }
    var completedTasks: Int { assignments.filter { $0.completedAt.map(calendar.isDateInToday) ?? false }.count }
    var focusMinutes: Int { focusMinutes(on: .now) }
    var dailyFocusGoal: Int { 180 }
    var focusGoalProgress: Double { min(Double(focusMinutes) / Double(dailyFocusGoal), 1) }

    var goals: [StudyGoal] {
        [
            .init(kind: .reading, title: "Read 30 pages", current: readingPagesToday, target: 30, symbol: "book", tint: .indigo),
            .init(kind: .tasks, title: "Finish 5 tasks", current: completedTasks, target: 5, symbol: "checkmark.circle", tint: .orange),
            .init(kind: .focus, title: "Focus for 3 hours", current: focusMinutes, target: dailyFocusGoal, symbol: "timer", tint: .mint)
        ]
    }

    func toggle(_ assignment: Assignment) {
        guard let index = assignments.firstIndex(where: { $0.id == assignment.id }) else {
            // A stale list row should never reach here; avoid silently changing unrelated state if it does.
            assertionFailure("Attempted to toggle an assignment that no longer exists")
            return
        }
        assignments[index].completedAt = assignments[index].done ? nil : .now
        persist()
    }

    func addAssignment(title: String, subject: Subject, due: Date, priority: Priority) {
        assignments.append(.init(title: title.trimmingCharacters(in: .whitespacesAndNewlines), subject: subject, due: due, priority: priority))
        persist()
    }

    func addEvent(title: String, date: Date, kind: EventKind) {
        events.append(.init(title: title.trimmingCharacters(in: .whitespacesAndNewlines), date: date, kind: kind))
        persist()
    }

    func addReadingPages(_ pages: Int) {
        readingPagesToday = max(0, readingPagesToday + pages)
        persist()
    }

    func recordFocusSession(minutes: Int, subject: Subject? = nil) {
        guard minutes > 0 else { return }
        focusSessions.append(.init(completedAt: .now, minutes: minutes, subject: subject))
        streak = calculateStreak()
        persist()
    }

    func focusMinutes(on date: Date) -> Int {
        focusSessions.filter { calendar.isDate($0.completedAt, inSameDayAs: date) }.reduce(0) { $0 + $1.minutes }
    }

    func focusMinutes(in interval: DateInterval) -> Int {
        focusSessions.filter { interval.contains($0.completedAt) }.reduce(0) { $0 + $1.minutes }
    }

    func weekFocus() -> [(day: Date, minutes: Int)] {
        let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (day, focusMinutes(on: day))
        }
    }

    func focusChart(for period: StatisticsPeriod) -> [(date: Date, minutes: Int)] {
        switch period {
        case .today:
            return [(.now, focusMinutes)]
        case .week:
            return weekFocus().map { ($0.day, $0.minutes) }
        case .month:
            guard let range = calendar.range(of: .day, in: .month, for: .now),
                  let start = calendar.date(from: calendar.dateComponents([.year, .month], from: .now))
            else { return [] }
            return range.compactMap { day in
                guard let date = calendar.date(byAdding: .day, value: day - 1, to: start) else { return nil }
                return (date, focusMinutes(on: date))
            }
        }
    }

    func focusMinutes(for period: StatisticsPeriod) -> Int {
        switch period {
        case .today: return focusMinutes
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
            return focusMinutes(in: interval)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: .now) else { return 0 }
            return focusMinutes(in: interval)
        }
    }

    func completedTasks(for period: StatisticsPeriod) -> Int {
        assignments.filter { assignment in
            guard let completedAt = assignment.completedAt else { return false }
            switch period {
            case .today: return calendar.isDateInToday(completedAt)
            case .week: return calendar.dateInterval(of: .weekOfYear, for: .now)?.contains(completedAt) ?? false
            case .month: return calendar.dateInterval(of: .month, for: .now)?.contains(completedAt) ?? false
            }
        }.count
    }

    func studyTimeText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    func focusMinutes(for subject: Subject) -> Int {
        focusSessions.filter { $0.subject == subject }.reduce(0) { $0 + $1.minutes }
    }

    var achievements: [AchievementStatus] {
        let totalMinutes = focusSessions.reduce(0) { $0 + $1.minutes }
        let finishedTasks = assignments.filter(\.done).count
        let earlySessions = focusSessions.filter { calendar.component(.hour, from: $0.completedAt) < 9 }.count
        let lateSessions = focusSessions.filter { calendar.component(.hour, from: $0.completedAt) >= 21 }.count

        return [
            .init(id: "first-focus", icon: "sparkles", title: "First study session", detail: focusSessions.isEmpty ? "Start your first session" : "Unlocked", tint: .purple, isUnlocked: !focusSessions.isEmpty),
            .init(id: "seven-day", icon: "flame.fill", title: "7-day streak", detail: streak >= 7 ? "Unlocked" : "\(7 - streak) day\(7 - streak == 1 ? "" : "s") to go", tint: .orange, isUnlocked: streak >= 7),
            .init(id: "thirty-hours", icon: "clock.fill", title: "30 hours studied", detail: "\(totalMinutes / 60) / 30 hours", tint: .indigo, isUnlocked: totalMinutes >= 1_800),
            .init(id: "task-master", icon: "checkmark.seal.fill", title: "Finish 100 tasks", detail: "\(finishedTasks) / 100 tasks", tint: .green, isUnlocked: finishedTasks >= 100),
            .init(id: "early-bird", icon: "sunrise.fill", title: "Early bird", detail: earlySessions > 0 ? "Unlocked" : "Focus before 9 AM", tint: .yellow, isUnlocked: earlySessions > 0),
            .init(id: "night-owl", icon: "moon.stars.fill", title: "Night owl", detail: lateSessions > 0 ? "Unlocked" : "Focus after 9 PM", tint: .indigo, isUnlocked: lateSessions > 0)
        ]
    }

    private func persist() {
        let data = StudentData(
            assignments: assignments,
            events: events,
            focusSessions: focusSessions,
            readingPagesToday: readingPagesToday,
            streak: streak,
            theme: theme
        )

        do {
            try repository.save(data)
        } catch {
            logger.error("Student data could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func calculateStreak() -> Int {
        let focusedDays = Set(focusSessions.map { calendar.startOfDay(for: $0.completedAt) })
        guard !focusedDays.isEmpty else { return 0 }

        var currentDay = calendar.startOfDay(for: .now)
        if !focusedDays.contains(currentDay) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: currentDay), focusedDays.contains(yesterday) else { return 0 }
            currentDay = yesterday
        }

        var total = 0
        while focusedDays.contains(currentDay) {
            total += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: currentDay) else { break }
            currentDay = previous
        }
        return total
    }

    private static func seedData(calendar: Calendar) -> StudentData {
        let now = Date.now
        let sessions: [FocusSession] = [
            .init(completedAt: calendar.date(byAdding: .day, value: -6, to: now) ?? now, minutes: 32, subject: .math),
            .init(completedAt: calendar.date(byAdding: .day, value: -5, to: now) ?? now, minutes: 42, subject: .computerScience),
            .init(completedAt: calendar.date(byAdding: .day, value: -4, to: now) ?? now, minutes: 63, subject: .english),
            .init(completedAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now, minutes: 95, subject: .science),
            .init(completedAt: calendar.date(byAdding: .day, value: -2, to: now) ?? now, minutes: 57, subject: .math),
            .init(completedAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now, minutes: 75, subject: .history),
            .init(completedAt: now, minutes: 87, subject: .computerScience)
        ]
        return .init(
            assignments: [
                .init(title: "Calculus problem set", subject: .math, due: now.addingTimeInterval(60 * 60 * 3), priority: .high),
                .init(title: "Read chapter 8", subject: .history, due: now.addingTimeInterval(60 * 60 * 8), priority: .medium),
                .init(title: "Lab report outline", subject: .science, due: now.addingTimeInterval(60 * 60 * 27), priority: .high),
                .init(title: "Binary trees practice", subject: .computerScience, due: now.addingTimeInterval(60 * 60 * 50), priority: .low, completedAt: now)
            ],
            events: [
                .init(title: "Calculus problem set due", date: now.addingTimeInterval(60 * 60 * 2), kind: .assignmentDeadline),
                .init(title: "English Literature", date: now.addingTimeInterval(60 * 60 * 6), kind: .classSession),
                .init(title: "Study session", date: now.addingTimeInterval(60 * 60 * 10.5), kind: .studySession)
            ],
            focusSessions: sessions,
            readingPagesToday: 18,
            streak: 0,
            theme: .system
        )
    }
}

