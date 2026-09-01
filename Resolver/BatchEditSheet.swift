import SwiftUI

// The Edit Masterlist mode's bulk-editing tool: pick a column, type one
// value, apply it to every currently selected shot at once (e.g. select the
// first 10 rows via shift-click, set "Episode" to "1").
struct BatchEditSheet: View {
    let columns: [String]
    let selectedCount: Int
    @Binding var column: String
    @Binding var value: String
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Batch Edit")
                    .font(.title2)
                    .bold()
                Spacer()
            }

            Text("Set one column to the same value on all \(selectedCount) selected VFX shots.")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Column:")
                        .bold()
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: $column) {
                        ForEach(columns, id: \.self) { col in
                            Text(col).tag(col)
                        }
                    }
                    .labelsHidden()
                }

                HStack {
                    Text("New Value:")
                        .bold()
                        .frame(width: 80, alignment: .leading)
                    TextField("e.g. 1", text: $value)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            .padding()
            .liquidGlassPanel(cornerRadius: 8)

            Spacer()

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Apply to \(selectedCount) Shots") { onApply() }
                    .liquidGlassButton(prominent: true)
                    .tint(.accentColor)
                    .disabled(column.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420, height: 320)
    }
}
