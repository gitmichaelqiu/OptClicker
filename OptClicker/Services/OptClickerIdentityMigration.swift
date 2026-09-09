import Foundation
import ServiceManagement

enum OptClickerIdentity {
    static let legacyBundleIdentifier = "michaelqiu.OptClicker"
    static let currentBundleIdentifier = "dev.mqiu.OptClicker"

    static let currentUpdateChannel = "dev-mqiu"
    static let appcastTargetBundleIdentifierKey = "optclicker:targetBundleIdentifier"

    static let migrationPackageURLKey = "OptClickerMigrationPackageURL"
    static let migrationPackageSHA256Key = "OptClickerMigrationPackageSHA256"
    static let migrationPackageVersionKey = "OptClickerMigrationPackageVersion"
    static let migrationAllowManualApprovalKey = "OptClickerMigrationAllowManualApproval"
    static let migrationStagingPathKey = "OptClickerMigrationStagingPath"
    static let releaseTagKey = "OptClickerReleaseTag"

    static let migrationLaunchAtLoginPendingKey = "OptClicker.IdentityMigration.LaunchAtLoginPending"
    static let migrationCleanupStagedPathKey = "OptClicker.IdentityMigration.CleanupStagedPath"
    static let migrationCleanupBackupPathKey = "OptClicker.IdentityMigration.CleanupBackupPath"
    static let migrationLaunchAcknowledgedKey = "OptClicker.IdentityMigration.LaunchAcknowledged"
    static let migrationCompletedKey = "OptClicker.IdentityMigration.Completed"

    static var isLegacyBridge: Bool {
        Bundle.main.bundleIdentifier == legacyBundleIdentifier
    }

    static var isCurrentApplication: Bool {
        Bundle.main.bundleIdentifier == currentBundleIdentifier
    }
}

enum OptClickerMigrationStorage {
    static let migrationDirectoryName = "Migration"
    static let manifestFileName = "manifest.json"

    static var applicationSupportDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OptClicker", isDirectory: true)
            .appendingPathComponent(migrationDirectoryName, isDirectory: true)
    }

    static var manifestURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent(manifestFileName)
    }

    static var cacheDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OptClicker", isDirectory: true)
            .appendingPathComponent(migrationDirectoryName, isDirectory: true)
    }

    static func writeManifest(_ manifest: OptClickerMigrationManifest) throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
    }

    static func readManifest(from url: URL = manifestURL) throws -> OptClickerMigrationManifest {
        try JSONDecoder().decode(
            OptClickerMigrationManifest.self,
            from: Data(contentsOf: url)
        )
    }

    static func discardPendingMigration() {
        try? FileManager.default.removeItem(at: manifestURL)
        try? FileManager.default.removeItem(at: cacheDirectoryURL)
    }
}

struct OptClickerMigrationManifest: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sourceApplicationPath: String
    let sourceProcessIdentifier: Int32
    let targetBundleIdentifier: String
    let stagingApplicationPath: String
    let launchAtLoginEnabled: Bool
    let expectedVersion: String
    let createdAt: Date
}

enum OptClickerMigrationVersion {
    static func isAtLeast(_ candidate: String, _ expected: String) -> Bool {
        guard let candidate = numericComponents(candidate),
              let expected = numericComponents(expected) else { return false }

        let count = max(candidate.count, expected.count)
        for index in 0..<count {
            let candidateValue = index < candidate.count ? candidate[index] : 0
            let expectedValue = index < expected.count ? expected[index] : 0
            if candidateValue != expectedValue { return candidateValue > expectedValue }
        }
        return true
    }

    private static func numericComponents(_ version: String) -> [Int]? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 4,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        let values = components.compactMap { Int($0) }
        return values.count == components.count ? values : nil
    }
}

