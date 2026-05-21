import SwiftUI

struct LayerPanelView: View {
    @Bindable var settings: MapLayerSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Map Layers")
                .font(.subheadline).bold()

            // Base style picker
            HStack(spacing: 8) {
                ForEach(MapBaseStyle.allCases, id: \.self) { style in
                    Button {
                        settings.baseStyle = style
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: style.icon)
                                .font(.title3)
                            Text(style.label)
                                .font(.caption2).bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(settings.baseStyle == style ? Color.orange : Color.gray.opacity(0.15))
                        .foregroundStyle(settings.baseStyle == style ? .white : .primary)
                        .cornerRadius(12)
                    }
                }
            }

            Divider()

            Text("Overlays")
                .font(.caption).bold().foregroundStyle(.secondary)

            Toggle(isOn: $settings.showExploredHexes) {
                Label("Explored Hexes", systemImage: "hexagon.fill")
                    .font(.subheadline)
            }
            .tint(.orange)
        }
        .padding(16)
        .frame(width: 240)
        .background(.ultraThickMaterial)
        .cornerRadius(20)
        .shadow(radius: 16)
    }
}
