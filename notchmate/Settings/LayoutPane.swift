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
                HStack {
                    Text("Modules")
                    Spacer()
                    Text("\(prefs.enabledModules.count) of \(NotchPreferences.maxVisibleModules) shown")
                        .font(.caption)
                        .foregroundStyle(prefs.canEnableMoreModules ? Color.secondary : Color.orange)
                }
            } footer: {
                Text("Up to \(NotchPreferences.maxVisibleModules) modules show in the panel. Drag to reorder; order determines placement in the grid. Disable one to free a slot.")
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
        .frame(minHeight: CGFloat(LayoutModule.allCases.count) * 48)
    }

    private func moduleRow(_ module: LayoutModule) -> some View {
        let isOn = prefs.enabledModules.contains(module)
        // At the cap, only already-enabled rows stay interactive (so they can be turned
        // off); disabled rows can't be enabled until a slot frees up.
        let canToggle = isOn || prefs.canEnableMoreModules
        return HStack(spacing: 10) {
            Image(systemName: module.icon)
                .frame(width: 18)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.displayName)
                Text(module.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { _ in prefs.toggleModule(module) }
            ))
            .labelsHidden()
            .disabled(!canToggle)
        }
        .contentShape(Rectangle())
        .opacity(canToggle ? 1 : 0.5)
    }
}
