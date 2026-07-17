# -*- coding: utf-8 -*-
"""
日常词汇 — 主题图解目录（人工定稿，不交给 GPT）。

与 lesson_catalog.py（生活场景 ×6 国）的区别：
  - 主题课是「图解词典板」：按语义主题组词（身体/颜色/水果…），全球通用，
    只生成一版（伪国家 "daily"），美式拼写 + en-US 发音。
  - 无 anchor / 无国家品牌语境 / culture_tips 定位为「用法小贴士」。

OSS 目录：lessons/daily/{lesson_id}/…（与国家目录同构，App 复用同一套接口）。
课堂 id 约定：lesson_daily_{slug}

结构：
  THEME_CATEGORIES   6 大类（App 端 chips 顺序 = LessonStore.themeCategoryOrder）
  THEME_BOARDS       主题板定义（zones[].hint 告诉 GPT 该板希望覆盖的词方向）
  FREE_THEME_SLUGS   免费课（每批 3 门，覆盖 3 个大类）
  all_theme_lessons() 展开成课堂定义列表（字段与 lesson_catalog.all_lessons() 对齐）
"""

THEME_CATEGORIES = {
    "body":     {"zh": "人与身体", "icon_emoji": "🧍"},
    "basics":   {"zh": "基础概念", "icon_emoji": "🔢"},
    "home":     {"zh": "家与日用", "icon_emoji": "🏠"},
    "grocery":  {"zh": "食物食材", "icon_emoji": "🥕"},
    "clothing": {"zh": "穿着", "icon_emoji": "👕"},
    "outdoor":  {"zh": "户外与自然", "icon_emoji": "🌳"},
}

# 免费课：身体部位 / 数字与时间 / 水果（覆盖三个大类，图解体验最好的选题）
FREE_THEME_SLUGS = {"body_parts", "numbers_time", "fruits"}


def _t(zh, en):
    return {"zh": zh, "en": en}


