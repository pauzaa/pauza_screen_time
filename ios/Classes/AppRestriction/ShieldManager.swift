import Foundation
import FamilyControls
import ManagedSettings

/// Wrapper around ManagedSettingsStore for app restriction management.
@available(iOS 16.0, *)
final class ShieldManager {
    static let shared = ShieldManager()
    private let store = ManagedSettingsStore()

    private init() {}

    func setRestrictedApps(_ tokens: Set<ApplicationToken>) {
        store.shield.applications = tokens
    }

    /// Decodes base64-encoded `ApplicationToken`s, preserving input order and de-duplicating by
    /// the original base64 strings.
    ///
    /// This does **not** mutate the current restrictions. Callers can decide whether to apply
    /// changes (e.g., fail-fast if any token is invalid).
    func decodeTokens(base64Tokens: [String]) -> TokenDecodeResult {
        var uniqueBase64Tokens: [String] = []
        uniqueBase64Tokens.reserveCapacity(base64Tokens.count)
        var seen = Set<String>()

        for value in base64Tokens {
            if seen.insert(value).inserted {
                uniqueBase64Tokens.append(value)
            }
        }

        var tokens = Set<ApplicationToken>()
        var invalidTokens: [String] = []
        invalidTokens.reserveCapacity(0)

        for tokenValue in uniqueBase64Tokens {
            do {
                let token = try decodeToken(tokenValue)
                tokens.insert(token)
            } catch {
                print("⚠️ [ShieldManager] Error decoding token: \(error)")
                invalidTokens.append(tokenValue)
            }
        }

        return TokenDecodeResult(
            tokens: tokens,
            appliedBase64Tokens: invalidTokens.isEmpty ? uniqueBase64Tokens : [],
            invalidTokens: invalidTokens
        )
    }

    @discardableResult
    func addRestrictedApp(base64Token: String) -> Bool? {
        do {
            let token = try decodeToken(base64Token)
            var current = store.shield.applications ?? Set<ApplicationToken>()
            let inserted = current.insert(token).inserted
            store.shield.applications = current
            return inserted
        } catch {
            print("⚠️ [ShieldManager] Error decoding token in addRestrictedApp: \(error)")
            return nil
        }
    }

    @discardableResult
    func removeRestrictedApp(base64Token: String) -> Bool? {
        do {
            let token = try decodeToken(base64Token)
            var current = store.shield.applications ?? Set<ApplicationToken>()
            let removed = current.remove(token) != nil
            store.shield.applications = current
            return removed
        } catch {
            print("⚠️ [ShieldManager] Error decoding token in removeRestrictedApp: \(error)")
            return nil
        }
    }

    func isRestricted(base64Token: String) -> Bool? {
        do {
            let token = try decodeToken(base64Token)
            let current = store.shield.applications ?? Set<ApplicationToken>()
            return current.contains(token)
        } catch {
            print("⚠️ [ShieldManager] Error decoding token in isRestricted: \(error)")
            return nil
        }
    }

    func clearRestrictions() {
        store.shield.applications = nil
        store.shield.webDomains = nil
    }

    func getRestrictedApps() -> [String] {
        guard let tokens = store.shield.applications else {
            return []
        }
        return tokens.compactMap { token in 
            do {
                return try encodeToken(token)
            } catch {
                print("⚠️ [ShieldManager] Error encoding token in getRestrictedApps: \(error)")
                return nil
            }
        }
    }

    struct TokenDecodeResult {
        let tokens: Set<ApplicationToken>
        /// The base64 token strings that are valid and were intended to be applied, in input order,
        /// de-duplicated by base64 string.
        ///
        /// If `invalidTokens` is not empty, this will be an empty list to support fail-fast callers.
        let appliedBase64Tokens: [String]
        let invalidTokens: [String]
    }

    private func decodeToken(_ base64Token: String) throws -> ApplicationToken {
        guard let data = Data(base64Encoded: base64Token) else {
            throw TokenCodecError.invalidBase64(base64Token)
        }
        do {
            return try JSONDecoder().decode(ApplicationToken.self, from: data)
        } catch {
            throw TokenCodecError.decodeFailed(underlying: error)
        }
    }

    private func encodeToken(_ token: ApplicationToken) throws -> String? {
        do {
            let data = try JSONEncoder().encode(token)
            return data.base64EncodedString()
        } catch {
            throw TokenCodecError.encodeFailed(underlying: error)
        }
    }
}
