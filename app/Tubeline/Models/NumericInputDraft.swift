import Foundation

/// Display formatting never changes the stored precision unless the user edits the field.
struct NumericInputDraft {
    private(set) var text = ""
    private(set) var error: String?
    private var originalText = ""

    mutating func synchronize(value: Double, locale: Locale, fractionDigits: Int) {
        let style = FloatingPointFormatStyle<Double>.number.grouping(.never)
            .precision(.fractionLength(0...fractionDigits)).locale(locale)
        text = value.formatted(style)
        if value != 0, (try? Double(text, format: style)) == 0 {
            text = value.formatted(.number.notation(.scientific).precision(.significantDigits(1...8)).locale(locale))
        }
        originalText = text
        error = nil
    }

    mutating func edit(_ text: String) {
        self.text = text
        error = nil
    }

    mutating func commit(rule: NumericInputRule, locale: Locale) -> Double? {
        guard text != originalText else { error = nil; return nil }
        guard let value = rule.parse(text, locale: locale) else {
            error = rule.guidance + " This edit hasn’t been applied."
            return nil
        }
        error = nil
        return value
    }
}
