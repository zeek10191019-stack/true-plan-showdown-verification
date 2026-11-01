import Foundation

// R27.465: explicit, local, unverified WHITE-GLYPH shape diagnostic.
// Input is a side-specific icon ROI from the *current displayed frame*.
// It MUST NOT infer sex from Pokemon species, icon background colour, or opponent.
// The geometry is calibrated on ONE captured 578:267 research layout.
// It is not a production classifier or a general accuracy certification.
enum ResearchGenderGlyphProbe {
    struct Result {
        let literal: String
        let upperLeft: Int
        let bottomCenter: Int
        let circleLeft: Int
        let totalWhite: Int
    }
    static func inspect(rgba:[UInt8], width:Int, height:Int, side:String) -> Result? {
        guard side == "own" || side == "opp", width >= 90, height >= 90,
              width <= 400, height <= 400, rgba.count == width*height*4 else { return nil }
        let cx = Double(width) * (side == "own" ? 39.0/121.0 : 43.0/126.0)
        let cy = Double(height) * (side == "own" ? 82.0/130.0 : 69.0/136.0)
        let radius = Double(width) * (side == "own" ? 24.0/121.0 : 26.0/126.0)
        var upperLeft=0, bottomCenter=0, circleLeft=0, total=0
        for y in 0..<height {
            for x in 0..<width {
                let dx=(Double(x)-cx)/radius, dy=(Double(y)-cy)/radius
                if dx*dx + dy*dy >= 1.2*1.2 { continue }
                let i=4*(y*width+x)
                let red=Int(rgba[i]),green=Int(rgba[i+1]),blue=Int(rgba[i+2])
                // Shape, NOT badge colour: isolate approximately neutral white glyph pixels.
                let low=min(red,min(green,blue)),high=max(red,max(green,blue))
                if low < 170 || high-low > 105 { continue }
                total+=1
                if dx < -0.20 && dy < -0.23 && dy > -0.90 { upperLeft+=1 }
                if abs(dx) < 0.22 && dy > 0.40 && dy < 1.00 { bottomCenter+=1 }
                if dx < -0.28 && abs(dy) < 0.40 { circleLeft+=1 }
            }
        }
        // Both mutually exclusive shape checks must remain strict and abstain otherwise.
        // Normalize pixel-area thresholds to the original research ROI resolution.
        let areaScale=(Double(width)/Double(side == "own" ? 121 : 126))
            * (Double(height)/Double(side == "own" ? 130 : 136))
        let factor=max(0.5, areaScale)
        let female = Double(upperLeft) >= 12*factor && Double(bottomCenter) >= 14*factor
            && Double(circleLeft) >= 12*factor && Double(circleLeft) < Double(upperLeft)*2.1
            && Double(total) >= 100*factor
        let male = Double(upperLeft) <= 4*factor && Double(bottomCenter) <= 8*factor
            && Double(circleLeft) >= 14*factor && Double(total) >= 90*factor
        guard female != male else { return nil }
        return Result(literal: female ? "♀" : "♂",upperLeft:upperLeft,
            bottomCenter:bottomCenter,circleLeft:circleLeft,totalWhite:total)
    }
}
