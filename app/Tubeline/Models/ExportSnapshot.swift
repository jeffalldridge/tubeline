import Foundation
import TubelineCore

struct ExportSnapshot {
    let job: Job
    let output: URL
    let options: ConversionOptions
    let revision: Int
    let sourceStamp: SourceStamp
}
