import SwiftUI
import AppKit

struct TacticalEyebrow: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text).font(TacticalTypography.log.weight(.semibold)).tracking(1.4)
            .foregroundStyle(TacticalColors(scheme: scheme).muted)
    }
}

// Original vector geometry. A static identity graphic, never network/game telemetry.
struct TacticalGlobe: View {
    var chinese = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let radius = min(size.width, size.height) * 0.34
            // Fine drafting grid, clipped to this graphic's own bounds.
            var grid = Path()
            for x in stride(from: CGFloat(0), to: size.width, by: 22) {
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), to: size.height, by: 22) {
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(c.line.opacity(0.25)), lineWidth: 0.5)
            let earth = CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)
            context.fill(Path(ellipseIn: earth), with: .color(c.accent.opacity(0.07)))
            context.stroke(Path(ellipseIn: earth), with: .color(c.accent), lineWidth: 1.5)
            for ratio in [0.35, 0.7] {
                context.stroke(Path(ellipseIn: CGRect(x: center.x-radius*ratio, y: center.y-radius, width: radius*ratio*2, height: radius*2)), with: .color(c.accent.opacity(0.45)), lineWidth: 0.7)
            }
            for ratio in [-0.5, 0.0, 0.5] {
                let half = radius * sqrt(1-ratio*ratio)
                context.stroke(Path(ellipseIn: CGRect(x: center.x-half, y: center.y+radius*ratio-radius*0.12, width: half*2, height: radius*0.24)), with: .color(c.accent.opacity(0.4)), lineWidth: 0.7)
            }
            // An original angular landmass silhouette, not traced game artwork.
            var land = Path()
            let points: [CGPoint] = [CGPoint(x: -0.50,y: -0.54),CGPoint(x: -0.12,y: -0.67),CGPoint(x: 0.12,y: -0.42),CGPoint(x: -0.04,y: -0.16),CGPoint(x: 0.22,y: 0.02),CGPoint(x: 0.06,y: 0.30),CGPoint(x: -0.06,y: 0.61),CGPoint(x: -0.27,y: 0.30),CGPoint(x: -0.34,y: 0.02),CGPoint(x: -0.65,y: -0.13)]
            land.addLines(points.map { CGPoint(x: center.x+$0.x*radius,y: center.y+$0.y*radius) }); land.closeSubpath()
            context.fill(land, with: .color(c.accent.opacity(0.35)))
            let orbit = CGRect(x: center.x-radius*1.35,y: center.y-radius*1.35,width:radius*2.7,height:radius*2.7)
            context.stroke(Path(ellipseIn: orbit), with: .color(c.accent.opacity(0.4)), style: StrokeStyle(lineWidth: 0.7, dash: [4,6]))
            for degrees in stride(from: 0, to: 360, by: 15) {
                let angle = Double(degrees) * .pi / 180
                let a = radius * 1.43, b = radius * (degrees % 90 == 0 ? 1.58 : 1.48)
                var tick = Path(); tick.move(to: CGPoint(x: center.x+cos(angle)*a,y:center.y+sin(angle)*a))
                tick.addLine(to: CGPoint(x:center.x+cos(angle)*b,y:center.y+sin(angle)*b))
                context.stroke(tick, with: .color(c.accent.opacity(0.7)), lineWidth: 1)
            }
            // Wing-like industrial bars carry the old emblem's horizontal rhythm.
            for side in [-1.0,1.0] {
                for row in 0..<3 {
                    let x = center.x+side*radius*1.72
                    let y = center.y+CGFloat(row-1)*12
                    var bar = Path();bar.move(to:CGPoint(x:x,y:y));bar.addLine(to:CGPoint(x:x+side*CGFloat(26-row*6),y:y))
                    context.stroke(bar,with:.color(c.accent),lineWidth:4)
                }
            }
        }
        .overlay(alignment: .topLeading) { TacticalEyebrow(text: "SE / 01").padding(10) }
        .overlay(alignment: .bottomTrailing) { TacticalEyebrow(text: chinese ? "超级地球" : "SUPER EARTH").padding(10) }
        .accessibilityHidden(true)
    }
}

// Width comes from the proposed content region, so language does not choose a layout.
struct TacticalStatusLayout: Layout {
    private let gap: CGFloat = 12
    private func columns(_ width: CGFloat) -> Int { width >= 700 ? 3 : width >= 440 ? 2 : 1 }
    private func itemWidth(_ index: Int, count: Int, width: CGFloat, columns: Int) -> CGFloat {
        if columns == 2 && index == count - 1 && index % columns == 0 { return width }
        return (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        let cols = columns(width)
        var height: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: cols) {
            let rowHeight = (start..<min(start + cols, subviews.count)).map { i in
                subviews[i].sizeThatFits(ProposedViewSize(width: itemWidth(i, count: subviews.count, width: width, columns: cols), height: nil)).height
            }.max() ?? 0
            height += rowHeight + (start == 0 ? 0 : gap)
        }
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cols = columns(bounds.width)
        let cellWidth = (bounds.width-gap*CGFloat(cols-1))/CGFloat(cols)
        var y = bounds.minY
        for start in stride(from: 0, to: subviews.count, by: cols) {
            let row = start..<min(start+cols, subviews.count)
            let height = row.map { i in
                subviews[i].sizeThatFits(ProposedViewSize(width: itemWidth(i, count: subviews.count, width: bounds.width, columns: cols), height: nil)).height
            }.max() ?? 0
            for i in row {
                subviews[i].place(at: CGPoint(x: bounds.minX + CGFloat(i % cols)*(cellWidth+gap), y: y), anchor: .topLeading,
                                 proposal: ProposedViewSize(width: itemWidth(i, count: subviews.count, width: bounds.width, columns: cols), height: height))
            }
            y += height + gap
        }
    }
}

// Reserved for a separately licensed, standalone soldier asset. Never uses a UI screenshot.
struct SoldierBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        GeometryReader { geometry in
            // Preserve the complete vertical composition: fist, helmet and flag.
            // Only surplus scenery on the left may leave the header's bounds.
            Image("HelldiverHero")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geometry.size.height * 1672 / 941, height: geometry.size.height)
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.48),
                    .init(color: .white, location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                .overlay(LinearGradient(stops: [
                    .init(color: c.panel, location: 0),
                    .init(color: c.panel.opacity(0.96), location: 0.25),
                    .init(color: c.panel.opacity(0.12), location: 0.62),
                    .init(color: .clear, location: 0.82)
                ], startPoint: .leading, endPoint: .trailing))
                .overlay(LinearGradient(stops: [
                    .init(color: .clear, location: 0.60),
                    .init(color: c.panel.opacity(0.35), location: 0.83),
                    .init(color: c.panel, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .clipped()
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
