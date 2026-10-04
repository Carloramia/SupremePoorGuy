from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math, random, subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'玩法演示'; OUT.mkdir(exist_ok=True)
W,H,FPS,LENGTH=1280,720,20,66
FONT='C:/Windows/Fonts/msyh.ttc'
F={s:ImageFont.truetype(FONT,s) for s in [15,16,18,20,22,24,28,32]}
BG='#122029'; PANEL='#20333d'; WHITE='#f0ede0'; MUTE='#acbab8'; GOLD='#f1c67b'; GREEN='#96d4b2'; RED='#e5a28d'
A=(.13,.74); B=(.68,.20); C=(.34,.535); D=(.45,.73); E=(.84,.36); Q=(.65,.53)
def clamp(p): return max(0,min(1,p))
def mix(a,b,p): return tuple(x+(y-x)*p for x,y in zip(a,b))
def txt(d,p,s,n=20,c=WHITE): d.text(p,s,font=F[n],fill=c)
def dashed(d,a,b,c=GOLD):
    distance=math.dist(a,b)
    for k in range(0,int(distance),22): d.line([mix(a,b,k/max(distance,1)),mix(a,b,min(1,(k+12)/max(distance,1)))],fill=c,width=4)
def pin(d,p,c=GREEN,r=8):
    x,y=p; d.ellipse((x-r-5,y-r-5,x+r+5,y+r+5),outline=c,width=2); d.ellipse((x-r,y-r,x+r,y+r),fill=c)
def pill(d,box,s,c=GOLD):
    d.rounded_rectangle(box,8,fill='#253b42',outline=c,width=2); txt(d,(box[0]+15,box[1]+10),s,20,c)
def button(d,y,s,on=False):
    d.rounded_rectangle((971,y,1218,y+43),8,fill=GOLD if on else '#304a55',outline=GOLD if on else '#516b70',width=2)
    width=d.textbbox((0,0),s,font=F[20])[2]; txt(d,(1094-width/2,y+9),s,20,BG if on else WHITE)

# Point-to-hex classification is internal only. No cell edges or grid-center paths are drawn.
radius=86
centers=[(75+1.5*radius*i,42+math.sqrt(3)*radius*(j+.5*(i%2))) for i in range(8) for j in range(4)]
def cell(p):
    point=(p[0]*883,p[1]*467)
    return min(range(len(centers)),key=lambda i:math.dist(point,centers[i]))
def location(p):
    if cell(p)==cell(E): return '赤岩遗迹','【干旱】【沙】','高难度 · 守护 Boss'
    if cell(p)==cell(Q): return '赤岩山道','【干旱】【沙】','中高难度 · 可能伏击'
    if cell(p)==cell(D): return '苍林洞穴外围','【潮湿】','低难度 · 当地怪物'
    return ('苍林边地','【潮湿】','低难度') if p[0]<.58 else ('赤岩荒野','【干旱】【沙】','中高难度')

