import Foundation

// R27.416. ONLY a visual diagnostics orientation/ROI geometry tool.
// It is NOT Pokémon Champions classification, OCR truth, or a legal action source.
struct FrameOrientationGeometry {
    static let columns = 48
    static let rows = 24

    enum Turn: Int, CaseIterable {
        case none = 0, left = 1, half = 2, right = 3
        func rotatedRight() -> Turn { Turn(rawValue: (rawValue + 3) % 4)! }
        func rotatedLeft() -> Turn { Turn(rawValue: (rawValue + 1) % 4)! }
    }
    struct Crop: Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        var valid: Bool {
            x >= 0 && y >= 0 && width > 0 && height > 0 &&
            x + width <= 1.0000001 && y + height <= 1.0000001
        }
    }
    struct Proposal: Equatable {
        let crop: Crop
        let suggestedTurn: Turn
        let sidePillarSuspected: Bool
        let status: String
    }

    static let full = Crop(x: 0,y: 0,width: 1,height: 1)
    // Simple brightness-only geometry check. Black bars + a narrow central strip
    // can also be an app switcher; never identify the game by this test.
    static func inspect(rgb: [UInt8], width: Int = columns, height: Int = rows) -> Proposal {
        guard width == columns, height == rows, rgb.count == width * height * 3 else {
            return Proposal(crop: full, suggestedTurn: .none,
                            sidePillarSuspected: false, status: "無効な画像サンプル／補正なし")
        }
        var active = [Bool](repeating:false,count:width)
        for x in 0..<width {
            var visible = 0
            for y in 0..<height {
                let i=(y*width+x)*3
                if max(rgb[i],rgb[i+1],rgb[i+2]) >= 38 { visible += 1 }
            }
            active[x] = visible >= (height * 3 / 5)
        }
        let indices = active.indices.filter { active[$0] }
        guard let first = indices.first, let last = indices.last else {
            return Proposal(crop: full, suggestedTurn: .none,
                            sidePillarSuspected: false, status: "空白または判定不能／補正なし")
        }
        let span = last-first+1
        let ratio = Double(span)/Double(width)
        let outerL = first >= width/6, outerR = (width-1-last) >= width/6
        let centered = abs(Double(first+last+1)/Double(width)-1) <= 0.22
        let dense = active[first...last].filter { $0 }.count >= (span*7/10)
        if outerL && outerR && centered && dense && ratio >= 0.14 && ratio <= 0.62 {
            // Include a 1-sample safety margin around the detected active strip.
            let from = max(0,first-1), to=min(width,last+2)
            let crop = Crop(x:Double(from)/Double(width),y:0,
                            width:Double(to-from)/Double(width),height:1)
            return Proposal(crop:crop,suggestedTurn:.left,sidePillarSuspected:true,
                            status:"中央縦帯を検出／左90°を診断表示に仮適用（ゲーム認証なし）")
        }
        return Proposal(crop:full,suggestedTurn:.none,sidePillarSuspected:false,
                        status:"縦帯未検出／自動補正なし（手動切替可能）")
    }

    // All points are top-left-origin normalized; Vision bottom-left ROIs must
    // be converted explicitly by the caller. This does not authorize OCR use.
    static func sourcePoint(displayX u:Double,displayY v:Double,
                            crop:Crop,turn:Turn) -> (x:Double,y:Double)? {
        guard crop.valid, u >= 0, v >= 0, u <= 1, v <= 1 else { return nil }
        let x:Double,y:Double
        switch turn {
        case .none: (x,y)=(u,v)
        case .left: (x,y)=(1-v,u)
        case .right: (x,y)=(v,1-u)
        case .half: (x,y)=(1-u,1-v)
        }
        return (crop.x+x*crop.width,crop.y+y*crop.height)
    }
    static func sourceROI(displayX:Double,displayY:Double,width:Double,height:Double,
                          crop:Crop,turn:Turn) -> Crop? {
        guard width>0,height>0,displayX>=0,displayY>=0,
            displayX+width<=1,displayY+height<=1 else{return nil}
        let corners=[(displayX,displayY),(displayX+width,displayY),
                     (displayX,displayY+height),(displayX+width,displayY+height)]
        let pts=corners.compactMap{ sourcePoint(displayX:$0.0,displayY:$0.1,crop:crop,turn:turn) }
        guard pts.count==4 else {return nil}
        let xs=pts.map{$0.x},ys=pts.map{$0.y}
        let x=xs.min()!,y=ys.min()!,w=xs.max()!-x,h=ys.max()!-y
        let result=Crop(x:x,y:y,width:w,height:h)
        return result.valid ? result : nil
    }
}
