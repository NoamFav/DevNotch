//
//  ClockPeekView.swift
//  boringNotch
//
//  Spike: persistent clock that lives inside the closed notch shape,
//  mirroring the AeroSpace workspace row on the opposite side.
//

import SwiftUI

struct ClockPeekView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(context.date, style: .time)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.gray)
                .monospacedDigit()
        }
        .padding(.trailing, 6)
        .transition(.opacity)
    }
}
