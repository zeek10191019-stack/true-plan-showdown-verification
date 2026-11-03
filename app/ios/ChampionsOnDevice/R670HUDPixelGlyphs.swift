import Foundation

// Actual RGBA scan of HUD-adjacent colored shapes. No text OCR is used.
// Color groups are NOT Pokémon status types or owner identity.
enum R670HUDPixelGlyphs {
    static let schema = "trueplan.r670.hud-rgba-glyphs.v1"
    private static let scopes:[(String,Double,Double,Double,Double)] = [
        ("OWN_HUD_POSITION_ONLY",0.11,0.77,0.34,0.22),
        ("OPPONENT_HUD_POSITION_ONLY",0.61,0.03,0.36,0.27)]
    private static func sha(_ s:String)->Bool {
        s.utf8.count==64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func hold(_ why:String)->[String:Any] {
        ["schema":schema,"status":why,"candidates":[[String:Any]](),
         "candidate_count":0,"owner_certified":false,
         "status_icon_class_certified":false,"mega_form_certified":false,
         "current_state_eligible":false,"battle_advice_authorized":false]
    }
    static func unavailable(epoch:Int64,frame:Int64,ms:Int64,
                            sha256:String)->[String:Any] {
        var out=hold("HOLD_RGBA_RENDER_UNAVAILABLE")
        out["epoch"]=epoch;out["frame_id"]=frame
        out["observed_ms"]=ms;out["raw_image_sha256"]=sha256
        return out
    }
    // HSV bins deliberately do not map colors to conditions.
    private static func bin(_ r:UInt8,_ g:UInt8,_ b:UInt8)->Int {
        let a=Double(r)/255, v=Double(g)/255, c=Double(b)/255
        let hi=max(a,v,c), lo=min(a,v,c), delta=hi-lo
        guard hi>=0.32,delta>=0.19,delta/hi>=0.45 else{return -1}
        let hue:Double
        if hi==a {hue=60*((v-c)/delta).truncatingRemainder(dividingBy:6)}
        else if hi==v {hue=60*((c-a)/delta+2)}
        else {hue=60*((a-v)/delta+4)}
        let h=hue<0 ? hue+360 : hue
        if h<44 || h>=345 {return 0} // orange/red
        if h<75 {return 1} // yellow
        if h<165 {return 2} // green, often HP bar
        if h<260 {return 3} // cyan/blue
        return 4 // violet/magenta
    }
    private static func sourceUV(_ x:Double,_ y:Double,_ deg:Int)
        ->(Double,Double) {
        switch deg {
        case 90:return (y,1-x)
        case 180:return (1-x,1-y)
        case 270:return (1-y,x)
        default:return (x,y)
        }
    }
    static func inspect(pixels:[UInt8],width:Int,height:Int,
                        rowBytes:Int,epoch:Int64,frame:Int64,
                        ms:Int64,sha256:String)->[String:Any] {
        guard width>=128,height>=128,width<=4096,height<=4096,
              rowBytes>=width*4,rowBytes<=width*8,
              rowBytes<=Int.max/height,
              pixels.count==rowBytes*height,
              epoch>0,frame>0,ms>0,sha(sha256) else {
            return hold("HOLD_RGBA_SOURCE_INVALID")
        }
        let families=["WARM","YELLOW","GREEN_HP_LIKE",
                      "BLUE_CYAN","VIOLET"]
        var output=[[String:Any]]()
        var orientations=0
        for deg in [0,90,180,270] {
            let rw=deg%180==0 ? width:height
            let rh=deg%180==0 ? height:width
            let aspect=Double(rw)/Double(rh)
            guard (1.65...2.35).contains(aspect) else{continue}
            orientations+=1
            for (scope,x0,y0,ww,hh) in scopes {
                let cols=min(160,max(24,Int(ww*Double(rw)/3)))
                let rows=min(100,max(20,Int(hh*Double(rh)/3)))
                let count=cols*rows
                var mask=[Int8](repeating:-1,count:count)
                for j in 0..<rows {
                    for i in 0..<cols {
                        let x=x0+ww*(Double(i)+0.5)/Double(cols)
                        let y=y0+hh*(Double(j)+0.5)/Double(rows)
                        let (u,v)=sourceUV(x,y,deg)
                        let px=min(width-1,max(0,Int(u*Double(width))))
                        let py=min(height-1,max(0,Int(v*Double(height))))
                        let off=py*rowBytes+px*4
                        if pixels[off+3]<128 {continue}
                        mask[j*cols+i]=Int8(bin(pixels[off],
                            pixels[off+1],pixels[off+2]))
                    }
                }
                var visited=[Bool](repeating:false,count:count)
                var candidates=[[String:Any]]()
                for k in 0..<count {
                    let family=Int(mask[k])
                    if family<0 || visited[k] {continue}
                    visited[k]=true
                    var queue=[k],ptr=0,pminx=k%cols,pmaxx=pminx
                    var pminy=k/cols,pmaxy=pminy
                    while ptr<queue.count {
                        let n=queue[ptr];ptr+=1
                        let nx=n%cols,ny=n/cols
                        pminx=min(pminx,nx);pmaxx=max(pmaxx,nx)
                        pminy=min(pminy,ny);pmaxy=max(pmaxy,ny)
                        // Four-connected components; avoid diagonal noise.
                        for (dx,dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                            let ax=nx+dx,ay=ny+dy
                            if ax<0 || ax>=cols || ay<0 || ay>=rows {continue}
                            let idx=ay*cols+ax
                            if !visited[idx] && Int(mask[idx])==family {
                                visited[idx]=true;queue.append(idx)
                            }
                        }
                    }
                    let bw=pmaxx-pminx+1,bh=pmaxy-pminy+1
                    let component=queue.count
                    let xFrac=Double(bw)/Double(cols)*ww
                    let yFrac=Double(bh)/Double(rows)*hh
                    let ratio=Double(bw)/Double(max(1,bh))
                    // Discard pixel noise and long bars or big panels.
                    guard component>=5,component<=300,
                          bw>=2,bh>=2,(0.3...3.2).contains(ratio),
                          xFrac<=0.070,yFrac<=0.095,
                          Double(component)/Double(bw*bh)>=0.35 else {
                        continue
                    }
                    // Eight-by-eight binary glyph outline retained for
                    // a future independently labeled reference matcher.
                    var silhouette=[Bool](repeating:false,count:64)
                    for n in queue {
                        let gx=min(7,(n%cols-pminx)*8/max(1,bw))
                        let gy=min(7,(n/cols-pminy)*8/max(1,bh))
                        silhouette[gy*8+gx]=true
                    }
                    let hexdigits=Array("0123456789abcdef")
                    var shape=""
                    for pos in stride(from:0,to:64,by:4) {
                        var v=0
                        for bit in 0..<4 {
                            if silhouette[pos+bit] {v |= 1<<(3-bit)}
                        }
                        shape.append(hexdigits[v])
                    }
                    candidates.append([
                        "silhouette_8x8_hex_unlabeled":shape,
                        "position_hint":scope,
                        "rotation_hypothesis_degrees":deg,
                        "color_family_unclassified":families[family],
                        "normalized_box_x":x0+ww*Double(pminx)/Double(cols),
                        "normalized_box_y":y0+hh*Double(pminy)/Double(rows),
                        "normalized_box_width":xFrac,
                        "normalized_box_height":yFrac,
                        "sample_pixels_in_component":component,
                        "is_status_icon":false,
                        "owner_verified":false,
                        "current_state_eligible":false])
                }
                // Bounded deterministic output per orientation and HUD.
                candidates.sort {
                    let a=$0["sample_pixels_in_component"] as? Int ?? 0
                    let b=$1["sample_pixels_in_component"] as? Int ?? 0
                    if a != b {return a>b}
                    return ($0["normalized_box_y"] as? Double ?? 0) <
                           ($1["normalized_box_y"] as? Double ?? 0)
                }
                output.append(contentsOf:candidates.prefix(12))
            }
        }
        return ["schema":schema,
            "status":"HISTORICAL_HUD_RGBA_GLYPH_CANDIDATES_ONLY",
            "epoch":epoch,"frame_id":frame,"observed_ms":ms,
            "raw_image_sha256":sha256,
            "raster_width":width,"raster_height":height,
            "raw_bitmap_origin":"UNVERIFIED_CGCONTEXT_BUFFER_ORIGIN",
            "rotations_evaluated":orientations,
            "candidate_count":output.count,"candidates":output,
            "status_icon_class_certified":false,"owner_certified":false,
            "mega_form_certified":false,"current_state_eligible":false,
            "battle_advice_authorized":false,
            "accuracy":"NOT_MEASURED",
            "limitations":"RGBA colored blobs, not labeled status icons. " +
                "Uncalibrated orientation and HUD geometry."]
    }
}
