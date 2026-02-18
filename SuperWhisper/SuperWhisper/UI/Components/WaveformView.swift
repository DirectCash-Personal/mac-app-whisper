import SwiftUI

/// Animated audio waveform visualization with purple gradient bars.
struct WaveformView: View {
    let amplitudes: [Float]
    let barCount: Int
    let isAnimating: Bool

    init(amplitudes: [Float] = [], barCount: Int = 24, isAnimating: Bool = true) {
        self.amplitudes = amplitudes
        self.barCount = barCount
        self.isAnimating = isAnimating
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    amplitude: amplitude(for: index),
                    isAnimating: isAnimating,
                    delay: Double(index) * 0.03
                )
            }
        }
    }

    private func amplitude(for index: Int) -> CGFloat {
        guard !amplitudes.isEmpty else {
            // Generate idle animation
            return isAnimating ? CGFloat.random(in: 0.1...0.4) : 0.15
        }

        let normalizedIndex = Float(index) / Float(barCount) * Float(amplitudes.count)
        let ampIndex = min(Int(normalizedIndex), amplitudes.count - 1)
        return CGFloat(amplitudes[ampIndex]).clamped(to: 0.05...1.0)
    }
}

struct WaveformBar: View {
    let amplitude: CGFloat
    let isAnimating: Bool
    let delay: Double

    @State private var animatedAmplitude: CGFloat = 0.15

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(AppColors.accentGradient)
            .frame(width: 3, height: max(4, animatedAmplitude * 40))
            .animation(
                isAnimating ? .easeInOut(duration: 0.15).delay(delay) : .default,
                value: animatedAmplitude
            )
            .onChange(of: amplitude) { _, newValue in
                animatedAmplitude = newValue
            }
            .onAppear {
                animatedAmplitude = amplitude
            }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
