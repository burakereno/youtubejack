import SwiftUI

enum AppControlMetrics {
    static let height: CGFloat = 40
    static let cornerRadius: CGFloat = 8
}

struct FlexibleControlSizing: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonSizing(.flexible)
        } else {
            content
        }
    }
}

struct NativeProminentButton: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

struct MenuField<Content: View>: View {
    let title: String
    let value: String
    let content: Content

    init(_ title: String, value: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Text(value)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .menuIndicator(.visible)
        .controlSize(.extraLarge)
        .modifier(FlexibleControlSizing())
        .frame(height: AppControlMetrics.height)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

struct MenuChoice: View {
    let title: String
    let isSelected: Bool
    var isAvailable = true
    let action: () -> Void

    var body: some View {
        // Use the native checkmark column so every option title stays aligned.
        Toggle(title, isOn: Binding(
            get: { isSelected },
            set: { _ in action() }
        ))
        .toggleStyle(.automatic)
        .disabled(isAvailable == false)
    }
}
