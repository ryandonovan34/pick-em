import SwiftUI

struct ErrorView: View {
    let message: String
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(AdaptiveColor.peTertiary)

            Text(message)
                .font(.peBodyMd())
                .multilineTextAlignment(.center)
                .foregroundStyle(AdaptiveColor.peOnSurfaceVar)

            if let retry = retryAction {
                Button("Try Again") { retry() }
                    .buttonStyle(PEPrimaryButton())
                    .padding(.horizontal, 48)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AdaptiveColor.peBackground)
    }
}

#Preview {
    ErrorView(message: "Something went wrong. Please try again.") {}
}