enum OptClickerMigrationError: LocalizedError {
    case invalidConfiguration
    case invalidDownloadResponse
    case invalidPackageHash
    case packageVerificationFailed
    case installerClosed
    case stagingApplicationNotFound
    case stagingApplicationInvalid
    case stagingApplicationDidNotTerminate
    case manifestInvalid
    case legacyApplicationDidNotTerminate
    case targetApplicationInvalid
    case applicationSwapFailed
    case applicationLaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "The OptClicker migration is not configured for this build."
        case .invalidDownloadResponse: return "The migration package could not be downloaded."
        case .invalidPackageHash: return "The migration package checksum did not match the signed release."
        case .packageVerificationFailed: return "The migration package did not pass macOS package verification."
        case .installerClosed: return "The migration installer was closed before the new application was installed."
        case .stagingApplicationNotFound: return "The migration package was installed, but its staged application was not found."
        case .stagingApplicationInvalid: return "The staged application has an unexpected identity or version."
        case .stagingApplicationDidNotTerminate: return "The previous staged OptClicker process did not close safely."
        case .manifestInvalid: return "The migration manifest is missing or invalid."
        case .legacyApplicationDidNotTerminate: return "The previous OptClicker process did not close safely."
        case .targetApplicationInvalid: return "The previous application location is not safe to replace."
        case .applicationSwapFailed: return "The new OptClicker application could not be installed."
        case .applicationLaunchFailed: return "The new OptClicker application could not be launched."
        }
    }
}

enum OptClickerMigrationConfiguration {
    static var packageURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: OptClickerIdentity.migrationPackageURLKey) as? String,
              let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    static var packageSHA256: String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: OptClickerIdentity.migrationPackageSHA256Key) as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.count == 64, value.allSatisfy({ $0.isNumber || ("a"..."f").contains($0) }) else { return nil }
        return value
    }

    static var packageVersion: String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: OptClickerIdentity.migrationPackageVersionKey) as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static var allowsManualApproval: Bool {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: OptClickerIdentity.migrationAllowManualApprovalKey)
        if let value = rawValue as? Bool { return value }
        guard let value = rawValue as? String else { return false }
        return ["1", "yes", "true"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static var stagingApplicationURL: URL {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: OptClickerIdentity.migrationStagingPathKey) as? String {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("/"), value.hasSuffix(".app") {
                return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
            }
        }
        return URL(fileURLWithPath: "/Applications/OptClicker-Migration.app", isDirectory: true)
    }

    static var isConfigured: Bool {
        packageURL != nil && packageSHA256 != nil && packageVersion != nil
    }
}

enum OptClickerIdentityMigration {
    static func prepareLegacyBridgeLaunch() {
        guard OptClickerIdentity.isLegacyBridge else { return }
        let legacyDomain = UserDefaults.standard.persistentDomain(forName: OptClickerIdentity.legacyBundleIdentifier) ?? [:]
        guard legacyDomain.isEmpty,
              var currentDomain = UserDefaults.standard.persistentDomain(forName: OptClickerIdentity.currentBundleIdentifier),
              !currentDomain.isEmpty else { return }
        currentDomain = currentDomain.filter { key, _ in !isSparkleKey(key) && !key.hasPrefix("OptClicker.IdentityMigration.") }
        guard !currentDomain.isEmpty else { return }
        UserDefaults.standard.setPersistentDomain(currentDomain, forName: OptClickerIdentity.legacyBundleIdentifier)
        UserDefaults.standard.synchronize()
    }

    static func migrateLegacyDefaults(launchAtLoginEnabled: Bool) {
        guard OptClickerIdentity.isCurrentApplication,
              !UserDefaults.standard.bool(forKey: OptClickerIdentity.migrationCompletedKey) else { return }
        let legacyDomain = UserDefaults.standard.persistentDomain(forName: OptClickerIdentity.legacyBundleIdentifier) ?? [:]
        var currentDomain = UserDefaults.standard.persistentDomain(forName: OptClickerIdentity.currentBundleIdentifier) ?? [:]
        for (key, value) in legacyDomain where !isSparkleKey(key) { currentDomain[key] = value }
        currentDomain["HasInitializedDefaults"] = true
        UserDefaults.standard.setPersistentDomain(currentDomain, forName: OptClickerIdentity.currentBundleIdentifier)
        UserDefaults.standard.set(launchAtLoginEnabled, forKey: OptClickerIdentity.migrationLaunchAtLoginPendingKey)
        UserDefaults.standard.set(true, forKey: OptClickerIdentity.migrationCompletedKey)
    }

