import SwiftUI
import Combine
import Charts
import ActivityKit

// MARK: - Data Models

// Enum for the different types of exercises
enum ExerciseType: String, CaseIterable, Codable, Identifiable {
    case squat = "Squat"
    case benchPress = "Bench Press"
    case barbellRow = "Barbell Row"
    case overheadPress = "Overhead Press"
    case deadlift = "Deadlift"
    
    var id: String { self.rawValue }
    
    var sets: Int {
        return self == .deadlift ? 1 : 5
    }
    
    var reps: Int {
        return 5
    }
}

// Struct to log a workout session
struct WorkoutLog: Identifiable, Codable {
    let id: UUID
    let date: Date
    let workoutType: WorkoutType
    let exercises: [CompletedExercise]
    let accessoryWork: [CompletedAccessory] // For logging
}

struct CompletedExercise: Identifiable, Codable {
    let id: UUID
    let name: String
    let weight: Double
    let sets: Int
    let reps: Int
    var success: Bool // Flag for success/failure
}

struct CompletedAccessory: Identifiable, Codable {
    let id: UUID
    let name: String
}


// Enum for Workout A/B types
enum WorkoutType: String, Codable {
    case a = "A"
    case b = "B"
}

// Structs for new features
struct WarmupSet {
    let weight: Double
    let reps: String
}

struct Plate: Hashable {
    let weight: Double
    var count: Int
}

struct AccessoryExercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var sets: Int
    var reps: String
}


// MARK: - View Model / Manager

class WorkoutManager: ObservableObject {
    @Published var todaysExercises: [TrackedExercise] = []
    @Published var todaysAccessoryExercises: [TrackedAccessory] = []
    @Published var workoutHistory: [WorkoutLog] = []
    @Published var accessoryExercisesA: [AccessoryExercise] = []
    @Published var accessoryExercisesB: [AccessoryExercise] = []
    @Published var isTimerActive = false
    @Published var timerValue = 180
    @Published var initialTimerDuration = 180
    
    @AppStorage("lastWorkoutType") private var lastWorkoutType: String = "B"
    @AppStorage("workoutHistoryData") private var workoutHistoryData: Data = Data()
    
    @AppStorage("accessoryAData") private var accessoryAData: Data = Data()
    @AppStorage("accessoryBData") private var accessoryBData: Data = Data()
    
    // Store current weight and failure counts for each exercise
    @AppStorage("squatWeight") private var squatWeight: Double = 20.0
    @AppStorage("benchPressWeight") private var benchPressWeight: Double = 20.0
    @AppStorage("barbellRowWeight") private var barbellRowWeight: Double = 30.0
    @AppStorage("overheadPressWeight") private var overheadPressWeight: Double = 20.0
    @AppStorage("deadliftWeight") private var deadliftWeight: Double = 40.0
    
    @AppStorage("squatFailures") private var squatFailures: Int = 0
    @AppStorage("benchPressFailures") private var benchPressFailures: Int = 0
    @AppStorage("barbellRowFailures") private var barbellRowFailures: Int = 0
    @AppStorage("overheadPressFailures") private var overheadPressFailures: Int = 0
    @AppStorage("deadliftFailures") private var deadliftFailures: Int = 0
    
    // ★★★ FIX: 타이머 종료 시간을 기록할 프로퍼티
    private var timerEndDate: Date? = nil
    
    private var timer: AnyCancellable?
    private let barWeight = 20.0

    init() {
        loadHistory()
        generateTodaysWorkout()
    }
    
    // Generate today's workout routine
    func generateTodaysWorkout() {
        let nextWorkoutType: WorkoutType = (lastWorkoutType == "A") ? .b : .a
        
        switch nextWorkoutType {
        case .a:
            todaysExercises = [
                TrackedExercise(type: .squat, weight: squatWeight),
                TrackedExercise(type: .benchPress, weight: benchPressWeight),
                TrackedExercise(type: .barbellRow, weight: barbellRowWeight)
            ]
            todaysAccessoryExercises = accessoryExercisesA.map { TrackedAccessory(exercise: $0) }
        case .b:
            todaysExercises = [
                TrackedExercise(type: .squat, weight: squatWeight),
                TrackedExercise(type: .overheadPress, weight: overheadPressWeight),
                TrackedExercise(type: .deadlift, weight: deadliftWeight)
            ]
            todaysAccessoryExercises = accessoryExercisesB.map { TrackedAccessory(exercise: $0) }
        }
    }
    
