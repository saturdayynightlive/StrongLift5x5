//
//  StrongLift5x5App.swift
//  StrongLift5x5
//
//  Created by 지환 on 9/19/25.
//

import SwiftUI


struct StrongLift5x5App: App {
    @StateObject private var manager = WorkoutManager()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
            WindowGroup {
                // 이 부분은 기존 코드와 동일합니다.
                ContentView()
                    .environmentObject(manager)
            }
            // ⭐️ 추가: 앱 상태가 바뀔 때마다 manager의 함수를 호출
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    manager.handleAppBecomingActive()
                }
            }
        }
}
