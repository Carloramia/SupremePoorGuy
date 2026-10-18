"""Package Bird sheets non-destructively; only derived Bird outputs are written.
Uses the existing approved pixel alpha cleanup and built-in AI occlusion edits.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import hashlib, importlib.util, json, math, shutil, sys
import numpy as np

sys.dont_write_bytecode = True
P = next(p for p in Path(__file__).resolve().parents if (p/'project.godot').is_file())
S = P/'Assets/2DResources/Bird'
OUT = P/'Assets/3DResources/Creatures/Bird'
spec = importlib.util.spec_from_file_location('bird_cleanup', P/'Assets/3DResources/Creatures/Human/Tools/prepare_assets.py')
cleanup = importlib.util.module_from_spec(spec); spec.loader.exec_module(cleanup)
spec = importlib.util.spec_from_file_location('bird_holes', P/'Assets/3DResources/Creatures/Rats/Tools/prepare_assets.py')
helpers = importlib.util.module_from_spec(spec); spec.loader.exec_module(helpers)
JOBS = []


def add(v, name, box=None, inlet=None, outlet=None, polygon=None, raw=None, native_width=None):
    role = name.split('/')[0]
    tags = {'Torso':[0], 'Head':[3], 'Wings':[7,8], 'Feathers':[9], 'Legs':[5], 'Feet':[1], 'Tail':[10], 'Decorations':[]}[role]
    if 'Fan' in name and role == 'Wings': tags = [7,9]
    JOBS.append(dict(set=v, key=f'Bird_{v}/{name}', file=f'Bird_{v}/{name}.png', role=role,
                     name=name.split('/')[-1], category=f'Bird_{v}/{role}', source_box=box,
                     inlet=inlet, outlet=outlet, polygon=polygon, raw=raw, native_width=native_width, tags=tags))


def definitions():
    add(1,'Head/HeadMain',(643,34,881,258),(843,191),(843,232))
    add(1,'Torso/TorsoMain',raw='bird1_TorsoClean.png',native_width=495,inlet=[.52,.58],outlet=[.68,.12])
    add(1,'Wings/RootLeft',(405,8,636,135),(607,83),(509,53),[(408,9),(518,30),(635,55),(638,98),(572,133),(477,101),(428,54)])
    add(1,'Wings/RootRight',(923,10,1179,146),(950,99),(1152,36))
    add(1,'Wings/FanLeft',raw='bird1_WingFanLeft.png',native_width=590,inlet=[.96,.55],outlet=[.06,.13])
    add(1,'Wings/FanRight',raw='bird1_WingFanRight.png',native_width=510,inlet=[.25,.28],outlet=[.93,.14])
    add(1,'Feathers/TipFanLeft',(268,209,543,408),(515,234),(301,357))
    add(1,'Feathers/TipFanRight',(1028,269,1310,434),(1050,289),(1270,368))
    upper=[((77,571,257,752),(237,592),(101,733),[(185,580),(239,572),(257,593),(247,615),(216,642),(207,694),(154,740),(112,751),(78,739),(78,715),(137,663)]),
           ((230,571,365,756),(336,603),(261,723),[(327,573),(352,574),(367,594),(350,653),(305,704),(285,750),(253,754),(231,729),(241,701),(283,660)]),
           ((388,506,473,710),(430,543),(411,680),[(405,517),(430,505),(455,526),(470,547),(471,632),(443,665),(434,699),(411,710),(390,690),(388,666),(398,606)]),
           ((937,506,1028,723),(980,543),(1005,697),[(958,510),(985,506),(1001,532),(1016,567),(1018,651),(1027,696),(1013,720),(987,723),(968,697),(940,650),(938,564)]),
           ((1027,569,1185,721),(1054,602),(1153,696),[(1047,572),(1072,570),(1096,600),(1131,640),(1167,673),(1185,692),(1176,715),(1152,721),(1129,699),(1072,673),(1034,641),(1027,608)]),
           ((1187,580,1377,755),(1247,614),(1346,730),[(1188,596),(1209,580),(1254,588),(1272,608),(1277,652),(1328,694),(1363,710),(1377,735),(1362,751),(1337,755),(1295,734),(1245,695),(1226,643),(1196,626)])]
    lower=[((24,707,131,992),(101,733),(35,970),[(101,707),(121,718),(132,766),(87,842),(78,907),(34,991),(24,973),(26,838),(72,755),(78,725)]),
           ((232,701,338,992),(261,723),(330,970),[(260,701),(282,708),(304,754),(318,789),(303,824),(331,922),(338,991),(312,962),(275,914),(263,833),(237,785),(232,732)]),
           ((387,654,612,982),(411,680),(600,967),[(409,654),(438,665),(508,738),(511,796),(550,835),(589,914),(612,982),(583,963),(526,924),(470,849),(442,760),(389,701)]),
           ((846,671,1028,990),(1005,697),(858,971),[(1000,671),(1025,686),(1028,710),(955,774),(963,827),(915,897),(847,990),(860,941),(879,865),(910,818),(917,751),(973,700)]),
           ((1092,673,1192,983),(1153,696),(1139,962),[(1153,673),(1177,682),(1185,709),(1152,767),(1192,819),(1179,889),(1137,983),(1124,954),(1126,854),(1093,799),(1112,737),(1128,694)]),
           ((1318,704,1428,1002),(1346,730),(1420,981),[(1346,704),(1371,714),(1382,743),(1394,799),(1418,871),(1428,1002),(1414,977),(1373,900),(1362,828),(1322,770),(1318,737)])]
    for i,(b,a,z,poly) in enumerate(upper,1): add(1,f'Legs/Variant{i:02d}Upper',b,a,z,poly)
    for i,(b,a,z,poly) in enumerate(lower,1): add(1,f'Legs/Variant{i:02d}Lower',b,a,z,poly)
    add(1,'Legs/ThighLeft',(203,439,426,586),(402,475),(347,463))
    add(1,'Legs/ThighRight',(1007,447,1239,580),(1027,491),(1096,470))
    add(1,'Legs/BodyLinkUpper',(473,401,632,592),(494,423),(555,493),[(494,401),(523,415),(552,447),(579,457),(591,491),(632,574),(614,592),(574,559),(533,525),(493,486),(474,443)])
    add(1,'Legs/BodyLinkLower',(606,506,683,716),(643,530),(633,696),[(633,506),(655,511),(670,542),(672,585),(682,622),(655,673),(654,702),(638,716),(617,711),(606,692),(610,655),(620,606),(615,551)])
    add(1,'Legs/ClawLinkRight',(779,629,860,754),(800,665),(842,732),[(798,629),(813,641),(832,689),(857,716),(860,738),(841,753),(815,740),(793,708),(779,666)])
    add(1,'Feet/ClawLeft',(604,718,726,909),(634,739),(657,858))
    add(1,'Feet/ClawRight',(745,711,876,881),(842,732),(806,831))
    add(1,'Decorations/Rivet',(315,1007,358,1055),(336,1029),(336,1029))

    add(2,'Head/HeadMain',(678,39,982,330),(830,306),(821,240))
    add(2,'Torso/TorsoMain',(687,312,978,677),(835,654),(832,370))
    add(2,'Wings/RootLeft',(385,26,694,356),(659,311),(578,145),[(385,27),(458,48),(533,68),(574,98),(597,138),(617,205),(649,264),(681,283),(694,311),(683,338),(655,356),(610,347),(574,319),(554,278),(540,218),(497,191),(451,170),(422,119),(400,72)])
    add(2,'Wings/RootRight',(975,25,1292,356),(1011,312),(1097,145),[(1292,27),(1217,47),(1142,66),(1099,97),(1075,136),(1055,204),(1024,264),(989,284),(975,311),(986,339),(1015,356),(1061,347),(1098,318),(1118,277),(1134,217),(1175,190),(1222,168),(1255,118),(1277,70)])
    add(2,'Wings/FanLeft',raw='bird2_WingFanLeft.png',native_width=528,inlet=[.65,.07],outlet=[.04,.32])
    add(2,'Wings/FanRight',raw='bird2_WingFanRight.png',native_width=528,inlet=[.35,.07],outlet=[.96,.32])
    add(2,'Feathers/CovertsLeft',(525,369,697,512),(671,397),(548,471))
    add(2,'Feathers/CovertsRight',(975,369,1148,512),(1004,397),(1120,471))
    add(2,'Feathers/FlightLeft01',(60,17,405,104),(380,77),(79,44))
    add(2,'Feathers/FlightLeft02',(5,96,366,186),(341,123),(25,155))
    add(2,'Feathers/FlightRight01',(1262,17,1613,104),(1285,77),(1597,45))
    add(2,'Feathers/FlightRight02',(1303,96,1672,186),(1323,123),(1642,155))
    upper=[((104,474,275,642),(249,499),(125,615)),((233,500,379,649),(354,525),(258,625)),((358,479,487,642),(460,509),(381,622)),((474,526,613,650),(590,548),(496,624)),
           ((1054,526,1195,649),(1077,548),(1171,624)),((1186,480,1313,644),(1212,509),(1289,622)),((1297,500,1443,649),(1319,525),(1414,625)),((1404,474,1574,642),(1427,499),(1549,615))]
    lower=[((25,610,129,860),(106,625),(36,841)),((195,626,258,888),(232,643),(204,870)),((350,643,420,847),(370,658),(408,829)),((483,643,578,815),(509,659),(566,796)),
           ((1091,643,1188,815),(1163,659),(1103,796)),((1250,643,1321,847),(1302,658),(1264,829)),((1414,626,1479,888),(1440,643),(1468,870)),((1543,610,1648,860),(1565,625),(1638,841))]
    for i,(b,a,z) in enumerate(upper,1): add(2,f'Legs/Variant{i:02d}Upper',b,a,z)
    for i,(b,a,z) in enumerate(lower,1): add(2,f'Legs/Variant{i:02d}Lower',b,a,z)
    add(2,'Feet/ClawLeft',(647,614,789,791),(766,639),(719,732))
    add(2,'Feet/ClawRight',(898,614,1028,797),(918,639),(965,741))
    add(2,'Decorations/Rivet',(463,869,500,906),(481,887),(481,887))

    add(3,'Head/HeadMain',(574,9,834,319),(679,279),(777,171))
    add(3,'Torso/TorsoMain',raw='bird3_TorsoClean.png',native_width=450,inlet=[.50,.60],outlet=[.53,.10])
    add(3,'Tail/TailMain',raw='bird3_BodyTail.png',native_width=220,inlet=[.21,.10],outlet=[.84,.90])
    add(3,'Tail/TailFan',(1045,425,1644,681),(1077,451),(1578,462),[(1070,425),(1098,430),(1175,469),(1334,488),(1597,438),(1594,466),(1515,532),(1557,563),(1644,568),(1627,593),(1541,632),(1479,650),(1548,665),(1498,681),(1383,666),(1225,611),(1122,558),(1086,530),(1055,489),(1045,452)])
    add(3,'Wings/RootLeft',(344,18,581,309),(556,281),(529,126))
    add(3,'Wings/RootRight',(936,18,1255,343),(966,309),(1040,133))
    add(3,'Wings/FanLeft',(4,184,565,494),(387,215),(475,301))
    add(3,'Wings/FanRight',(1037,183,1619,452),(1212,214),(1130,296))
    add(3,'Feathers/FlightLeft01',(31,22,361,119),(330,89),(53,48))
    add(3,'Feathers/FlightLeft02',(8,94,368,183),(338,154),(26,147))
    add(3,'Feathers/FlightRight01',(1210,23,1618,117),(1238,88),(1597,45))
    add(3,'Feathers/FlightRight02',(1205,94,1663,183),(1236,154),(1638,146))
    thighs=[((426,460,590,700),(561,491),(559,672),[(556,460),(582,470),(590,503),(573,570),(545,636),(567,646),(586,666),(580,687),(557,700),(531,690),(492,667),(459,681),(450,657),(425,656),(451,609),(461,554),(512,486)]),
            ((585,539,742,701),(617,566),(698,677),[(609,539),(637,554),(665,580),(711,598),(740,624),(735,649),(715,658),(719,680),(706,700),(684,700),(671,680),(661,663),(618,649),(595,624),(585,574)]),
            ((876,590,989,711),(913,615),(959,683),[(906,591),(930,600),(941,629),(957,654),(983,669),(989,691),(974,710),(953,711),(932,694),(895,689),(879,666),(876,637),(887,609)]),
            ((1114,550,1268,671),(1139,578),(1237,648))]
    feet=[((352,649,586,836),(559,672),(432,787),[(550,649),(576,656),(587,679),(561,710),(527,754),(551,782),(530,811),(475,818),(438,835),(394,829),(353,811),(352,758),(389,735),(453,741),(501,700),(530,672)]),
          ((575,650,740,862),(698,677),(649,809),[(692,650),(715,656),(721,683),(713,708),(699,746),(720,766),(740,793),(734,821),(711,836),(677,838),(653,860),(613,855),(584,837),(575,797),(588,775),(620,778),(655,738),(672,694)]),
          ((846,658,989,859),(959,683),(922,811),[(952,658),(976,667),(989,689),(978,722),(967,766),(984,786),(989,820),(969,841),(930,855),(897,859),(870,840),(846,829),(847,792),(870,773),(893,782),(922,735),(932,695)]),
          ((1149,666,1337,870),(1237,696),(1241,824))]
    for i,(b,a,z,*poly) in enumerate(thighs,1): add(3,f'Legs/Variant{i:02d}Upper',b,a,z,poly[0] if poly else None)
    for i,(b,a,z,*poly) in enumerate(feet,1): add(3,f'Feet/Claw{i:02d}',b,a,z,poly[0] if poly else None)
    add(3,'Decorations/Rivet',(387,875,429,917),(408,895),(408,895))


def package(image):
    data=np.array(image.convert('RGBA')); rgb=data[:,:,:3].astype(np.int16)
    inside=np.array(Image.fromarray((data[:,:,3]>=128).astype(np.uint8)*255).filter(ImageFilter.MinFilter(7)))>0
    vivid=(rgb[:,:,0]>220)&(rgb[:,:,2]<65)&((rgb[:,:,1]<70)|(rgb[:,:,1]>190))
    data[vivid & ~inside,3]=0
    data[data[:,:,3]<128,3]=0
    # Every final file is one connected component/overlapping feather assembly.
    # Neighbor fragments can be large, so the generic multi-part cutoff is insufficient.
    keep=helpers.largest_component(data[:,:,3]>=128); data[~keep,3]=0
    data[data[:,:,3]==0,:3]=0
    image=Image.fromarray(data); box=image.getchannel('A').getbbox(); assert box
    image=image.crop(box)
    result=Image.new('RGBA',(image.width+24,image.height+24)); result.alpha_composite(image,(12,12))
    return result,box


def main():
    definitions(); records=[]
    repairs=S/'Metadata/small_repair_settings.json'
    if repairs.exists():
        replacements=json.loads(repairs.read_text(encoding='utf-8'))
        for job in JOBS:
            if job['key'] in replacements: job.update(replacements[job['key']])
    for v in range(1,4):
        original=P/f'Assets/2DResources/AIGenerated/Unprocessed/Bird/Bird_{v}.png'
        dest=S/'Originals'/original.name; dest.parent.mkdir(parents=True,exist_ok=True)
        if not dest.exists(): shutil.copyfile(original,dest)
        assert hashlib.sha256(original.read_bytes()).digest()==hashlib.sha256(dest.read_bytes()).digest()
    for job in JOBS:
        if job['raw']:
            raw=S/'RawEdits'/job['raw']; image,_=cleanup.clean(raw)
            bounds=image.getchannel('A').getbbox(); image=image.crop(bounds)
            scale=job['native_width']/image.width
            image=image.resize((job['native_width'],round(image.height*scale)),Image.Resampling.LANCZOS)
            image,box=package(image)
            bounds=image.getchannel('A').getbbox(); x0,y0,x1,y1=bounds
            anchors=[[x0+q[0]*(x1-x0),y0+q[1]*(y1-y0)] for q in [job['inlet'],job['outlet']]]
            holes=helpers.hole_centers(image)
            for j,a in enumerate(anchors):
                if holes:
                    nearest=min(holes,key=lambda h:math.dist(a,h))
                    if math.dist(a,nearest)<min(x1-x0,y1-y0)*.22: anchors[j]=nearest
            origin='built_in_imagegen_occlusion_completion'; raw_source='res://'+raw.relative_to(P).as_posix()
        else:
            original=S/'Originals'/f'Bird_{job["set"]}.png'; box=job['source_box']
            image=Image.open(original).convert('RGBA').crop(box)
            if job['polygon']:
                mask=Image.new('L',image.size)
                ImageDraw.Draw(mask).polygon([(x-box[0],y-box[1]) for x,y in job['polygon']],fill=255)
                data=np.array(image); data[:,:,3]=np.minimum(data[:,:,3],np.array(mask)); image=Image.fromarray(data)
            crop_path=S/'SourceCrops'/f'{job["key"]}.png'; crop_path.parent.mkdir(parents=True,exist_ok=True); image.save(crop_path)
            image,trim=package(image)
            anchors=[[q[0]-box[0]-trim[0]+12,q[1]-box[1]-trim[1]+12] for q in [job['inlet'],job['outlet']]]
            origin='original_pixel_crop'; raw_source='res://'+original.relative_to(P).as_posix()
        dest=S/'Separated'/job['file']; dest.parent.mkdir(parents=True,exist_ok=True); image.save(dest)
        assert image.getpixel((0,0))[3]==0
        bounds=image.getchannel('A').getbbox(); x0,y0,x1,y1=bounds
        normalized=[[(q[0]-x0)/(x1-x0),(q[1]-y0)/(y1-y0)] for q in anchors]
        assert all(-.2<=c<=1.2 for q in normalized for c in q),(job['key'],normalized)
        records.append({k:job[k] for k in ['set','key','file','name','role','category','tags','source_box','polygon']} | dict(
            joint_in=normalized[0],joint_out=normalized[1],joint_pixels=anchors,units_per_pixel=.01,
            origin=origin,raw_source=raw_source,texture_size=list(image.size),mass=1.0 if job['role']=='Torso' else .1,
            sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),marker_status='initial_art_reference'))
    assert len({r['key'] for r in records})==len(records)
    for path,data in [(OUT/'Metadata/build_settings.json',dict(thickness=.08,parts=records)),
                      (S/'Separated/asset_manifest.json',dict(count=len(records),source_sheets_untouched=True,parts=records))]:
        path.parent.mkdir(parents=True,exist_ok=True); path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for v in range(1,4): overview([r for r in records if r['set']==v],S/'Metadata'/f'Bird_{v}_PartsOverview.png')
    overview(records,S/'Metadata/PartsOverview.png')
    print('PASS:',len(records),'Bird cutouts;',dict((v,sum(r['set']==v for r in records)) for v in range(1,4)))


def overview(records,path):
    cw,ch,cols=260,236,6
    result=Image.new('RGB',(cols*cw,math.ceil(len(records)/cols)*ch),(230,230,230)); draw=ImageDraw.Draw(result)
    try: font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',14)
    except OSError: font=ImageFont.load_default()
    for i,r in enumerate(records):
        x,y=i%cols*cw,i//cols*ch
        for cy in range(y,y+196,16):
            for cx in range(x,x+cw,16): draw.rectangle((cx,cy,cx+15,cy+15),fill=(212,216,222) if (cx//16+cy//16)%2 else (241,241,241))
        image=Image.open(S/'Separated'/r['file']); image.thumbnail((cw-20,186),Image.Resampling.LANCZOS)
        result.paste(image,(x+(cw-image.width)//2,y+(196-image.height)//2),image)
        draw.text((x+7,y+201),r['key'].split('/',1)[1],font=font,fill=(25,25,25))
        draw.text((x+7,y+219),f'Bird_{r["set"]} | '+r['origin'].split('_')[0],font=font,fill=(80,80,80))
    result.save(path)


if __name__=='__main__': main()