    // Process workout completion
    func finishWorkout() {
        let currentWorkoutType: WorkoutType = (lastWorkoutType == "A") ? .b : .a
        var completedExercises: [CompletedExercise] = []
        
        for exercise in todaysExercises {
            let isSuccess = !exercise.completedSets.contains(false)
            
            if isSuccess {
                let increment = (exercise.type == .deadlift) ? 5.0 : 2.5
                updateWeight(for: exercise.type, to: exercise.weight + increment)
                setFailures(for: exercise.type, to: 0)
            } else {
                let failures = getFailures(for: exercise.type) + 1
                setFailures(for: exercise.type, to: failures)
                if failures >= 3 {
                    let newWeight = deloadWeight(exercise.weight, isDeadlift: exercise.type == .deadlift)
                    updateWeight(for: exercise.type, to: newWeight)
                    setFailures(for: exercise.type, to: 0)
                }
            }
            
            let completed = CompletedExercise(id: UUID(), name: exercise.type.rawValue, weight: exercise.weight, sets: exercise.type.sets, reps: exercise.type.reps, success: isSuccess)
            completedExercises.append(completed)
        }
        
        let completedAccessory = todaysAccessoryExercises
            .filter { !$0.completedSets.contains(false) }
            .map { CompletedAccessory(id: $0.id, name: "\($0.name) \($0.sets)x\($0.reps)") }

        
        let newLog = WorkoutLog(id: UUID(), date: Date(), workoutType: currentWorkoutType, exercises: completedExercises, accessoryWork: completedAccessory)
        workoutHistory.insert(newLog, at: 0)
        saveHistory()
        
        lastWorkoutType = currentWorkoutType.rawValue
        generateTodaysWorkout()
        objectWillChange.send()
    }
    
    // Manually update weight
    func updateWeight(for exerciseType: ExerciseType, to newWeight: Double) {
        let roundedWeight = (floor(newWeight / 2.5)) * 2.5
        switch exerciseType {
        case .squat: squatWeight = roundedWeight
        case .benchPress: benchPressWeight = roundedWeight
        case .barbellRow: barbellRowWeight = roundedWeight
        case .overheadPress: overheadPressWeight = roundedWeight
        case .deadlift: deadliftWeight = (floor(newWeight / 5.0)) * 5.0
        }
        
        if let index = todaysExercises.firstIndex(where: { $0.type == exerciseType }) {
            todaysExercises[index].weight = getWeight(for: exerciseType)
        }
    }

    // Calculate deload weight
    private func deloadWeight(_ weight: Double, isDeadlift: Bool = false) -> Double {
        let deloaded = weight * 0.9
        let unit = isDeadlift ? 5.0 : 2.5
        let calculatedWeight = floor(deloaded / unit) * unit
        return max(20.0, calculatedWeight)
    }
    
