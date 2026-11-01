import Foundation

@main struct R590ColorHUDCorroborationHarness {
 static func main() {
    var passes=0
    func ok(_ value:Bool,_ tag:String) {
        guard value else {fatalError("R590_FAIL_\(tag)")}
        passes+=1
    }
    let w=480,h=240,sha=String(repeating:"c",count:64)
    func paint(_ own:String="GREEN",_ opp:String="YELLOW",flip:Bool=false,alpha:UInt8=255)->[UInt8] {
        var p=[UInt8](repeating:0,count:w*h*4)
        func rgb(_ c:String)->(UInt8,UInt8,UInt8) {
            switch c {
            case "GREEN":return (38,202,48)
            case "YELLOW":return (230,188,20)
            case "RED":return (214,31,35)
            default:return (0,0,0)
            }
        }
        for y in 0..<h {
            for x in 0..<w {
                let yy=flip ? h-1-y : y
                let ownBar=(65..<132).contains(x) && (208...212).contains(yy)
                let oppBar=(384..<435).contains(x) && (26...29).contains(yy)
                let c=rgb(ownBar ? own : oppBar ? opp : "")
                let i=(y*w+x)*4
                p[i]=c.0;p[i+1]=c.1;p[i+2]=c.2;p[i+3]=(ownBar || oppBar) ? alpha : 255
            }
        }
        return p
    }
    func inspect(_ pix:[UInt8],frame:Int64=3,hash:String=sha,stride:Int=w*4)->[String:Any] {
        R590ColorHUDCorroboration.inspect(pixels:pix,width:w,height:h,
            rowBytes:stride,epoch:2,frame:frame,observedMs:400,imageSHA:hash)
    }
    func props(_ report:[String:Any],_ expected:[String])->Bool {
        let rows=report["color_run_candidates"] as? [[String:Any]] ?? []
        return rows.compactMap{$0["color_hypothesis"] as? String}.sorted() == expected.sorted()
    }
    let p1=inspect(paint())
    ok(p1["status"] as? String == "UNCALIBRATED_COLOR_RUN_CANDIDATES","two-colors")
    ok(props(p1,["GREEN","YELLOW"]),"pixel-color-distinct")
    ok(p1["candidate_count"] as? Int == 2,"two-only")
    ok(p1["owner_certified"] as? Bool == false,"owner-held")
    ok(p1["hp_certified"] as? Bool == false,"hp-held")
    ok(p1["orientation_certified"] as? Bool == false,"orientation-held")
    ok(p1["current_state_eligible"] as? Bool == false,"history-only")
    ok(p1["automatic_upload"] as? Bool == false,"no-upload")
    let p2=inspect(paint("RED","GREEN"))
    ok(props(p2,["RED","GREEN"]),"red+green")
    let p3=inspect(paint("YELLOW","RED",flip:true))
    ok(props(p3,["YELLOW","RED"]),"inverted-rows")
    let colors=p3["color_run_candidates"] as! [[String:Any]]
    ok(colors.allSatisfy{$0["raster_row_order_hypothesis"] as? String == "MEMORY_LAST_ROW_TOP_HYPOTHESIS"},"flip-bound")
    let bad=inspect(paint(),hash:String(repeating:"A",count:64))
    ok(bad["status"] as? String == "HOLD_INVALID_PIXEL_INPUT","hash-reject")
    ok((bad["candidate_count"] as? Int)==0,"hash-reject-no-candidates")
    ok(inspect(paint(),frame:0)["status"] as? String == "HOLD_INVALID_PIXEL_INPUT","frame-reject")
    ok(inspect(paint(),stride:w*4-1)["status"] as? String == "HOLD_INVALID_PIXEL_INPUT","stride-reject")
    ok(inspect(Array(paint().dropLast()))["status"] as? String == "HOLD_INVALID_PIXEL_INPUT","bytes-reject")
    ok(inspect(paint(alpha:100))["candidate_count"] as? Int == 0,"transparent-reject")
    ok(inspect(paint("", ""))["candidate_count"] as? Int == 0,"no-bars")
    // R587 uses only EXACT same-frame, exact-SHA numeric hypotheses.
    let textRoot:[String:Any] = [
        "schema":"trueplan.r587.frame-hud-association.v1",
        "status":"HISTORICAL_FRAME_HUD_ASSOCIATIONS_ONLY",
        "current_state_eligible":false,"owner_certified":false,"orientation_certified":false,
        "frame_count":1,"frames":[["epoch":Int64(2),"frame_id":Int64(3),
            "observed_ms_monotonic":Int64(400),"image_sha256":sha,
            "anchors":[
                ["hypothesis":"HYPOTHESIS_OWN_HP_FRACTION","value":"170/185"],
                ["hypothesis":"HYPOTHESIS_OPPONENT_HP_PERCENT","value":"64%"]]]]
    ]
    let joined=R590ColorHUDCorroboration.correlate(pixelFrames:[p1],associations:textRoot)
    ok(joined["status"] as? String == "HISTORICAL_PIXEL_OCR_CORROBORATION_ONLY","join")
    ok(joined["frame_count"] as? Int == 1,"join-count")
    let rows=(joined["frames"] as! [[String:Any]])[0]["regions"] as! [[String:Any]]
    ok(rows.count==2,"join-2-regions")
    ok(rows.allSatisfy{$0["status"] as? String == "PIXEL_AND_OCR_SAME_FRAME_HYPOTHESIS_ONLY"},"join-crossmodal")
    ok(joined["hp_certified"] as? Bool == false,"join-no-cert")
    var wrong=textRoot
    var frames=wrong["frames"] as! [[String:Any]]
    frames[0]["image_sha256"]=String(repeating:"f",count:64)
    wrong["frames"]=frames
    ok(R590ColorHUDCorroboration.correlate(pixelFrames:[p1],associations:wrong)["status"] as? String == "HOLD_INCONSISTENT_FRAME_EVIDENCE","cross-sha-reject")
    wrong=textRoot
    frames=wrong["frames"] as! [[String:Any]]
    frames[0]["frame_id"]=Int64(4)
    wrong["frames"]=frames
    ok(R590ColorHUDCorroboration.correlate(pixelFrames:[p1],associations:wrong)["status"] as? String == "HOLD_INCONSISTENT_FRAME_EVIDENCE","cross-frame-reject")
    let empty=R590ColorHUDCorroboration.correlate(pixelFrames:[],associations:textRoot)
    ok(empty["status"] as? String == "HOLD_INCONSISTENT_FRAME_EVIDENCE","frame-count-reject")
    var ambiguous=textRoot
    frames=ambiguous["frames"] as! [[String:Any]]
    var anchors=frames[0]["anchors"] as! [[String:Any]]
    anchors.append(["hypothesis":"HYPOTHESIS_OWN_HP_FRACTION","value":"110/185"])
    frames[0]["anchors"]=anchors
    ambiguous["frames"]=frames
    let mixed=R590ColorHUDCorroboration.correlate(pixelFrames:[p1],associations:ambiguous)
    let mr=(mixed["frames"] as! [[String:Any]])[0]["regions"] as! [[String:Any]]
    ok(mr[0]["status"] as? String == "HOLD_AMBIGUOUS_PIXEL_OR_OCR","conflicting-ocr")
    ok(mr[1]["status"] as? String == "PIXEL_AND_OCR_SAME_FRAME_HYPOTHESIS_ONLY","other-side-intact")
    let none=inspect(paint("",""))
    let crossNone=R590ColorHUDCorroboration.correlate(pixelFrames:[none],associations:textRoot)
    let cr=(crossNone["frames"] as! [[String:Any]])[0]["regions"] as! [[String:Any]]
    ok(cr.allSatisfy{$0["status"] as? String == "INSUFFICIENT_CROSS_MODAL_EVIDENCE"},"ocr-without-pixels")
    // R591: geometric negatives that previously passed the longest-line scan.
    func custom(_ bands:[(Int,Int,Int,Int,String)])->[UInt8] {
        var bytes=paint("","")
        func rgb(_ color:String)->(UInt8,UInt8,UInt8) {
            color=="RED" ? (214,31,35) : color=="YELLOW" ? (230,188,20) : (38,202,48)
        }
        for (x0,x1,y0,y1,c) in bands {
            let v=rgb(c)
            for y in y0..<y1 {for x in x0..<x1 {
                let i=(y*w+x)*4
                bytes[i]=v.0;bytes[i+1]=v.1;bytes[i+2]=v.2
            }}
        }
        return bytes
    }
    let disconnected=inspect(custom([(65,130,207,208,"GREEN"),(65,130,213,214,"GREEN")]))
    ok(disconnected["candidate_count"] as? Int == 0,"r591-disconnected-rows-rejected")
    let tall=inspect(custom([(65,105,197,224,"GREEN")]))
    ok(tall["candidate_count"] as? Int == 0,"r591-tall-ui-block-rejected")
    let vertical=inspect(custom([(85,91,207,219,"GREEN")]))
    ok(vertical["candidate_count"] as? Int == 0,"r591-vertical-status-stripe-rejected")
    let drift=inspect(custom([(65,102,208,209,"GREEN"),(117,153,209,210,"GREEN")]))
    ok(drift["candidate_count"] as? Int == 0,"r591-disjoint-x-rejected")
    let separated=inspect(custom([(65,132,203,207,"GREEN"),(65,132,215,219,"GREEN")]))
    let components=separated["color_run_candidates"] as? [[String:Any]] ?? []
    ok(components.count==1,"r591-one-representative")
    ok(components[0]["shape_ambiguous"] as? Bool == true,"r591-two-components-ambiguity")
    ok(components[0]["disjoint_shape_count"] as? Int == 2,"r591-component-count")
    let combined=R590ColorHUDCorroboration.correlate(pixelFrames:[separated],associations:textRoot)
    let combinedRows=(combined["frames"] as? [[String:Any]])?.first?["regions"] as? [[String:Any]] ?? []
    ok(combinedRows.first?["status"] as? String == "HOLD_AMBIGUOUS_PIXEL_OR_OCR","r591-ambiguous-bar-held")
    let geometry=p1["color_run_candidates"] as? [[String:Any]] ?? []
    ok(geometry.allSatisfy{$0["shape_provenance"] as? String == "R591_CONNECTED_SCANLINE_GEOMETRY_HYPOTHESIS"},"r591-shape-provenance")
    ok(geometry.allSatisfy{($0["horizontal_aspect_min"] as? Double ?? 0)>=4},"r591-horizontal-aspect")
    ok(geometry.allSatisfy{($0["bounds_right_normalized"] as? Double ?? 0)>($0["bounds_left_normalized"] as? Double ?? 1)},"r591-positive-x-bounds")
    ok(geometry.allSatisfy{($0["bounds_bottom_normalized"] as? Double ?? 0)>($0["bounds_top_normalized"] as? Double ?? 1)},"r591-positive-y-bounds")
    ok(p1["r591_connected_scanline_filter"] as? Bool == true,"r591-filter-flag")
    let original=paint()
    let stride=w*4+16
    var padded=[UInt8](repeating:0,count:stride*h)
    for y in 0..<h {for x in 0..<(w*4) {padded[y*stride+x]=original[y*w*4+x]}}
    ok(inspect(padded,stride:stride)["candidate_count"] as? Int == 2,"r591-padded-row-stride")
    ok(R590ColorHUDCorroboration.correlate(pixelFrames:[separated],associations:textRoot)["owner_certified"] as? Bool == false,"r591-no-owner-promotion")
    print("R591_CONNECTED_COMPONENT_PIXEL_OCR_PASS \(passes)/\(passes)")
 }
}
