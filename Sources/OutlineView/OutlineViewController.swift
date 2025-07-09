import Cocoa

@available(macOS 10.15, *)
public class OutlineViewController<Data: Sequence, Drop: DropReceiver>: NSViewController
where Drop.DataElement == Data.Element {
    let outlineView = ContextMenuOutlineView()
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))

    let dataSource: OutlineViewDataSource<Data, Drop>
    let delegate: OutlineViewDelegate<Data>
    let updater = OutlineViewUpdater<Data>()

    let childrenSource: ChildSource<Data>

    var didLayout: ((NSOutlineView) -> Void)?
    var hasPerformedInitialLayout = false

    init(
        data: Data,
        childrenSource: ChildSource<Data>,
        content: @escaping (Data.Element) -> NSView,
        isGroupItem: ((Data.Element) -> Bool)?,
        groupTitle: ((Data.Element) -> String)?,
        configuration: ((NSOutlineView) -> Void)?,
        selectionChanged: @escaping (Data.Element?) -> Void,
        separatorInsets: ((Data.Element) -> NSEdgeInsets)?
    ) {
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalRuler = true
        scrollView.drawsBackground = false

        outlineView.autoresizesOutlineColumn = false
        outlineView.headerView = nil
        outlineView.usesAutomaticRowHeights = true
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let onlyColumn = NSTableColumn()
        onlyColumn.resizingMask = .autoresizingMask
        outlineView.addTableColumn(onlyColumn)

        dataSource = OutlineViewDataSource(
            items: data.map { OutlineViewItem(value: $0, children: childrenSource) },
            childSource: childrenSource
        )
        delegate = OutlineViewDelegate(
            content: content,
            selectionChanged: selectionChanged,
            separatorInsets: separatorInsets,
            isGroupItem: isGroupItem,
            groupTitle: groupTitle,
            configuration: configuration
        )
        outlineView.dataSource = dataSource
        outlineView.delegate = delegate

        self.childrenSource = childrenSource

        super.init(nibName: nil, bundle: nil)

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    public override func loadView() {
        view = NSView()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        // NOTE: We hide the scroll view so that any animations on view load aren't visible.
        // Also gives us a chance to make sure any group items render correctly
        outlineView.enclosingScrollView?.isHidden = true
    }

    public override func viewWillAppear() {
        // Size the column to take the full width. This combined with
        // the uniform column autoresizing style allows the column to
        // adjust its width with a change in width of the outline view.
        outlineView.sizeLastColumnToFit()
        super.viewWillAppear()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()

        guard !hasPerformedInitialLayout else { return }
        hasPerformedInitialLayout = true

        DispatchQueue.main.async {
            self.didLayout?(self.outlineView)
        }

        // FIXME: !!! MAJOR HACK !!!
        // I have this async after 0.3 to fix a bug where the group titles are not sized appropriately,
        // and you can see animations if the user is expanding items on launch.
        // Need to come up with a more determinate signal to trigger this code on.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.outlineView.enclosingScrollView?.isHidden = false
        }
    }
}

// MARK: - Performing updates
@available(macOS 10.15, *)
extension OutlineViewController {
    func updateData(newValue: Data) {
        let newState = newValue.map { OutlineViewItem(value: $0, children: childrenSource) }

        outlineView.beginUpdates()

        dataSource.items = newState
        updater.performUpdates(
            outlineView: outlineView,
            oldStateTree: dataSource.treeMap,
            newState: newState,
            parent: nil)

        outlineView.endUpdates()
        
        // After updates, dataSource must rebuild its idTree for future updates
        dataSource.rebuildIDTree(rootItems: newState, outlineView: outlineView)
    }

    func changeSelectedItem(to item: Data.Element?) {
        delegate.changeSelectedItem(
            to: item.map { OutlineViewItem(value: $0, children: childrenSource) },
            in: outlineView)
    }

    @available(macOS 11.0, *)
    func setStyle(to style: NSOutlineView.Style) {
        outlineView.style = style
    }

    func setIndentation(to width: CGFloat) {
        outlineView.indentationPerLevel = width
    }

    func setRowSeparator(visibility: SeparatorVisibility) {
        switch visibility {
        case .hidden:
            outlineView.gridStyleMask = []
        case .visible:
            outlineView.gridStyleMask = .solidHorizontalGridLineMask
        }
    }

    func setRowSeparator(color: NSColor) {
        guard color != outlineView.gridColor else {
            return
        }

        outlineView.gridColor = color
        outlineView.reloadData()
    }
        
    func setDragSourceWriter(_ writer: DragSourceWriter<Data.Element>?) {
        dataSource.dragWriter = writer
    }
    
    func setDropReceiver(_ receiver: Drop?) {
        dataSource.dropReceiver = receiver
    }
    
    func setAcceptedDragTypes(_ acceptedTypes: [NSPasteboard.PasteboardType]?) {
        outlineView.unregisterDraggedTypes()
        if let acceptedTypes,
           !acceptedTypes.isEmpty
        {
            outlineView.registerForDraggedTypes(acceptedTypes)
        }
    }

    func setAutoSaveExpandedItems(_ saveExpandedItems: Bool) {
        outlineView.autosaveExpandedItems = saveExpandedItems
    }

    func setAutoSaveName(_ name: String?) {
        outlineView.autosaveName = name
    }
}

@available(macOS 10.15, *)
internal final class ContextMenuOutlineView: NSOutlineView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        let row = row(at: location)

        guard row >= 0,
              let view = view(atColumn: 0, row: row, makeIfNecessary: false),
              let menu = view.menu(for: event)
        else {
            return super.menu(for: event)
        }

        return menu
    }
}