# === 主题板（首批 12 课，每大类 2 课）===
# zones[].hint 给 GPT 的词方向；图解板画风由 generate_lesson_images 的 daily 分支控制
# （单主体大图 + 词典式铺排，而非环境场景）。
THEME_BOARDS = [
    # ---------- 人与身体 ----------
    {
        "slug": "body_parts", "category": "body", "icon": "figure.arms.open",
        "title": _t("身体部位", "Parts of the Body"),
        "zones": [
            {"id": "full_body", **_t("全身", "The Full Body"),
             "hint": "one front-facing person: head, neck, shoulder, chest, arm, elbow, hand, leg, knee, foot"},
            {"id": "hands_feet", **_t("手与脚", "Hands & Feet"),
             "hint": "close-up of a hand and a foot: finger, thumb, nail, wrist, palm, ankle, toe, heel"},
        ],
    },
    {
        "slug": "face", "category": "body", "icon": "face.smiling.fill",
        "title": _t("脸与五官", "The Face"),
        "zones": [
            {"id": "face_features", **_t("五官", "Face Features"),
             "hint": "one large friendly face: forehead, eyebrow, eye, nose, cheek, mouth, lip, chin, ear"},
            {"id": "hair_details", **_t("头发与细节", "Hair & Details"),
             "hint": "heads with different styles: hair, bangs, ponytail, beard, mustache, eyelash, teeth, tongue"},
        ],
    },
    # ---------- 基础概念 ----------
    {
        "slug": "numbers_time", "category": "basics", "icon": "clock.fill",
        "title": _t("数字与时间", "Numbers & Time"),
        "zones": [
            {"id": "telling_time", **_t("看时间", "Telling Time"),
             "hint": "clock, hour hand, minute hand, alarm clock, watch, calendar, schedule; expressions like o'clock, half past, quarter to, a.m./p.m. go to extra_words"},
            {"id": "numbers_in_life", **_t("生活中的数字", "Numbers in Life"),
             "hint": "price tag, receipt, elevator buttons, phone keypad, scale, thermometer, house number; dozens/percent/date expressions in extra_words"},
        ],
    },
    {
        "slug": "colors_shapes", "category": "basics", "icon": "paintpalette.fill",
        "title": _t("颜色与形状", "Colors & Shapes"),
        "zones": [
            {"id": "colors", **_t("颜色", "Colors"),
             "hint": "objects that carry each color clearly: red apple, orange carrot, yellow lemon, green leaf, blue sky patch, purple grapes, pink flower, brown bear, black cat, white cloud — the WORD is the color"},
            {"id": "shapes", **_t("形状", "Shapes"),
             "hint": "clean geometric cutouts: circle, square, triangle, rectangle, star, heart, diamond, oval"},
        ],
    },
    # ---------- 家与日用 ----------
    {
        "slug": "kitchen", "category": "home", "icon": "refrigerator.fill",
        "title": _t("厨房", "The Kitchen"),
        "zones": [
            {"id": "cooking_area", **_t("灶台区", "The Cooking Area"),
             "hint": "stove, pot, pan, kettle, oven, microwave, fridge, range hood"},
            {"id": "sink_prep", **_t("水槽与备菜", "Sink & Prep"),
             "hint": "sink, tap/faucet, cutting board, kitchen knife, bowl, sponge, dish rack, trash can"},
        ],
    },
    {
        "slug": "everyday_items", "category": "home", "icon": "bag.fill",
        "title": _t("随身物品", "Everyday Carry"),
        "zones": [
            {"id": "in_your_bag", **_t("包里", "In Your Bag"),
             "hint": "wallet, keys, earphones, charger, power bank, tissues, umbrella, lip balm"},
            {"id": "on_the_desk", **_t("桌面上", "On the Desk"),
             "hint": "phone, laptop, water bottle, glasses, watch, notebook, pen, lamp"},
        ],
    },
    # ---------- 食物食材 ----------
    {
        "slug": "fruits", "category": "grocery", "icon": "basket.fill",
        "title": _t("水果", "Fruits"),
        "zones": [
            {"id": "common_fruits", **_t("常见水果", "Everyday Fruits"),
             "hint": "apple, banana, orange, grape, strawberry, watermelon, pear, peach"},
            {"id": "tropical_berries", **_t("热带与浆果", "Tropical & Berries"),
             "hint": "mango, pineapple, kiwi, blueberry, cherry, lemon, coconut, avocado"},
        ],
    },
    {
        "slug": "vegetables", "category": "grocery", "icon": "carrot.fill",
        "title": _t("蔬菜", "Vegetables"),
        "zones": [
            {"id": "everyday_veggies", **_t("常吃的菜", "Everyday Veggies"),
             "hint": "tomato, potato, carrot, onion, cucumber, lettuce, broccoli, corn"},
            {"id": "asian_kitchen", **_t("中式厨房常客", "Asian Kitchen Staples"),
             "hint": "garlic, ginger, green onion/scallion, mushroom, eggplant, chili pepper, cabbage, spinach"},
        ],
    },
    # ---------- 穿着 ----------
    {
        "slug": "clothes", "category": "clothing", "icon": "tshirt.fill",
        "title": _t("衣物", "Clothes"),
        "zones": [
            {"id": "tops", **_t("上装", "Tops"),
             "hint": "T-shirt, shirt, sweater, hoodie, jacket, coat, vest"},
            {"id": "bottoms_more", **_t("下装与全身", "Bottoms & One-Pieces"),
             "hint": "jeans, pants/trousers, shorts, skirt, dress, pajamas, socks, underwear"},
        ],
    },
    {
        "slug": "accessories", "category": "clothing", "icon": "eyeglasses",
        "title": _t("鞋帽与配饰", "Shoes & Accessories"),
        "zones": [
            {"id": "shoes", **_t("鞋", "Shoes"),
             "hint": "sneakers, boots, sandals, slippers, high heels, flip-flops, shoelace"},
            {"id": "accessories", **_t("配饰", "Accessories"),
             "hint": "hat, cap, scarf, gloves, belt, tie, backpack, sunglasses, earrings"},
        ],
    },
    # ---------- 户外与自然 ----------
    {
        "slug": "vehicles", "category": "outdoor", "icon": "bus.fill",
        "title": _t("交通工具", "Getting Around"),
        "zones": [
            {"id": "on_the_road", **_t("路上", "On the Road"),
             "hint": "car, bus, taxi, bicycle, motorcycle, truck, scooter"},
            {"id": "rail_air_sea", **_t("轨道与远行", "Rail, Air & Sea"),
             "hint": "train, subway, high-speed train, plane, ship, ferry, helicopter"},
        ],
    },
    {
        "slug": "street", "category": "outdoor", "icon": "signpost.right.fill",
        "title": _t("街道设施", "On the Street"),
        "zones": [
            {"id": "street_corner", **_t("街角", "The Street Corner"),
             "hint": "traffic light, crosswalk, sidewalk, street sign, bus stop, bench, trash can, streetlight"},
            {"id": "around_the_block", **_t("街区里", "Around the Block"),
             "hint": "mailbox, fire hydrant, fountain, billboard, vending machine, parking meter, fence"},
        ],
    },
]


def all_theme_lessons():
    """展开成课堂定义列表（字段与 lesson_catalog.all_lessons() 对齐，
    多一个 is_theme=True 供生成脚本分支）。"""
    lessons = []
    for board in THEME_BOARDS:
        lessons.append({
            "id": "lesson_daily_%s" % board["slug"],
            "slug": board["slug"],
            "country": "daily",
            "category": board["category"],
            "category_zh": THEME_CATEGORIES[board["category"]]["zh"],
            "icon": board["icon"],
            "title_zh": board["title"]["zh"],
            "title_en": board["title"]["en"],
            "anchor": "",
            "zones": board["zones"],
            "is_free": board["slug"] in FREE_THEME_SLUGS,
            "is_theme": True,
        })
    return lessons


if __name__ == "__main__":
    ls = all_theme_lessons()
    print("themes: %d lessons, %d free" % (len(ls), sum(1 for l in ls if l["is_free"])))
    by_cat = {}
    for l in ls:
        by_cat.setdefault(l["category"], []).append(l)
    for cat, meta in THEME_CATEGORIES.items():
        items = by_cat.get(cat, [])
        print("  %s %s: %s" % (meta["icon_emoji"], meta["zh"],
                               ", ".join(i["title_zh"] for i in items)))
