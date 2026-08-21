import SwiftUI
import TimeTacKit

/// The status item itself: a symbol, plus the running duration when there is one.
///
/// `MenuBarExtra` renders its label into a fixed-height status item and only reliably supports
/// simple image + text composition, so this stays deliberately plain.
struct MenuBarLabel: View {
    let snapshot: PresenceSnapshot
    let tick: Date

    var body: some View {
        if let elapsed = snapshot.elapsed(asOf: tick) {
            Label {
                // Monospaced digits stop the item resizing every time a minute ticks over.
                Text(DurationFormat.compact(elapsed)).monospacedDigit()
            } icon: {
                Image(systemName: snapshot.status.symbolName)
            }
        } else {
            Image(systemName: snapshot.status.symbolName)
        }
    }
}