rng=random.Random(17)
trees=[(rng.uniform(.035,.535),rng.uniform(.20,.94),rng.uniform(8,15)) for _ in range(62)]
mountains=[(rng.uniform(.62,.97),rng.uniform(.16,.87),rng.uniform(13,26)) for _ in range(26)]
def world(p,zoom,discovered):
    im=Image.new('RGB',(883,467),'#c6bd9a'); d=ImageDraw.Draw(im)
    def xy(q): return ((q[0]-.42)*883*zoom+.42*883,(q[1]-.56)*467*zoom+.56*467)
    d.polygon([xy(q) for q in [(0,0),(.48,0),(.58,.17),(.52,.48),(.57,.76),(.45,1),(0,1)]],fill='#829879')
    d.polygon([xy(q) for q in [(.65,0),(1,0),(1,1),(.58,1),(.62,.70),(.58,.36)]],fill='#b5a17f')
    river=[xy(q) for q in [(.54,0),(.57,.16),(.52,.37),(.57,.57),(.52,.78),(.56,1)]]
    d.line(river,fill='#5d777c',width=int(23*zoom)); d.line(river,fill='#a5c1b9',width=int(13*zoom))
    # Natural routes are scenic details, not restrictions on player movement.
    road=[xy(q) for q in [(.13,.74),(.22,.46),(.38,.40),(.63,.49),(.84,.36)]]
    d.line(road,fill='#968364',width=5)
    for x,y,r in trees:
        xx,yy=xy((x,y)); r*=zoom
        d.line((xx,yy,xx,yy+r+5),fill='#3e5c4d',width=3)
        d.polygon([(xx,yy-r),(xx-r*.7,yy+r*.5),(xx+r*.7,yy+r*.5)],fill='#526f53',outline='#b1bc8b')
    for x,y,r in mountains:
        xx,yy=xy((x,y)); r*=zoom
        d.polygon([(xx-r,yy+r*.65),(xx,yy-r),(xx+r,yy+r*.65)],fill='#897b65',outline='#ded0a4')
        d.line([(xx-r*.5,yy+r*.4),(xx,yy-r),(xx+r*.4,yy+r*.3)],fill='#6c6356',width=2)
    def marker(q,name,kind):
        x,y=xy(q)
        if kind=='town':
            d.rectangle((x-13,y-9,x+13,y+12),fill='#e8d8b2',outline='#443f36',width=2)
            d.polygon([(x-17,y-9),(x,y-25),(x+17,y-9)],fill='#6c5948',outline='#443f36')
        elif kind=='wonder':
            d.polygon([(x,y-24),(x+14,y),(x,y+19),(x-14,y)],fill='#edf0cc',outline='#544f3b')
        elif kind=='ruin':
            d.rectangle((x-17,y-13,x+17,y+13),fill='#d8c291',outline='#554b40',width=2)
            for off in [-11,2]: d.rectangle((x+off,y-24,x+off+8,y+11),fill='#b4a17c',outline='#554b40')
        else:
            d.pieslice((x-19,y-24,x+19,y+17),180,360,fill='#e0d7b5',outline='#473f33',width=3)
            d.ellipse((x-10,y-12,x+10,y+4),fill='#3f4c3d')
        tw=d.textbbox((0,0),name,font=F[18])[2]
        d.rounded_rectangle((x-tw/2-7,y+19,x+tw/2+7,y+48),5,fill='#354a43')
        txt(d,(x-tw/2,y+21),name,18)
    marker((.17,.36),'城镇','town'); marker((.38,.16),'奇观','wonder'); marker(E,'赤岩遗迹','ruin')
    if discovered: marker((.455,.76),'已发现：洞穴','cave')
    txt(d,(23,20),'苍林',24,'#243d32'); txt(d,(662,24),'赤岩荒野',24,'#594c38')
    return im,xy

def square(d,p,c,hp=1,size=19):
    x,y=p; d.ellipse((x-size-8,y+size-1,x+size+8,y+size+13),outline=c,width=2)
    d.rounded_rectangle((x-size,y-size,x+size,y+size),4,fill=c,outline=WHITE,width=2)
    d.rectangle((x-size,y-size-12,x+size,y-size-7),fill='#1c292b')
    if hp>0: d.rectangle((x-size,y-size-12,x-size+2*size*hp,y-size-7),fill=c)
def battle(d,t,start,end,boss=False):
    p=clamp((t-start)/(end-start)); alive=p<1
    for i in range(3):
        q=mix((190,348+i*64),(430,348+i*52),min(.9,p*2))
        square(d,q,GREEN,max(.35,1-.5*p))
        if .15<p<1 and int(t*5+i)%3==0: d.line([q,(610 if boss else 530,400 if boss else 348+i*52)],fill=GOLD,width=3)
    if alive:
        if boss: square(d,(610,407),RED,1-p,45); txt(d,(541,471),'守护 Boss',20,RED)
        else:
            for i in range(3): square(d,mix((727,348+i*64),(530,348+i*52),min(.9,p*2)),RED,1-p)
    txt(d,(78,546),'我方与敌方自主索敌、移动、攻击 · 方块仅为玩法占位',18,MUTE)
