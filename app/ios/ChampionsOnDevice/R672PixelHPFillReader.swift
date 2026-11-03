import Foundation

/// R672: reads actual RGBA HP-bar-like filled+unfilled tracks.
/// A visual fill ratio is NOT an authenticated Pokémon HP percentage.
/// The raw image's orientation, UI location and ownership are uncalibrated.
enum R672PixelHPFillReader {
    static let schema = "trueplan.r672.rgba-hp-fill-track.v1"
    private static let regions: [(String,Double,Double,Double,Double)] = [
        ("LOWER_LEFT_HUD_POSITION_ONLY",0.10,0.40,0.79,0.98),
        ("UPPER_RIGHT_HUD_POSITION_ONLY",0.70,0.97,0.04,0.26)]
    private static func sha(_ s:String)->Bool {
        s.utf8.count==64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func hold(_ reason:String,frame:Int64=0,epoch:Int64=0,
                             sha:String="")->[String:Any] {
        ["schema":schema,"status":reason,"frame_id":frame,"epoch":epoch,
         "raw_image_sha256":sha,"tracks":[[String:Any]](),"track_count":0,
         "hp_percent_certified":false,"owner_certified":false,
         "orientation_certified":false,"current_state_eligible":false,
         "battle_advice_authorized":false]
    }
    private static func kind(_ r:Int,_ g:Int,_ b:Int,_ a:Int)->Int {
        guard a>=160 else{return -1}
        let high=max(r,g,b),low=min(r,g,b)
        if high>=90 && high-low>=40 {
            if g>=100 && g>r*12/10 && g>b*11/10 {return 1} // green
            if r>=140 && g>=85 && b<125 && r>=g*9/10 {return 2} // yellow
            if r>=125 && r>g*14/10 && r>b*14/10 {return 3} // red
        }
        if low>=30 && high<=140 && high-low<=20 {return 0} // empty track
        return -1
    }
    private static func sourceUV(_ u:Double,_ v:Double,_ rotation:Int)
        ->(Double,Double) {
        switch rotation {
        case 90:return (v,1-u)
        case 180:return (1-u,1-v)
        case 270:return (1-v,u)
        default:return (u,v)
        }
    }
    private struct Run {
        let left:Int,split:Int,right:Int,row:Int,color:Int
        var percentage:Double {100*Double(split-left)/Double(right-left)}
    }
    // Returns a track only if adjacent filled and empty sections repeat in
    // multiple contiguous scanlines with stable endpoints and color.
    private static func scan(_ pixels:[UInt8],width:Int,height:Int,
                             rowBytes:Int,rotation:Int,flipY:Bool,
                             region:(String,Double,Double,Double,Double)) -> [[String:Any]] {
        let rw=rotation%180==0 ? width:height
        let rh=rotation%180==0 ? height:width
        let x0=Int(Double(rw)*region.1),x1=Int(Double(rw)*region.2)
        let y0=Int(Double(rh)*region.3),y1=Int(Double(rh)*region.4)
        guard x1-x0>=56,y1>y0 else{return []}
        func sample(_ x:Int,_ y:Int)->Int {
            let (u,v)=sourceUV((Double(x)+0.5)/Double(rw),
                                (Double(y)+0.5)/Double(rh),rotation)
            let xx=min(width-1,max(0,Int(u*Double(width))))
            let visualY=min(height-1,max(0,Int(v*Double(height))))
            let yy=flipY ? height-1-visualY:visualY
            let idx=yy*rowBytes+xx*4
            return kind(Int(pixels[idx]),Int(pixels[idx+1]),
                        Int(pixels[idx+2]),Int(pixels[idx+3]))
        }
        let minFilled=max(12,rw/70),minEmpty=max(8,rw/90)
        let minTotal=max(48,rw/16),maxTotal=min(x1-x0,rw/3)
        var strips=[Run]()
        for y in y0..<y1 {
            var states=[Int](repeating:-1,count:x1-x0)
            for x in x0..<x1 {states[x-x0]=sample(x,y)}
            var i=1
            while i<states.count-1 {
                let c=states[i]
                guard (1...3).contains(c),states[i-1] != c else {i+=1;continue}
                let left=i
                while i<states.count && states[i]==c {i+=1}
                let split=i
                guard split-left>=minFilled else {continue}
                while i<states.count && states[i]==0 {i+=1}
                let right=i
                let filled=split-left,empty=right-split
                let total=right-left
                // Require both ends: a bare colored run has no percentage.
                guard empty>=minEmpty,total>=minTotal,
                      total<=maxTotal,filled*100>=8*total,
                      filled*100<=92*total,
                      left>0,right<states.count,
                      states[left-1] != 0,states[right] != 0 else {continue}
                strips.append(Run(left:x0+left,split:x0+split,
                                  right:x0+right,row:y,color:c))
            }
        }
        var stacks=[[Run]]()
        for s in strips {
            if let j=stacks.indices.last(where: {j in
                guard let prev=stacks[j].last else{return false}
                return s.row==prev.row+1 && s.color==prev.color &&
                    abs(s.left-prev.left)<=2 && abs(s.right-prev.right)<=2 &&
                    abs(s.split-prev.split)<=2
            }) {stacks[j].append(s)} else {stacks.append([s])}
        }
        let accepted=stacks.filter {$0.count>=3 && $0.count<=max(18,rh/12)}
        let names=[1:"GREEN",2:"YELLOW",3:"RED"]
        return accepted.sorted {$0.count>$1.count}.prefix(2).compactMap { stack in
            guard let first=stack.first,let last=stack.last else{return nil}
            let fraction=stack.map{$0.percentage}.reduce(0,+)/Double(stack.count)
            return ["position_hint":region.0,"rotation_hypothesis_degrees":rotation,
                    "raw_row_origin_hypothesis":flipY ? "BOTTOM_FIRST":"TOP_FIRST",
                    "color_class_hypothesis":names[first.color] ?? "UNKNOWN",
                    "fill_percentage_candidate_not_hp":
                        (fraction*10).rounded()/10,
                    "bar_left_normalized":Double(first.left)/Double(rw),
                    "bar_right_normalized":Double(first.right)/Double(rw),
                    "bar_top_normalized":Double(first.row)/Double(rh),
                    "bar_bottom_normalized":Double(last.row+1)/Double(rh),
                    "supporting_scanlines":stack.count,
                    "owner":"UNKNOWN","owner_certified":false,
                    "hp_percent_certified":false,"current_state_eligible":false]
        }
    }
    static func unavailable(epoch:Int64,frame:Int64,ms:Int64,sha256:String)
        ->[String:Any] {
        hold("HOLD_RGBA_RENDER_UNAVAILABLE",frame:frame,epoch:epoch,sha:sha256)
    }
    static func inspect(pixels:[UInt8],width:Int,height:Int,rowBytes:Int,
                        epoch:Int64,frame:Int64,ms:Int64,sha256:String)->[String:Any] {
        guard width>=128,height>=128,width<=4096,height<=4096,
              rowBytes>=width*4,rowBytes<=width*4+4096,
              rowBytes<=64*1024*1024/height,
              pixels.count==rowBytes*height,epoch>0,frame>0,ms>0,
              sha(sha256) else {return hold("HOLD_INVALID_RGBA_SOURCE")}
        var found=[[String:Any]]()
        for rotation in [0,90,180,270] {
            let rw=rotation%180==0 ? width:height
            let rh=rotation%180==0 ? height:width
            let aspect=Double(rw)/Double(rh)
            guard (1.65...2.35).contains(aspect) else{continue}
            for flip in [false,true] {
                for region in regions {
                    found.append(contentsOf:scan(pixels,width:width,height:height,
                        rowBytes:rowBytes,rotation:rotation,flipY:flip,region:region))
                }
            }
        }
        return ["schema":schema,
            "status":found.isEmpty ? "NO_PARTIAL_BAR_TRACK_CANDIDATES" :
              "PARTIAL_BAR_FILL_TRACKS_UNVERIFIED",
            "raw_image_sha256":sha256,"frame_id":frame,"epoch":epoch,
            "observed_ms":ms,"track_count":found.count,"tracks":found,
            "no_full_or_empty_bar_inference":true,
            "no_uncalibrated_owner_or_hp_claim":true,
            "hp_percent_certified":false,"owner_certified":false,
            "orientation_certified":false,"current_state_eligible":false,
            "battle_advice_authorized":false,
            "real_game_accuracy":"NOT_MEASURED"]
    }
}
