//
//  LegNavigatorView.swift
//  RPS
//
//  The big, glanceable, swipeable per-leg view — what actually gets read
//  mid-race: heading (true/magnetic), distance, and which side to leave the
//  mark. Large text, high contrast, built for a phone in a cockpit with one
//  hand on the tiller.
//

import SwiftUI

struct LegNavigatorView: View {
    @Environment(CourseStateStore.self) private var course

    private var legs: [LegInfo] { course.legComputation.legs }

    var body: some View {
        Group {
            if legs.isEmpty {
                ContentUnavailableView(
                    "No course plotted",
                    systemImage: "flag.slash",
                    description: Text("Build and plot a course first.")
                )
            } else {
                TabView(selection: Binding(
                    get: { course.currentLegIndex ?? 0 },
                    set: { course.setCurrentLeg($0) }
                )) {
                    ForEach(legs) { leg in
                        LegPage(leg: leg, useMagnetic: course.variationDeg != 0)
                            .tag(leg.legIndex)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

private struct LegPage: View {
    let leg: LegInfo
    let useMagnetic: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)

            VStack(spacing: 4) {
                Text("LEG \(leg.legIndex + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Text("\(leg.fromLabel) → \(leg.toLabel)")
                    .font(.title3.weight(.semibold))
                Text(leg.toMark.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if leg.missing {
                ContentUnavailableView(
                    "Position missing",
                    systemImage: "questionmark.diamond",
                    description: Text("Set a position for \(leg.toLabel) in the course builder.")
                )
                .frame(maxHeight: 220)
            } else {
                VStack(spacing: 18) {
                    headingBlock

                    HStack(spacing: 24) {
                        statTile(title: "DISTANCE", value: String(format: "%.2f", leg.distNm ?? 0), unit: "nm")
                        if let rounding = leg.rounding {
                            statTile(title: "ROUNDING", value: rounding == .starboard ? "S" : "P", unit: roundingWord(rounding))
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headingBlock: some View {
        VStack(spacing: 6) {
            Text(GeoMath.fmtHeading(leg.magHdg ?? leg.trueHdg ?? 0))
                .font(.system(size: 88, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text("MAGNETIC")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(2)
            if let trueHdg = leg.trueHdg {
                Text("\(GeoMath.fmtHeading(trueHdg)) true")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statTile(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(1.5)
            Text(value).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    LegNavigatorView()
        .environment(CourseStateStore())
}
