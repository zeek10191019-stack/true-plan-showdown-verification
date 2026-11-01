"""Independent integer geometry audit. PNG hashes do not prove game orientation."""

def need(condition,reason):
    if not condition:raise ValueError('PROJECTION_'+reason)

def integer(value,minimum=0,maximum=3072):
    return type(value) is int and minimum<=value<=maximum

def rect(value,width,height):
    return (isinstance(value,dict) and set(value)=={'x','y','width','height'} and
            integer(value['x']) and integer(value['y']) and integer(value['width'],1) and integer(value['height'],1) and
            value['x']+value['width']<=width and value['y']+value['height']<=height)

def source_rect(value,crop,turn):
    x,y,w,h=(value[k] for k in ('x','y','width','height'))
    cw,ch=crop['width'],crop['height']
    # Independently derive inverse edge coordinates from each transformed corner.
    corners=[]
    for u,v in [(x,y),(x+w,y),(x,y+h),(x+w,y+h)]:
        if turn==0:a,b=u,v
        elif turn==1:a,b=cw-v,u
        elif turn==2:a,b=cw-u,ch-v
        else:a,b=v,ch-u
        corners.append((a+crop['x'],b+crop['y']))
    xs,ys=zip(*corners)
    return dict(x=min(xs),y=min(ys),width=max(xs)-min(xs),height=max(ys)-min(ys))

def validate_projection(p,selected,packet):
    need(isinstance(p,dict) and packet is not None,'MISSING_PACKET')
    need(p.get('schema')=='trueplan.screen-read.analysis-projection.v1' and
         p.get('status')=='DECLARED_GEOMETRY_ONLY' and
         p.get('reason')=='OCR_MEANING_AND_PER_FRAME_PIXEL_EQUALITY_UNCERTIFIED','SCHEMA_OR_STATUS')
    for key in ['pixel_equality_verified','game_orientation_certified','owner_certified','current_state_eligible','battle_advice_authorized']:
        need(p.get(key) is False,'FALSE_CERTIFICATION_'+key)
    need(p.get('battle_id') is None and p.get('turn') is None,'GAME_IDENTITY')
    for report_key,source_key in [('capture_session_id','capture_session_id'),('frame_id','frame_id'),('epoch','epoch'),('receipt_uptime_ms','observed_ms_monotonic')]:
        need(p.get(report_key)==selected[source_key] and type(p.get(report_key)) is type(selected[source_key]),'SOURCE_IDENTITY')
    analysis=selected.get('analysis_image')
    need(isinstance(analysis,dict),'ANALYSIS_IMAGE')
    need(p.get('raw_image_sha256')==selected['png_sha256'] and p.get('analysis_image_sha256')==analysis['png_sha256'],'IMAGE_BINDING')
    rw,rh=p.get('raw_width'),p.get('raw_height')
    need(integer(rw,1) and integer(rh,1) and rw*rh<=4_500_000 and rw==selected['image_width'] and rh==selected['image_height'],'RAW_DIMENSIONS')
    crop=p.get('pixel_crop');need(rect(crop,rw,rh),'CROP_BOUNDS')
    turn=p.get('quarter_turns_ccw');need(integer(turn,0,3),'ROTATION')
    aw,ah=(crop['width'],crop['height']) if turn%2==0 else (crop['height'],crop['width'])
    need(type(p.get('analysis_width')) is int and type(p.get('analysis_height')) is int and
         p['analysis_width']==aw==analysis['width'] and p['analysis_height']==ah==analysis['height'],'ANALYSIS_DIMENSIONS')
    need(p.get('coordinate_convention')=='HALF_OPEN_PIXELS_TOP_LEFT' and p.get('transform')=='INTEGER_CROP_THEN_CCW_QUARTER_TURN','CONVENTION')
    expected,omitted=[],[]
    rows=packet.get('readings');need(isinstance(rows,list) and len(rows)<=512,'READINGS')
    need(all(isinstance(row,dict) for row in rows),'READING_TYPES')
    for index,row in enumerate(rows):
        if row.get('reason')!='FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND':continue
        reference=f'payload_json.readings[{index}]'
        roi=row.get('roi_rect')
        bound=(type(row.get('source_frame_id')) is int and row['source_frame_id']==selected['frame_id'] and
               type(row.get('source_epoch')) is int and row['source_epoch']==selected['epoch'] and
               row.get('source_image_sha256')==analysis['png_sha256'] and row.get('roi_owner_certified') is False and
               row.get('roi_source')=='VISION_FIRST_PASS_GEOMETRY_UNCERTIFIED' and rect(roi,aw,ah))
        if bound:expected.append({'evidence_ref':reference,'analysis_rect':roi,'raw_rect':source_rect(roi,crop,turn)})
        else:omitted.append({'evidence_ref':reference,'reason':'ROI_MISSING_OR_UNBOUND'})
    need(p.get('mapped_rois')==expected and p.get('omitted_rois')==omitted,'ROI_COVERAGE_OR_TRANSFORM')
    # Equality alone would allow True == 1 in a nested rectangle.
    for row in p['mapped_rois']:
        need(rect(row['analysis_rect'],aw,ah) and rect(row['raw_rect'],rw,rh),'ROI_TYPE_OR_BOUNDS')
    return {'status':'DECLARED_GEOMETRY_AUDIT_PASS','mapped_rois':len(expected),
            'omitted_rois':len(omitted),'pixel_equality_verified':False,'game_orientation_certified':False}
