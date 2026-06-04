//
//  OnLoadModifier.swift
//  PickEm
//
//  Created by Ryan Donovan on 6/4/26.
//

import SwiftUI

private struct OnLoadModifier: ViewModifier {
    let action: () async -> Void
    @State private var hasRun = false

    func body(content: Content) -> some View {
        content.task {
            guard !hasRun else { return }
            hasRun = true
            await action()
        }
    }
}

extension View {
    /// Like `.task`, but fires only once for the lifetime of the view instance.
    /// Re-appearances (e.g. navigating back) are ignored; pull-to-refresh still works.
    func onLoad(_ action: @escaping () async -> Void) -> some View {
        modifier(OnLoadModifier(action: action))
    }
}