    // ★★★ FIX: Timer functions
    func startTimer(duration: Int) {
        stopTimer()
        initialTimerDuration = duration
        timerValue = duration
        isTimerActive = true
        // 종료 시점 기록
        timerEndDate = Date().addingTimeInterval(TimeInterval(duration))
                    
        // UI 업데이트용 타이머
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            if self.timerValue > 0 {
                self.timerValue -= 1
            } else {
                self.stopTimer()
            }
        }
    }
    
    func stopTimer() {
        timer?.cancel()
        isTimerActive = false
        // 종료 시점 기록 삭제
        timerEndDate = nil
    }
    
    // ★★★ FIX: 앱 활성화 시 호출될 함수
    func handleAppBecomingActive() {
        guard let endDate = timerEndDate else { return }

        let remainingTime = endDate.timeIntervalSince(Date())

        if remainingTime <= 0 {
            stopTimer()
        } else {
            timerValue = Int(round(remainingTime))
        }
    }
    
    // Generate data for charts
    func getChartData(for exerciseType: ExerciseType) -> [(Date, Double)] {
        workoutHistory
            .compactMap { log -> (Date, Double)? in
                if let exercise = log.exercises.first(where: { $0.name == exerciseType.rawValue }) {
                    return (log.date, exercise.weight)
                }
                return nil
            }
            .reversed()
    }
    
    // Delete workout log and restore state
    func deleteLog(log: WorkoutLog) {
        if let index = workoutHistory.firstIndex(where: { $0.id == log.id }) {
            let offsets = IndexSet(integer: index)
            
            workoutHistory.remove(atOffsets: offsets)
            saveHistory()
            
            recalculateCurrentState()
            
            generateTodaysWorkout()
            objectWillChange.send()
        }
    }
    
    // Get log for a specific date
    func logFor(date: Date) -> WorkoutLog? {
        let calendar = Calendar.current
        return workoutHistory.first { log in
            calendar.isDate(log.date, inSameDayAs: date)
        }
    }
    
    // Recalculate current state from history
    private func recalculateCurrentState() {
        resetToInitialState()
        
        let reversedHistory = workoutHistory.reversed()
        
        for log in reversedHistory {
            for exercise in log.exercises {
                if let type = ExerciseType(rawValue: exercise.name) {
                    if exercise.success {
                        let increment = (type == .deadlift) ? 5.0 : 2.5
                        updateWeight(for: type, to: exercise.weight + increment)
                        setFailures(for: type, to: 0)
                    } else {
                        let failures = getFailures(for: type) + 1
                        setFailures(for: type, to: failures)
                        if failures >= 3 {
                            let newWeight = deloadWeight(exercise.weight, isDeadlift: type == .deadlift)
                            updateWeight(for: type, to: newWeight)
                            setFailures(for: type, to: 0)
                        } else {
                             updateWeight(for: type, to: exercise.weight)
                        }
                    }
                }
            }
            lastWorkoutType = log.workoutType.rawValue
        }
    }
    
    // Reset weights and failures to initial state
    private func resetToInitialState() {
        squatWeight = 20.0; benchPressWeight = 20.0; barbellRowWeight = 30.0
        overheadPressWeight = 20.0; deadliftWeight = 40.0
        squatFailures = 0; benchPressFailures = 0; barbellRowFailures = 0
        overheadPressFailures = 0; deadliftFailures = 0
        lastWorkoutType = "B"
    }

    // Save/Load history to UserDefaults
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(workoutHistory) {
            workoutHistoryData = data
        }
    }
    
    private func loadHistory() {
        if let logs = try? JSONDecoder().decode([WorkoutLog].self, from: workoutHistoryData) {
            self.workoutHistory = logs
        }
    }
    
    // Helper functions
    private func getWeight(for type: ExerciseType) -> Double {
        switch type {
        case .squat: return squatWeight
        case .benchPress: return benchPressWeight
        case .barbellRow: return barbellRowWeight
        case .overheadPress: return overheadPressWeight
        case .deadlift: return deadliftWeight
        }
    }
    
    private func getFailures(for type: ExerciseType) -> Int {
        switch type {
        case .squat: return squatFailures
        case .benchPress: return benchPressFailures
        case .barbellRow: return barbellRowFailures
        case .overheadPress: return overheadPressFailures
        case .deadlift: return deadliftFailures
        }
    }
    
    func setFailures(for type: ExerciseType, to value: Int) {
        switch type {
        case .squat: squatFailures = value
        case .benchPress: benchPressFailures = value
        case .barbellRow: barbellRowFailures = value
        case .overheadPress: overheadPressFailures = value
        case .deadlift: deadliftFailures = value
        }
    }

    // Warm-up Calculator
    func calculateWarmupSets(for workWeight: Double) -> [WarmupSet] {
        if workWeight <= barWeight {
            return [WarmupSet(weight: barWeight, reps: "5"), WarmupSet(weight: barWeight, reps: "5")]
        }
        
        let percentages: [Double] = [0, 0, 0.4, 0.6, 0.8]
        let reps: [String] = ["5", "5", "5", "3", "2"]
        
        var warmupSets: [WarmupSet] = []
        
        for i in 0..<percentages.count {
            var weight = workWeight * percentages[i]
            if weight < barWeight {
                weight = barWeight
            }
            weight = round(weight / 2.5) * 2.5
            
            if warmupSets.last?.weight != weight {
                warmupSets.append(WarmupSet(weight: weight, reps: reps[i]))
            }
        }
        
        return warmupSets
    }
    
    // Plate Calculator
    func calculatePlates(for targetWeight: Double) -> [Plate] {
        if targetWeight <= barWeight {
            return []
        }
        
        let platesAvailable: [Double] = [20, 15, 10, 5, 2.5, 1.25]
        var platesPerSide: [Plate] = []
        var remainingWeight = (targetWeight - barWeight) / 2.0
        
        for plateWeight in platesAvailable {
            if remainingWeight >= plateWeight {
                let count = floor(remainingWeight / plateWeight)
                if count > 0 {
                    platesPerSide.append(Plate(weight: plateWeight, count: Int(count)))
                    remainingWeight -= Double(count) * plateWeight
                }
            }
        }
        return platesPerSide
    }

    // Get Personal Record (5RM)
    func getPR(for exerciseType: ExerciseType) -> Double? {
        workoutHistory
            .compactMap { $0.exercises.first(where: { $0.name == exerciseType.rawValue && $0.success }) }
            .map { $0.weight }
            .max()
    }

    // Estimated 1RM Calculator
    func getEstimated1RM(for exerciseType: ExerciseType) -> Double? {
        guard let pr5x5 = getPR(for: exerciseType) else { return nil }
        // Using Epley formula: 1RM = w * (1 + r / 30)
        let estimated1RM = pr5x5 * (1 + 5.0 / 30.0)
        return estimated1RM
    }
}


