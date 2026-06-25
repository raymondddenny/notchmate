import SwiftUI

/// Layout settings pane. Controls the horizontal grid configuration:
/// - Row count (1, 2, or 3 rows)
/// - Which modules are visible (enable toggles)
/// - Module display order (drag to reorder)
struct LayoutPane: View {
    @ObservedObject private var prefs = NotchPreferences.shared

    var body: some View {
        Form {
            Section {
                Picker("Rows", selection: $prefs.expandedRowCount) {
                    Text("1 row (wide)").tag(1)
                    Text("2 rows").tag(2)
                    Text("3 rows (compact)").tag(3)
                }
                .pickerStyle(.radioGroup)
                Text("Fewer rows = wider panel. Modules flow left-to-right, then top-to-bottom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Panel Layout")
            }

            Section {
                moduleList
            } header: {
                Text("Modules")
            } footer: {
                Text("Drag to reorder. Order determines placement in the grid.")
                    .font(.caption)
            }

            Section {
                Button("Reset to Defaults") {
                    prefs.resetLayoutToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Layout")
    }

    private var moduleList: some View {
        List {
            ForEach($prefs.moduleOrder, id: \.self) { $module in
                moduleRow(module)
            }
            .onMove { from, to in
                prefs.moduleOrder.move(fromOffsets: from, toOffset: to)
            }
        }
        .listStyle(.plain)
        .frame(minHeight: CGFloat(LayoutModule.allCases.count) * 38)
    }

    private func moduleRow(_ module: LayoutModule) -> some View {
        HStack(spacing: 10) {
            Image(systemName: module.icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(module.displayName)
            Spacer()
            Toggle("", isOn: Binding(
                get: { prefs.enabledModules.contains(module) },
                set: { _ in prefs.toggleModule(module) }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
    }
}
