from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math, random, subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'玩法演示'
OUT.mkdir(exist_ok=True)
W,H,FPS,DURATION=1280,720,20,46
FONT='C:/Windows/Fonts/msyh.ttc'
fonts={n:ImageFont.truetype(FONT,n) for n in [16,18,20,22,24,28,34]}
BG='#111d28'; PANEL='#1b2c39'; WHITE='#edf2ed'; MUTED='#a7bac2'; GOLD='#f3ca79'; GREEN='#85d9b0'; RED='#df9983'
A=(.15,.70); B=(.66,.25); C=(.36,.515); D=(.49,.68); E=(.82,.40)
random.seed(12)
trees=[(random.uniform(.03,.56),random.uniform(.15,.92),random.uniform(7,13)) for _ in range(78)]
rocks=[(random.uniform(.64,.95),random.uniform(.12,.86),random.uniform(8,16)) for _ in range(23)]
def mix(a,b,p): return tuple(x+(y-x)*p for x,y in zip(a,b))
def clamp(x): return max(0,min(1,x))
def txt(d,xy,s,size=20,color=WHITE): d.text(xy,s,font=fonts[size],fill=color)
def dash(d,a,b,color,width=4):
    dist=math.dist(a,b)
    for k in range(0,int(dist),22):
        p=k/max(1,dist); q=min(1,(k+12)/max(1,dist))
        d.line([mix(a,b,p),mix(a,b,q)],fill=color,width=width)
def pin(d,p,color=GOLD,r=8):
    x,y=p; d.ellipse((x-r-5,y-r-5,x+r+5,y+r+5),outline=color,width=2)
    d.ellipse((x-r,y-r,x+r,y+r),fill=color)
def button(d,box,label,active=False):
    d.rounded_rectangle(box,9,fill=GOLD if active else '#2a4351',outline=GOLD if active else '#436070',width=2)
    textw=d.textbbox((0,0),label,font=fonts[20])[2]
    txt(d,((box[0]+box[2]-textw)/2,box[1]+11),label,20,BG if active else WHITE)
