import SwiftUI

enum TacticalTypography {
    static let brand = Font.system(size: 46, weight: .black).width(.condensed).italic()
    static let page = Font.system(size: 28, weight: .bold)
    static let module = Font.system(size: 15, weight: .semibold)
    static let value = Font.system(size: 18, weight: .semibold)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11, weight: .medium)
    static let log = Font.system(size: 11, design: .monospaced)
}
