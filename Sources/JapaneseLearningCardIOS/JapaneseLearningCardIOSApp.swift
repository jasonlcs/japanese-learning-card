import JapaneseLearningCardCore
import JapaneseLearningCardUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - App entry point

@main
struct JapaneseLearningCardIOSApp: App {
    @StateObject private var holder = AppHolder()

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel = holder.viewModel {
                    IOSRootView(viewModel: viewModel)
                } else {
                    ProgressView("初始化中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Async initialisation wrapper

/// Owns the AppStore + AppViewModel; initialised asynchronously in a background Task.
@MainActor
private final class AppHolder: ObservableObject {
    @Published private(set) var viewModel: AppViewModel?

    init() {
        Task {
            let store = await AppStore()
            let vm = AppViewModel(store: store)
            self.viewModel = vm
            vm.start()
        }
    }
}

// MARK: - iOS root view

/// Wraps RootView inside a NavigationStack and handles iOS lifecycle events.
struct IOSRootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            #if canImport(UIKit)
            RootView(viewModel: viewModel)
                .navigationBarTitleDisplayMode(.inline)
            #else
            RootView(viewModel: viewModel)
            #endif
        }
        #if canImport(UIKit)
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            // iOS 只做學習與同步：回前景時從 CloudKit 拉最新資料，
            // 內容產生（爬蟲 / AI 造卡）留在 macOS 版。
            Task { await viewModel.performPull() }
        }
        #endif
    }
}
