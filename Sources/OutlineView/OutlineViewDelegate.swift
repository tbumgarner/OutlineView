import Cocoa

@available(macOS 10.15, *)
class OutlineViewDelegate<Data: Sequence>: NSObject, NSOutlineViewDelegate
where Data.Element: Identifiable {
    let content: (Data.Element) -> NSView
    let selectionChanged: (Data.Element?) -> Void
    let separatorInsets: ((Data.Element) -> NSEdgeInsets)?
    var selectedItem: OutlineViewItem<Data>?
    let isGroupItem: ((Data.Element) -> Bool)?
    let groupTitle: ((Data.Element) -> String)?
    let configuration: ((NSOutlineView) -> Void)?

    func typedItem(_ item: Any) -> OutlineViewItem<Data> {
        item as! OutlineViewItem<Data>
    }

    init(
        content: @escaping (Data.Element) -> NSView,
        selectionChanged: @escaping (Data.Element?) -> Void,
        separatorInsets: ((Data.Element) -> NSEdgeInsets)?,
        isGroupItem: ((Data.Element) -> Bool)? = nil,
        groupTitle: ((Data.Element) -> String)? = nil,
        configuration: ((NSOutlineView) -> Void)? = nil
    ) {
        self.content = content
        self.selectionChanged = selectionChanged
        self.separatorInsets = separatorInsets
        self.isGroupItem = isGroupItem
        self.groupTitle = groupTitle
        self.configuration = configuration
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        let value = typedItem(item).value
        if let isGroupItem, isGroupItem(value) {
            let groupTitle = groupTitle?(value) ?? ""

            // Reuse identifier
            let identifier = NSUserInterfaceItemIdentifier("GroupCell")
            if let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                cell.textField?.stringValue = groupTitle
                return cell
            }

            // Create new
            let cell = NSTableCellView()
            cell.identifier = identifier

            let label = NSTextField(labelWithString: groupTitle)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            label.textColor = NSColor.secondaryLabelColor

            cell.textField = label
            cell.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

       return  content(typedItem(item).value)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        rowViewForItem item: Any
    ) -> NSTableRowView? {
        let value = typedItem(item).value
        if let isGroupItem, isGroupItem(value) {
            return nil
        } else {
            if #available(macOS 11.0, *) {
                // For normal rows, provide adjustable separator row view.
                releaseUnusedRowViews(from: outlineView)
                let rowView = AdjustableSeparatorRowView(frame: .zero)
                rowView.separatorInsets = separatorInsets?(value)
                return rowView
            } else {
                return nil
            }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let isGroupItem else { return false }
        return isGroupItem(typedItem(item).value)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        shouldSelectItem item: Any
    ) -> Bool {
        let value = typedItem(item).value
        if let isGroupItem, isGroupItem(value) {
            return false
        }
        return true
    }

    // There seems to be a memory leak on macOS 11 where row views returned
    // from `rowViewForItem` are never freed. This hack patches the leak.
    func releaseUnusedRowViews(from outlineView: NSOutlineView) {
        guard #available(macOS 11.0, *) else { return }

        // Equivalent to _rowData._rowViewPurgatory
        let purgatoryPath = unmangle("^qnvC`s`-^qnvUhdvOtqf`snqx")
        if let rowViewPurgatory = outlineView.value(forKeyPath: purgatoryPath) as? NSMutableSet {
            rowViewPurgatory
                .compactMap { $0 as? AdjustableSeparatorRowView }
                .forEach {
                    $0.removeFromSuperview()
                    rowViewPurgatory.remove($0)
                }
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        heightOfRowByItem item: Any
    ) -> CGFloat {
        // It appears that for outline views with automatic row heights, the
        // initial height of the row still needs to be provided. Not providing
        // a height for each cell would lead to the outline view defaulting to the
        // `outlineView.rowHeight` when inserted. The cell may resize to the correct
        // height if the outline view is reloaded.

        // I am not able to find a better way to compute the final width of the cell
        // other than hard-coding some of the constants.
        let columnHorizontalInset: CGFloat
        if #available(macOS 11.0, *) {
            if outlineView.effectiveStyle == .plain {
                columnHorizontalInset = 18
            } else {
                columnHorizontalInset = 9
            }
        } else {
            columnHorizontalInset = 9
        }

        let column = outlineView.tableColumns.first.unsafelyUnwrapped
        let indentInset = CGFloat(outlineView.level(forItem: item)) * outlineView.indentationPerLevel

        let width = column.width - indentInset - columnHorizontalInset

        // The view is provided by the user. And the width info is not provided
        // separately. It does not seem efficient to create a new cell to find
        // out the width of a cell. In practice I have not experienced any issues
        // with a moderate number of cells.
        let view = content(typedItem(item).value)
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view.fittingSize.height
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        let outlineView = notification.object as! NSOutlineView
        if outlineView.selectedRow == -1 {
            selectRow(for: selectedItem, in: outlineView)
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let outlineView = notification.object as! NSOutlineView
        if outlineView.selectedRow != -1 {
            let newSelection = outlineView.item(atRow: outlineView.selectedRow).map(typedItem)
            if selectedItem?.id != newSelection?.id {
                selectedItem = newSelection
                selectionChanged(selectedItem?.value)
            }
        }
    }

    func selectRow(
        for item: OutlineViewItem<Data>?,
        in outlineView: NSOutlineView
    ) {
        // Returns -1 if row is not found.
        let index = outlineView.row(forItem: selectedItem)
        if index != -1 {
            outlineView.selectRowIndexes(IndexSet([index]), byExtendingSelection: false)
        } else {
            outlineView.deselectAll(nil)
        }
    }

    func changeSelectedItem(
        to item: OutlineViewItem<Data>?,
        in outlineView: NSOutlineView
    ) {
        guard selectedItem?.id != item?.id else { return }
        selectedItem = item
        selectRow(for: selectedItem, in: outlineView)
    }
}
