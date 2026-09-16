"""Generate 10 flat-style product PNGs for splash screen animation."""
from PIL import Image, ImageDraw, ImageFont
import os

OUT = os.path.dirname(os.path.abspath(__file__))
SIZE = 200

def rounded_rect(draw, xy, radius, fill):
    x0, y0, x1, y1 = xy
    r = radius
    draw.rectangle([x0+r, y0, x1-r, y1], fill=fill)
    draw.rectangle([x0, y0+r, x1, y1-r], fill=fill)
    draw.pieslice([x0, y0, x0+2*r, y0+2*r], 180, 270, fill=fill)
    draw.pieslice([x1-2*r, y0, x1, y0+2*r], 270, 360, fill=fill)
    draw.pieslice([x0, y1-2*r, x0+2*r, y1], 90, 180, fill=fill)
    draw.pieslice([x1-2*r, y1-2*r, x1, y1], 0, 90, fill=fill)

def circle(draw, cx, cy, r, fill):
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=fill)

def make_rice_bag():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Bag body
    rounded_rect(d, (30, 40, 170, 175), 15, (245, 245, 240))
    # Top fold
    rounded_rect(d, (50, 30, 150, 60), 10, (230, 230, 220))
    # Green stripe
    d.rectangle([30, 90, 170, 110], fill=(34, 139, 34))
    # Label area
    rounded_rect(d, (55, 115, 145, 155), 8, (220, 240, 220))
    # Text "RICE"
    d.text((72, 125), "RICE", fill=(34, 100, 34))
    # Small grain dots
    for x, y in [(70, 75), (90, 80), (110, 72), (130, 78), (80, 160), (120, 162)]:
        circle(d, x, y, 3, (200, 190, 160))
    img.save(os.path.join(OUT, 'rice_bag.png'))

def make_oil_bottle():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Bottle cap
    rounded_rect(d, (80, 15, 120, 40), 5, (180, 140, 30))
    # Neck
    d.rectangle([85, 35, 115, 55], fill=(255, 220, 50))
    # Body
    rounded_rect(d, (45, 50, 155, 175), 20, (255, 215, 0))
    # Oil level shine
    rounded_rect(d, (55, 70, 100, 165), 12, (255, 230, 80))
    # Label
    rounded_rect(d, (55, 110, 145, 150), 8, (255, 255, 240))
    d.text((72, 120), "OIL", fill=(180, 130, 0))
    # Drop shape
    circle(d, 125, 90, 8, (255, 200, 0))
    img.save(os.path.join(OUT, 'oil_bottle.png'))

def make_detergent():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Box body
    rounded_rect(d, (35, 45, 165, 175), 12, (30, 100, 200))
    # Top flap
    rounded_rect(d, (45, 30, 155, 55), 8, (50, 120, 220))
    # White label
    rounded_rect(d, (45, 60, 155, 145), 8, (240, 248, 255))
    # Waves
    for y in [85, 105, 125]:
        for x in range(55, 140, 20):
            circle(d, x, y, 5, (100, 180, 255))
    # Text
    d.text((58, 148), "SURF", fill=(255, 255, 255))
    # Cap
    rounded_rect(d, (75, 20, 125, 38), 6, (40, 90, 180))
    img.save(os.path.join(OUT, 'detergent.png'))

def make_shampoo():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Cap
    rounded_rect(d, (70, 10, 130, 45), 10, (180, 50, 150))
    # Neck
    d.rectangle([80, 40, 120, 60], fill=(200, 80, 180))
    # Body - bottle shape
    rounded_rect(d, (50, 55, 150, 175), 25, (200, 70, 170))
    # Highlight
    rounded_rect(d, (60, 65, 95, 165), 15, (220, 110, 200))
    # Label
    rounded_rect(d, (60, 100, 140, 145), 8, (255, 230, 245))
    d.text((75, 112), "SHAM", fill=(150, 40, 120))
    # Star decoration
    cx, cy, r = 120, 80, 8
    for i in range(5):
        import math
        angle = math.radians(i * 72 - 90)
        x = cx + r * math.cos(angle)
        y = cy + r * math.sin(angle)
        circle(d, int(x), int(y), 2, (255, 200, 230))
    img.save(os.path.join(OUT, 'shampoo.png'))

