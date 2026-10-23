@testable import TubelineCore

extension ConversionOptions {
    /// Default settings at true print size (1×), for tests that check exact physical
    /// dimensions. The shipping default Output Scale is 10×.
    static var trueSize: ConversionOptions {
        var options = ConversionOptions()
        options.outputScale = 1
        return options
    }
}
