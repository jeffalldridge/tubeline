import Foundation

struct SourceStamp: Equatable {
    let modified: Date?
    let size: Int?

    init(url: URL) {
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        let values = try? freshURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        modified = values?.contentModificationDate
        size = values?.fileSize
    }
}
