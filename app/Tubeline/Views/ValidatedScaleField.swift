import SwiftUI

struct ValidatedScaleField: View {
    let accessibilityTitle: String
    @Binding var value: Int
    var contextID = ""

    var body: some View {
        ValidatedNumberField(title: "Output Scale", accessibilityTitle: accessibilityTitle,
                             value: Binding(get: { Double(value) }, set: { value = Int($0) }),
                             unit: "×", rule: .outputScale, fractionDigits: 0, fieldWidth: 65,
                             contextID: contextID)
    }
}
