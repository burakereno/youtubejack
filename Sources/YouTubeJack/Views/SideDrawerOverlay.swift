import SwiftUI

struct SideDrawerOverlay<Content: View>: View {
    let title: String
    let closeLabel: String
    @Binding var isPresented: Bool
    @FocusState private var isCloseButtonFocused: Bool
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                isPresented = false
            } label: {
                Color.black.opacity(isPresented ? 0.22 : 0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeLabel)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.title2.weight(.semibold))

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Label(closeLabel, systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .keyboardShortcut(.cancelAction)
                    .focused($isCloseButtonFocused)
                    .help(closeLabel)
                }

                content
            }
            .padding(20)
            .frame(width: 430)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 28, x: -10, y: 0)
            .padding(.trailing, 16)
            .padding(.vertical, 16)
            .offset(x: isPresented ? 0 : 480)
            .opacity(isPresented ? 1 : 0.96)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .allowsHitTesting(isPresented)
        .disabled(isPresented == false)
        .accessibilityHidden(isPresented == false)
        .onChange(of: isPresented) { _, presented in
            if presented { isCloseButtonFocused = true }
        }
    }
}
