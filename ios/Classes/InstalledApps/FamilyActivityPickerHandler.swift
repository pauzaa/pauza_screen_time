/// Handles FamilyActivityPicker presentation and ApplicationToken management for iOS.
///
/// This class manages the iOS app selection flow using FamilyActivityPicker,
/// which is the only way to get app information on iOS due to privacy restrictions.
/// Selected app tokens are returned to Flutter; this handler does not persist selection locally.

import Foundation
import FamilyControls
import ManagedSettings
import SwiftUI

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
    
    /// Presents the FamilyActivityPicker and returns selected apps as serialized tokens.
    ///
    /// - Parameter viewController: The view controller to present the picker from.
    /// - Parameter preSelectedTokens: Optional array of base64-encoded ApplicationTokens to pre-select.
    /// - Parameter completion: Callback with list of maps containing applicationToken and platform.
    func showPicker(
        from viewController: UIViewController,
        preSelectedTokens: [String]? = nil,
        completion: @escaping ([[String: Any]]) -> Void
    ) {
        // If pre-selected tokens are provided, decode and set them
        if let tokens = preSelectedTokens, !tokens.isEmpty {
            setPreSelectedTokens(tokens)
        }
        
        // Create a hosting controller for the picker
        let pickerView = FamilyActivityPickerView(
            selection: Binding(
                get: { self.activitySelection },
                set: { self.activitySelection = $0 }
            ),
            completion: { [weak self] in
                guard let self = self else {
                    completion([])
                    return
                }

                // Convert tokens to serializable format
                let result = self.serializeSelection()
                completion(result)
            }
        )
        
        let hostingController = UIHostingController(rootView: pickerView)
        hostingController.modalPresentationStyle = .formSheet
        
        viewController.present(hostingController, animated: true)
    }
    
    /// Sets pre-selected tokens from base64-encoded strings.
    ///
    /// - Parameter base64Tokens: Array of base64-encoded ApplicationToken strings.
    func setPreSelectedTokens(_ base64Tokens: [String]) {
        var tokens = Set<ApplicationToken>()
        
        for base64Token in base64Tokens {
            if let tokenData = Data(base64Encoded: base64Token),
               let token = try? JSONDecoder().decode(ApplicationToken.self, from: tokenData) {
                tokens.insert(token)
            }
        }
        
        // Update the selection with decoded tokens
        activitySelection.applicationTokens = tokens
    }
    
    // MARK: - Private Methods
    
    /// Serializes the current selection to a list of maps for Flutter.
    private func serializeSelection() -> [[String: Any]] {
        var result: [[String: Any]] = []
        
        // Serialize application tokens
        for token in activitySelection.applicationTokens {
            if let tokenData = try? JSONEncoder().encode(token) {
                let base64Token = tokenData.base64EncodedString()
                result.append(
                    IOSSelectedAppPayload(
                        platform: "ios",
                        applicationToken: base64Token
                    ).toChannelMap()
                )
            }
        }
        
        return result
    }
}

private struct IOSSelectedAppPayload {
    let platform: String
    let applicationToken: String

    func toChannelMap() -> [String: Any] {
        return [
            "platform": platform,
            "applicationToken": applicationToken,
        ]
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
/// FamilyActivityPicker is not available on iOS < 16.0,
/// so this handler returns empty results.
class LegacyFamilyActivityPickerHandler {
    
    /// Shared instance.
    static let shared = LegacyFamilyActivityPickerHandler()
    
    private init() {}
    
    /// Returns an error result since FamilyActivityPicker is not available.
    func showPicker(completion: @escaping ([[String: Any]]) -> Void) {
        // FamilyActivityPicker requires iOS 16.0+
        completion([])
    }
    
    /// Returns empty array.
    func getSelectedApps() -> [[String: Any]] {
        return []
    }
}
