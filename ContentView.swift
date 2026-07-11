import SwiftUI
import Combine

@main
struct TinApp: App {
    @StateObject private var store = StudyViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.theme.scheme)
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: StudyViewModel
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { DashboardView(selectedTab: $selectedTab) }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            NavigationStack { FocusTimerView() }
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(1)
            NavigationStack { AssignmentsView() }
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(2)
            NavigationStack { CalendarView() }
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(3)
            NavigationStack { StatisticsView() }
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(4)
        }
        .tint(store.accent)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var store: StudyViewModel
    @Binding var selectedTab: Int
    @State private var showTimer = false
    private let schedule: [(String, String, Subject)] = [("09:00", "Mathematics", .math), ("11:00", "Computer Science", .computerScience), ("14:00", "English Literature", .english)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(greeting), Tin").font(.title.bold())
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ZStack { Circle().fill(store.accent.opacity(0.15)).frame(width: 44, height: 44); Image(systemName: "person.fill").foregroundStyle(store.accent) }
                }

                FocusHero { showTimer = true }

                HStack(spacing: 11) {
                    MetricCard(value: "\(store.focusMinutes)m", label: "Studied today", symbol: "timer", tint: .indigo)
                    MetricCard(value: "\(store.completedTasks)", label: "Tasks finished", symbol: "checkmark.circle", tint: .green)
                    MetricCard(value: "\(store.streak)", label: "Day streak", symbol: "flame.fill", tint: .orange)
                }

                SectionLabel(title: "Today's schedule", action: "Calendar") { selectedTab = 3 }
                VStack(spacing: 0) {
                    ForEach(Array(schedule.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 14) {
                            Text(item.0).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                            RoundedRectangle(cornerRadius: 2).fill(item.2.color).frame(width: 4, height: 35)
                            VStack(alignment: .leading, spacing: 2) { Text(item.1).fontWeight(.semibold); Text("Class session").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 11)
                        if index < schedule.count - 1 { Divider().padding(.leading, 56) }
                    }
                }.padding(.horizontal, 14).background(.background, in: RoundedRectangle(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06)) }

                SectionLabel(title: "Up next", action: "See all") { selectedTab = 2 }
                ForEach(store.openTasks.prefix(2)) { task in TaskRow(task: task) { store.toggle(task) } }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarHidden(true)
        .sheet(isPresented: $showTimer) { NavigationStack { FocusTimerView() } }
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }
}

