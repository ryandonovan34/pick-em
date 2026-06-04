import SwiftUI

struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AdaptiveColor.pePrimaryFill)
                .scaleEffect(1.2)
            Text(message.uppercased())
                .font(.peLabelBold())
                .tracking(2)
                .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AdaptiveColor.peBackground)
    }
}

#Preview {
    LoadingView()
}
