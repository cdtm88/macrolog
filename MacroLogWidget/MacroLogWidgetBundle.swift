import WidgetKit
import SwiftUI

@main
struct MacroLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        FavoritesWidget()
    }
}
