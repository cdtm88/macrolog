from PIL import Image, ImageDraw
import math

S = 1024
img = Image.new("RGB", (S, S), (26, 26, 30))  # #1a1a1e dark
# supersample for smooth arcs
SS = 4
big = Image.new("RGB", (S*SS, S*SS), (26, 26, 30))
d = ImageDraw.Draw(big)

cx = cy = S*SS/2
r = S*SS*0.30
width = int(S*SS*0.11)

protein = (0, 122, 255)
carbs = (255, 149, 0)
fat = (175, 82, 222)

# arc fractions (protein, carbs, fat) sized like a real-ish meal
segs = [(protein, 0.52), (carbs, 0.30), (fat, 0.18)]
gap = 6  # degrees gap between arcs
start = -90.0
box = [cx-r, cy-r, cx+r, cy+r]
for color, frac in segs:
    extent = frac*360
    a0 = start + gap/2
    a1 = start + extent - gap/2
    d.arc(box, a0, a1, fill=color, width=width)
    start += extent

big = big.resize((S, S), Image.LANCZOS)
big.save("MacroLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
big.save("MacroLogWidget/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
print("icon written")
