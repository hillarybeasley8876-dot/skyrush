"""Neon / sign atlas drawing (PIL).  Every sign is a printed or lit panel with a
coloured tube and a white-hot core - never white text with a coloured rim.

Vertical blades use a 1:3 cell, fascia lightboxes a 4:1 cell, lane plaques a 2:1
cell.  The character size is fitted to the cell and asserted to lie inside it, so a
name is never cut short (a truncated shop name is gibberish, and the brief forbids
that).  Five fonts are used, as the art dossier lists.
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_DIR = os.path.expanduser("~/m/skyrush/blender/city/buildings/fonts")
FONTS = [
    os.path.expanduser("~/Library/Fonts/NotoSansCJKsc-Bold.otf"),
    os.path.expanduser("~/Library/Fonts/NotoSerifCJKsc-Regular.otf"),
    os.path.join(FONT_DIR, "ZCOOLKuaiLe-Regular.ttf"),
    os.path.join(FONT_DIR, "ZCOOLQingKeHuangYou-Regular.ttf"),
    os.path.join(FONT_DIR, "MaShanZheng-Regular.ttf"),
]

FONT_BOLD = os.path.expanduser("~/Library/Fonts/NotoSansCJKsc-Bold.otf")
FONT_SERIF = os.path.expanduser("~/Library/Fonts/NotoSerifCJKsc-Regular.otf")

NEON_COLS = {
    "red": (255, 42, 58),
    "magenta": (255, 63, 216),
    "cyan": (41, 211, 255),
    "yellow": (255, 210, 63),
    "green": (57, 255, 136),
    "amber": (255, 176, 0),
    "violet": (154, 92, 255),
    "white": (255, 240, 220),
}

BLADE_NAMES = [
    "海派百货", "赛博火锅", "量子奶茶", "星光量贩", "破晓电竞", "云端速递",
    "浦江电讯", "东方霓虹", "申城快递", "老弄堂小笼", "申城闪充", "中石华",
    "永福大药房", "飞驰申城", "浦江照相", "海派理发", "申城干洗", "沪上书屋",
    "静安咖啡", "城隍点心", "光明眼镜", "大众浴室", "新亚旅社", "恒丰烟酒",
    "顺风面馆", "味香小炒", "万利五金", "家和超市", "康乐药房", "远洋旅店",
    "锦江钟表", "申通洗衣", "北方饺子", "竹林茶庄", "星光网吧", "蓝鲸网吧",
    "潮人美发", "都市丽人", "金鹰电器", "银发理发", "四季水果", "宏发汽配",
    "夜宵排档", "弄堂生煎", "城南书报", "沪上花店", "大宁药房", "永昌电器",
    "中原置业", "福彩代销", "新亚照相", "光明眼镜行", "顺达物流", "恒通汽配",
    "百姓超市", "安平旅馆", "康乐药房行", "浦江书城", "丽人坊", "便民菜场",
]

BOX_NAMES = [
    "邻里24", "老弄堂小笼", "赛博火锅", "量子奶茶", "永福大药房",
    "申城快递", "东方霓虹", "申城闪充", "海派百货", "弄堂生煎",
    "申城面馆", "东方便利", "浦江照相", "海派理发", "飞驰申城", "申城干洗",
    "沪上书屋", "静安咖啡", "城隍点心", "光明眼镜", "大众浴室", "新亚旅社",
    "恒丰烟酒", "顺风面馆", "味香小炒", "万利五金", "家和超市", "康乐药房",
    "远洋旅店", "锦江钟表", "申通洗衣", "北方饺子", "竹林茶庄", "星光网吧",
    "蓝鲸网吧", "潮人美发", "都市丽人", "金鹰电器", "银发理发", "四季水果",
    "宏发汽配", "夜宵排档", "城南书报", "沪上花店", "大宁药房", "永昌电器",
    "中原置业", "福彩代销", "新亚照相", "光明眼镜行", "顺达物流", "恒通汽配",
    "百姓超市", "安平旅馆", "浦江书城", "丽人坊", "便民菜场", "修鞋配钥",
]

LANE_NAMES = [
    "张家弄", "王家弄", "李家弄", "陈家弄", "沈家弄", "朱家弄",
    "曹家弄", "薛家弄", "同福里", "永安里", "福安里", "德庆里",
    "文昌里", "承德里", "兴顺里", "清和里", "静安里", "昌平里",
    "泰和里", "西兴里", "德安里", "新福里", "复兴里", "同德里",
    "万顺里", "三益里", "广德里", "仁和里", "春阳里", "安乐里",
    "南康里", "福寿里", "光华里", "宁和里", "中正里", "爱国里",
    "永兴里", "合和里", "乐善里", "大德里", "久安里", "崇德里",
    "宝庆里", "福顺里", "同兴里", "永泰里", "海宁里", "嘉兴里",
    "东兴里", "西兴里", "南兴里", "北兴里", "文德里", "和顺里",
    "长乐里", "永祥里", "德胜里", "安平里", "济阳里", "天祥里",
    "福安弄", "大通弄", "小通弄", "三多弄", "九曲弄", "德庆弄",
]

BOX_EN = [
    "NEIGHBOR 24", "DUMPLING 24H", "CYBER HOTPOT", "QUANTUM TEA", "DRUGSTORE",
    "EXPRESS", "NEON EAST", "FLASH CHARGE", "HAIPAI", "XIAOLONGBAO",
    "NOODLES", "CONVENIENCE", "PHOTO", "HAIR SALON", "SKYRUSH", "LAUNDRY",
    "BOOKS", "COFFEE", "DIM SUM", "OPTICAL", "BATHHOUSE", "HOSTEL",
    "TOBACCO", "NOODLE BAR", "HOME COOKING", "HARDWARE", "GROCERY", "PHARMACY",
    "HOTEL", "WATCHES", "DRY CLEAN", "DUMPLINGS", "TEA HOUSE", "KTV",
    "CYBER CAFE", "SALON", "FASHION", "ELECTRICS", "BARBER", "FRUIT",
    "AUTO PARTS", "LATE NIGHT", "BOOKSHOP", "FLOWERS", "PHARMACY 2", "ELECTRIC",
    "PROPERTY", "LOTTERY", "PHOTO 2", "OPTICAL 2", "LOGISTICS", "AUTO 2",
    "SUPERMARKET", "INN", "BOOKSTORE", "BEAUTY", "MARKET", "KEY CUT",
]

BOX_COLOURS = [(200, 30, 40), (232, 120, 20), (20, 90, 180), (200, 170, 30),
               (20, 140, 90), (150, 40, 160), (200, 60, 140), (30, 30, 34),
               (120, 40, 30), (40, 120, 120), (90, 40, 120), (170, 90, 40),
               (60, 70, 110), (140, 120, 40), (40, 110, 60), (110, 50, 70)]


def font(path, size):
    return ImageFont.truetype(path, size)


def available_fonts():
    """The fonts that are actually installed."""
    return [p for p in FONTS if os.path.exists(p)]


def _bbox(text, fnt):
    d = ImageDraw.Draw(Image.new("L", (1, 1)))
    return d.textbbox((0, 0), text, font=fnt)


def _rotated(index):
    """The font list, rotated so a different face can be asked for."""
    fonts = available_fonts()
    if not fonts:
        raise RuntimeError("no CJK sign font is installed")
    k = index % len(fonts)
    return fonts[k:] + fonts[:k]


def fit_vertical(name, cell_w, cell_h, margin=0.04, font_index=0):
    """Font, size and the glyph boxes of a vertical stack of characters.

    The characters are NEVER truncated: the font is shrunk until the whole name
    fits inside the cell minus the margin, and the result is asserted.
    """
    limit_w = cell_w * (1.0 - 2.0 * margin)
    limit_h = cell_h * (1.0 - 2.0 * margin)
    n = max(1, len(name))
    for path in _rotated(font_index):
        size = int(limit_h / n)
        for _ in range(6):
            fnt = font(path, max(8, size))
            boxes = [_bbox(ch, fnt) for ch in name]
            widths = [b[2] - b[0] for b in boxes]
            heights = [b[3] - b[1] for b in boxes]
            if max(widths) <= limit_w and sum(heights) <= limit_h:
                return path, fnt, boxes
            size = int(size * 0.86)
    raise ValueError("blade %r does not fit in %dx%d" % (name, cell_w, cell_h))


def fit_horizontal(name, max_w, max_h, font_index=0):
    """Font, size and the glyph box of a single line of text."""
    for path in _rotated(font_index):
        size = int(max_h)
        for _ in range(6):
            fnt = font(path, max(8, size))
            bb = _bbox(name, fnt)
            if bb[2] - bb[0] <= max_w and bb[3] - bb[1] <= max_h:
                return path, fnt, bb
            size = int(size * 0.9)
    raise ValueError("fascia %r does not fit in %dx%d" % (name, max_w, max_h))


def neon_mask(size, xy, text, fnt):
    """A mask of the text (255 = glyph)."""
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).text(xy, text, font=fnt, fill=255)
    return mask


def draw_neon(img, mask, colour, core_erode=3, glow=1.0):
    """Composite a neon tube: coloured tube, white-hot core, coloured halo (numpy)."""
    import numpy as np
    arr = np.asarray(img).astype(np.float32)
    tube = np.asarray(mask.filter(ImageFilter.MaxFilter(3))).astype(np.float32) / 255.0
    halo = np.asarray(mask.filter(ImageFilter.GaussianBlur(9))).astype(np.float32) / 255.0
    core = mask
    for _ in range(max(0, core_erode)):
        core = core.filter(ImageFilter.MinFilter(3))
    c = np.asarray(core).astype(np.float32) / 255.0
    col = np.array(colour, dtype=np.float32)
    arr = arr * (1.0 - (tube * 0.88)[..., None]) + col[None, None, :] * (tube * 0.88)[..., None]
    k = (c ** 2)[..., None]
    arr = arr * (1.0 - k) + np.array([255.0, 250.0, 238.0], dtype=np.float32)[None, None, :] * k
    arr = arr + col[None, None, :] * (halo * 0.55 * glow)[..., None]
    img.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)))


def draw_vertical_cell(cell, name, colour, dead=False, font_index=0):
    """A blade sign: dark back plate, coloured border, stacked characters in neon."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(16, 16, 20))
    d.rectangle([8, 8, w - 9, h - 9], outline=colour, width=5)
    path, fnt, boxes = fit_vertical(name, w, h, font_index=font_index)
    total = sum(b[3] - b[1] for b in boxes)
    y = (h - total) * 0.5
    for i, ch in enumerate(name):
        bb = boxes[i]
        x = (w - (bb[2] - bb[0])) * 0.5 - bb[0]
        m = neon_mask(cell.size, (x, y - bb[1]), ch, fnt)
        draw_neon(cell, m, colour)
        if dead and i == len(name) - 1:
            d.rectangle([x - 3, y - 3, x + bb[2] - bb[0] + 3, y + bb[3] - bb[1] + 3],
                        fill=(16, 16, 20))
        y += bb[3] - bb[1]



