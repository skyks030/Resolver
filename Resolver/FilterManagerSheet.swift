import SwiftUI

// Opened via the "…" on the master list's Filter button. One "contains" search field per
// column; every column with a non-empty value must match (AND) for a shot to stay visible.
// Values persist here even while the Filter button itself is switched off (`isActive == false`)
// — turning it back on re-applies whatever was configured without retyping anything.
struct FilterManagerSheet: View {
    let columns: [String]
    @Binding var filters: [String: String]
    @Binding var isActive: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var visibleColumns: [String] {
        guard !searchText.isEmpty else { return columns }
        return columns.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var activeFilterCount: Int {
        filters.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Filter Manager")
                    .font(.title2)
                    .bold()
                Spacer()
                Toggle("Apply Filters", isOn: $isActive)
            }

            Text("Only shots matching every column filled in below are shown — leave a column empty to ignore it.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search columns...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .liquidGlassPanel(cornerRadius: 8)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleColumns, id: \.self) { col in
                        HStack {
                            Text(col)
                                .frame(width: 160, alignment: .leading)
                            TextField("Contains…", text: Binding(
                                get: { filters[col] ?? "" },
                                set: { newValue in
                                    if newValue.isEmpty {
                                        filters.removeValue(forKey: col)
                                    } else {
                                        filters[col] = newValue
                                    }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 280)

            Divider()

            HStack {
                Button("Clear All", role: .destructive) { filters.removeAll() }
                    .disabled(filters.isEmpty)

                Spacer()

                Text(activeFilterCount == 0 ? "No filters set" : "\(activeFilterCount) filter\(activeFilterCount == 1 ? "" : "s") set")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Done") { dismiss() }
                    .liquidGlassButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460, height: 480)
    }
}