struct FocusHero: View {
    @EnvironmentObject var store: StudyViewModel
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Label("TODAY'S GOAL", systemImage: "target").font(.caption.weight(.bold)); Spacer(); Text("\(store.focusMinutes) / \(store.dailyFocusGoal) min").font(.caption.weight(.semibold)) }
            ProgressView(value: Double(store.focusMinutes), total: Double(store.dailyFocusGoal)).tint(.white).scaleEffect(y: 1.7)
            HStack(alignment: .bottom) { VStack(alignment: .leading) { Text("Keep your momentum").font(.title3.bold()); Text("You're \(Int(store.focusGoalProgress * 100))% through your goal.").font(.caption).opacity(0.8) }; Spacer(); Button(action: action) { Image(systemName: "play.fill").font(.title3).padding(12).background(.white, in: Circle()).foregroundStyle(store.accent) } }
        }.foregroundStyle(.white).padding(20).background(LinearGradient(colors: [store.accent, store.accent.opacity(0.68)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct MetricCard: View { let value, label, symbol: String; let tint: Color
    var body: some View { VStack(alignment: .leading, spacing: 8) { Image(systemName: symbol).foregroundStyle(tint); Text(value).font(.title3.bold()); Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16)) }
}
struct SectionLabel: View {
    let title, action: String
    var onAction: (() -> Void)? = nil
    var body: some View { HStack { Text(title).font(.headline); Spacer(); if let onAction { Button(action, action: onAction).font(.subheadline.weight(.medium)).foregroundStyle(.indigo) } else { Text(action).font(.subheadline.weight(.medium)).foregroundStyle(.indigo) } } }
}

// MARK: - Focus

struct FocusTimerView: View {
    @EnvironmentObject var store: StudyViewModel
    @State private var selection = "Pomodoro"
    @State private var isRunning = false
    @State private var seconds = 25 * 60
    @State private var music = "Rain"
    @State private var locked = false
    @State private var customMinutes = 45
    @State private var showCompletion = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let modes = ["Pomodoro", "Short break", "Long break", "Custom"]
    var duration: Int { selection == "Pomodoro" ? 25 * 60 : selection == "Short break" ? 5 * 60 : selection == "Long break" ? 15 * 60 : customMinutes * 60 }
    var body: some View {
        ScrollView { VStack(spacing: 25) {
            Picker("Timer type", selection: $selection) { ForEach(modes, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).onChange(of: selection) { _, _ in seconds = duration; isRunning = false }
            if selection == "Custom" { Stepper("\(customMinutes) minutes", value: $customMinutes, in: 10...120, step: 5).onChange(of: customMinutes) { _, val in seconds = val * 60 } }
            ZStack {
                Circle().stroke(store.accent.opacity(0.13), lineWidth: 15)
                Circle().trim(from: 0, to: max(0.05, Double(seconds) / Double(duration))).stroke(store.accent, style: StrokeStyle(lineWidth: 15, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 6) { Text(timeString).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit(); Text(isRunning ? "Deep focus in progress" : "Ready when you are").foregroundStyle(.secondary) }
            }.frame(width: 250, height: 250).padding(.top, 10)
            Button { isRunning.toggle() } label: { Label(isRunning ? "Pause session" : "Start focusing", systemImage: isRunning ? "pause.fill" : "play.fill").fontWeight(.bold).frame(maxWidth: .infinity).padding().background(store.accent, in: Capsule()).foregroundStyle(.white) }.padding(.horizontal, 28)
            VStack(alignment: .leading, spacing: 0) {
                SettingLine(icon: "music.note", title: "Background sound", detail: music, tint: .purple) { Picker("Sound", selection: $music) { ForEach(["Rain", "Cafe", "White noise", "Off"], id: \.self) { Text($0) } }.labelsHidden() }
                Divider().padding(.leading, 45)
                Toggle(isOn: $locked) { Label { VStack(alignment: .leading) { Text("Lock interface"); Text("Reduce distractions while focusing").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "lock.fill").foregroundStyle(.orange) } }.tint(store.accent).padding(.vertical, 12)
            }.padding(.horizontal, 16).background(.background, in: RoundedRectangle(cornerRadius: 18))
        }.padding(20) }
        .background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Focus timer")
        .onReceive(ticker) { _ in
            guard isRunning else { return }
            if seconds > 1 { seconds -= 1 }
            else {
                isRunning = false
                showCompletion = true
                if selection != "Short break" && selection != "Long break" { store.recordFocusSession(minutes: duration / 60) }
            }
        }
        .alert("Session complete!", isPresented: $showCompletion) {
            Button("Start another") { seconds = duration; isRunning = true }
            Button("Done", role: .cancel) { seconds = duration }
        } message: { Text("Nice work. Your focus time has been saved.") }
    }
    var timeString: String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}

struct SettingLine<Accessory: View>: View { let icon, title, detail: String; let tint: Color; @ViewBuilder var accessory: () -> Accessory
    var body: some View { HStack { Image(systemName: icon).frame(width: 28).foregroundStyle(tint); Text(title); Spacer(); accessory() }.padding(.vertical, 12) }
}

// MARK: - Tasks

struct AssignmentsView: View {
    @EnvironmentObject var store: StudyViewModel
    @State private var search = ""; @State private var filter: Subject?; @State private var sortHighFirst = true; @State private var showAdd = false
    var results: [Assignment] { store.assignments.filter { (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) && (filter == nil || $0.subject == filter) }.sorted { sortHighFirst ? priorityValue($0.priority) > priorityValue($1.priority) : $0.due < $1.due } }
    var body: some View { VStack(spacing: 0) {
        ScrollView(.horizontal, showsIndicators: false) { HStack { FilterChip(title: "All", selected: filter == nil) { filter = nil }; ForEach(Subject.allCases) { s in FilterChip(title: s.rawValue, selected: filter == s) { filter = s } } }.padding(.horizontal).padding(.vertical, 8) }
        List { ForEach(results) { task in TaskRow(task: task) { store.toggle(task) }.listRowSeparator(.hidden).listRowBackground(Color.clear) } }
        .listStyle(.plain)
    }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Assignments").searchable(text: $search, prompt: "Search assignments").toolbar { ToolbarItem(placement: .topBarLeading) { Menu { Button("Priority") { sortHighFirst = true }; Button("Deadline") { sortHighFirst = false } } label: { Image(systemName: "arrow.up.arrow.down") } }; ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") } } }.sheet(isPresented: $showAdd) { AddAssignmentView() } }
    func priorityValue(_ p: Priority) -> Int { p == .high ? 3 : p == .medium ? 2 : 1 }
}

