import SwiftUI

struct CSVImportView: View {
    let url: URL
    let onImport: ([ClipData]) -> Void
    let onCancel: () -> Void
    
    @State private var rawRows: [[String]] = []
    @State private var headerRowIndex: Int = 0
    @State private var columnIncludes: [Bool] = []
    @State private var renamedHeaders: [String] = []
    @State private var rowIncludes: [Bool] = []
    
    @State private var errorMsg: String?
    
    // Duplicates State
    @State private var showOnlyDuplicates = false
    
    // Column Resizing
    @State private var customColumnWidths: [Int: CGFloat] = [:]
    @State private var dragInitialWidth: CGFloat? = nil
    @State private var duplicateRowIndices: Set<Int> = []
    
    // Search & Filter State
    @State private var searchText: String = ""
    
    // Enum for per-column empty filters
    enum ColumnFilter: Equatable {
        case showEmpty(Int)   // show only rows where this column is empty
        case hideEmpty(Int)   // hide rows where this column is empty
    }
    @State private var columnEmptyFilter: ColumnFilter? = nil
    @State private var debugMode: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Data Import Preview")
                    .font(.title2)
                    .bold()
                Spacer()
                
                // Duplicate Controls
                if !rawRows.isEmpty {
                    Toggle("Show Duplicate Rows (\(duplicateRowIndices.count))", isOn: Binding(
                        get: { showOnlyDuplicates },
                        set: {
                            showOnlyDuplicates = $0
                            if $0 { recalculateDuplicates() }
                        }
                    ))
                    .toggleStyle(.button)
                    .tint(showOnlyDuplicates ? .orange : .accentColor)
                }
                
