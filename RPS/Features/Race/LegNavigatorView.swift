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
    @Environment(WindService.self) private var windService

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
                        LegPage(
                            leg: leg,
                            useMagnetic: course.variationDeg != 0,
                            wind: windService.wind,
                            windIsStale: windService.stale
                        )
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
    let wind: WindReading?
    let windIsStale: Bool

    var body: some View {
        // Deliberately no ScrollView: everything about this page is meant to
        // be read in a glance from the helm, and a page you have to scroll
        // is a page whose bottom half does not exist mid-race. It is sized
        // to fit instead, and shrinks rather than overflows.
        VStack(spacing: 14) {
            header

            if leg.missing {
                Spacer()
                ContentUnavailableView(
                    "Position missing",
                    systemImage: "questionmark.diamond",
                    description: Text("Set a position for \(leg.toLabel) in the course builder.")
                )
                Spacer()
            } else {
                // Heading and the wind picture side by side rather than
                // stacked: they are read together ("047, and the breeze is
                // on my left"), and stacking them was what pushed the page
                // past one screen.
                HStack(alignment: .center, spacing: 16) {
                    headingBlock
                        .frame(maxWidth: .infinity)
                    windGraphic
                }

                statsRow
                windCallout
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("LEG \(leg.legIndex + 1)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(2)
            Text("\(leg.fromLabel) → \(leg.toLabel)")
                .font(.title3.weight(.semibold))
            Text(leg.toMark.name)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The wind rose, or a compact placeholder holding the same footprint so
    /// the layout doesn't jump when a forecast arrives.
    @ViewBuilder
    private var windGraphic: some View {
        if let wind, let heading = leg.trueHdg {
            WindRoseView(legHeadingDeg: heading, windFromDeg: wind.fromDeg, size: 118)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "wind")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No wind\nforecast")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 118, height: 118)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(title: "DISTANCE", value: String(format: "%.2f", leg.distNm ?? 0), unit: "nm")
            if let rounding = leg.rounding {
                statTile(
                    title: "ROUNDING",
                    value: rounding == .starboard ? "S" : "P",
                    unit: rounding == .starboard ? "starboard" : "port"
                )
            }
        }
    }

    /// One line of sail advice under the numbers. Uses the leg's *true*
    /// heading, not the magnetic one shown above: the forecast reports wind
    /// in degrees true, and mixing the two would put the boat on the wrong
    /// tack on paper.
    @ViewBuilder
    private var windCallout: some View {
        if let wind, let heading = leg.trueHdg {
            let plan = SailPlan(legHeadingDeg: heading, windFromDeg: wind.fromDeg)
            VStack(spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(Int(abs(plan.twaDeg).rounded()))°")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    Text(plan.tack == .port ? "PORT" : "STBD")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            plan.tack == .port
                                ? Color(red: 0.816, green: 0.126, blue: 0.122)
                                : Color(red: 0.086, green: 0.478, blue: 0.239),
                            in: Capsule()
                        )
                    Text(plan.pointOfSail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(plan.sails)
                    .font(.caption)
                    .foregroundStyle(plan.isBeat ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(
                    "Forecast \(Int(wind.fromDeg.rounded()))° · \(Int(wind.speedKts.rounded())) kt"
                    + (windIsStale ? " · stale" : "")
                )
                .font(.caption2)
                .foregroundStyle(windIsStale ? Color.orange : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var headingBlock: some View {
        VStack(spacing: 2) {
            Text(GeoMath.fmtHeading(leg.magHdg ?? leg.trueHdg ?? 0))
                .font(.system(size: 62, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text("MAGNETIC")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(2)
            if let trueHdg = leg.trueHdg {
                Text("\(GeoMath.fmtHeading(trueHdg)) true")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statTile(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(1.5)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    LegNavigatorView()
        .environment(CourseStateStore())
        .environment(WindService())
}