struct FilterChip: View { let title: String; let selected: Bool; var action: () -> Void; var body: some View { Button(title, action: action).font(.subheadline.weight(.medium)).padding(.horizontal, 13).padding(.vertical, 8).background(selected ? Color.indigo : Color.primary.opacity(0.08), in: Capsule()).foregroundStyle(selected ? .white : .primary) } }
struct TaskRow: View { let task: Assignment; var action: () -> Void
    var body: some View { HStack(spacing: 12) { Button(action: action) { Image(systemName: task.done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(task.done ? .green : .secondary) }; VStack(alignment: .leading, spacing: 5) { Text(task.title).strikethrough(task.done).fontWeight(.semibold); HStack { Label(task.subject.rawValue, systemImage: task.subject.icon); Text("•"); Text(task.due, style: .date) }.font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(task.priority.rawValue).font(.caption2.weight(.bold)).foregroundStyle(task.priority.color).padding(.horizontal, 8).padding(.vertical, 5).background(task.priority.color.opacity(0.13), in: Capsule()) }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 16)) }
}

struct AddAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StudyViewModel
    @State private var title = ""
    @State private var subject: Subject = .math
    @State private var due = Date.now.addingTimeInterval(3_600)
    @State private var priority: Priority = .medium

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && due >= Date.now
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Assignment title", text: $title)
                Picker("Subject", selection: $subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }
                DatePicker("Deadline", selection: $due, in: Date.now...)
                Picker("Priority", selection: $priority) { ForEach(Priority.allCases) { Text($0.rawValue).tag($0) } }
                if !title.isEmpty && !isValid { Text("Enter a title and a future deadline.").foregroundStyle(.red) }
            }
            .navigationTitle("New assignment")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Add") { store.addAssignment(title: title, subject: subject, due: due, priority: priority); dismiss() }.disabled(!isValid) }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Calendar

struct CalendarView: View {
    @EnvironmentObject var store: StudyViewModel
    private let calendar = Calendar.current
    @State private var showAdd = false
    @State private var displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now

    private var todaysEvents: [CalendarEvent] { store.events.filter { calendar.isDateInToday($0.date) }.sorted { $0.date < $1.date } }
    private var monthDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth), let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else { return [] }
        let leadingDays = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        return Array(repeating: nil, count: leadingDays) + days
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(displayedMonth.formatted(.dateTime.month(.wide).year())).font(.title.bold())
                    Spacer()
                    Button { displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth } label: { Image(systemName: "chevron.right") }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                    ForEach(Array(calendar.shortWeekdaySymbols.enumerated()), id: \.offset) { _, dayName in Text(dayName).font(.caption.weight(.bold)).foregroundStyle(.secondary) }
                    ForEach(monthDays.indices, id: \.self) { index in
                        if let date = monthDays[index] {
                            let hasEvent = store.events.contains { calendar.isDate($0.date, inSameDayAs: date) }
                            VStack(spacing: 5) {
                                Text(date.formatted(.dateTime.day()))
                                    .fontWeight(calendar.isDateInToday(date) ? .bold : .regular)
                                    .frame(width: 32, height: 32)
                                    .background(calendar.isDateInToday(date) ? store.accent : .clear, in: Circle())
                                    .foregroundStyle(calendar.isDateInToday(date) ? .white : .primary)
                                Circle().fill(hasEvent ? store.accent : .clear).frame(width: 5, height: 5)
                            }
                        } else { Color.clear.frame(height: 42) }
                    }
                }
                SectionLabel(title: "Today's schedule", action: "")
                if todaysEvents.isEmpty { ContentUnavailableView("Nothing scheduled", systemImage: "calendar", description: Text("Tap + to add an event.")) }
                ForEach(todaysEvents) { event in EventRow(time: event.date.formatted(date: .omitted, time: .shortened), title: event.title, detail: event.detail, tint: event.tint) }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") } } }
        .sheet(isPresented: $showAdd) { AddCalendarEventView() }
    }
}
struct EventRow: View { let time, title, detail: String; let tint: Color; var body: some View { HStack(spacing: 13) { Text(time).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36); RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4, height: 43); VStack(alignment: .leading, spacing: 4) { Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(.vertical, 5) } }

