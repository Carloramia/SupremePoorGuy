from pathlib import Path
from PIL import Image, ImageDraw
import json
P=next(p for p in Path(__file__).resolve().parents if (p/'project.godot').is_file())
S=P/'Assets/2DResources/Human/Separated'
jobs=json.loads((S/'generation_jobs.json').read_text(encoding='utf-8'))['specs']
crops={
'human1_forearm_left':(1,(201,414,289,594)),
'human1_forearm_right':(1,(973,475,1160,594)),
'human1_hand_left':(1,(195,557,288,695)),
'human1_hand_right':(1,(1134,530,1244,635)),
'human2_hand_left':(2,(125,516,239,677)),
'human2_hand_right':(2,(1047,551,1208,733)),
'human2_upper_leg_right':(2,(776,625,1046,849)),
'human3_forearm_right':(3,(1026,447,1170,620)),
'human2_leaf_branch_left':(2,(100,180,304,551)),
'human2_leaf_branch_right':(2,(992,296,1174,562))}
(S/'SourceCrops').mkdir(exist_ok=True)
for key,(i,box) in crops.items():
    src=P/f'Assets/2DResources/AIGenerated/Unprocessed/Human/Humanoid_{i}.png'
    Image.open(src).crop(box).save(S/'SourceCrops'/f'{key}.png')
for i in (1,2,3):
    group=[j for j in jobs if j['set']==i]
    canvas=Image.new('RGB',(1800,((len(group)+4)//5)*260),(218,222,228))
    d=ImageDraw.Draw(canvas)
    for n,j in enumerate(group):
        im=Image.open(S/'RawEdits'/f"{j['key']}.png").convert('RGBA')
        b=im.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
        im=im.crop(b)
        im.thumbnail((340,220))
        x=(n%5)*360+(360-im.width)//2;y=(n//5)*260
        canvas.paste(im,(x,y),im)
        d.text(((n%5)*360+8,y+228),j['key'],fill=(15,20,30))
    canvas.save(S/f'RawReview{i}.jpg',quality=90)
print('Prepared source crops and raw review sheets')