def draw_box_cell(cell, name, english, ground, ink, font_index=0):
    """A printed backlit fascia lightbox: coloured ground, a logo mark, the shop name,
    an English sub-line and a fictional phone number."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=ground)
    d.rectangle([0, 0, w - 1, h - 1], outline=ink, width=max(2, h // 24))
    # a small logo mark (a circle with a bar) at the left
    r = int(h * 0.30)
    cx = int(h * 0.52)
    d.ellipse([cx - r, h // 2 - r, cx + r, h // 2 + r], outline=ink, width=max(2, h // 24))
    d.rectangle([cx - r // 2, h // 2 - r // 2, cx + r // 2, h // 2 + r // 2], fill=ink)
    left = cx + r + 8
    path, fnt, bb = fit_horizontal(name, w - left - 12, int(h * 0.42), font_index)
    d.text((left, h * 0.16 - bb[1]), name, font=fnt, fill=ink)
    sub = font(path, max(8, int(h * 0.16)))
    d.text((left + 2, h * 0.68), english, font=sub, fill=ink)
    tel = "TEL 5%07d" % (1000000 + (sum(ord(c) for c in name) * 7919 % 8999999))
    tb = _bbox(tel, sub)
    d.text((w - (tb[2] - tb[0]) - 14, h * 0.68), tel, font=sub, fill=ink)


def draw_plaque_cell(cell, name, font_index=0):
    """A carved stone plaque: incised dark characters on pale stone."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(207, 200, 184))
    d.rectangle([4, 4, w - 5, h - 5], outline=(150, 142, 124), width=max(2, h // 32))
    path, fnt, bb = fit_horizontal(name, w - 24, int(h * 0.52), font_index)
    x = (w - (bb[2] - bb[0])) * 0.5 - bb[0]
    y = (h - (bb[3] - bb[1])) * 0.5 - bb[1]
    d.text((x + 3, y + 3), name, font=fnt, fill=(160, 152, 136))   # the cut shadow
    d.text((x, y), name, font=fnt, fill=(42, 38, 34))              # the incised character