struct AddCalendarEventView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StudyViewModel
    @State private var title = ""
    @State private var date = Date.now.addingTimeInterval(3_600)
    @State private var kind: EventKind = .studySession

    private var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && date >= Date.now }

    var body: some View { NavigationStack { Form {
        TextField("Event title", text: $title)
        DatePicker("Date & time", selection: $date, in: Date.now...)
        Picker("Type", selection: $kind) { ForEach(EventKind.allCases) { Text($0.rawValue).tag($0) } }
        if !title.isEmpty && !isValid { Text("Enter a title and a future date.").foregroundStyle(.red) }
    }.navigationTitle("Add to calendar").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Add") { store.addEvent(title: title, date: date, kind: kind); dismiss() }.disabled(!isValid) }
    } } }
}

// MARK: - Progress, goals & achievement

struct StatisticsView: View {
    @EnvironmentObject var store: StudyViewModel
    @State private var period: StatisticsPeriod = .week

    private var chart: [(date: Date, minutes: Int)] { store.focusChart(for: period) }
    private var maximum: Int { max(chart.map(\.minutes).max() ?? 1, 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker("Period", selection: $period) {
                    ForEach(StatisticsPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    MetricCard(value: store.studyTimeText(store.focusMinutes(for: period)), label: period.rawValue, symbol: "clock.fill", tint: .indigo)
                    MetricCard(value: "\(store.completedTasks(for: period))", label: "Tasks done", symbol: "checkmark.seal.fill", tint: .green)
                }

                Text(period == .today ? "Focus today" : "Focus by day").font(.headline)
                ChartBars(items: chart, maximum: maximum, accent: store.accent, isMonth: period == .month)

                Text("Study by subject").font(.headline)
                ForEach(Subject.allCases) { subject in
                    HStack {
                        Image(systemName: subject.icon).foregroundStyle(subject.color).frame(width: 25)
                        Text(subject.rawValue)
                        Spacer()
                        Text(store.studyTimeText(store.focusMinutes(for: subject))).font(.subheadline.weight(.medium))
                    }
                    .padding(.vertical, 5)
                }

                SectionLabel(title: "Goals", action: "")
                ForEach(store.goals) { goal in GoalCard(goal: goal) }

                Text("Achievements").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(store.achievements) { achievement in Achievement(achievement: achievement) } }
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Your progress")
    }
}

struct ChartBars: View {
    let items: [(date: Date, minutes: Int)]
    let maximum: Int
    let accent: Color
    let isMonth: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: isMonth ? 5 : 12) {
                ForEach(items, id: \.date) { item in
                    VStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Calendar.current.isDateInToday(item.date) ? accent : accent.opacity(0.25))
                            .frame(width: isMonth ? 10 : nil, height: max(4, CGFloat(item.minutes) / CGFloat(maximum) * 115))
                        Text(isMonth ? item.date.formatted(.dateTime.day()) : item.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: isMonth ? 10 : 0, maxWidth: isMonth ? 10 : .infinity)
                }
            }
            .frame(height: 150)
            .padding()
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct GoalCard: View {
    let goal: StudyGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(goal.title, systemImage: goal.symbol).foregroundStyle(goal.tint)
                Spacer()
                Text("\(goal.current)/\(goal.target)").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: goal.progress).tint(goal.tint)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct Achievement: View {
    let achievement: AchievementStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: achievement.icon)
                .font(.title2)
                .foregroundStyle(achievement.isUnlocked ? achievement.tint : .secondary)
                .padding(10)
                .background(achievement.tint.opacity(achievement.isUnlocked ? 0.12 : 0.05), in: Circle())
            Text(achievement.title).font(.subheadline.bold())
            Text(achievement.detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 140, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

