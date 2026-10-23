import Foundation

enum NumericInputRule: Equatable {
    case positive
    case outputScale

    var guidance: String {
        switch self {
        case .positive: "Enter a finite number greater than zero."
        case .outputScale: "Enter a whole number from 1 to 10,000."
        }
    }

    func parse(_ text: String, locale: Locale) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, Self.isCompleteNumber(text, locale: locale),
              let value = try? Double(text, format: .number.locale(locale), lenient: false),
              value.isFinite else { return nil }
        switch self {
        case .positive: return value > 0 ? value : nil
        case .outputScale:
            return (1...10_000).contains(value) && value.rounded() == value ? value : nil
        }
    }

    /// Foundation's numeric parser accepts a valid prefix, even with lenient parsing off.
    /// Check the whole localized token before allowing it to change a setting.
    private static func isCompleteNumber(_ text: String, locale: Locale) -> Bool {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let decimal = NSRegularExpression.escapedPattern(for: formatter.decimalSeparator ?? ".")
        let grouping = formatter.groupingSeparator ?? ""
        let digit = #"\p{Nd}"#
        var integer = "\(digit)+"
        if !grouping.isEmpty, formatter.groupingSize > 0 {
            let group = NSRegularExpression.escapedPattern(for: grouping)
            let primary = formatter.groupingSize
            let secondary = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primary
            let grouped = "\(digit){1,\(secondary)}(?:\(group)\(digit){\(secondary)})*\(group)\(digit){\(primary)}"
            integer = "(?:\(integer)|\(grouped))"
        }
        let fraction = "(?:\(integer)(?:\(decimal)\(digit)*)?|\(decimal)\(digit)+)"
        let exponent = NSRegularExpression.escapedPattern(for: formatter.exponentSymbol ?? "E")
        let pattern = "^[+−-]?\(fraction)(?:(?:[eE]|\(exponent))[+−-]?\(digit)+)?$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
