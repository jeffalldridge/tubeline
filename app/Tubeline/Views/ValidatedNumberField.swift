import SwiftUI

struct ValidatedNumberField: View {
    let title: String
    let accessibilityTitle: String
    @Binding var value: Double
    let unit: String
    var rule = NumericInputRule.positive
    var fractionDigits = 2
    var fieldWidth: CGFloat = 75
    var contextID = ""

    @Environment(\.locale) private var locale
    @FocusState private var focused: Bool
    @State private var draft = NumericInputDraft()
    @State private var displayedContext = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                TextField(accessibilityTitle, text: Binding(get: { draft.text }, set: { draft.edit($0) }))
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: fieldWidth)
                    .focused($focused)
                    .onSubmit { commit() }
                    .accessibilityHint(draft.error ?? rule.guidance)
                if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
                if rule == .outputScale {
                    Stepper(accessibilityTitle, value: $value, in: 1...10_000, step: 1)
                        .labelsHidden().fixedSize()
                }
            }
            if let error = draft.error {
                Label("\(title): \(error)", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { synchronize() }
        .onChange(of: value) { synchronize() }
        .onChange(of: contextID) { synchronize() }
        .onChange(of: locale) { synchronize() }
        .onChange(of: focused) { if !focused { commit() } }
    }

    private func synchronize() {
        displayedContext = contextID
        draft.synchronize(value: value, locale: locale, fractionDigits: fractionDigits)
    }

    private func commit() {
        guard displayedContext == contextID else { synchronize(); return }
        guard let parsed = draft.commit(rule: rule, locale: locale) else { return }
        value = parsed
        synchronize()
    }
}