    static func prepareNormalLaunch() {
        guard OptClickerIdentity.isCurrentApplication else { return }
        let hasPendingCleanup = UserDefaults.standard.string(forKey: OptClickerIdentity.migrationCleanupStagedPathKey) != nil
        let cleanupCompleted = cleanupStagedApplicationIfNeeded()
        if hasPendingCleanup {
            UserDefaults.standard.set(true, forKey: OptClickerIdentity.migrationLaunchAcknowledgedKey)
            UserDefaults.standard.synchronize()
            if !cleanupCompleted { retryPendingCleanup() }
        }
        guard let launchAtLogin = UserDefaults.standard.object(forKey: OptClickerIdentity.migrationLaunchAtLoginPendingKey) as? Bool else { return }
        do {
            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            UserDefaults.standard.removeObject(forKey: OptClickerIdentity.migrationLaunchAtLoginPendingKey)
        } catch {
            print("OptClicker IdentityMigration: failed to restore launch at login: \(error)")
        }
    }

    private static func retryPendingCleanup(attemptsRemaining: Int = 120) {
        guard UserDefaults.standard.string(forKey: OptClickerIdentity.migrationCleanupStagedPathKey) != nil,
              attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !cleanupStagedApplicationIfNeeded() { retryPendingCleanup(attemptsRemaining: attemptsRemaining - 1) }
        }
    }

    @discardableResult
    private static func cleanupStagedApplicationIfNeeded() -> Bool {
        guard let stagedPath = UserDefaults.standard.string(forKey: OptClickerIdentity.migrationCleanupStagedPathKey) else { return true }
        let stagedURL = URL(fileURLWithPath: stagedPath, isDirectory: true).standardizedFileURL
        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        guard stagedURL != currentURL, stagedURL.pathExtension == "app" else {
            UserDefaults.standard.removeObject(forKey: OptClickerIdentity.migrationCleanupStagedPathKey)
            return true
        }
        do {
            if FileManager.default.fileExists(atPath: stagedURL.path) { try FileManager.default.removeItem(at: stagedURL) }
            if let backupPath = UserDefaults.standard.string(forKey: OptClickerIdentity.migrationCleanupBackupPathKey) {
                let backupURL = URL(fileURLWithPath: backupPath, isDirectory: true).standardizedFileURL
                if backupURL.pathExtension == "app", backupURL != currentURL, FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.removeItem(at: backupURL)
                }
            }
            try? FileManager.default.removeItem(at: OptClickerMigrationStorage.manifestURL)
            try? FileManager.default.removeItem(at: OptClickerMigrationStorage.cacheDirectoryURL)
            try? SMAppService.loginItem(identifier: OptClickerIdentity.legacyBundleIdentifier).unregister()
            UserDefaults.standard.removePersistentDomain(forName: OptClickerIdentity.legacyBundleIdentifier)
            UserDefaults.standard.removeObject(forKey: OptClickerIdentity.migrationCleanupStagedPathKey)
            UserDefaults.standard.removeObject(forKey: OptClickerIdentity.migrationCleanupBackupPathKey)
            return true
        } catch {
            print("OptClicker IdentityMigration: staged application cleanup deferred: \(error)")
            return false
        }
    }

    private static func isSparkleKey(_ key: String) -> Bool {
        key.hasPrefix("SU") || key.hasPrefix("SPU") || key.hasPrefix("org.sparkle-project")
    }
}