// Model for tracking exercises in the view
struct TrackedExercise: Identifiable {
    let id = UUID()
    let type: ExerciseType
    var weight: Double
    var completedSets: [Bool]
    
    init(type: ExerciseType, weight: Double) {
        self.type = type
        self.weight = weight
        self.completedSets = Array(repeating: false, count: type.sets)
    }
}

struct TrackedAccessory: Identifiable {
    let id: UUID
    let name: String
    let sets: Int
    let reps: String
    var completedSets: [Bool]
    
    init(exercise: AccessoryExercise) {
        self.id = exercise.id
        self.name = exercise.name
        self.sets = exercise.sets
        self.reps = exercise.reps
        self.completedSets = Array(repeating: false, count: sets)
    }
}

// ★★★ FIX: 앱의 진입점(Entry Point)
@main
struct WorkoutApp: App {
    @StateObject private var manager = WorkoutManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                manager.handleAppBecomingActive()
            }
        }
    }
}


// MARK: - Views

import SwiftUI

struct ContentView: View {
    // ⭐️ 수정된 부분: @StateObject -> @EnvironmentObject
    // 이제 부모로부터 WorkoutManager를 물려받아 사용합니다.
    @EnvironmentObject var manager: WorkoutManager
    
    var body: some View {
        TabView {
            WorkoutView()
                .tabItem {
                    Image(systemName: "flame.fill")
                    Text("Today's Workout")
                }
            
            HistoryView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("History")
                }
            
            ChartsView()
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Progress")
                }
            
            RecordsView()
                .tabItem {
                    Image(systemName: "star.fill")
                    Text("Records")
                }

    
        }
        // 물려받은 manager를 자식 뷰(WorkoutView, HistoryView 등)에게 다시 전달합니다.
        .environmentObject(manager)
        .preferredColorScheme(.dark)
    }
}

struct WorkoutView: View {
    @EnvironmentObject var manager: WorkoutManager
    @State private var showFinishAlert = false
    
    private var nextWorkoutType: String {
        manager.todaysExercises.first?.type == .squat && manager.todaysExercises.count == 3 && manager.todaysExercises[1].type == .benchPress ? "A" : "B"
    }
    
    private var isAllSetsCompleted: Bool {
        !manager.todaysExercises.flatMap { $0.completedSets }.contains(false)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("Workout \(nextWorkoutType)").font(.headline)) {
                        ForEach($manager.todaysExercises) { $exercise in
                            ExerciseRowView(exercise: $exercise)
                        }
                    }
                }
                
                if manager.isTimerActive {
                    LinearTimerBar()
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).animation(.easeOut))
                } else {
                    Button(action: {
                        showFinishAlert = true
                    }) {
                        Text("Finish Workout")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                    .padding(.bottom)
                }
            }
            .navigationTitle("StrongLifts 5x5")
            .alert(isAllSetsCompleted ? "Workout Complete" : "Failed Sets", isPresented: $showFinishAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Finish") {
                    manager.finishWorkout()
                }
            } message: {
                Text(isAllSetsCompleted ? "Great job! Your weights will be increased for the next workout." : "You failed some sets. You will attempt the same weight next time. After 3 consecutive failures, the weight will be deloaded by 10%.")
            }
        }
    }
}