def render(t):
    im=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(im)
    txt(d,(38,22),'大地图探索 · 玩法效果示意',28)
    txt(d,(963,31),'概念动画 / 非游戏实录',18,MUTED)
    steps=['观察地图','行动与改道','林地探索','遗迹探索']
    step=0 if t<7 else 1 if t<25 else 2 if t<36 else 3
    for i,s in enumerate(steps):
        x=40+i*305; d.rounded_rectangle((x,79,x+290,117),7,fill=GOLD if step==i else PANEL)
        txt(d,(x+18,86),f'{i+1:02d}  {s}',18,BG if step==i else MUTED)
    local=(25<=t<30) or (36<=t<41)
    second=36<=t<41
    if t<7: pos=A; mins=0; status='待命'; caption='缩放查看区域：先观察难度，再选择探索方向。'
    elif t<12:
        p=clamp((t-8)/4); pos=mix(A,C,p); mins=round(32*p); status='移动中'; caption='点击「行动」：未走路线为虚线，走过部分逐段变为实线。'
    elif t<18: pos=C; mins=32; status='移动已暂停'; caption='空格暂停：停在当前位置，可随时更改目的地。' if t<15 else '改道：保留已走实线，从暂停位置重新规划剩余虚线。'
    elif t<23:
        p=clamp((t-19)/4); pos=mix(C,D,p); mins=32+round(18*p); status='移动中'; caption='再次点击「行动」继续：从当前地点出发，旅行时间继续累积。'
    elif t<32: pos=D; mins=50; status='探索中' if local else '已抵达'; caption='随时进入当前位置的小地图，不依赖固定入口。' if t<25 else '林地小地图：地形对应当前区域，探索并收集素材。' if t<30 else '返回大地图：位置不变，已取得的素材保留。'
    elif t<36:
        p=clamp((t-32)/4); pos=mix(D,E,p); mins=50+round(40*p); status='移动中'; caption='前往更高难度地区：距离带来旅行时间，区域决定探索风险。'
    else: pos=E; mins=90; status='探索中' if local else '已返回'; caption='遗迹小地图：不同布局与风险，探索取得关键阵眼引导物。' if local else '移动 → 选区 → 探索：收集素材与引导物，为后续阵眼配置做准备。'
    d.rounded_rectangle((38,139,927,612),14,fill=PANEL,outline='#365464',width=2)
    if not local:
        layer=Image.new('RGB',(883,467),'#344b45'); ld=ImageDraw.Draw(layer)
        scale=1+(.16*clamp((t-4)/2) if 4<=t<7 else .16 if 7<=t<25 else 0)
        def mp(p): return ((p[0]-.38)*scale*883+.38*883,(p[1]-.52)*scale*467+.52*467)
        ld.polygon([mp((.60,0)),mp((1,0)),mp((1,1)),mp((.66,1)),mp((.63,.55))],fill='#66534a')
        for xx in range(0,884,50): ld.line((xx,0,xx,467),fill='#3c5149',width=1)
        for yy in range(0,468,50): ld.line((0,yy,883,yy),fill='#3c5149',width=1)
        river=[mp(p) for p in [(.59,0),(.55,.22),(.59,.43),(.54,.64),(.58,1)]]
        ld.line(river,fill='#233c47',width=27); ld.line(river,fill='#689ca4',width=14)
        for x,y,r in trees:
            px,py=mp((x,y)); ld.polygon([(px,py-r),(px-r,py+r),(px+r,py+r)],fill='#50725b',outline='#83a586')
        for x,y,r in rocks:
            px,py=mp((x,y)); ld.polygon([(px-r,py+r),(px,py-r),(px+r,py+r)],fill='#7d6d60',outline='#ba9d81')
        ld.rounded_rectangle((20,18,257,62),9,fill='#253c36'); txt(ld,(34,29),'苍林 · 低难度 / 素材',20,GREEN)
        ld.rounded_rectangle((576,18,861,62),9,fill='#43382f'); txt(ld,(591,29),'赤岩遗迹 · 高难度 / 线索',20,GOLD)
        # Routes are split at the actual player position.
        if 7<=t<15:
            ld.line([mp(A),mp(pos)],fill=GOLD,width=5); dash(ld,mp(pos),mp(B),GOLD)
            pin(ld,mp(B),WHITE,5); txt(ld,(mp(B)[0]+14,mp(B)[1]-10),'原目的地',18)
        elif 15<=t<32:
            ld.line([mp(A),mp(C)],fill=GOLD,width=5)
            if t<23: ld.line([mp(C),mp(pos)],fill=GOLD,width=5); dash(ld,mp(pos),mp(D),GOLD)
            else: ld.line([mp(C),mp(D)],fill=GOLD,width=5)
            pin(ld,mp(D),WHITE,5)
        elif t>=32:
            ld.line([mp(A),mp(C),mp(D)],fill=GOLD,width=5)
            ld.line([mp(D),mp(pos)],fill=GOLD,width=5); dash(ld,mp(pos),mp(E),GOLD)
            pin(ld,mp(E),WHITE,5)
        pin(ld,mp(pos),GREEN,9)
        txt(ld,(mp(pos)[0]+17,mp(pos)[1]-12),'当前位置',18,WHITE)
        # A UI pointer highlights actions without implying a playable recording.
        if 15<=t<18: pin(ld,mp(D),GOLD,15); txt(ld,(mp(D)[0]+23,mp(D)[1]+10),'新目的地',18,GOLD)
        im.paste(layer,(41,142)); d=ImageDraw.Draw(im)
        txt(d,(61,571),f'缩放  {round(scale*100)}%     实线：已走    虚线：未走',18,WHITE)
    else:
        ld=d
        area=(49,150,916,601); d.rounded_rectangle(area,10,fill='#55493e' if second else '#304b40')
        txt(d,(66,162),'小地图 / 赤岩遗迹' if second else '小地图 / 苍林河岸',24,GOLD if second else GREEN)
        txt(d,(66,197),'位置关联：赤岩地区 + 遗迹外围' if second else '位置关联：苍林地区 + 河流西岸',18,WHITE)
        if second:
            for x,y,w,h in [(140,270,170,30),(140,270,30,170),(550,270,170,30),(690,270,30,150),(350,480,230,30)]:
                d.rectangle((x,y,x+w,y+h),fill='#a79579',outline='#dbc49c',width=3)
            for x,y in [(585,380),(655,462)]:
                d.rectangle((x-15,y-15,x+15,y+15),fill=RED); txt(d,(x-28,y+23),'敌方',16,RED)
            item=(470,337); start=(230,470); elapsed=t-36; got=elapsed>=3
            d.polygon([(470,308),(487,337),(470,366),(453,337)],fill='#ffd379' if not got else '#79684d',outline=GOLD)
            txt(d,(398,376),'关键阵眼引导物',20,GOLD)
        else:
            d.line([(790,228),(750,340),(795,465),(760,594)],fill='#699ca5',width=37)
            for x,y in [(145,295),(237,285),(380,274),(570,280),(137,497),(340,540),(599,511)]:
                d.polygon([(x,y-25),(x-24,y+24),(x+24,y+24)],fill='#648b67',outline='#a4ba89')
            item=(484,403); start=(225,452); elapsed=t-25; got=elapsed>=3
            for x,y in [(471,401),(490,388),(505,414)]: d.ellipse((x-9,y-9,x+9,y+9),fill='#c5cf8e' if not got else '#526b4a')
            txt(d,(424,439),'素材采集点',20,GREEN)
        pp=mix(start,item,clamp(elapsed/3)); pin(d,pp,GREEN,10)
        if got:
            d.rounded_rectangle((300,240,668,294),10,fill='#233a34',outline=GOLD,width=2)
            txt(d,(320,253),'已获得：引导物 ×1' if second else '已获得：林地素材 ×3',24,GOLD)
        txt(d,(65,566),'场景关系示意；非正式地图、美术或战斗规则',16,MUTED)
    d.rounded_rectangle((948,139,1242,612),14,fill=PANEL)
    txt(d,(971,158),'探索状态',22)
    txt(d,(971,204),status,24,GOLD if status=='移动已暂停' else GREEN)
    txt(d,(971,253),'累计旅行时间',18,MUTED)
    txt(d,(971,280),f'{mins:02d} 分钟',34,GOLD)
    txt(d,(971,331),'本次探索收获',18,MUTED)
    txt(d,(971,362),f'林地素材  ×{3 if t>=28 else 0}',20)
    txt(d,(971,396),f'阵眼引导物  ×{1 if t>=39 else 0}',20)
    button(d,(971,449,1219,496),'返回大地图' if local else '行动',active=(7<=t<8 or 18<=t<19))
    button(d,(971,511,1219,558),'进入当前区域',active=23<=t<25)
    txt(d,(971,577),'空格：暂停移动',18,GOLD)
    d.rounded_rectangle((38,629,1242,682),9,fill='#263d4a')
    txt(d,(57,643),caption,22)
    txt(d,(42,693),'演示假设：暂停不计旅行时间；改道后点击行动恢复。数值、界面与收获仅为占位。',16,MUTED)
    return im

video=OUT/'大地图探索_路线暂停改道_效果示意_v01.mp4'
cmd=['C:/ProgramData/chocolatey/bin/ffmpeg.exe','-y','-f','rawvideo','-vcodec','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
p=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
for frame in range(FPS*DURATION):
    p.stdin.write(render(frame/FPS).tobytes())
    if frame%(FPS*10)==0: print(f'rendered {frame//FPS}s',flush=True)
p.stdin.close(); err=p.stderr.read(); rc=p.wait()
if rc: raise RuntimeError(err.decode(errors='replace'))
render(16).save(OUT/'大地图探索_视频封面_v01.png')
for tm in [9,13,16,21,28,39,43]: render(tm).save(Path(__file__).parent/f'检查帧_{tm:02d}s.png')
print(str(video),flush=True)
