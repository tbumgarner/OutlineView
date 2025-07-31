import Cocoa

// MARK: ContextualOutlineView
//
class ContextualOutlineView: NSOutlineView {
    /// NSOutlineView doesn't appear to support contextual menus by right/control clicking on rows.
    /// This will look for the row clicked, and if it conforms to ContextmenuProviding, call that view
    /// to get a menu to be returned.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        
        guard row >= 0,
              let view = self.view(atColumn: 0, row: row, makeIfNecessary: false)
        else {
            return nil
        }
        
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        
        return view.menu(for: event)
    }
}
