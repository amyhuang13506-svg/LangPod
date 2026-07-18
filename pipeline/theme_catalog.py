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
  THEME_CATEGORIES   8 大类（App 端 chips 顺序 = LessonStore.themeCategoryOrder）
  THEME_BOARDS       主题板定义（zones[].hint 告诉 GPT 该板希望覆盖的词方向）
  FREE_THEME_SLUGS   免费课（每大类第一课免费）
  all_theme_lessons() 展开成课堂定义列表（字段与 lesson_catalog.all_lessons() 对齐）

分类配色：每个大类一套底色（同生活场景「一国一色」的做法），复用 6 国已定稿的
色系 + body 沿用主题板初版的浅青 + basics 新增黄油黄，共 8 色互不重样。
palette 只染背景，物体一律保持真实自然色（图解词典靠颜色认物）。
"""

# palette = 该大类图解板的底色色系（generate_lesson_images.theme_palette 组装完整 prompt）
# 色系复用来源：sg 金橙 / us 奶油 / 主题板初版浅青 / ca 粉玫 / uk 天蓝 / au 草绿 / nz 薰衣草
# + 新增兰紫（basics）。
#
# ⚠️ 8 个粉彩底色排在一起，必须拉开色相距离，否则用户看不出差别。实测教训：
# basics 初版用 butter-yellow (#fdf6c2) 和 home 的 warm cream (#fef1ce) 只差 RGB 13，
# 肉眼就是同一个色 —— 改成兰紫（色相 ~310°，离 work 的薰衣草 260° 和 clothing 的
# 粉玫 15° 各差 50°+）。改色前先用四角像素采样比一比（见 git log）。
THEME_CATEGORIES = {
    "grocery":   {"zh": "食物",      "icon_emoji": "🥕", "palette": "warm golden-amber and coral"},
    "home":      {"zh": "家居",      "icon_emoji": "🏠", "palette": "warm cream and soft honey"},
    "body":      {"zh": "身体", "icon_emoji": "🧍", "palette": "pale-aqua and soft teal"},
    "clothing":  {"zh": "穿着",      "icon_emoji": "👕", "palette": "fresh blush-pink and rose"},
    "transport": {"zh": "出行", "icon_emoji": "🚌", "palette": "fresh sky-blue and cornflower"},
    "nature":    {"zh": "自然", "icon_emoji": "🌳", "palette": "fresh sage-green and mint"},
    "work":      {"zh": "工作", "icon_emoji": "💼", "palette": "fresh lavender and soft periwinkle"},
    "basics":    {"zh": "基础",   "icon_emoji": "🔢", "palette": "soft orchid and light mauve"},
}

# 免费课：每大类一门。nature / work 的免费课随该类内容批次补上（届时补进本集合）。
FREE_THEME_SLUGS = {
    "fruits",        # 食物
    "kitchen",       # 家居
    "body_parts",    # 身体与健康
    "clothes",       # 穿着
    "vehicles",      # 出行与城市
    "numbers_time",  # 基础概念
}


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
             "hint": "clock, hour hand, minute hand, alarm clock, watch, calendar, schedule; single-word expressions like noon, midnight, o'clock go to extra_words (avoid words with slashes or dots like a.m.)"},
            {"id": "numbers_in_life", **_t("生活中的数字", "Numbers in Life"),
             "hint": "price tag, receipt, elevator button, keypad, scale, thermometer, house number; dozen/percent/date expressions in extra_words"},
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
             "hint": "sneakers, boots, sandals, slippers, high heels, flip-flops"},
            {"id": "accessories", **_t("配饰", "Accessories"),
             "hint": "hat, cap, scarf, gloves, belt, necktie, backpack, sunglasses, earrings (use 'tie' only once in the whole lesson)"},
        ],
    },
    # ---------- 出行与城市 ----------
    {
        "slug": "vehicles", "category": "transport", "icon": "bus.fill",
        "title": _t("交通工具", "Getting Around"),
        "zones": [
            {"id": "on_the_road", **_t("路上", "On the Road"),
             "hint": "car, bus, taxi, bicycle, motorcycle, truck, scooter"},
            {"id": "rail_air_sea", **_t("轨道与远行", "Rail, Air & Sea"),
             "hint": "train, subway, high-speed train, plane, ship, ferry, helicopter"},
        ],
    },
    {
        "slug": "street", "category": "transport", "icon": "signpost.right.fill",
        "title": _t("街道设施", "On the Street"),
        "zones": [
            {"id": "street_corner", **_t("街角", "The Street Corner"),
             "hint": "traffic light, crosswalk, sidewalk, street sign, bus stop, bench, trash can, streetlight"},
            {"id": "around_the_block", **_t("街区里", "Around the Block"),
             "hint": "mailbox, fire hydrant, fountain, billboard, vending machine, parking meter, fence"},
        ],
    },

    # ================= B1 批次：食物 +10 =================
    {
        "slug": "meat_eggs", "category": "grocery", "icon": "fork.knife",
        "title": _t("肉与蛋", "Meat & Eggs"),
        "zones": [
            {"id": "meat_counter", **_t("肉柜", "At the Meat Counter"),
             "hint": "beef, pork, chicken, lamb, steak, ribs, ham, bacon — raw cuts laid out on a counter"},
            {"id": "eggs_and_cuts", **_t("蛋与部位", "Eggs & Cuts"),
             "hint": "egg, egg yolk, eggshell, drumstick, chicken wing, ground meat, sausage; raw/cooked/tender expressions go to extra_words"},
        ],
    },
    {
        "slug": "seafood", "category": "grocery", "icon": "fish.fill",
        "title": _t("海鲜", "Seafood"),
        "zones": [
            {"id": "fish_stall", **_t("鱼摊", "The Fish Stall"),
             "hint": "fish, salmon, tuna, fish fillet, fish head, fish tail, ice tray, tongs"},
            {"id": "shellfish", **_t("贝类与虾蟹", "Shellfish"),
             "hint": "shrimp, crab, lobster, clam, oyster, scallop, squid, mussel"},
        ],
    },
    {
        "slug": "dairy", "category": "grocery", "icon": "takeoutbag.and.cup.and.straw.fill",
        "title": _t("乳制品", "Dairy"),
        "zones": [
            {"id": "milk_shelf", **_t("冷藏柜", "The Dairy Case"),
             "hint": "milk carton, yogurt cup, butter, cheese, cream, sour cream — items on a fridge shelf"},
            {"id": "cheese_board", **_t("奶酪与更多", "Cheese & More"),
             "hint": "cheese slice, cheese wheel, shredded cheese, ice cream, whipped cream, condensed milk"},
        ],
    },
    {
        "slug": "staples", "category": "grocery", "icon": "birthday.cake.fill",
        "title": _t("主食与面点", "Bread & Staples"),
        "zones": [
            {"id": "bakery", **_t("面包房", "At the Bakery"),
             "hint": "bread loaf, baguette, bun, croissant, bagel, toast, muffin, donut"},
            {"id": "grains", **_t("米面谷物", "Rice & Grains"),
             "hint": "rice, noodles, pasta, flour, oatmeal, cereal, corn tortilla, dumpling"},
        ],
    },
    {
        "slug": "drinks", "category": "grocery", "icon": "cup.and.saucer.fill",
        "title": _t("饮料", "Drinks"),
        "zones": [
            {"id": "cold_drinks", **_t("冷饮", "Cold Drinks"),
             "hint": "water bottle, soda can, juice box, iced tea, smoothie, milkshake, sports drink"},
            {"id": "hot_drinks", **_t("热饮", "Hot Drinks"),
             "hint": "coffee mug, teapot, tea bag, hot chocolate, espresso cup, thermos, kettle steam"},
        ],
    },
    {
        "slug": "seasoning", "category": "grocery", "icon": "drop.fill",
        "title": _t("调味料", "Seasonings"),
        "zones": [
            {"id": "spice_rack", **_t("调料架", "The Spice Rack"),
             "hint": "salt shaker, pepper mill, sugar jar, chili powder, cinnamon stick, garlic clove, herb leaves"},
            {"id": "sauces", **_t("酱料与油", "Sauces & Oils"),
             "hint": "soy sauce bottle, vinegar, cooking oil, ketchup, mustard, mayonnaise, honey jar, hot sauce"},
        ],
    },
    {
        "slug": "snacks", "category": "grocery", "icon": "popcorn.fill",
        "title": _t("零食与甜点", "Snacks & Sweets"),
        "zones": [
            {"id": "snack_aisle", **_t("零食货架", "The Snack Aisle"),
             "hint": "potato chips bag, popcorn, cookies, crackers, nuts, candy, chocolate bar, gum"},
            {"id": "desserts", **_t("甜点", "Desserts"),
             "hint": "cake slice, cupcake, pie, pudding, jelly, lollipop, marshmallow, waffle"},
        ],
    },
    {
        "slug": "tableware", "category": "grocery", "icon": "fork.knife.circle.fill",
        "title": _t("餐具与厨具", "Tableware & Utensils"),
        "zones": [
            {"id": "table_setting", **_t("餐桌摆盘", "The Table Setting"),
             "hint": "plate, fork, table knife, spoon, chopsticks, napkin, drinking glass, placemat"},
            {"id": "kitchen_utensils", **_t("厨房小工具", "Kitchen Utensils"),
             "hint": "ladle, spatula, whisk, peeler, grater, measuring cup, rolling pin, colander"},
        ],
    },
    {
        # 动作板：热点是动词本身（每个动词画成一格小图），不是动作里的物体。
        # 没有 board_type 的话模板会强制「热点必须是具体物体」，动词全被挤进
        # extra_words，热点退化成 carrot/potato/pan/pot —— 还和蔬菜课、餐具课撞词。
        "slug": "cooking_verbs", "category": "grocery", "icon": "flame.fill",
        "board_type": "action",
        "title": _t("烹饪动作", "Cooking Actions"),
        "zones": [
            {"id": "prep_actions", **_t("备菜", "Prepping"),
             "hint": "hands performing each prep action: chop, peel, wash, grate, crack, pour "
                     "(slice looks the same as chop — extra_words)"},
            {"id": "heat_actions", **_t("下锅", "Cooking with Heat"),
             "hint": "each cooking-with-heat action in progress: boil, fry, steam, bake, grill, reheat. "
                     "roast draws the same as bake and simmer the same as boil — extra_words"},
        ],
    },
    {
        "slug": "supermarket", "category": "grocery", "icon": "cart.fill",
        "title": _t("逛超市", "At the Supermarket"),
        "zones": [
            {"id": "shopping", **_t("挑货", "Down the Aisles"),
             "hint": "shopping cart, shopping basket, aisle shelf, price tag, freezer, produce scale, trolley"},
            {"id": "checkout", **_t("结账", "At the Checkout"),
             "hint": "cash register, conveyor belt, barcode scanner, receipt, grocery bag, card reader, coupon"},
        ],
    },

    # ================= B1 批次：家居 +8 =================
    {
        "slug": "living_room", "category": "home", "icon": "sofa.fill",
        "title": _t("客厅", "The Living Room"),
        "zones": [
            {"id": "seating", **_t("沙发区", "The Seating Area"),
             "hint": "sofa, armchair, coffee table, cushion, throw blanket, rug, floor lamp"},
            {"id": "tv_wall", **_t("电视墙", "The TV Wall"),
             "hint": "television, remote control, bookshelf, picture frame, houseplant, curtain, wall clock"},
        ],
    },
    {
        "slug": "bedroom", "category": "home", "icon": "bed.double.fill",
        "title": _t("卧室", "The Bedroom"),
        "zones": [
            {"id": "the_bed", **_t("床", "The Bed"),
             "hint": "bed, pillow, blanket, bed sheet, mattress, headboard, nightstand, alarm clock"},
            {"id": "storage", **_t("收纳", "Storage & Corners"),
             "hint": "wardrobe, closet, dresser, drawer, hanger, mirror, laundry basket, slippers"},
        ],
    },
    {
        "slug": "bathroom", "category": "home", "icon": "shower.fill",
        "title": _t("浴室", "The Bathroom"),
        "zones": [
            {"id": "wash_area", **_t("洗漱区", "The Wash Area"),
             "hint": "sink basin, faucet, mirror, toothbrush, toothpaste, soap, hand towel, razor"},
            {"id": "shower_area", **_t("淋浴与马桶", "Shower & Toilet"),
             "hint": "shower head, bathtub, shower curtain, toilet, toilet paper, bath towel, shampoo bottle, bath mat"},
        ],
    },
    {
        "slug": "cleaning", "category": "home", "icon": "bubbles.and.sparkles.fill",
        "title": _t("家务与清洁", "Chores & Cleaning"),
        "zones": [
            {"id": "cleaning_tools", **_t("清洁工具", "Cleaning Tools"),
             "hint": "broom, dustpan, mop, bucket, vacuum cleaner, feather duster, rubber gloves, trash bag"},
            {"id": "supplies", **_t("清洁用品", "Supplies"),
             "hint": "detergent bottle, dish soap, sponge, scrub brush, spray bottle, paper towel roll, laundry pod"},
        ],
    },
    {
        "slug": "tools", "category": "home", "icon": "hammer.fill",
        "title": _t("工具与维修", "Tools & Repairs"),
        "zones": [
            {"id": "toolbox", **_t("工具箱", "The Toolbox"),
             "hint": "hammer, screwdriver, wrench, pliers, nail, screw, tape measure, toolbox"},
            {"id": "around_the_house", **_t("修修补补", "Fixing Things"),
             "hint": "ladder, drill, saw, paint can, paintbrush, duct tape, light bulb, flashlight"},
        ],
    },
    {
        "slug": "appliances", "category": "home", "icon": "washer.fill",
        "title": _t("家电", "Appliances"),
        "zones": [
            {"id": "big_appliances", **_t("大件", "The Big Ones"),
             "hint": "washing machine, dryer, dishwasher, air conditioner, water heater, vacuum robot, heater"},
            {"id": "small_appliances", **_t("小家电", "Small Appliances"),
             "hint": "toaster, blender, rice cooker, electric fan, hair dryer, iron, coffee maker, power strip"},
        ],
    },
    {
        "slug": "balcony_garden", "category": "home", "icon": "leaf.fill",
        "title": _t("阳台与庭院", "Balcony & Yard"),
        "zones": [
            {"id": "balcony", **_t("阳台", "On the Balcony"),
             "hint": "clothesline, clothespin, drying rack, potted plant, railing, folding chair, watering can"},
            {"id": "yard", **_t("庭院", "In the Yard"),
             "hint": "lawn, garden hose, rake, shovel, flowerbed, mailbox post, garden gnome, barbecue grill"},
        ],
    },
    {
        "slug": "building", "category": "home", "icon": "building.2.fill",
        "title": _t("公寓与楼道", "Apartment Building"),
        "zones": [
            {"id": "entrance", **_t("门口", "The Entrance"),
             "hint": "front door, doorbell, door handle, keyhole, doormat, intercom panel, mailbox wall, house key"},
            {"id": "hallway", **_t("楼道", "Halls & Stairs"),
             "hint": "staircase, handrail, elevator door, hallway light, fire extinguisher, trash chute, parking garage"},
        ],
    },

    # ================= B2 批次：身体与健康 +8 =================
    {
        "slug": "daily_actions", "category": "body", "icon": "figure.walk",
        "board_type": "action",
        "title": _t("日常动作", "Everyday Actions"),
        "zones": [
            {"id": "moving", **_t("身体移动", "Moving Around"),
             "hint": "walk, run, jump, sit, stand, climb (crawl and kneel draw much like sit — extra_words)"},
            {"id": "routines", **_t("日常起居", "Daily Routines"),
             "hint": "sleep, eat, drink, wash, brush, read (write draws much like read — extra_words)"},
        ],
    },
    {
        "slug": "emotions", "category": "body", "icon": "face.smiling.fill",
        "board_type": "state",
        "title": _t("情绪与感受", "Feelings"),
        "zones": [
            {"id": "core_feelings", **_t("基本情绪", "Core Feelings"),
             "hint": "each feeling on one face and posture: happy, sad, angry, scared, surprised, tired "
                     "(upset draws like sad, furious like angry — extra_words)"},
            {"id": "everyday_moods", **_t("日常状态", "Everyday Moods"),
             "hint": "bored, excited, nervous, relaxed, confused, embarrassed"},
        ],
    },
    {
        "slug": "appearance", "category": "body", "icon": "person.fill",
        "board_type": "state",
        "title": _t("外貌与体型", "What People Look Like"),
        "zones": [
            {"id": "build", **_t("身材", "Build & Height"),
             "hint": "contrast pairs on drawn people: tall, short, slim, heavy, strong, young, old"},
            {"id": "looks", **_t("样子", "Looks"),
             "hint": "curly, straight, bald, blonde, freckled, tanned — each on a distinct drawn person"},
        ],
    },
    {
        "slug": "family", "category": "body", "icon": "figure.2.and.child.holdinghands",
        "title": _t("家庭称谓", "Family"),
        "zones": [
            {"id": "close_family", **_t("直系", "Close Family"),
             "hint": "one family group portrait: father, mother, son, daughter, brother, sister, baby"},
            {"id": "relatives", **_t("亲戚", "Relatives"),
             "hint": "a wider family gathering: grandfather, grandmother, uncle, aunt, cousin, nephew, niece"},
        ],
    },
    {
        "slug": "symptoms", "category": "body", "icon": "thermometer.medium",
        "board_type": "state",
        "title": _t("症状与不适", "Not Feeling Well"),
        "zones": [
            {"id": "common_symptoms", **_t("常见症状", "Common Symptoms"),
             "hint": "each shown on one person: headache, fever, cough, runny nose, sore throat, stomachache"},
            {"id": "other_troubles", **_t("其它不适", "Other Troubles"),
             "hint": "dizzy, itchy, sneeze, toothache, backache, sprained ankle"},
        ],
    },
    {
        "slug": "doctor_pharmacy", "category": "body", "icon": "cross.case.fill",
        "title": _t("看医生与买药", "Doctor & Pharmacy"),
        "zones": [
            {"id": "at_the_doctor", **_t("诊室", "At the Doctor's"),
             "hint": "stethoscope, thermometer, blood pressure cuff, examination table, syringe, prescription pad, face mask"},
            {"id": "at_the_pharmacy", **_t("药房", "At the Pharmacy"),
             "hint": "pill bottle, tablet, capsule, cough syrup, bandage, ointment tube, pharmacy shelf"},
        ],
    },
    {
        "slug": "hospital", "category": "body", "icon": "building.2.crop.circle.fill",
        "title": _t("牙医与医院", "Dentist & Hospital"),
        "zones": [
            {"id": "dentist", **_t("牙科", "At the Dentist"),
             "hint": "dental chair, dental mirror, drill, x-ray image, braces, floss, spit sink"},
            {"id": "hospital_ward", **_t("医院里", "In the Hospital"),
             "hint": "hospital bed, IV drip, wheelchair, crutches, cast, monitor screen, nurse call button"},
        ],
    },
    {
        "slug": "fitness", "category": "body", "icon": "dumbbell.fill",
        "title": _t("健身与作息", "Fitness & Rest"),
        "zones": [
            {"id": "at_the_gym", **_t("健身房", "At the Gym"),
             "hint": "dumbbell, treadmill, yoga mat, jump rope, exercise bike, water bottle, gym towel"},
            {"id": "rest", **_t("休息与作息", "Rest & Sleep"),
             "hint": "pillow, eye mask, earplugs, sleep tracker watch, herbal tea cup, stretching mat, alarm"},
        ],
    },

    # ================= B2 批次：基础概念 +6 =================
    {
        "slug": "money", "category": "basics", "icon": "banknote.fill",
        "title": _t("金钱与价格", "Money & Prices"),
        "zones": [
            {"id": "cash", **_t("现金", "Cash"),
             "hint": "coin, bill, wallet, purse, piggy bank, change tray, cash stack"},
            {"id": "paying", **_t("付款", "Paying"),
             "hint": "credit card, ATM, bank card reader, checkbook, invoice, discount sign, shopping receipt"},
        ],
    },
    {
        "slug": "position", "category": "basics", "icon": "arrow.up.left.and.arrow.down.right",
        "board_type": "contrast",
        "title": _t("方位与位置", "Where Things Are"),
        "zones": [
            # image_hint 里一个抽象词都不能出现 —— 递给图模型的是画面，不是词表。
            # 参照物（球+木箱 / 男孩+球）全板锁死不变，关系才读得出来。
            {"id": "basic_position", **_t("基本方位", "Basic Positions"),
             "hint": "same ball and box in each vignette, only the relation changes: on, under, in, out, behind, ahead",
             "image_hint": "A 3x2 grid of six small scenes with generous empty space between them. "
                           "Every scene contains the SAME red rubber ball and the SAME open wooden crate, "
                           "drawn identically each time — only where the ball sits changes: "
                           "(1) the ball resting on top of the closed crate lid; "
                           "(2) the crate raised on short legs, the ball on the ground beneath it; "
                           "(3) the ball sitting down inside the open crate; "
                           "(4) the ball held in the air just above the open crate, the crate now empty; "
                           "(5) the ball mostly hidden behind the crate, only its top edge showing; "
                           "(6) the ball on the ground clearly in front of the crate, closer to the viewer"},
            {"id": "directions", **_t("方向", "Directions"),
             "hint": "left, right, up, down, near, far — each read off where the ball sits relative to the same boy",
             "image_hint": "A 3x2 grid of six small scenes with generous empty space between them. "
                           "Every scene contains the SAME boy in an orange shirt standing facing the viewer and "
                           "the SAME red ball, drawn identically each time — only the ball changes place. "
                           "The red ball MUST appear in all six scenes; a scene without the ball is wrong: "
                           "(1) the ball on the ground at the far left of the scene, the boy turning his head to look at it; "
                           "(2) the ball on the ground at the far right, the boy turning his head to look at it; "
                           "(3) the ball high in the air above the boy's head, the boy looking up at it; "
                           "(4) the ball on the ground at the boy's feet, the boy looking down at it; "
                           "(5) the ball right beside the boy's shoe, almost touching it; "
                           "(6) the ball tiny in the far distance behind the boy, small with distance"},
        ],
    },
    {
        "slug": "quantity", "category": "basics", "icon": "shippingbox.fill",
        "title": _t("数量与包装", "Packs & Portions"),
        "zones": [
            {"id": "containers", **_t("容器", "Containers"),
             "hint": "bottle, can, jar, box, bag, carton, tube — each holding something ordinary"},
            {"id": "portions", **_t("份量", "Portions"),
             "hint": "slice, piece, bunch, pack, roll, bowl, spoonful"},
        ],
    },
    {
        "slug": "size_degree", "category": "basics", "icon": "arrow.up.and.down.text.horizontal",
        "board_type": "contrast",
        "title": _t("大小与程度", "Big, Small & In Between"),
        "zones": [
            # 反义词成对同框：一格里画同一样东西的两个极端，两个词各占一个热点。
            # 拆开画就没得比 —— 单看一个球说不出它"大"。
            {"id": "size", **_t("大小长短", "Size & Length"),
             "hint": "opposites paired in one vignette, same object at both extremes: big, small, long, short, thick, thin",
             "image_hint": "Three scenes in a row with generous empty space between them, each comparing the "
                           "SAME kind of object at two extremes, side by side: "
                           "(1) two red rubber balls, one enormous and one tiny; "
                           "(2) two yellow pencils lying parallel, one very long and one worn down to a stub; "
                           "(3) two blue books standing upright side by side, one very thick and one very thin"},
            {"id": "degree", **_t("轻重冷热", "Weight & Temperature"),
             "hint": "opposites paired in one vignette, same object at both extremes: heavy, light, hot, cold, full, empty",
             "image_hint": "Three scenes in a row, fully inside the frame, with generous empty space between them. "
                           "Each scene compares the SAME kind of object at two extremes, side by side — "
                           "BOTH objects must be drawn in every scene: "
                           "(1) two identical cardboard boxes, each held by its own man: the left man hunched and "
                           "straining under his box, knees bent, face red; the right man holding his box up "
                           "balanced on one fingertip, relaxed and smiling; "
                           "(2) two identical white mugs — one with curling steam rising from it, "
                           "the other with ice cubes in it and frost on its side; "
                           "(3) two identical drinking glasses — one filled to the brim with orange juice, "
                           "the other completely empty"},
        ],
    },
    {
        "slug": "signs", "category": "basics", "icon": "exclamationmark.triangle.fill",
        "title": _t("标志与符号", "Signs & Symbols"),
        "zones": [
            {"id": "public_signs", **_t("公共标志", "Public Signs"),
             "hint": "stop sign, exit sign, restroom sign, no smoking sign, wheelchair sign, warning triangle, arrow sign"},
            {"id": "everyday_symbols", **_t("日常符号", "Everyday Symbols"),
             "hint": "wifi symbol, battery icon, power button, recycle symbol, heart icon, magnifying glass icon, plus sign"},
        ],
    },
    {
        # 「看日历」板退役：today/weekend/holiday/appointment 是日历上的标记，不是独立物体，
        # 定位器认物体在行、认标记不在（同方位/左右的失败）。整块板 5 词全定位不到 → 只留
        # planning 一块实物板（planner/便签/挂历…，6/6 定位）。抽象时间词并入 extra_words 保留。
        "slug": "dates", "category": "basics", "icon": "calendar",
        "title": _t("日程用品", "Planning Tools"),
        "zones": [
            {"id": "planning", **_t("安排日程", "Planning"),
             "hint": "planner, sticky note, wall calendar, desk calendar, reminder on a phone, pen marking a date. "
                     "Put today, weekend, holiday, appointment, date, month, week, year in extra_words — "
                     "they are calendar markings, not pointable objects"},
        ],
    },

    # ================= B3 批次：穿着 +6 =================
    {
        "slug": "underwear", "category": "clothing", "icon": "figure.stand",
        "title": _t("内衣与袜子", "Underwear & Socks"),
        "zones": [
            {"id": "innerwear", **_t("贴身衣物", "Innerwear"),
             "hint": "bra, briefs, boxers, undershirt, camisole, thermal underwear — folded on a shelf, plain and modest"},
            {"id": "legwear", **_t("袜子与腿部", "Socks & Legwear"),
             "hint": "ankle socks, knee socks, tights, leggings, slipper socks, wool socks. Put stockings in extra_words (looks like tights)"},
        ],
    },
    {
        "slug": "bags", "category": "clothing", "icon": "bag.fill",
        "title": _t("包与钱包", "Bags & Wallets"),
        "zones": [
            {"id": "bags", **_t("各种包", "Kinds of Bags"),
             "hint": "handbag, tote bag, shoulder bag, briefcase, suitcase, drawstring bag. Put backpack in extra_words (owned by the accessories lesson)"},
            {"id": "small_carry", **_t("钱包与小件", "Wallets & Small Carry"),
             "hint": "wallet, coin purse, card holder, keychain, cosmetic pouch, luggage tag — small personal carriers laid out"},
        ],
    },
    {
        "slug": "jewelry", "category": "clothing", "icon": "crown.fill",
        "title": _t("首饰与手表", "Jewelry & Watches"),
        "zones": [
            {"id": "jewelry", **_t("首饰", "Jewelry"),
             "hint": "ring, necklace, bracelet, pendant, brooch, anklet. Put earrings in extra_words (owned by the accessories lesson)"},
            {"id": "watch_hair", **_t("手表与发饰", "Watches & Hair Accessories"),
             "hint": "watch, smartwatch, hairpin, hair clip, headband, scrunchie — a watch face plus hair pieces"},
        ],
    },
    {
        "slug": "materials", "category": "clothing", "icon": "square.grid.3x3.fill",
        "title": _t("材质与图案", "Fabrics & Patterns"),
        "zones": [
            {"id": "fabrics", **_t("材质", "Fabrics"),
             "hint": "each word is one fabric swatch with an unmistakable texture: cotton, wool, leather, denim, silk, fur",
             "image_hint": "A row of six square fabric swatches with empty space between them, each a clearly different "
                           "material texture and NO text: plain white woven cotton, thick cream cable-knit wool, "
                           "smooth brown leather, blue jeans denim with a seam, glossy rippling red silk, soft grey fur"},
            {"id": "patterns", **_t("图案", "Patterns"),
             "hint": "each word is one patterned swatch, the pattern is the word: striped, plaid, floral, polka-dot, checkered, solid",
             "image_hint": "A row of six square fabric swatches with empty space between them, each showing ONE pattern and "
                           "NO text: bold horizontal stripes, tartan plaid, scattered flowers, evenly spaced polka dots, "
                           "a checkerboard grid, one flat solid color"},
        ],
    },
    {
        "slug": "laundry", "category": "clothing", "icon": "washer.fill",
        "title": _t("洗衣与护理", "Laundry & Care"),
        "zones": [
            {"id": "washing", **_t("洗衣", "Washing"),
             "hint": "washing machine, dryer, detergent bottle, laundry basket, clothes hanger, clothespin"},
            {"id": "ironing", **_t("熨烫与整理", "Ironing & Tidying"),
             "hint": "iron, ironing board, lint roller, fabric softener, drying rack, laundry bag. Put wrinkle and stain in extra_words (they are marks, not objects)"},
        ],
    },
    {
        "slug": "makeup", "category": "clothing", "icon": "paintbrush.pointed.fill",
        "title": _t("化妆与护肤", "Makeup & Skincare"),
        "zones": [
            {"id": "makeup", **_t("化妆品", "Makeup"),
             "hint": "lipstick, mascara, eyeliner, blush, foundation bottle, eyeshadow palette"},
            {"id": "skincare", **_t("护肤品", "Skincare"),
             "hint": "cleanser, toner bottle, moisturizer jar, sunscreen, sheet mask, cotton pad"},
        ],
    },

    # ================= B3 批次：出行与城市 +9 =================
    {
        "slug": "driving", "category": "transport", "icon": "car.fill",
        "title": _t("开车与路况", "Driving"),
        "zones": [
            {"id": "inside_car", **_t("车里", "Inside the Car"),
             "hint": "steering wheel, seatbelt, dashboard, gas pedal, gear shift, rearview mirror"},
            {"id": "road_stops", **_t("路上", "Out on the Road"),
             "hint": "gas station, parking lot, tunnel, toll booth, speed bump, road cone. Put traffic jam in extra_words (a situation, not one object)"},
        ],
    },
    {
        # on_the_bus 退役：公交内部件（window/bus window/aisle）太 generic，画出来分不清，图模型
        # 每次都退回闪卡模式给每件印字幕（试过明令「无文字」也压不住 —— 物体本身不够独特）。
        # subway_station 的物体（扶梯/闸机/线路图/售票机）个个独特、不需文字就能认，单区块成课。
        # 公交内部件并入 extra_words 保留。
        "slug": "bus_subway", "category": "transport", "icon": "tram.fill",
        "title": _t("地铁站", "The Subway Station"),
        "zones": [
            {"id": "subway_station", **_t("地铁站", "The Subway Station"),
             "hint": "turnstile, platform, escalator, subway map, ticket machine, subway train. "
                     "Put handrail, stop button, fare card, priority seat, aisle in extra_words "
                     "(generic bus-interior parts that don't read without a caption)"},
        ],
    },
    {
        "slug": "airport", "category": "transport", "icon": "airplane",
        "title": _t("机场与飞机", "Airport & Plane"),
        "zones": [
            # boarding pass / departure board 离开文字就认不出（票根 / 黑屏），而它俩正是要教的词
            # → 图模型只能把 BOARDING PASS、DEPARTURE 印上去（还拼错成 DEPARTURE BORD）。换成可画
            # 的实物（登机口、行李转盘、塔台），抽象旅行词进 extra_words 保留。passport 靠护照形状 +
            # 烫金地球认得出，内在烫金可留。
            {"id": "at_the_airport", **_t("在机场", "At the Airport"),
             "hint": "check-in counter, luggage cart, security gate, boarding gate, baggage carousel, control tower. "
                     "Put boarding pass, departure board, passport in extra_words if they can only be told apart by "
                     "printed words"},
            {"id": "on_the_plane", **_t("飞机上", "On the Plane"),
             "hint": "tray table, window shade, overhead bin, life vest, flight attendant, airplane seat"},
        ],
    },
    {
        "slug": "directions", "category": "transport", "icon": "map.fill",
        "title": _t("问路与导航", "Asking Directions"),
        "zones": [
            {"id": "nav_tools", **_t("导航工具", "Finding the Way"),
             "hint": "paper map, GPS on a phone, compass, signpost, landmark tower, street sign. "
                     "Put turn, left, right, straight, block in extra_words — directions are not pointable objects"},
            {"id": "junctions", **_t("路口", "Junctions"),
             "hint": "intersection, crosswalk, corner, roundabout, overpass, pedestrian bridge"},
        ],
    },
    {
        # 店铺天生靠招牌辨识。试过明令「无招牌、只靠货品」，图模型照样把店名印上去（这个先验压
        # 不住）—— 而且反而画得更少更含糊。所以接受店招：真实店铺本就有招牌，橱窗货品也能辨识，
        # App 还叠自己的可点标签，英文店名只是轻微冗余，不像抽象词那样「离开文字就认不出」。
        "slug": "shops", "category": "transport", "icon": "storefront.fill",
        "title": _t("商店类型", "Types of Shops"),
        "zones": [
            {"id": "daily_shops", **_t("日常店铺", "Everyday Shops"),
             "hint": "supermarket, convenience store, bakery, bookstore, flower shop, toy store — six storefronts in a row, "
                     "each with its goods visible in the window (a cart, bread, books, flowers, toys)"},
            {"id": "service_shops", **_t("服务店铺", "Service Shops"),
             "hint": "barber shop, hair salon, laundromat, hardware store, pet shop, repair shop — six storefronts, "
                     "each shown with the iconic objects of its trade (barber pole, styling chair, washing machines, tools, a puppy)"},
        ],
    },
    {
        "slug": "restaurant", "category": "transport", "icon": "fork.knife.circle.fill",
        "title": _t("餐厅与咖啡馆", "Restaurant & Café"),
        "zones": [
            {"id": "dining_out", **_t("在餐厅", "Dining Out"),
             "hint": "menu, waiter, booth, high chair, napkin holder, order pad. Put bill and tip in extra_words (paper marks / abstract)"},
            {"id": "at_the_cafe", **_t("在咖啡馆", "At the Café"),
             "hint": "coffee cup, straw, barista, pastry case, to-go cup, cafe counter"},
        ],
    },
    {
        "slug": "post", "category": "transport", "icon": "envelope.fill",
        "title": _t("邮局与快递", "Post & Delivery"),
        "zones": [
            {"id": "post_office", **_t("邮局", "The Post Office"),
             "hint": "envelope, stamp, postcard, mailbox, postal scale, mail slot"},
            {"id": "delivery", **_t("快递", "Delivery"),
             "hint": "parcel, delivery van, courier, shipping label, packing tape, cardboard box"},
        ],
    },
    {
        "slug": "hotel", "category": "transport", "icon": "bed.double.fill",
        "title": _t("酒店与住宿", "Hotel & Lodging"),
        "zones": [
            {"id": "front_desk", **_t("前台与大堂", "Front Desk & Lobby"),
             "hint": "reception desk, room card, bellhop, luggage trolley, lobby sofa, elevator button"},
            {"id": "guest_room", **_t("客房", "The Guest Room"),
             "hint": "minibar, room safe, hair dryer, bath towel, do-not-disturb sign, slippers"},
        ],
    },
    {
        "slug": "park", "category": "transport", "icon": "tree.fill",
        "title": _t("公园与景点", "Park & Sights"),
        "zones": [
            {"id": "playground", **_t("游乐区", "The Playground"),
             "hint": "swing, slide, seesaw, sandbox, pond, picnic table"},
            {"id": "sights", **_t("景点", "The Sights"),
             "hint": "statue, monument, ticket booth, map board, souvenir stand, viewpoint railing"},
        ],
    },

    # ================= B4 批次：自然与动物 +10（新 chip 一次性满配）=================
    {
        "slug": "pets", "category": "nature", "icon": "pawprint.fill",
        "title": _t("宠物", "Pets"),
        "zones": [
            {"id": "common_pets", **_t("常见宠物", "Common Pets"),
             "hint": "dog, cat, rabbit, hamster, goldfish, parrot — each a distinct animal"},
            {"id": "pet_things", **_t("宠物用品", "Pet Supplies"),
             "hint": "leash, collar, pet bowl, dog house, bird cage, cat litter box"},
        ],
    },
    {
        "slug": "farm_animals", "category": "nature", "icon": "hare.fill",
        "title": _t("农场动物", "Farm Animals"),
        "zones": [
            {"id": "livestock", **_t("家畜", "Livestock"),
             "hint": "cow, pig, horse, sheep, goat, donkey"},
            {"id": "poultry_barn", **_t("家禽与农场", "Poultry & Barn"),
             "hint": "chicken, rooster, duck, goose, turkey, barn"},
        ],
    },
    {
        "slug": "wild_animals", "category": "nature", "icon": "pawprint",
        "title": _t("野生动物", "Wild Animals"),
        "zones": [
            {"id": "big_wild", **_t("大型野兽", "Big Wild Animals"),
             "hint": "lion, tiger, elephant, giraffe, bear, zebra"},
            {"id": "more_wild", **_t("更多野兽", "More Wild Animals"),
             "hint": "monkey, kangaroo, fox, deer, wolf, hippo"},
        ],
    },
    {
        "slug": "birds", "category": "nature", "icon": "bird.fill",
        "title": _t("鸟类", "Birds"),
        "zones": [
            {"id": "city_birds", **_t("身边的鸟", "Everyday Birds"),
             "hint": "sparrow, pigeon, crow, swallow, owl, woodpecker"},
            {"id": "water_showy_birds", **_t("水鸟与彩鸟", "Water & Showy Birds"),
             "hint": "swan, duck, peacock, flamingo, penguin, eagle"},
        ],
    },
    {
        "slug": "insects", "category": "nature", "icon": "ant.fill",
        "title": _t("昆虫", "Insects & Bugs"),
        "zones": [
            {"id": "flying_bugs", **_t("会飞的虫", "Flying Bugs"),
             "hint": "butterfly, bee, dragonfly, mosquito, moth, ladybug"},
            {"id": "crawling_bugs", **_t("爬行的虫", "Crawling Bugs"),
             "hint": "ant, spider, caterpillar, snail, beetle, grasshopper"},
        ],
    },
    {
        "slug": "sea_life", "category": "nature", "icon": "fish",
        "title": _t("海洋生物", "Sea Life"),
        "zones": [
            {"id": "big_sea", **_t("大海生灵", "Ocean Creatures"),
             "hint": "whale, dolphin, shark, octopus, jellyfish, sea turtle"},
            {"id": "small_sea", **_t("浅海与贝类", "Reef & Shells"),
             "hint": "crab, starfish, seahorse, shrimp, clam, coral"},
        ],
    },
    {
        "slug": "flowers_plants", "category": "nature", "icon": "leaf.fill",
        "title": _t("花与植物", "Flowers & Plants"),
        "zones": [
            {"id": "flowers", **_t("花", "Flowers"),
             "hint": "rose, tulip, sunflower, lily, daisy, cherry blossom"},
            {"id": "green_plants", **_t("绿植", "Green Plants"),
             "hint": "cactus, fern, bamboo, ivy, potted plant, mushroom. Put leaf, stem, root, petal in extra_words (parts, not whole plants)"},
        ],
    },
    {
        "slug": "trees_forest", "category": "nature", "icon": "tree.fill",
        "title": _t("树与森林", "Trees & Forest"),
        "zones": [
            {"id": "trees", **_t("树", "Trees"),
             "hint": "pine tree, oak tree, palm tree, willow, maple tree, tree stump"},
            {"id": "forest_floor", **_t("林间", "In the Forest"),
             "hint": "bush, log, acorn, pinecone, moss, vine"},
        ],
    },
    {
        "slug": "weather", "category": "nature", "icon": "cloud.sun.fill",
        "title": _t("天气与季节", "Weather & Seasons"),
        "zones": [
            {"id": "weather", **_t("天气", "Weather"),
             "hint": "each is a small sky scene: sunny, rainy, cloudy, snowy, windy, stormy",
             "image_hint": "Six small square sky scenes in a grid with space between them, each showing ONE weather "
                           "with NO text: a bright sun in blue sky; rain falling from a grey cloud; a sky of fluffy "
                           "clouds; snow falling with white flakes; a tree bending in wind with leaves flying; "
                           "a dark cloud with a lightning bolt"},
            {"id": "sky_things", **_t("天空", "In the Sky"),
             "hint": "rainbow, lightning, snowflake, raindrop, cloud, star"},
        ],
    },
    {
        "slug": "landscape", "category": "nature", "icon": "mountain.2.fill",
        "title": _t("地形与风光", "Land & Scenery"),
        "zones": [
            {"id": "landforms", **_t("地形", "Landforms"),
             "hint": "mountain, hill, river, lake, waterfall, valley"},
            {"id": "more_scenery", **_t("更多风光", "More Scenery"),
             "hint": "beach, desert, forest, island, cave, volcano"},
        ],
    },

    # ================= B5 批次：工作与休闲 +13（新 chip 一次性满配）=================
    {
        "slug": "classroom", "category": "work", "icon": "graduationcap.fill",
        "title": _t("教室与文具", "Classroom & Stationery"),
        "zones": [
            {"id": "classroom", **_t("教室", "The Classroom"),
             "hint": "blackboard, desk, chair, globe, bookshelf, clock — a classroom scene"},
            {"id": "stationery", **_t("文具", "Stationery"),
             "hint": "pencil, eraser, ruler, scissors, glue stick, backpack"},
        ],
    },
    {
        "slug": "computer", "category": "work", "icon": "desktopcomputer",
        "title": _t("电脑与办公", "Computer & Desk"),
        "zones": [
            {"id": "computer_set", **_t("电脑", "The Computer"),
             "hint": "monitor, keyboard, mouse, laptop, printer, speaker — plain hardware, screens blank/off"},
            {"id": "desk_supplies", **_t("桌面用品", "Desk Supplies"),
             "hint": "stapler, folder, paper clip, sticky note, calculator, mug. Put email, file, download in extra_words (screen actions, not objects)"},
        ],
    },
    {
        "slug": "phone_apps", "category": "work", "icon": "iphone",
        "title": _t("手机与配件", "Phone & Gadgets"),
        "zones": [
            {"id": "the_phone", **_t("手机", "The Phone"),
             "hint": "smartphone (blank screen), phone case, screen, camera lens, charging port, power button — a plain phone and its parts, NO app icons or text on screen"},
            {"id": "gadgets", **_t("数码配件", "Gadgets"),
             "hint": "earbuds, charger cable, power bank, smartwatch, tablet, selfie stick"},
        ],
    },
    {
        "slug": "office", "category": "work", "icon": "building.2.fill",
        "title": _t("办公室", "The Office"),
        "zones": [
            {"id": "office_room", **_t("办公室", "In the Office"),
             "hint": "office desk, swivel chair, filing cabinet, whiteboard, water cooler, potted plant"},
            {"id": "meeting", **_t("开会", "The Meeting Room"),
             "hint": "projector, conference table, name tag, coffee mug, notepad, wall clock"},
        ],
    },
    {
        "slug": "jobs_1", "category": "work", "icon": "person.fill",
        "title": _t("常见职业·上", "Jobs I"),
        "zones": [
            {"id": "uniform_jobs", **_t("制服职业", "In Uniform"),
             "hint": "each person shown by their clear uniform and one tool: doctor, nurse, police officer, firefighter, chef, pilot",
             "image_hint": "Six people, each a head-to-waist figure in the unmistakable uniform of their job holding "
                           "one signature tool, NO text anywhere: a doctor in a white coat with a stethoscope; a nurse "
                           "in scrubs; a police officer in a blue uniform and cap; a firefighter in a red helmet and "
                           "coat; a chef in a white hat holding a pan; a pilot in a cap with wing badges"},
            {"id": "service_jobs", **_t("服务职业", "Service Jobs"),
             "hint": "each person by uniform and tool: teacher, waiter, farmer, mail carrier, cleaner, cashier",
             "image_hint": "Six people, each a head-to-waist figure dressed for their job with one signature prop, "
                           "NO text anywhere: a teacher by a small blackboard; a waiter in a vest holding a tray; a "
                           "farmer in overalls and straw hat; a mail carrier with a letter bag; a cleaner holding a mop; "
                           "a cashier at a small register"},
        ],
    },
    {
        "slug": "jobs_2", "category": "work", "icon": "person.2.fill",
        "title": _t("常见职业·下", "Jobs II"),
        "zones": [
            {"id": "skilled_jobs", **_t("技术职业", "Skilled Trades"),
             "hint": "each person by their tool: mechanic, electrician, plumber, carpenter, painter, barber",
             "image_hint": "Six people, each a head-to-waist figure dressed for their trade holding its signature tool, "
                           "NO text anywhere: a mechanic in overalls with a wrench; an electrician with pliers and wire; "
                           "a plumber holding a pipe; a carpenter with a hammer and saw; a painter with a roller and can; "
                           "a barber with scissors and comb"},
            {"id": "creative_jobs", **_t("创意与专业", "Creative & Pro"),
             "hint": "each person by their tool: artist, photographer, scientist, singer, athlete, dentist",
             "image_hint": "Six people, each a head-to-waist figure with the clear tool of their work, NO text anywhere: "
                           "an artist with a palette and brush; a photographer with a camera; a scientist in a lab coat "
                           "with a flask; a singer with a microphone; an athlete in a jersey with a medal; a dentist "
                           "with a dental mirror"},
        ],
    },
    {
        "slug": "money_bank", "category": "work", "icon": "banknote.fill",
        "title": _t("银行与理财", "Bank & Money"),
        "zones": [
            {"id": "at_the_bank", **_t("在银行", "At the Bank"),
             "hint": "ATM, bank card, safe/vault, teller window, coin stack, checkbook"},
            {"id": "money_things", **_t("理财用品", "Money Matters"),
             "hint": "piggy bank, gold coins, banknote bundle, wallet, calculator, credit card. Put save, spend, budget in extra_words (actions)"},
        ],
    },
    {
        "slug": "ball_sports", "category": "work", "icon": "sportscourt.fill",
        "title": _t("球类运动", "Ball Sports"),
        "zones": [
            {"id": "balls", **_t("各种球", "The Balls"),
             "hint": "soccer ball, basketball, tennis ball, baseball, volleyball, ping-pong ball"},
            {"id": "gear", **_t("球具与场地", "Gear & Court"),
             "hint": "tennis racket, baseball bat, goal net, basketball hoop, whistle, badminton racket"},
        ],
    },
    {
        "slug": "outdoor_sports", "category": "work", "icon": "figure.hiking",
        "title": _t("户外与健身", "Outdoors & Fitness"),
        "zones": [
            {"id": "outdoor", **_t("户外运动", "Outdoor Sports"),
             "hint": "bicycle, skateboard, tent, fishing rod, ski, surfboard"},
            {"id": "gym_gear", **_t("健身器材", "Gym Gear"),
             "hint": "dumbbell, jump rope, yoga mat, treadmill, kettlebell, exercise ball"},
        ],
    },
    {
        "slug": "music", "category": "work", "icon": "music.note",
        "title": _t("音乐与乐器", "Music & Instruments"),
        "zones": [
            {"id": "string_key", **_t("弦与键", "Strings & Keys"),
             "hint": "guitar, piano, violin, drums, harp, ukulele"},
            {"id": "wind_more", **_t("管乐与更多", "Winds & More"),
             "hint": "flute, trumpet, saxophone, harmonica, tambourine, microphone"},
        ],
    },
    {
        "slug": "screen_fun", "category": "work", "icon": "gamecontroller.fill",
        "title": _t("影视与游戏", "Screen & Games"),
        "zones": [
            {"id": "watching", **_t("看片与听歌", "Watch & Listen"),
             "hint": "television, remote control, headphones, movie clapperboard, popcorn bucket, speaker"},
            {"id": "playing", **_t("玩乐", "Games & Play"),
             "hint": "game controller, dice, playing cards, chess board, jigsaw puzzle, board game"},
        ],
    },
    {
        "slug": "travel", "category": "work", "icon": "suitcase.fill",
        "title": _t("旅行与度假", "Travel & Vacation"),
        "zones": [
            {"id": "packing", **_t("行李与装备", "Packing"),
             "hint": "suitcase, backpack, camera, sunglasses, sun hat, travel pillow"},
            {"id": "on_vacation", **_t("度假", "On Vacation"),
             "hint": "beach umbrella, beach ball, snorkel mask, map, compass, binoculars"},
        ],
    },
    {
        "slug": "holidays", "category": "work", "icon": "party.popper.fill",
        "title": _t("节日与庆祝", "Holidays & Celebrations"),
        "zones": [
            {"id": "party", **_t("派对", "The Party"),
             "hint": "balloon, birthday cake, gift box, party hat, candle, confetti"},
            {"id": "festive", **_t("节庆物件", "Festive Things"),
             "hint": "Christmas tree, jack-o-lantern, fireworks, lantern, wreath, ribbon bow"},
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
            # object（默认）= 物体图解板；action = 动词板，热点是动作本身
            "board_type": board.get("board_type", "object"),
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