                Toggle("Debug", isOn: $debugMode)
                    .toggleStyle(.button)
                    .tint(debugMode ? .green : .secondary)
                    .controlSize(.small)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            if let errorMsg = errorMsg {
                Text(errorMsg)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Divider()
            
            HStack {
                Stepper("Header Row: \(headerRowIndex + 1)", value: $headerRowIndex, in: 0...max(0, rawRows.count - 1))
                    .onChange(of: headerRowIndex) { _ in updateColumns() }
                
                Spacer()
                
                // Bulk Row Selection
                Button("Select All") {
                    setAllVisibleRows(to: true)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Text("|").foregroundColor(.secondary)
                
                Button("Deselect All") {
                    setAllVisibleRows(to: false)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search rows...", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .frame(width: 250)
                
                Spacer()
                
                let includedCount = rowIncludes.filter { $0 }.count
                Text("Importing \(includedCount) rows")
                    .foregroundColor(.secondary)
            }
            .padding()
            
            // Active Filter Banner + Debug Info
            if columnEmptyFilter != nil || debugMode {
                HStack(spacing: 12) {
                    if let filter = columnEmptyFilter {
                        let (label, colIdx) = {
                            switch filter {
                            case .showEmpty(let i): return ("Show Empty – Col \(i+1)", i)
                            case .hideEmpty(let i): return ("Hide Empty – Col \(i+1)", i)
                            }
                        }()
                        
                        Label("Filter: \(label)", systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(filter == .showEmpty(colIdx) ? Color.orange : Color.purple)
                            .cornerRadius(6)
                        
                        Button("✕ Clear Filter") {
                            columnEmptyFilter = nil
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                    }
                    
                    if debugMode {
                        Divider().frame(height: 16)
                        Text("columnEmptyFilter: \(String(describing: columnEmptyFilter))") 
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.07))
            }
            
            Divider()
            // Preview Table
            ScrollView([.horizontal, .vertical]) {
                if !rawRows.isEmpty && columnIncludes.count == renamedHeaders.count && !renamedHeaders.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section(header: unifiedHeaderView) {
                            let maxRows = rawRows.count
                            let start = headerRowIndex + 1
                            if start < maxRows {
                                ForEach(start..<maxRows, id: \.self) { rIdx in
                                    if (!showOnlyDuplicates || duplicateRowIndices.contains(rIdx)) && rowMatchesSearch(rIdx) {
                                        rowView(rIdx: rIdx)
                                    }
                                }
                            } else {
                                Text("No Data Rows").foregroundColor(.secondary).padding()
                            }
                        }
                    }
                    .padding(.bottom, 20)
                } else if rawRows.isEmpty {
                    Text("Loading data...")
                        .foregroundColor(.secondary)
                        .padding(40)
                        .border(Color.secondary.opacity(0.2))
                }
            }
            .border(Color.secondary.opacity(0.2))
            
            Divider()
            
            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Process Import") {
                    processImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(rawRows.isEmpty || columnIncludes.allSatisfy { !$0 } || rowIncludes.allSatisfy { !$0 })
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            loadCSV()
        }
    }
    
    // MARK: - Row Views
    
    private func colWidth(_ index: Int) -> CGFloat {
        return customColumnWidths[index] ?? 150
    }
    
    private var unifiedHeaderView: some View {
        HStack(alignment: .bottom, spacing: 1) {
            topLeftCornerBox
            columnHeaderStrip
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    @ViewBuilder
    private func rowView(rIdx: Int) -> some View {
        HStack(alignment: .center, spacing: 1) {
            leftRowIndicatorView(rIdx: rIdx)
            dataOnlyRowView(rIdx: rIdx)
        }
        // Background and overals are already handled by the individual views
    }
    
    private var topLeftCornerBox: some View {
        VStack {
            Text("Import Row")
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)
        }
        .frame(width: 80, height: 130)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .trailing)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .bottom)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .top)
    }
    
    private var columnHeaderStrip: some View {
        HStack(alignment: .bottom, spacing: 1) {
            
            ForEach(0..<renamedHeaders.count, id: \.self) { cIdx in
                VStack(alignment: .leading, spacing: 5) {
                    // Col number
                    Text("Col \(cIdx + 1)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // Import toggle row
                    HStack(spacing: 5) {
                        Text("Import:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Toggle("", isOn: Binding(
                            get: { self.columnIncludes[cIdx] },
                            set: {
                                self.columnIncludes[cIdx] = $0
                                if showOnlyDuplicates { recalculateDuplicates() }
                            }
                        ))
                        .labelsHidden()
                        .help("Include this column in import")
                    }
                    
                    // Show Empty / Hide Empty buttons
                    let activeShowEmpty = columnEmptyFilter == .showEmpty(cIdx)
                    let activeHideEmpty = columnEmptyFilter == .hideEmpty(cIdx)
                    
                    HStack(spacing: 5) {
                        Text("Show:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Button(action: {
                            columnEmptyFilter = activeShowEmpty ? nil : .showEmpty(cIdx)
                        }) {
                            Image(systemName: activeShowEmpty ? "checkmark.square.fill" : "square")
                                .foregroundColor(activeShowEmpty ? .orange : .secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help(activeShowEmpty ? "Remove filter" : "Show only rows where this column is empty")
                        
                        Text("Hide:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Button(action: {
                            columnEmptyFilter = activeHideEmpty ? nil : .hideEmpty(cIdx)
                        }) {
                            Image(systemName: activeHideEmpty ? "checkmark.square.fill" : "square")
                                .foregroundColor(activeHideEmpty ? .purple : .secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help(activeHideEmpty ? "Remove filter" : "Hide rows where this column is empty")
                    }
                    
                    // Header rename field
                    TextField("Header Name", text: Binding(
                        get: { self.renamedHeaders[cIdx] },
                        set: { self.renamedHeaders[cIdx] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .disabled(!self.columnIncludes[cIdx])
                }
                .padding(.horizontal, 4)
                .frame(width: colWidth(cIdx), height: 130)
                .background(columnIncludes[cIdx] ? Color(nsColor: .windowBackgroundColor) : Color.red.opacity(0.05))
                .overlay(
                    (columnEmptyFilter == .showEmpty(cIdx)) ? Color.orange.opacity(0.08) :
                    (columnEmptyFilter == .hideEmpty(cIdx)) ? Color.purple.opacity(0.08) : Color.clear
                )
                .opacity(columnIncludes[cIdx] ? 1.0 : 0.5)
                
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 4, height: 130)
                    .onHover { isHovering in
                        if isHovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if dragInitialWidth == nil {
                                    dragInitialWidth = colWidth(cIdx)
                                }
                                let newWidth = max(60, (dragInitialWidth ?? 150) + value.translation.width)
                                customColumnWidths[cIdx] = newWidth
                            }
                            .onEnded { _ in
                                dragInitialWidth = nil
                            }
                    )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .bottom)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .top)
    }
    
    private func leftRowIndicatorView(rIdx: Int) -> some View {
        let isIncluded = rowIncludes.count > rIdx ? rowIncludes[rIdx] : false
        return HStack(spacing: 6) {
            Text("\(rIdx + 1)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 25, alignment: .trailing)
                
            Toggle("", isOn: Binding(
                get: { isIncluded },
                set: { if rIdx < rowIncludes.count { rowIncludes[rIdx] = $0 } }
            ))
            .labelsHidden()
        }
        .frame(width: 80, height: 35)
        .background(isIncluded ? Color.clear : Color.secondary.opacity(0.1))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.1)), alignment: .bottom)
        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .trailing)
    }
    
    @ViewBuilder
    private func dataOnlyRowView(rIdx: Int) -> some View {
        let isIncluded = rowIncludes.count > rIdx ? rowIncludes[rIdx] : false
        HStack(alignment: .center, spacing: 1) {
            ForEach(0..<renamedHeaders.count, id: \.self) { cIdx in
                let cellVal = cIdx < rawRows[rIdx].count ? rawRows[rIdx][cIdx] : ""
                Text(cellVal)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: max(0, colWidth(cIdx) - 10), alignment: .leading)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .frame(width: colWidth(cIdx), height: 35)
                    .background(columnIncludes[cIdx] ? Color.clear : Color.red.opacity(0.05))
                    .opacity(columnIncludes[cIdx] ? 1.0 : 0.4)
                
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 4, height: 35)
            }
        }
        .background(isIncluded ? Color.clear : Color.secondary.opacity(0.1))
        .opacity(isIncluded ? 1.0 : 0.5)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.1)), alignment: .bottom)
    }
    
    // MARK: - Logic
    
    private func loadCSV() {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            
            if let firstLine = lines.first {
                let delimiter = CSVManager.detectDelimiter(in: firstLine)
                rawRows = lines.map { CSVManager.parseCSVRow($0, delimiter: delimiter) }
            } else {
                rawRows = []
            }
            
            // Initialize rowIncludes to true for all rows
            rowIncludes = Array(repeating: true, count: rawRows.count)
            updateColumns()
        } catch {
            errorMsg = "Failed to load CSV: \(error.localizedDescription)\n\nPlease ensure your file is saved as a UTF-8 encoded CSV."
        }
    }
    
    private func updateColumns() {
        guard headerRowIndex >= 0, headerRowIndex < rawRows.count else { return }
        let rawHeader = rawRows[headerRowIndex]
        columnIncludes = Array(repeating: true, count: rawHeader.count)
        
        var newHeaders: [String] = []
        for i in 0..<rawHeader.count {
            let clean = rawHeader[i].trimmingCharacters(in: .whitespacesAndNewlines)
            newHeaders.append(clean.isEmpty ? "Column \(i+1)" : clean)
        }
        renamedHeaders = newHeaders
        
        // Ensure rowIncludes array matches total row count (e.g. if loaded async)
        if rowIncludes.count != rawRows.count {
            rowIncludes = Array(repeating: true, count: rawRows.count)
        }
        // Force header rows to be excluded
        for i in 0...headerRowIndex {
            if i < rowIncludes.count { rowIncludes[i] = false }
        }
        
        recalculateDuplicates()
    }
    
    private func recalculateDuplicates() {
        var seen: [String: [Int]] = [:]
        let start = headerRowIndex + 1
        guard start < rawRows.count else { 
            duplicateRowIndices.removeAll()
            return 
        }
        
        for i in start..<rawRows.count {
            var sigParts: [String] = []
            for cIdx in 0..<columnIncludes.count {
                if columnIncludes[cIdx], cIdx < rawRows[i].count {
                    sigParts.append(rawRows[i][cIdx])
                }
            }
            let sig = sigParts.joined(separator: "|_|_|")
            seen[sig, default: []].append(i)
        }
        
        var dups = Set<Int>()
        for (_, indices) in seen {
            if indices.count > 1 {
                for idx in indices { dups.insert(idx) }
            }
        }
        duplicateRowIndices = dups
    }
    
    private func setAllVisibleRows(to state: Bool) {
        let start = headerRowIndex + 1
        guard start < rawRows.count else { return }
        
        for i in start..<rawRows.count {
            if (!showOnlyDuplicates || duplicateRowIndices.contains(i)) && rowMatchesSearch(i) {
                if i < rowIncludes.count {
                    rowIncludes[i] = state
                }
            }
        }
    }
    
    private func rowMatchesSearch(_ rIdx: Int) -> Bool {
        guard rIdx < rawRows.count else { return false }
        let rawRow = rawRows[rIdx]
        
        // Empty-cell column filter
        if let filter = columnEmptyFilter {
            switch filter {
            case .showEmpty(let cIdx):
                let cellValue = cIdx < rawRow.count ? rawRow[cIdx].trimmingCharacters(in: .whitespaces) : ""
                if !cellValue.isEmpty { return false }
            case .hideEmpty(let cIdx):
                let cellValue = cIdx < rawRow.count ? rawRow[cIdx].trimmingCharacters(in: .whitespaces) : ""
                if cellValue.isEmpty { return false }
            }
        }
        
        // Text search filter
        if searchText.isEmpty { return true }
        
        for cIdx in 0..<columnIncludes.count {
            if columnIncludes[cIdx] && cIdx < rawRow.count {
                if rawRow[cIdx].localizedStandardContains(searchText) {
                    return true
                }
            }
        }
        return false
    }
    
    private func processImport() {
        var importedClips: [ClipData] = []
        let startIndex = headerRowIndex + 1
        
        guard startIndex <= rawRows.count else { return onImport([]) }
        
        for i in startIndex..<rawRows.count {
            if i < rowIncludes.count && !rowIncludes[i] { continue } // Skip unchecked rows
            
            let row = rawRows[i]
            var dict: [String: String] = [:]
            
            for cIdx in 0..<renamedHeaders.count {
                if columnIncludes[cIdx], cIdx < row.count {
                    let colName = renamedHeaders[cIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                    let cVal = row[cIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !colName.isEmpty && !cVal.isEmpty {
                        dict[colName] = cVal
                    }
                }
            }
            
            if !dict.isEmpty {
                let clip = ClipData(id: UUID(), dict: dict)
                importedClips.append(clip)
            }
        }
        
        onImport(importedClips)
    }
}

// MARK: - Standalone Window Management
extension CSVImportView {
    static func showStandalone(url: URL, onImport: @escaping ([ClipData]) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Import CSV: \(url.lastPathComponent)"
        window.center()
        
        let view = CSVImportView(
            url: url,
            onImport: { clips in
                onImport(clips)
                window.close()
            },
            onCancel: {
                window.close()
            }
        )
        
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
    }
}
