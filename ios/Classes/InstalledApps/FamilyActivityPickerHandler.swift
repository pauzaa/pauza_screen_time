/// Handles FamilyActivityPicker presentation and ApplicationToken management for iOS.
///
/// This class manages the iOS app selection flow using FamilyActivityPicker,
/// which is the only way to get app information on iOS due to privacy restrictions.
/// Selected app tokens are returned to Flutter; this handler does not persist selection locally.

import Flutter
import Foundation
import FamilyControls
import ManagedSettings
import SwiftUI

// MARK: - Token codec errors

/// Errors thrown when an ApplicationToken cannot be encoded or decoded.
enum TokenCodecError: Error {
    /// A base64 string could not be decoded to Data.
    case invalidBase64(String)
    /// JSONDecoder failed to decode an ApplicationToken from the provided data.
    case decodeFailed(underlying: Error)
    /// JSONEncoder failed to encode an ApplicationToken.
    case encodeFailed(underlying: Error)
}

// MARK: - Main handler

/// Handler for iOS FamilyActivityPicker and selected app management.
///
/// Uses FamilyControls framework to present the app picker and manages
/// selected ApplicationTokens for serialization to Flutter.
@available(iOS 16.0, *)
class FamilyActivityPickerHandler: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance of FamilyActivityPickerHandler.
    static let shared = FamilyActivityPickerHandler()
    
    // MARK: - Published Properties
    
    /// The current selection from FamilyActivityPicker.
    @Published var activitySelection = FamilyActivitySelection()
    
    private init() {
    }
    
    // MARK: - Public Methods
    
    /// Presents the FamilyActivityPicker and returns selected apps as serialised tokens.
    ///
    /// - Parameter viewController: The host to present the picker from.
    /// - Parameter preSelectedTokens: Optional array of base64-encoded ApplicationTokens to pre-select.
    /// - Parameter completion: Called with `.success([[String:Any]])` on normal completion,
    ///                         or `.failure(TokenCodecError)` if any token cannot be encoded.
    func showPicker(
        from viewController: UIViewController,
        preSelectedTokens: [String]? = nil,
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        // Decode pre-selected tokens; propagate errors immediately.
        if let tokens = preSelectedTokens, !tokens.isEmpty {
            do {
                try setPreSelectedTokens(tokens)
            } catch {
                completion(.failure(error))
                return
            }
        }

        let pickerView = FamilyActivityPickerView(
            selection: Binding(
                get: { self.activitySelection },
                set: { self.activitySelection = $0 }
            ),
            completion: { [weak self] in
                guard let self = self else {
                    completion(.success([]))
                    return
                }
                do {
                    let result = try self.serializeSelection()
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        )

        let hostingController = UIHostingController(rootView: pickerView)
        hostingController.modalPresentationStyle = .formSheet

        viewController.present(hostingController, animated: true)
    }
    
    // MARK: - Private Methods

    /// Decodes the provided base64 token strings and stores them as the active selection.
    ///
    /// - Throws: `TokenCodecError.invalidBase64` when a token string is not valid base64.
    /// - Throws: `TokenCodecError.decodeFailed` when JSONDecoder cannot reconstruct the token.
    private func setPreSelectedTokens(_ base64Tokens: [String]) throws {
        var tokens = Set<ApplicationToken>()

        for base64Token in base64Tokens {
            guard let tokenData = Data(base64Encoded: base64Token) else {
                throw TokenCodecError.invalidBase64(base64Token)
            }
            do {
                let token = try JSONDecoder().decode(ApplicationToken.self, from: tokenData)
                tokens.insert(token)
            } catch {
                throw TokenCodecError.decodeFailed(underlying: error)
            }
        }

        activitySelection.applicationTokens = tokens
    }

    /// Serialises the current selection to a list of channel maps for Flutter.
    ///
    /// - Throws: `TokenCodecError.encodeFailed` when a token cannot be JSON-encoded.
    private func serializeSelection() throws -> [[String: Any]] {
        var result: [[String: Any]] = []

        for token in activitySelection.applicationTokens {
            let tokenData: Data
            do {
                tokenData = try JSONEncoder().encode(token)
            } catch {
                throw TokenCodecError.encodeFailed(underlying: error)
            }
            let base64Token = tokenData.base64EncodedString()
            result.append(
                IOSSelectedAppPayload(
                    platform: "ios",
                    applicationToken: base64Token
                ).toChannelMap()
            )
        }

        return result
    }
}

// MARK: - Domain model

/// Payload for a single iOS-selected application returned over the method channel.
struct IOSSelectedAppPayload {
    let platform: String
    let applicationToken: String

    /// Serialises this payload to the method-channel wire format.
    func toChannelMap() -> [String: Any] {
        return [
            "platform": platform,
            "applicationToken": applicationToken,
        ]
    }

    /// Deserialises a raw method-channel map into an [IOSSelectedAppPayload].
    ///
    /// - Throws: `TokenCodecError.invalidBase64` when `applicationToken` is missing or empty.
    static func fromMap(_ map: [String: Any]) throws -> IOSSelectedAppPayload {
        guard let platform = map["platform"] as? String, !platform.isEmpty else {
            throw TokenCodecError.invalidBase64("IOSSelectedAppPayload: missing 'platform' field")
        }
        guard let token = map["applicationToken"] as? String, !token.isEmpty else {
            throw TokenCodecError.invalidBase64("IOSSelectedAppPayload: missing 'applicationToken' field")
        }
        return IOSSelectedAppPayload(platform: platform, applicationToken: token)
    }
}

// MARK: - SwiftUI Picker View

/// SwiftUI wrapper view for FamilyActivityPicker.
@available(iOS 16.0, *)
struct FamilyActivityPickerView: View {
    @Binding var selection: FamilyActivitySelection
    let completion: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Select Apps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                            completion()
                        }
                    }
                }
        }
    }
}

// MARK: - Legacy Handler for iOS < 16

/// Fallback handler for iOS versions below 16.0.
///
/// FamilyActivityPicker is not available on iOS < 16.0.
/// This handler propagates a proper UNSUPPORTED error to the Flutter caller
/// instead of silently returning an empty list.
class LegacyFamilyActivityPickerHandler {
    
    /// Shared instance.
    static let shared = LegacyFamilyActivityPickerHandler()
    
    private init() {}

    /// Reports an UNSUPPORTED error via [flutterResult] since FamilyActivityPicker
    /// requires iOS 16.0 or later.
    func showPicker(
        feature: String,
        action: String,
        flutterResult: @escaping FlutterResult
    ) {
        flutterResult(PluginErrors.unsupported(
            feature: feature,
            action: action,
            message: "FamilyActivityPicker requires iOS 16.0 or later"
        ))
    }
}