def make_toothpaste():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Tube body
    rounded_rect(d, (30, 55, 170, 165), 18, (0, 160, 80))
    # Cap
    rounded_rect(d, (140, 65, 180, 155), 12, (0, 130, 60))
    # Stripe 1
    d.rectangle([30, 80, 140, 100], fill=(255, 255, 255))
    # Stripe 2
    d.rectangle([30, 115, 140, 130], fill=(255, 255, 255))
    # Label
    rounded_rect(d, (40, 100, 130, 140), 6, (220, 255, 230))
    d.text((52, 110), "PASTE", fill=(0, 100, 50))
    # Squeeze tip
    d.polygon([(165, 85), (190, 100), (165, 120)], fill=(0, 100, 50))
    img.save(os.path.join(OUT, 'toothpaste.png'))

def make_tea():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Box body
    rounded_rect(d, (35, 35, 165, 175), 12, (139, 69, 19))
    # Front face
    rounded_rect(d, (40, 40, 160, 170), 10, (160, 82, 45))
    # Label
    rounded_rect(d, (50, 55, 150, 130), 8, (255, 240, 220))
    # Tea cup icon
    rounded_rect(d, (70, 65, 120, 105), 8, (180, 100, 50))
    # Cup handle
    d.arc([115, 72, 135, 97], 270, 90, fill=(180, 100, 50), width=3)
    # Steam lines
    for x in [85, 100, 115]:
        d.line([(x, 60), (x-3, 48)], fill=(200, 180, 160), width=2)
    # Text
    d.text((68, 140), "TEA", fill=(255, 240, 220))
    img.save(os.path.join(OUT, 'tea_packet.png'))

def make_biscuit():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Packet body
    rounded_rect(d, (25, 40, 175, 170), 15, (230, 130, 30))
    # Seal top
    d.polygon([(25, 55), (100, 35), (175, 55)], fill=(210, 110, 20))
    # Window
    rounded_rect(d, (40, 60, 160, 140), 10, (255, 240, 210))
    # Biscuit circles
    for cx, cy in [(70, 90), (110, 85), (145, 95), (85, 120), (125, 118)]:
        circle(d, cx, cy, 12, (200, 140, 50))
        circle(d, cx, cy, 6, (180, 120, 40))
    # Text
    d.text((55, 148), "BISCUIT", fill=(255, 255, 255))
    img.save(os.path.join(OUT, 'biscuit.png'))

def make_dal():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Bag body
    rounded_rect(d, (30, 35, 170, 175), 15, (240, 220, 160))
    # Top gather
    rounded_rect(d, (60, 25, 140, 50), 10, (225, 200, 140))
    # Tie
    d.line([(90, 30), (100, 20), (110, 30)], fill=(180, 140, 60), width=3)
    # Label
    rounded_rect(d, (45, 70, 155, 140), 10, (255, 250, 230))
    # Dal grains
    for x, y in [(65, 85), (85, 90), (105, 82), (125, 88), (75, 105), (95, 110), (115, 100)]:
        circle(d, x, y, 5, (230, 190, 80))
    # Text
    d.text((65, 145), "DAL", fill=(150, 110, 30))
    img.save(os.path.join(OUT, 'dal_pack.png'))

def make_soap():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Wrapper
    rounded_rect(d, (25, 45, 175, 165), 20, (255, 180, 190))
    # Soap bar
    rounded_rect(d, (35, 55, 165, 155), 18, (255, 220, 225))
    # Inner design
    rounded_rect(d, (50, 70, 150, 140), 12, (255, 235, 238))
    # Flower shape
    circle(d, 100, 100, 15, (255, 190, 200))
    for angle in range(0, 360, 60):
        import math
        x = 100 + int(22 * math.cos(math.radians(angle)))
        y = 100 + int(22 * math.sin(math.radians(angle)))
        circle(d, x, y, 8, (255, 200, 210))
    circle(d, 100, 100, 6, (255, 170, 180))
    # Text
    d.text((68, 145), "SOAP", fill=(200, 100, 120))
    img.save(os.path.join(OUT, 'soap.png'))

def make_hair_oil():
    img = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Cap
    rounded_rect(d, (75, 8, 125, 35), 8, (20, 120, 50))
    # Nozzle
    d.rectangle([90, 2, 110, 15], fill=(20, 100, 40))
    # Neck
    d.rectangle([82, 32, 118, 50], fill=(30, 140, 60))
    # Bottle body
    rounded_rect(d, (45, 45, 155, 175), 22, (30, 150, 60))
    # Highlight
    rounded_rect(d, (55, 55, 90, 165), 15, (60, 180, 90))
    # Label
    rounded_rect(d, (55, 90, 145, 140), 8, (220, 255, 225))
    # Oil drop
    d.polygon([(100, 60), (88, 80), (112, 80)], fill=(255, 215, 0))
    circle(d, 100, 75, 10, (255, 215, 0))
    # Text
    d.text((62, 100), "HAIR OIL", fill=(20, 100, 40))
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
    print("Generated 10 product PNGs")