struct ExerciseRowView: View {
    @EnvironmentObject var manager: WorkoutManager
    @Binding var exercise: TrackedExercise
    @State private var showingWeightEditor = false
    @State private var showingWarmup = false
    @State private var newWeightString = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exercise.type.rawValue)
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: "scalemass.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .padding(8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingWarmup.toggle()
                    }
            }
            
            Text("\(String(format: "%.1f", exercise.weight)) kg for \(exercise.type.sets) x \(exercise.type.reps)")
                .font(.headline)
                .foregroundColor(.secondary)
                .onTapGesture {
                    newWeightString = String(format: "%.1f", exercise.weight)
                    showingWeightEditor = true
                }
            
            HStack(spacing: 12) {
                ForEach(0..<exercise.type.sets, id: \.self) { index in
                    SetCircleView(isCompleted: $exercise.completedSets[index])
                        .onTapGesture {
                            exercise.completedSets[index].toggle()
                            if exercise.completedSets[index] {
                                let duration = (index == exercise.type.sets - 1) ? 300 : 180
                                manager.startTimer(duration: duration)
                            } else {
                                manager.stopTimer()
                            }
                        }
                }
            }
        }
        .padding(.vertical, 10)
        .sheet(isPresented: $showingWarmup) {
            WarmupPlateCalculatorView(workWeight: exercise.weight)
        }
        .alert("Edit Weight", isPresented: $showingWeightEditor) {
            TextField("New Weight (kg)", text: $newWeightString)
                .keyboardType(.decimalPad)
            Button("OK") {
                if let newWeight = Double(newWeightString) {
                    manager.updateWeight(for: exercise.type, to: newWeight)
                    manager.setFailures(for: exercise.type, to: 0)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SetCircleView: View {
    @Binding var isCompleted: Bool
    
    var body: some View {
        Circle()
            .stroke(isCompleted ? Color.green : Color.gray, lineWidth: 2)
            .background(Circle().fill(isCompleted ? Color.green.opacity(0.5) : Color.clear))
            .frame(width: 40, height: 40)
            .animation(.spring(), value: isCompleted)
    }
}

struct LinearTimerBar: View {
    @EnvironmentObject var manager: WorkoutManager

    var progress: Double {
        guard manager.initialTimerDuration > 0 else { return 0 }
        return Double(manager.timerValue) / Double(manager.initialTimerDuration)
    }
    
    var minutes: Int { manager.timerValue / 60 }
    var seconds: Int { manager.timerValue % 60 }

    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                .animation(.linear(duration: 1.0), value: progress)

            HStack {
                Text(String(format: "%02d:%02d", minutes, seconds))
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Button("Skip Rest") {
                    manager.stopTimer()
                }
                .font(.footnote)
                .foregroundColor(.gray)
            }
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
    }
}


struct HistoryView: View {
    @EnvironmentObject var manager: WorkoutManager
    @State private var selectedDate = Date()

    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)

                Divider()

                if let log = manager.logFor(date: selectedDate) {
                    WorkoutLogDetailView(log: log)
                        .padding()
                } else {
                    Spacer()
                    Text("No workout recorded for this date.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("Workout Calendar")
        }
    }
}

struct WorkoutLogDetailView: View {
    let log: WorkoutLog
    @EnvironmentObject var manager: WorkoutManager
    @State private var showingDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workout \(log.workoutType.rawValue)")
                    .font(.title2).bold()
                Spacer()
                Text(log.date, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 5)

            ForEach(log.exercises) { exercise in
                HStack {
                    Image(systemName: exercise.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(exercise.success ? .green : .red)
                    Text("\(exercise.name): \(String(format: "%.1f", exercise.weight)) kg for \(exercise.sets)x\(exercise.reps)")
                        .font(.body)
                }
            }
            
            if !log.accessoryWork.isEmpty {
                Text("Accessory Work")
                    .font(.headline)
                    .padding(.top, 5)
                ForEach(log.accessoryWork) { accessory in
                    Text("✓ \(accessory.name)")
                }
            }
            
            Button(action: {
                showingDeleteAlert = true
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "trash")
                    Text("Delete this Log")
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red, lineWidth: 1)
                )
            }
            .padding(.top)
            .alert("Delete Log", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    manager.deleteLog(log: log)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this workout log? This cannot be undone, and your current weights will be restored to their previous state.")
            }

        }
        .padding()
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(12)
    }
}


