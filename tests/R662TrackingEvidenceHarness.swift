import Foundation
@main struct R662TrackingEvidenceHarness {
    static func main() {
        var n=0
        func check(_ value:Bool,_ label:String) {
            precondition(value,"R662_GATE_FAIL_"+label);n+=1
        }
        let gate=R662TrackingEvidenceGate.self
        let seeds=gate.seeds
        let ok="REGION_GEOMETRY_HYPOTHESIS_ONLY"
        check(gate.geometry(seeds) == ok,"good_regions")
        check(gate.geometry([]) == "HOLD_UNAPPROVED_REGION_SET","zero")
        check(gate.geometry([seeds[1],seeds[0]]) == "HOLD_UNAPPROVED_REGION_SET","swapped")
        let bad=R662TrackingEvidenceGate.Region(
            name:seeds[0].name,x:0.9,y:0.4,width:0.3,height:0.3)
        check(gate.geometry([bad,seeds[1]]) == "HOLD_REGION_GEOMETRY","outside")
        let nan=R662TrackingEvidenceGate.Region(
            name:seeds[0].name,x:Double.nan,y:0.4,width:0.3,height:0.3)
        check(gate.geometry([nan,seeds[1]]) == "HOLD_REGION_GEOMETRY","nan")
        let overlap=R662TrackingEvidenceGate.Region(
            name:seeds[1].name,x:0.3,y:0.4,width:0.3,height:0.3)
        check(gate.geometry([seeds[0],overlap]) == "HOLD_OVERLAPPING_HYPOTHESES","overlap")
        check(gate.box([0.2,0.4,0.2,0.3]) == "NORMALIZED_BOX_DIAGNOSTIC_ONLY","box")
        check(gate.box([0.9,0.4,0.2,0.3]) == "HOLD_TRACK_BOX_OUTSIDE_IMAGE","box_outside")
        check(gate.box([0,0,Double.infinity,0.1]) == "HOLD_TRACK_BOX_OUTSIDE_IMAGE","box_inf")
        let ids:[Int64]=[100,101,102,103]
        let times:[Int64]=[1000,2000,3000,4000]
        let sha=["a","b","c","d"].map{String(repeating:$0,count:64)}
        var rows=[[String:Any]]()
        for i in 0..<3 {
            rows.append(["from_frame_id":ids[i],
                "to_frame_id":ids[i+1],
                "source_sha256_from":sha[i],
                "source_sha256_to":sha[i+1],
                "diagnostic_only":true,
                "camera_or_actor_motion_distinguished":false,
                "mega_event_confirmed":false])
        }
        let join:[String:Any]=[
            "status":"HISTORICAL_CROSS_MODAL_EVIDENCE_ONLY",
            "source_join_verified":true,"pairs_checked":3,
            "region_calibrated":false,"owner_certified":false,
            "species_certified":false,"mega_event_certified":false,
            "mega_form_certified":false,
            "current_state_eligible":false,
            "battle_advice_authorized":false,
            "held_out_accuracy":"NOT_MEASURED","pairs":rows]
        func verdict(_ a:[Int64],_ t:[Int64],_ h:[String],
                     _ e:[String:Any])->String {
            gate.provenance(frameIDs:a,times:t,hashes:h,evidence:e)
        }
        check(verdict(ids,times,sha,join) == "TRACK_SOURCE_BOUND_RESEARCH_ONLY","source")
        check(verdict([1],times,sha,join) == "HOLD_FOUR_FRAME_PROVENANCE","short")
        var j=join;j["source_join_verified"]=false
        check(verdict(ids,times,sha,j) == "HOLD_R661_JOIN_UNAVAILABLE","unjoined")
        j=join;j["mega_event_certified"]=true
        check(verdict(ids,times,sha,j) == "HOLD_R661_JOIN_UNAVAILABLE","mega")
        j=join;j["owner_certified"]=true
        check(verdict(ids,times,sha,j) == "HOLD_R661_JOIN_UNAVAILABLE","owner")
        check(verdict([100,101,101,103],times,sha,join) == "HOLD_TRACK_FRAME_ORDER","duplicate")
        check(verdict(ids,[1000,2000,1000,4000],sha,join) == "HOLD_TRACK_FRAME_ORDER","time")
        var hs=sha;hs[1]=sha[0]
        check(verdict(ids,times,hs,join) == "HOLD_TRACK_FRAME_ORDER","sha_duplicate")
        var rr=rows;rr[0]["source_sha256_from"]=sha[3]
        j=join;j["pairs"]=rr
        check(verdict(ids,times,sha,j) == "HOLD_TRACK_SOURCE_MISMATCH","mismatched_hash")
        rr=rows;rr[1]["mega_event_confirmed"]=true
        j=join;j["pairs"]=rr
        check(verdict(ids,times,sha,j) == "HOLD_TRACK_SOURCE_MISMATCH","fake_mega")
        rr=rows;rr[2]["from_frame_id"] = true
        j=join;j["pairs"]=rr
        check(verdict(ids,times,sha,j) == "HOLD_TRACK_SOURCE_MISMATCH","boolean_id")
        check(gate.schema == "trueplan.r662.region-track-fence.v1","schema")
        print("R662_REGION_TRACK_FENCE_PASS",n)
    }
}
