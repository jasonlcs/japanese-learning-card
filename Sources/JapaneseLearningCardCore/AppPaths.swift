import Foundation

enum AppPaths {
    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static var appSupportFolder: URL {
        applicationSupportDirectory.appendingPathComponent("JapaneseLearningCard", isDirectory: true)
    }
}