// MARK: - Chart View
struct ChartsView: View {
    @EnvironmentObject var manager: WorkoutManager
    @State private var selectedExercise: ExerciseType = .squat

    var body: some View {
        NavigationView {
            VStack {
                Picker("Select Exercise", selection: $selectedExercise) {
                    ForEach(ExerciseType.allCases) { exercise in
                        Text(exercise.rawValue).tag(exercise)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if manager.getChartData(for: selectedExercise).isEmpty {
                    Spacer()
                    Text("No records to display.")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    ExerciseChartView(data: manager.getChartData(for: selectedExercise), exerciseName: selectedExercise.rawValue)
                }
                
                Spacer()
            }
            .navigationTitle("Progress Chart")
        }
    }
}

struct ExerciseChartView: View {
    let data: [(Date, Double)]
    let exerciseName: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(exerciseName) Weight Progression")
                .font(.headline)
                .padding(.horizontal)
            
            Chart(data, id: \.0) { date, weight in
                LineMark(
                    x: .value("Date", date, unit: .day),
                    y: .value("Weight (kg)", weight)
                )
                .foregroundStyle(Color.green)
                .symbol(Circle().strokeBorder(lineWidth: 2))

                PointMark(
                    x: .value("Date", date, unit: .day),
                    y: .value("Weight (kg)", weight)
                )
                .foregroundStyle(Color.green)
                .annotation(position: .top) {
                    Text("\(String(format: "%.1f", weight))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .padding()
        }
    }
}

// MARK: - NEW VIEWS

struct RecordsView: View {
    @EnvironmentObject var manager: WorkoutManager
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Personal Records").font(.headline)) {
                    ForEach(ExerciseType.allCases) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.rawValue)
                                .font(.headline)
                            
                            HStack {
                                Text("Best 5-rep Max:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let pr = manager.getPR(for: exercise) {
                                    Text("\(String(format: "%.1f", pr)) kg")
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                } else {
                                    Text("N/A")
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack {
                                Text("Estimated 1-rep Max:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let e1rm = manager.getEstimated1RM(for: exercise) {
                                    Text("\(String(format: "%.1f", e1rm)) kg")
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                } else {
                                    Text("N/A")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle("Records")
        }
    }
}


struct WarmupPlateCalculatorView: View {
    @EnvironmentObject var manager: WorkoutManager
    let workWeight: Double
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Warm-up Sets")) {
                    let warmupSets = manager.calculateWarmupSets(for: workWeight)
                    ForEach(warmupSets.indices, id: \.self) { index in
                        let set = warmupSets[index]
                        VStack(alignment: .leading) {
                            Text("Set \(index + 1): \(String(format: "%.1f", set.weight)) kg x \(set.reps) reps")
                                .fontWeight(.bold)
                            PlateDisplayView(plates: manager.calculatePlates(for: set.weight))
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("Work Set")) {
                    VStack(alignment: .leading) {
                        Text("Work Set: \(String(format: "%.1f", workWeight)) kg x 5 reps")
                            .fontWeight(.bold)
                        PlateDisplayView(plates: manager.calculatePlates(for: workWeight))
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Warm-up & Plates")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

struct PlateDisplayView: View {
    let plates: [Plate]
    
    let plateColors: [Double: Color] = [
        20: .red, 15: .yellow, 10: .blue, 5: .green, 2.5: .black, 1.25: .gray
    ]
    
    var body: some View {
        if plates.isEmpty {
            Text("Bar only (20.0 kg)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else {
            HStack {
                Text("Each side:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                ForEach(plates, id: \.self) { plate in
                    Text("\(String(format: "%.2f", plate.weight))x\(plate.count)")
                        .font(.caption)
                        .padding(4)
                        .background(plateColors[plate.weight, default: .white].opacity(0.3))
                        .cornerRadius(4)
                }
            }
        }
    }
}



#Preview {
    ContentView()
}
