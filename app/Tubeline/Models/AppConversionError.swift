import Foundation

enum AppConversionError: LocalizedError {
    case sourceChanged

    var errorDescription: String? {
        "The SVG changed during conversion. Refresh the icon and export again."
    }
}
