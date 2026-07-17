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
    "body":      {"zh": "身体与健康", "icon_emoji": "🧍", "palette": "pale-aqua and soft teal"},
    "clothing":  {"zh": "穿着",      "icon_emoji": "👕", "palette": "fresh blush-pink and rose"},
    "transport": {"zh": "出行与城市", "icon_emoji": "🚌", "palette": "fresh sky-blue and cornflower"},
    "nature":    {"zh": "自然与动物", "icon_emoji": "🌳", "palette": "fresh sage-green and mint"},
    "work":      {"zh": "工作与休闲", "icon_emoji": "💼", "palette": "fresh lavender and soft periwinkle"},
    "basics":    {"zh": "基础概念",   "icon_emoji": "🔢", "palette": "soft orchid and light mauve"},
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
        "board_type": "state",
        "title": _t("方位与位置", "Where Things Are"),
        "zones": [
            {"id": "basic_position", **_t("基本方位", "Basic Positions"),
             "hint": "same ball and box in each vignette, only the relation changes: on, under, in, next to, behind, between"},
            {"id": "directions", **_t("方向", "Directions"),
             "hint": "left, right, up, down, near, far — each shown with a simple figure and arrow"},
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
        "board_type": "state",
        "title": _t("大小与程度", "Big, Small & In Between"),
        "zones": [
            {"id": "size", **_t("大小长短", "Size & Length"),
             "hint": "each word from an obvious contrast between two drawn objects: big, small, long, short, thick, thin"},
            {"id": "degree", **_t("轻重冷热", "Weight & Temperature"),
             "hint": "heavy, light, hot, cold, full, empty — each from a clear visual contrast"},
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
        "slug": "dates", "category": "basics", "icon": "calendar",
        "title": _t("日期与星期", "Dates & Days"),
        "zones": [
            {"id": "the_calendar", **_t("看日历", "Reading a Calendar"),
             "hint": "one large wall calendar with visible day columns and dates: weekend (shaded cells), "
                     "holiday (a red-marked date), today (a circled date), appointment (a note written in a cell), "
                     "month, week. Day and month names printed on the calendar are part of the object, not labels"},
            {"id": "planning", **_t("安排日程", "Planning"),
             "hint": "planner, sticky note, wall calendar, desk calendar, reminder on a phone, pen marking a date"},
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
