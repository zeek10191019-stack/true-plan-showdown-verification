import Foundation
@main struct R668PlainHUDSmoke {
    static func main() {
        typealias T=R668PlainHUDReader.Token
        func tok(_ id:String,_ text:String,_ x:Double,_ y:Double)->T {
            T(ref:id,text:text,x:x,y:y,w:0.05,h:0.03)
        }
        var tokens=[
            tok("ownhp","148/197",0.17,0.92),
            tok("opphp","81%",0.85,0.11),
            tok("ownname","ガブリアス♂",0.13,0.85),
            tok("oppname","サーナイト♀",0.77,0.045),
            tok("clock","9:57",0.77,0.29)]
        let names=["じしん","げきりん","がんせきふうじ","まもる"]
        for i in 0..<4 {
            let y=0.48+Double(i)*0.115
            tokens.append(tok("move\(i)",names[i],0.62,y))
            tokens.append(tok("pp\(i)","8/16",0.88,y))
        }
        let success=R668PlainHUDReader.scan(tokens,width:1920,height:1080)
        precondition(success["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY")
        precondition(success["move_pair_count"] as? Int==4)
        let rows=success["matches"] as! [[String:Any]]
        precondition(rows.count==9)
        precondition(rows.contains{$0["field"] as? String=="own.moves_four"})
        precondition(rows.contains{$0["field"] as? String=="own.active_species"})
        precondition(rows.contains{$0["field"] as? String=="own.gender"})
        precondition(rows.contains{$0["field"] as? String=="opponent.gender"})
        precondition(rows.contains{$0["field"] as? String=="battle.timer"})
        precondition(rows.contains{$0["field"] as? String=="opponent.active_species"})
        precondition(success["owner_verified"] as? Bool==false)
        precondition(success["game_fields_certified"] as? Int==0)
        let reverse=tokens.map {t in T(ref:t.ref,text:t.text,
            x:1-t.y,y:t.x,w:t.w,h:t.h)}
        let rotated=R668PlainHUDReader.scan(reverse,width:1080,height:1920)
        precondition(rotated["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY")
        precondition(rotated["move_pair_count"] as? Int==4)
        var duplicate=tokens
        duplicate.append(tok("other","91%",0.84,0.12))
        precondition((R668PlainHUDReader.scan(duplicate,width:1920,height:1080)["status"] as? String ?? "").hasPrefix("HOLD_"))
        precondition((R668PlainHUDReader.scan([],width:1920,height:1080)["status"] as? String ?? "").hasPrefix("HOLD_"))
        precondition((R668PlainHUDReader.scan(tokens,width:100,height:200)["status"] as? String ?? "").hasPrefix("HOLD_"))
        precondition((R668PlainHUDReader.audit([:],sourceKind:"LIVE_RETAINED_FRAME")["status"] as? String ?? "").hasPrefix("HOLD_"))
        let dup=tokens+[tokens[0]]
        precondition(R668PlainHUDReader.scan(dup,width:1920,height:1080)["status"] as? String=="HOLD_INVALID_TOKEN_GEOMETRY")
        let bad=tokens+[tok("nan","じしん",.nan,0.4)]
        precondition(R668PlainHUDReader.scan(bad,width:1920,height:1080)["status"] as? String=="HOLD_INVALID_TOKEN_GEOMETRY")
        let hash=String(repeating:"a",count:64)
        let sid="s668"
        let inventory:[[String:Any]]=tokens.map {t in
            ["evidence_ref":t.ref,"raw_text":t.text,
             "roi":["x":Int(t.x*1920),"y":Int(t.y*1080),
                    "width":96,"height":32],
             "image_sha256":hash,"capture_session_id":sid,
             "frame_id":12,"epoch":4,"owner_verified":false]
        }
        let packet:[String:Any]=[
            "r667_expanded_ocr_fields": [
                "status":"EXPANDED_TEXT_CANDIDATES_ONLY",
                "owner_verified":false,"game_fields_certified":0],
            "png_sha256":hash,"image_width":1920,"image_height":1080,
            "screen_read_state":[
                "source_validation":"PASS_FRAME_BINDING_ONLY",
                "current_state_eligible":false,
                "battle_advice_authorized":false,
                "capture_session_id":sid,"image_sha256":hash,
                "frame_id":12,"epoch":4,
                "ocr_source_inventory":inventory]
        ]
        let bound=R668PlainHUDReader.audit(packet,
                             sourceKind:"LIVE_RETAINED_FRAME")
        precondition(bound["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY")
        var altered=packet
        altered["png_sha256"]=String(repeating:"b",count:64)
        precondition((R668PlainHUDReader.audit(altered,
                            sourceKind:"LIVE_RETAINED_FRAME")["status"] as? String ?? "").hasPrefix("HOLD_"))
        altered=packet
        var snap=altered["screen_read_state"] as! [String:Any]
        var badInv=inventory
        badInv[0]["image_sha256"]=String(repeating:"c",count:64)
        snap["ocr_source_inventory"]=badInv
        altered["screen_read_state"]=snap
        precondition(R668PlainHUDReader.audit(altered,
            sourceKind:"LIVE_RETAINED_FRAME")["status"] as? String=="HOLD_CORRUPT_OCR_SOURCE")
        print("R668_PLAIN_HUD_TEST_PASS 22")
    }
}
