import SwiftUI

enum Subject: String, CaseIterable, Identifiable, Codable {
    case math = "Math"
    case english = "English"
    case science = "Science"
    case history = "History"
    case computerScience = "Computer Science"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .math: .indigo
        case .english: .orange
        case .science: .green
        case .history: .pink
        case .computerScience: .cyan
        }
    }

    var icon: String {
        switch self {
        case .math: "function"
        case .english: "text.book.closed"
        case .science: "atom"
        case .history: "building.columns"
        case .computerScience: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum Priority: String, CaseIterable, Identifiable, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }
    var color: Color { self == .high ? .red : self == .medium ? .orange : .green }
}

struct Assignment: Identifiable, Codable {
    var id = UUID()
    var title: String
    var subject: Subject
    var due: Date
    var priority: Priority
    var completedAt: Date?

    var done: Bool { completedAt != nil }
}

enum EventKind: String, CaseIterable, Identifiable, Codable {
    case studySession = "Study session"
    case classSession = "Class"
    case exam = "Exam"
    case assignmentDeadline = "Assignment deadline"

    var id: String { rawValue }
    var color: Color {
        switch self {
        case .studySession: .cyan
        case .classSession: .orange
        case .exam, .assignmentDeadline: .red
        }
    }
}

struct CalendarEvent: Identifiable, Codable {
    var id = UUID()
    var title: String
    var date: Date
    var kind: EventKind

    var detail: String { kind.rawValue }
    var tint: Color { kind.color }
}

struct FocusSession: Identifiable, Codable {
    var id = UUID()
    var completedAt: Date
    var minutes: Int
    var subject: Subject?
}

struct StudyGoal: Identifiable {
    enum Kind { case reading, tasks, focus }

    let kind: Kind
    let title: String
    let current: Int
    let target: Int
    let symbol: String
    let tint: Color

    var id: String { title }
    var progress: Double { min(Double(current) / Double(target), 1) }
}

enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This week"
    case month = "This month"

    var id: String { rawValue }
}

struct AchievementStatus: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    let isUnlocked: Bool
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    case dark = "Dark"
    case system = "Follow System"

    var id: String { rawValue }
    var scheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
}

struct StudentData: Codable {
    var assignments: [Assignment]
    var events: [CalendarEvent]
    var focusSessions: [FocusSession]
    var readingPagesToday: Int
    var streak: Int
    var theme: AppTheme
}

