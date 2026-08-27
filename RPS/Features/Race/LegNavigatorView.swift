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
    @Environment(LivePositionStore.self) private var liveStore
    @Environment(AppSettings.self) private var settings

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
                            legCount: legs.count,
                            speedKts: liveStore.fix?.speedKts,
                            useMagnetic: settings.useMagnetic,
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
    let legCount: Int
    /// Live speed over ground, when GPS is running - turns the leg's
    /// distance into a time, which is the form the question is usually
    /// asked in ("do we make the gun?").
    let speedKts: Double?
    /// Lead with magnetic instead of true. Both are always shown; this only
    /// decides which one gets the big type.
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
                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 14) {
                    headingBlock
                        .frame(maxWidth: .infinity)
                    windGraphic
                }

                Spacer(minLength: 0)

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
            Text("LEG \(leg.legIndex + 1) OF \(legCount)")
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
            WindRoseView(legHeadingDeg: heading, windFromDeg: wind.fromDeg, size: 132)
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
            .frame(width: 132, height: 132)
        }
    }

    /// Distance, rounding and time-on-leg. Three tiles rather than one
    /// stretched across the width: a single full-bleed DISTANCE panel was
    /// most of the page's wasted space, and the two beside it are things
    /// actually wanted on the way to the mark.
    private var statsRow: some View {
        HStack(spacing: 8) {
            statTile(title: "DISTANCE", value: String(format: "%.2f", leg.distNm ?? 0), unit: "nm")

            statTile(
                title: "ROUNDING",
                value: roundingValue,
                unit: roundingUnit
            )

            statTile(title: "TIME", value: legTimeValue, unit: legTimeUnit)
        }
    }

    private var roundingValue: String {
        switch leg.rounding {
        case .starboard: return "S"
        case .port: return "P"
        case nil: return "–"
        }
    }

    private var roundingUnit: String {
        switch leg.rounding {
        case .starboard: return "starboard"
        case .port: return "port"
        case nil: return "not set"
        }
    }

    /// Time to sail this leg at the speed being made right now. Blank rather
    /// than a guess when the boat isn't moving - a number extrapolated from
    /// a drift is worse than no number.
    private var legTimeValue: String {
        guard let speedKts, speedKts >= 0.5, let dist = leg.distNm else { return "–" }
        let minutes = (dist / speedKts) * 60
        if minutes < 60 { return "\(Int(minutes.rounded()))" }
        let hours = Int(minutes / 60)
        let rest = Int(minutes.truncatingRemainder(dividingBy: 60).rounded())
        return "\(hours):\(String(format: "%02d", rest))"
    }

    private var legTimeUnit: String {
        guard let speedKts, speedKts >= 0.5, let dist = leg.distNm else { return "need speed" }
        let minutes = (dist / speedKts) * 60
        return minutes < 60
            ? String(format: "min at %.1f kt", speedKts)
            : String(format: "h:mm at %.1f kt", speedKts)
    }

    /// The sail call, and where the breeze is coming from.
    ///
    /// Uses the leg's *true* heading, not whichever one is displayed above:
    /// the forecast reports wind in degrees true, and mixing the two would
    /// put the boat on the wrong tack on paper.
    ///
    /// The wind *angle* deliberately isn't repeated here - it sits under the
    /// rose, next to the picture it describes. This page was showing four
    /// bare numbers ending in a degree sign with nothing to say which was
    /// which.
    @ViewBuilder
    private var windCallout: some View {
        if let wind, let heading = leg.trueHdg {
            let plan = SailPlan(legHeadingDeg: heading, windFromDeg: wind.fromDeg)
            VStack(spacing: 4) {
                Text(plan.pointOfSail)
                    .font(.headline)
                Text(plan.sails)
                    .font(.subheadline)
                    .foregroundStyle(plan.isBeat ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(
                    "Wind from \(Int(wind.fromDeg.rounded()))°T at \(Int(wind.speedKts.rounded())) kt"
                    + (windIsStale ? " · stale" : "")
                )
                .font(.caption2)
                .foregroundStyle(windIsStale ? Color.orange : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// True leads by default, magnetic underneath.
    ///
    /// Everything else on this screen is in degrees true - the wind angle,
    /// the forecast direction, the start-line bias - so leading with
    /// magnetic meant the biggest number on the page was the one that
    /// agreed with nothing near it. Sailors steering to a bulkhead compass
    /// can flip it in Profile; either way both are shown.
    private var headingBlock: some View {
        VStack(spacing: 2) {
            Text(GeoMath.fmtHeading(primaryHeading))
                .font(.system(size: 62, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(useMagnetic ? "MAGNETIC" : "TRUE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(2)
            Text("\(GeoMath.fmtHeading(secondaryHeading)) \(useMagnetic ? "true" : "mag")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Heading \(Int(primaryHeading.rounded())) degrees \(useMagnetic ? "magnetic" : "true")"
        )
    }

    private var primaryHeading: Double {
        let trueHdg = leg.trueHdg ?? 0
        return useMagnetic ? (leg.magHdg ?? trueHdg) : trueHdg
    }

    private var secondaryHeading: Double {
        let trueHdg = leg.trueHdg ?? 0
        return useMagnetic ? trueHdg : (leg.magHdg ?? trueHdg)
    }

    private func statTile(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
        .environment(LivePositionStore())
        .environment(AppSettings.shared)
}