def summon(d,t,start,guide=False):
    p=clamp((t-start)/2); center=(450,406); rr=83
    d.arc((center[0]-rr,center[1]-rr,center[0]+rr,center[1]+rr),-90,-90+max(1,360*p),fill=GOLD,width=4)
    if p>=1:
        points=[(450+rr*math.cos(a*math.pi/180),406+rr*math.sin(a*math.pi/180)) for a in [0,144,288,72,216,0]]
        d.line(points,fill=GOLD,width=3); square(d,(450,406),GREEN,.9,23)
        txt(d,(383,512),'示例召唤产出',20,GREEN)
    if guide:
        d.polygon([(450,374),(463,394),(450,414),(437,394)],fill=GOLD,outline=WHITE)
        pill(d,(605,330,881,383),'引导物已配置 · 不消耗')
    txt(d,(76,553),'地点词条参与产出；形态与权重尚未定案',18,MUTE)

def render(t):
    im=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(im)
    txt(d,(38,20),'探索与当地召唤 · 玩法示意 v02',28)
    txt(d,(1005,29),'概念动画 / 非实录',18,MUTE)
    steps=['自由移动','探索与召唤','伏击战斗','Boss 与引导物']
    st=0 if t<26 else 1 if t<36 else 2 if t<48 else 3
    for i,s in enumerate(steps):
        x=40+i*305; d.rounded_rectangle((x,77,x+290,115),7,fill=GOLD if st==i else PANEL)
        txt(d,(x+18,84),f'{i+1:02d}  {s}',18,BG if st==i else MUTE)
    if t<9: pos=A; mins=0; state='观察地图'
    elif t<14: p=clamp((t-10)/4); pos=mix(A,C,p); mins=round(30*p); state='移动中'
    elif t<20: pos=C; mins=30; state='移动已暂停'
    elif t<24: p=clamp((t-20)/4); pos=mix(C,D,p); mins=30+round(18*p); state='移动中'
    elif t<36: pos=D; mins=48; state='小地图探索'
    elif t<40: p=clamp((t-36)/3); pos=mix(D,Q,p); mins=48+round(28*p); state='遭遇伏击' if t>=39 else '移动中'
    elif t<45: pos=Q; mins=76; state='战斗准备' if t<41 else '自动战斗' if t<44 else '战斗结算'
    elif t<48: p=clamp((t-45)/3); pos=mix(Q,E,p); mins=76+round(22*p); state='移动中'
    else: pos=E; mins=98; state='战斗准备' if t<49 else '守护 Boss 战斗' if t<53 else '引导物已获得'
    magic=0 if t<30 else 30 if t<34 else 20 if t<44 else 40 if t<53 else 60 if t<56 else 50 if t<60 else 40
    guide=t>=53; local=26<=t<36 or 40<=t<45 or 48<=t<62
    name,tags,risk=location(pos)
    if t<6: cap='完整地图，没有格线；城镇、奇观直接可见，未知洞穴暂不显示。'
    elif t<9: cap='缩放只改变观察尺度；移动不受隐藏地块边界限制。'
    elif t<14: cap='点击行动自由移动：已走部分实线，尚未走过部分虚线。'
    elif t<17: cap='空格暂停：位置与已走路线保留，旅行时间暂时停止。'
    elif t<20: cap='选择新目的地：替换剩余虚线，从暂停位置改道。'
    elif t<22: cap='继续自由移动；不会沿六边形格中心逐格移动，也不显示格子边界。'
    elif t<24: cap='靠近探索后发现洞穴：具体位置出现，之后保留发现标记。'
    elif t<27: cap='进入当前区域：只按当前位置所属的隐藏六边形，确定小地图。'
    elif t<30: cap='与当地怪物自动战斗，不需要采集点或逐件拾取。'
    elif t<31: cap='战斗掉落自动结算并统一兑换魔力：本次 +30。'
    elif t<36: cap='在当地绘制召唤阵：消耗魔力，地点词条参与影响产出。'
    elif t<39: cap='返回原位置继续旅行；进入哪张小地图仍按当前地块判断。'
    elif t<41: cap='遭遇怪物伏击：立即进入当时所在区域，先准备战斗。'
    elif t<44: cap='伏击战斗仍采用自主索敌与攻击；不是强制挑战守护 Boss。'
    elif t<45: cap='伏击战斗结束：普通掉落兑换魔力，原路线与位置保留。'
    elif t<49: cap='前往遗迹并进入对应小地图；取得引导物才需要击败守护 Boss。'
    elif t<53: cap='挑战该地块的守护 Boss；战斗结束前不能取得对应引导物。'
    elif t<54: cap='守护 Boss 已击败：获得独立引导物，不兑换成魔力。'
    elif t<58: cap='第一次配置引导物绘制召唤阵：魔力减少，引导物仍然保留。'
    elif t<62: cap='再次使用同一引导物：仍不消耗，可持续反复用于阵眼配置。'
    else: cap='自由移动与隐藏地块分离：探索地点、选址召唤、挑战获得可复用引导物。'
    d.rounded_rectangle((38,137,927,611),12,fill=PANEL,outline='#45616a',width=2)
    if not local:
        zoom=1+.14*clamp((t-6)/2) if t<9 else 1.14 if t<26 else 1
        layer,xy=world(pos,zoom,t>=22); ld=ImageDraw.Draw(layer)
        if 9<=t<17:
            ld.line([xy(A),xy(pos)],fill=GOLD,width=5); dashed(ld,xy(pos),xy(B)); pin(ld,xy(B),WHITE,5)
        elif 17<=t<36:
            ld.line([xy(A),xy(C),xy(pos)],fill=GOLD,width=5); dashed(ld,xy(pos),xy(D)); pin(ld,xy(D),WHITE,5)
        elif t>=36:
            ld.line([xy(A),xy(C),xy(D)],fill=GOLD,width=5)
            if t<45: ld.line([xy(D),xy(pos)],fill=GOLD,width=5); dashed(ld,xy(pos),xy(E))
            else: ld.line([xy(D),xy(Q),xy(pos)],fill=GOLD,width=5); dashed(ld,xy(pos),xy(E))
        pin(ld,xy(pos),GREEN,9)
        if 17<=t<20: pin(ld,xy(D),GOLD,13)
        if 14<=t<17: pill(ld,(236,124,610,171),'SPACE  /  移动已暂停')
        if 22<=t<24: pill(ld,(215,100,599,148),'探索发现：未知洞穴 → 已显示',GREEN)
        if 39<=t<40: pill(ld,(243,125,630,177),'遭遇伏击！进入当前区域',RED)
        txt(ld,(20,435),f'缩放 {round(zoom*100)}%   /   实线：已走   虚线：未走',18)
        im.paste(layer,(41,141)); d=ImageDraw.Draw(im)
    else:
        forest=t<36; ambush=40<=t<45
        d.rounded_rectangle((49,148,916,600),9,fill='#3c5445' if forest else '#655647')
        txt(d,(69,160),'小地图 / '+name,24,GREEN if forest else GOLD)
        txt(d,(69,198),'地点特性  '+tags,20)
        if forest:
            d.line([(836,233),(798,337),(839,449),(812,592)],fill='#80aaa8',width=26)
            for x,y in [(155,282),(247,267),(664,290),(124,496),(739,515)]: d.polygon([(x,y-26),(x-22,y+19),(x+22,y+19)],fill='#678563',outline='#acc799')
            d.arc((318,218,547,297),180,360,fill='#a8aa8a',width=18)
        elif ambush:
            for x,y in [(156,269),(716,273),(163,538),(758,511)]: d.polygon([(x-25,y+16),(x,y-28),(x+23,y+14)],fill='#a2947b',outline='#cfb995')
        else:
            for x,y,w,h in [(133,270,182,22),(133,270,22,220),(691,270,22,220),(573,270,140,22),(305,547,330,22)]: d.rectangle((x,y,x+w,y+h),fill='#b8a381',outline='#dac59c',width=2)
        if forest:
            if t<31: battle(d,t,27,30); state='战斗准备' if t<27 else '自动战斗' if t<30 else '战斗结算'
            else: summon(d,t,32); state='绘制召唤阵' if t<34 else '召唤产出示意'
            if 30<=t<31: pill(d,(275,252,686,306),'战斗掉落 → 魔力 +30',GREEN)
            if t>=31: pill(d,(66,241,330,287),'当地词条：【潮湿】',GREEN)
        elif ambush:
            battle(d,t,41,44)
            if t<41: pill(d,(264,240,706,294),'伏击进入 · 敌我就位 / 准备战斗',RED)
            if t>=44: pill(d,(285,244,695,298),'战斗掉落 → 魔力 +20',GREEN)
        else:
            if t<54:
                battle(d,t,49,53,True)
                pill(d,(69,240,389,286),'引导物：尚未取得' if t<53 else '引导物：已获得 / 可复用',GOLD)
                if t>=53: pill(d,(406,240,872,287),'Boss 已击败 · 引导物独立保留',GREEN)
            else:
                summon(d,t,54 if t<58 else 58,True)
                pill(d,(66,242,499,287),'第 1 次使用引导物' if t<58 else '第 2 次使用同一引导物',GOLD)
    d.rounded_rectangle((948,137,1242,611),12,fill=PANEL)
    txt(d,(971,154),'当前地点',18,MUTE); txt(d,(971,181),name,22)
    txt(d,(971,218),tags,20,GREEN if pos[0]<.58 else GOLD)
    txt(d,(971,249),risk,16,MUTE)
    txt(d,(971,286),state,20,RED if '伏击' in state else GREEN)
    txt(d,(971,324),f'旅行时间  {mins:02d} 分钟',20)
    txt(d,(971,362),f'魔力  {magic}',28,GOLD)
    txt(d,(971,407),f'引导物  {"已拥有 ×1" if guide else "未拥有"}',20)
    txt(d,(971,437),'无限复用 / 不消耗' if guide else '独立阵眼道具',18,GOLD if guide else MUTE)
    button(d,477,'绘制召唤阵' if local and (31<=t<36 or t>=54) else '返回大地图' if local else '行动',on=9<=t<10 or 20<=t<21 or 32<=t<33 or 54<=t<55 or 58<=t<59)
    button(d,530,'进入当前区域',on=24<=t<26)
    txt(d,(971,580),'空格：暂停移动',16,MUTE)
    d.rounded_rectangle((38,628,1242,680),9,fill='#2a414c'); txt(d,(55,642),cap,20)
    txt(d,(40,691),'示意假设：暂停停计时、掉落自动兑换；数值、发现范围和召唤产出均为占位，非最终规则。',15,MUTE)
    return im

video=OUT/'大地图探索_自由移动与当地召唤_效果示意_v02.mp4'
cmd=['C:/ProgramData/chocolatey/bin/ffmpeg.exe','-y','-f','rawvideo','-vcodec','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
p=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
for frame in range(FPS*LENGTH):
    p.stdin.write(render(frame/FPS).tobytes())
    if frame%(FPS*10)==0: print(f'rendered {frame//FPS}s',flush=True)
p.stdin.close(); err=p.stderr.read(); rc=p.wait()
if rc: raise RuntimeError(err.decode(errors='replace'))
render(22.5).save(OUT/'大地图探索_视频封面_v02.png')
for tm in [2,12,15,18,23,26,30,34,39,40,44,49,53,56,60,64]: render(tm).save(Path(__file__).parent/f'v02检查帧_{tm:02d}s.png')
print('Video complete.',flush=True)
