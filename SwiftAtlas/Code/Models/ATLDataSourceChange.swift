import Foundation
import LayerKit

class ATLDataSourceChange : NSObject {
    var type: LYRQueryControllerChangeType

    var newIndex: Int

    var currentIndex: Int

    static func changeObjectWithType(type: LYRQueryControllerChangeType, newIndex: Int, currentIndex: Int) -> ATLDataSourceChange {
        return ATLDataSourceChange(type: type, newIndex: newIndex, currentIndex: currentIndex)
    }
            
    init(type: LYRQueryControllerChangeType, newIndex: Int, currentIndex: Int) {
        self.type = type
        self.newIndex = newIndex
        self.currentIndex = currentIndex
    }
}