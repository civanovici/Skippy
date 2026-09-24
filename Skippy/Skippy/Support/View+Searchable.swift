import SwiftUI

extension View {
    @ViewBuilder
    func searchableIf(_ isEnabled: Bool, text: Binding<String>, prompt: String) -> some View {
        if isEnabled {
            searchable(text: text, prompt: prompt)
        } else {
            self
        }
    }
}
