"""Generate polished flat-style product PNGs for splash screen."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, math

OUT = os.path.dirname(os.path.abspath(__file__))
SIZE = 256

def new_canvas():
    return Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))

def rrect(d, xy, r, fill):
    x0,y0,x1,y1 = xy
    w,h = x1-x0, y1-y0
    r = min(r, w//2, h//2)
    if w <= 0 or h <= 0: return
    d.rectangle([x0+r,y0,x1-r,y1], fill=fill)
    d.rectangle([x0,y0+r,x1,y1-r], fill=fill)
    d.pieslice([x0,y0,x0+2*r,y0+2*r], 180, 270, fill=fill)
    d.pieslice([x1-2*r,y0,x1,y0+2*r], 270, 360, fill=fill)
    d.pieslice([x0,y1-2*r,x0+2*r,y1], 90, 180, fill=fill)
    d.pieslice([x1-2*r,y1-2*r,x1,y1], 0, 90, fill=fill)

def shadow(img, pad=8, blur=12, opacity=50):
    """Add drop shadow to non-transparent pixels."""
    shadow_layer = Image.new('RGBA', img.size, (0,0,0,0))
    for x in range(img.width):
        for y in range(img.height):
            r,g,b,a = img.getpixel((x,y))
            if a > 20:
                shadow_layer.putpixel((x,y), (0,0,0,opacity))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(blur))
    result = Image.new('RGBA', (img.width+pad*2, img.height+pad*2), (0,0,0,0))
    result.paste(shadow_layer, (pad, pad))
    result.paste(img, (0, 0), img)
    return result

def gradient_rect(d, xy, c1, c2, vertical=True):
    x0,y0,x1,y1 = xy
    steps = y1-y0 if vertical else x1-x0
    if steps <= 0: return
    for i in range(steps):
        t = i / max(steps-1, 1)
        r = int(c1[0] + (c2[0]-c1[0])*t)
        g = int(c1[1] + (c2[1]-c1[1])*t)
        b = int(c1[2] + (c2[2]-c1[2])*t)
        if vertical:
            d.line([(x0, y0+i), (x1, y0+i)], fill=(r,g,b))
        else:
            d.line([(x0+i, y0), (x0+i, y1)], fill=(r,g,b))

def make_rice_bag():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Shadow base
    rrect(d, (42, 52, 198, 218), 14, (0,0,0,40))
    # Bag body
    rrect(d, (35, 45, 195, 210), 14, (250,248,242))
    # Subtle top highlight
    rrect(d, (35, 45, 195, 90), 14, (255,255,252))
    # Fold at top
    rrect(d, (55, 35, 185, 65), 10, (235,232,225))
    d.line([(55,65),(185,65)], fill=(210,207,200), width=1)
    # Green band
    d.rectangle([35,100,195,130], fill=(46,125,50))
    d.rectangle([35,100,195,108], fill=(56,142,60))
    # Label
    rrect(d, (55,140,175,185), 8, (240,245,240))
    d.rectangle([55,140,175,148], fill=(230,238,232))
    # "RICE" text
    try: f = ImageFont.truetype("arial.ttf", 22)
    except: f = ImageFont.load_default()
    d.text((82, 152), "RICE", fill=(46,100,45), font=f)
    # Grain dots
    for x,y in [(75,80),(95,85),(115,78),(135,82),(155,80),(85,188),(130,190)]:
        d.ellipse([x-3,y-3,x+3,y+3], fill=(210,200,170))
    img = shadow(img)
    img.save(os.path.join(OUT, 'rice_bag.png'))

def make_oil_bottle():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Cap
    rrect(d, (92, 18, 148, 52), 8, (180,140,20))
    rrect(d, (92, 18, 148, 32), 8, (200,160,40))
    # Neck
    d.rectangle([100,48,140,72], fill=(255,210,30))
    # Body
    rrect(d, (55,65,185,218), 22, (255,205,0))
    # Left highlight
    rrect(d, (55,65,95,218), 22, (255,220,50))
    rrect(d, (55,65,75,218), 22, (255,230,80))
    # Label area
    rrect(d, (68,110,172,175), 10, (255,255,248))
    # Oil drop icon
    d.polygon([(120,100),(108,120),(132,120)], fill=(255,180,0))
    d.ellipse([106,112,134,138], fill=(255,180,0))
    # "OIL" text
    try: f = ImageFont.truetype("arial.ttf", 20)
    except: f = ImageFont.load_default()
    d.text((97,148), "OIL", fill=(180,130,0), font=f)
    img = shadow(img)
    img.save(os.path.join(OUT, 'oil_bottle.png'))

def make_detergent():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Box body
    rrect(d, (42,50,198,215), 12, (25,90,190))
    # Top flap
    rrect(d, (52,35,188,65), 10, (40,110,210))
    d.line([(52,65),(188,65)], fill=(30,85,170), width=1)
    # Cap
    rrect(d, (88,18,152,42), 8, (35,80,170))
    # White panel
    rrect(d, (55,72,185,160), 8, (240,248,255))
    # Wave pattern
    for row, y in enumerate([95, 115, 135]):
        for i, x in enumerate(range(65, 170, 22)):
            c = (100+row*20, 170+row*10, 255) if (i+row)%2==0 else (140,200,255)
            d.ellipse([x-6,y-6,x+6,y+6], fill=c)
    # "SURF" text
    try: f = ImageFont.truetype("arial.ttf", 22)
    except: f = ImageFont.load_default()
    d.text((75,168), "SURF", fill=(255,255,255), font=f)
    # Side highlight
    d.rectangle([42,50,55,215], fill=(40,110,210))
    img = shadow(img)
    img.save(os.path.join(OUT, 'detergent.png'))

def make_shampoo():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Cap
    rrect(d, (82,12,162,55), 10, (160,40,130))
    rrect(d, (82,12,162,30), 10, (180,60,150))
    # Neck
    d.rectangle([95,50,145,72], fill=(190,60,160))
    # Body
    rrect(d, (58,65,185,218), 28, (190,55,155))
    # Left highlight
    rrect(d, (58,65,100,218), 28, (210,90,180))
    rrect(d, (58,65,78,218), 28, (220,110,195))
    # Label
    rrect(d, (72,105,172,165), 10, (255,230,248))
    # Star burst
    cx,cy = 122, 85
    for i in range(8):
        angle = math.radians(i*45)
        x1 = cx + int(12*math.cos(angle))
        y1 = cy + int(12*math.sin(angle))
        d.line([(cx,cy),(x1,y1)], fill=(255,200,230), width=2)
    d.ellipse([cx-6,cy-6,cx+6,cy+6], fill=(255,180,220))
    # "SHAMPOO" text
    try: f = ImageFont.truetype("arial.ttf", 16)
    except: f = ImageFont.load_default()
    d.text((80,130), "SHAMPOO", fill=(140,30,110), font=f)
    img = shadow(img)
    img.save(os.path.join(OUT, 'shampoo.png'))

def make_toothpaste():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Tube body
    rrect(d, (30,65,175,180), 20, (0,150,70))
    # Left rounded end
    rrect(d, (30,65,55,180), 20, (0,150,70))
    # Cap
    rrect(d, (160,80,210,165), 14, (0,120,55))
    rrect(d, (160,80,180,165), 14, (0,140,65))
    # White stripes
    d.rectangle([55,90,160,108], fill=(255,255,255))
    d.rectangle([55,120,160,135], fill=(255,255,255))
    # Label panel
    rrect(d, (60,105,155,155), 8, (220,255,230))
    # Mint leaf shapes
    d.ellipse([72,95,92,112], fill=(100,200,130))
    d.ellipse([85,92,105,108], fill=(80,180,110))
    # "PASTE" text
    try: f = ImageFont.truetype("arial.ttf", 18)
    except: f = ImageFont.load_default()
    d.text((75,128), "PASTE", fill=(0,100,45), font=f)
    # Squeeze tip
    d.polygon([(200,110),(218,122),(200,140)], fill=(0,100,50))
    img = shadow(img)
    img.save(os.path.join(OUT, 'toothpaste.png'))

def make_tea():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Box body
    rrect(d, (40,38,200,210), 12, (120,55,15))
    # Front face lighter
    rrect(d, (48,45,192,205), 10, (150,75,30))
    # Highlight top
    rrect(d, (48,45,192,80), 10, (170,90,45))
    # Label
    rrect(d, (60,60,180,155), 10, (255,245,225))
    # Tea cup
    rrect(d, (85,72,145,115), 10, (180,100,40))
    rrect(d, (85,72,115,115), 10, (200,120,55))
    # Cup handle
    d.arc([140,80,162,110], 300, 120, fill=(180,100,40), width=4)
    # Saucer
    d.ellipse([80,108,150,120], fill=(180,100,40))
    # Steam
    for x in [100,115,130]:
        for dy in range(3):
            d.arc([x-4, 65-dy*8, x+4, 72-dy*8], 0, 180, fill=(200,180,160), width=2)
    # "TEA" text
    try: f = ImageFont.truetype("arial.ttf", 24)
    except: f = ImageFont.load_default()
    d.text((95,165), "TEA", fill=(255,240,220), font=f)
    img = shadow(img)
    img.save(os.path.join(OUT, 'tea_packet.png'))

def make_biscuit():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Wrapper
    rrect(d, (30,45,210,195), 16, (225,120,25))
    # Seal top crimp
    d.polygon([(30,55),(120,35),(210,55)], fill=(200,100,15))
    d.polygon([(30,55),(120,42),(210,55)], fill=(230,135,40))
    # Window
    rrect(d, (45,62,195,155), 10, (255,245,220))
    # Biscuits
    for cx,cy in [(80,95),(120,90),(155,95),(95,128),(140,125)]:
        d.ellipse([cx-16,cy-16,cx+16,cy+16], fill=(200,140,50))
        d.ellipse([cx-12,cy-12,cx+12,cy+12], fill=(215,155,65))
        # Dot pattern on biscuit
        for dx,dy in [(-5,-5),(5,-5),(0,0),(-5,5),(5,5)]:
            d.ellipse([cx+dx-2,cy+dy-2,cx+dx+2,cy+dy+2], fill=(180,120,40))
    # "BISCUIT" text
    try: f = ImageFont.truetype("arial.ttf", 20)
    except: f = ImageFont.load_default()
    d.text((68,165), "BISCUIT", fill=(255,255,255), font=f)
    img = shadow(img)
    img.save(os.path.join(OUT, 'biscuit.png'))

def make_dal():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Bag
    rrect(d, (38,42,198,215), 14, (235,215,150))
    # Top gathered
    rrect(d, (65,28,172,55), 10, (220,200,135))
    # Tie
    d.ellipse([108,22,132,38], fill=(180,140,50))
    d.rectangle([118,18,122,42], fill=(160,120,40))
    # Label
    rrect(d, (52,65,185,150), 10, (255,250,235))
    # Dal grains scattered
    for x,y in [(72,82),(100,78),(128,85),(155,80),(80,105),(110,100),(140,108),(90,130),(125,125),(155,130)]:
        d.ellipse([x-6,y-4,x+6,y+4], fill=(230,185,70))
        d.ellipse([x-4,y-3,x+4,y+3], fill=(240,200,90))
    # "DAL" text
    try: f = ImageFont.truetype("arial.ttf", 24)
    except: f = ImageFont.load_default()
    d.text((95,168), "DAL", fill=(150,110,30), font=f)
    img = shadow(img)
    img.save(os.path.join(OUT, 'dal_pack.png'))

def make_soap():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Wrapper back
    rrect(d, (30,50,220,190), 22, (240,140,160))
    # Soap bar
    rrect(d, (40,58,210,182), 20, (255,225,230))
    # Top face highlight
    rrect(d, (40,58,210,100), 20, (255,235,238))
    # Inner panel
    rrect(d, (58,72,192,165), 14, (255,240,243))
    # Flower center
    cx,cy = 125,115
    d.ellipse([cx-8,cy-8,cx+8,cy+8], fill=(255,170,185))
    for i in range(6):
        angle = math.radians(i*60)
        px = cx + int(18*math.cos(angle))
        py = cy + int(18*math.sin(angle))
        d.ellipse([px-10,py-10,px+10,py+10], fill=(255,195,210))
    d.ellipse([cx-5,cy-5,cx+5,cy+5], fill=(255,155,170))
    # "SOAP" text
    try: f = ImageFont.truetype("arial.ttf", 22)
    except: f = ImageFont.load_default()
    d.text((90,155), "SOAP", fill=(200,80,100), font=f)
    img = shadow(img)
    img.save(os.path.join(OUT, 'soap.png'))

def make_hair_oil():
    img = new_canvas(); d = ImageDraw.Draw(img)
    # Cap
    rrect(d, (88,12,152,45), 8, (25,115,45))
    rrect(d, (88,12,152,28), 8, (35,135,55))
    # Nozzle
    d.rectangle([102,2,138,18], fill=(20,100,40))
    # Neck
    d.rectangle([95,42,145,65], fill=(35,145,60))
    # Body
    rrect(d, (55,58,188,218), 24, (35,155,65))
    # Left highlight
    rrect(d, (55,58,95,218), 24, (55,175,85))
    rrect(d, (55,58,75,218), 24, (70,190,100))
    # Label
    rrect(d, (68,98,178,165), 10, (225,255,230))
    # Oil drop
    cx,cy = 123, 82
    d.ellipse([cx-10,cy-6,cx+10,cy+10], fill=(255,210,0))
    d.polygon([(cx,cy-14),(cx-10,cy+2),(cx+10,cy+2)], fill=(255,210,0))
    # "HAIR OIL" text
    try: f = ImageFont.truetype("arial.ttf", 16)
    except: f = ImageFont.load_default()
    d.text((80,120), "HAIR OIL", fill=(20,95,35), font=f)
    img = shadow(img)
    img.save(os.path.join(OUT, 'hair_oil.png'))

if __name__ == '__main__':
    make_rice_bag()
    make_oil_bottle()
    make_detergent()
    make_shampoo()
    make_toothpaste()
    make_tea()
    make_biscuit()
    make_dal()
    make_soap()
    make_hair_oil()
    print("Generated 10 polished product PNGs with shadows")
