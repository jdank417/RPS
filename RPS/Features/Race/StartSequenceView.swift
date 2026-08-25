//
//  StartSequenceView.swift
//  RPS
//
//  The start-sequence countdown as its own big, glanceable screen: phase
//  color, the flag that should be flying (so the sailor can cross-check
//  against the committee boat rather than trusting the phone blind), and
//  sync/bump/start controls.
//

import SwiftUI

struct StartSequenceView: View {
    @Environment(StartSequenceViewModel.self) private var sequence

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Text(sequence.flag.isEmpty ? "START SEQUENCE" : sequence.flag.uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(phaseColor)
                    .tracking(1.5)

                Text(sequence.display)
                    .font(.system(size: 104, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(phaseColor)
                    .contentTransition(.numericText())
                    .accessibilityLabel(accessibilityTime)

                if sequence.running {
                    Text(phaseSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(phaseColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal)

            Spacer(minLength: 24)

            if sequence.running {
                runningControls
            } else {
                startControls
            }

            Spacer(minLength: 12)
        }
        .padding(.bottom)
    }

    private var runningControls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                bigButton("Sync", systemImage: "arrow.triangle.2.circlepath") { sequence.sync() }
                bigButton("+1:00", systemImage: "goforward.plus") { sequence.bump(seconds: 60) }
                bigButton("-1:00", systemImage: "gobackward.minus") { sequence.bump(seconds: -60) }
            }
            Button(role: .destructive) {
                sequence.stop()
            } label: {
                Text("Cancel Sequence").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal)
    }

    private var startControls: some View {
        VStack(spacing: 12) {
            Text("Start a sequence")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach([5.0, 4.0, 1.0], id: \.self) { minutes in
                    Button {
                        sequence.startIn(minutes: minutes)
                    } label: {
                        VStack(spacing: 2) {
                            Text(minutes == 1 ? "1" : String(Int(minutes)))
                                .font(.title.weight(.bold))
                            Text(minutes == 1 ? "min" : "min")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(.horizontal)
    }

    private func bigButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title2)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var phaseColor: Color {
        switch sequence.phase {
        case .idle: return .secondary
        case .warning: return .blue
        case .preparatory: return .yellow
        case .oneMinute: return .orange
        case .racing: return .green
        }
    }

    private var phaseSubtitle: String {
        switch sequence.phase {
        case .warning: return "Warning signal — 5 minutes to start"
        case .preparatory: return "Preparatory signal"
        case .oneMinute: return "One minute to the gun"
        case .racing: return "Racing"
        case .idle: return ""
        }
    }

    private var accessibilityTime: String {
        guard let s = sequence.secondsToStart else { return "No sequence running" }
        let mins = abs(s) / 60
        let secs = abs(s) % 60
        let prefix = s < 0 ? "elapsed" : "to start"
        return "\(mins) minutes \(secs) seconds \(prefix)"
    }
}

#Preview {
    StartSequenceView()
        .environment(StartSequenceViewModel())
}
