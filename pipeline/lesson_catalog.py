# -*- coding: utf-8 -*-
"""
词汇小课堂 — 场景矩阵目录（人工定稿，不交给 GPT）。

结构：
  COUNTRIES        6 国元数据（口音/拼写/本地化上下文）
  SCENE_TEMPLATES  共享场景模板（每国按本地品牌/体系生成一版）
  COUNTRY_EXTRAS   每国特色课堂（只此国家有）
  DAILY_SCENE_BACKLOG  每日更新的人工种子池
  all_lessons()    展开成全部课堂定义列表

课堂 id 约定：lesson_{country}_{slug}
"""

COUNTRIES = {
    "us": {
        "zh": "美国", "flag": "🇺🇸", "accent": "en-US", "spelling": "American English",
        "context": "the United States. Use American brands, US dollar prices, American daily-life culture (tipping 18-20%, sales tax added at checkout, imperial units).",
    },
    "uk": {
        "zh": "英国", "flag": "🇬🇧", "accent": "en-GB", "spelling": "British English",
        "context": "the United Kingdom. Use British brands, pound prices, British vocabulary (trolley, queue, till, chemist, petrol), NHS healthcare, polite indirect phrasing.",
    },
    "au": {
        "zh": "澳洲", "flag": "🇦🇺", "accent": "en-AU", "spelling": "British English (Australian usage)",
        "context": "Australia. Use Australian brands, dollar prices, Aussie vocabulary and casual tone (arvo, heaps, no worries), Medicare healthcare, no tipping culture.",
    },
    "ca": {
        "zh": "加拿大", "flag": "🇨🇦", "accent": "en-US", "spelling": "Canadian English (mostly American spelling)",
        "context": "Canada. Use Canadian brands, dollar prices, Canadian specifics (GST/PST tax, interac debit, politeness, winter life), provincial health cards.",
    },
    "nz": {
        "zh": "新西兰", "flag": "🇳🇿", "accent": "en-AU", "spelling": "British English (New Zealand usage)",
        "context": "New Zealand. Use NZ brands, dollar prices, Kiwi vocabulary (dairy = corner shop, jandals, bach), casual friendly tone, no tipping culture.",
    },
    "sg": {
        "zh": "新加坡", "flag": "🇸🇬", "accent": "en-SG", "spelling": "British English (Singapore usage)",
        "context": "Singapore. Use Singapore brands and places, Singapore dollar prices. Standard English for word entries, but examples may reflect local context (hawker centres, HDB, MRT). Mention Singlish only in culture tips.",
    },
}

CATEGORIES = {
    "arrival":  {"zh": "刚落地", "icon_emoji": "🛬"},
    "food":     {"zh": "吃喝购物", "icon_emoji": "🍔"},
    "health":   {"zh": "看病买药", "icon_emoji": "💊"},
    "settling": {"zh": "安顿下来", "icon_emoji": "🏠"},
    "social":   {"zh": "学习与社交", "icon_emoji": "🎓"},
}

# 闸门：只有第一个国家（美国）的第一课（Chase 开户 bank_account）免费体验，其余全部 Pro。
# App 端最终以「第一国第一课」判定免费，此处仅保证生成内容的 is_free 标记与之一致。
FREE_COUNTRY = "us"
FREE_SLUGS = {"bank_account"}


def _t(zh, en):
    return {"zh": zh, "en": en}


# === 共享场景模板 ===
# zones[].hint 告诉 GPT 这一分区希望覆盖的物品/表达方向；
# countries[cc] 给出该国的品牌锚点（用于标题和内容语境）。
SCENE_TEMPLATES = [
    {
        "slug": "customs", "category": "arrival", "icon": "airplane.arrival",
        "zones": [
            {"id": "passport_control", **_t("护照检查", "Passport Control"),
             "hint": "immigration counter, passport, visa, officer, fingerprint scanner, arrival form; questions about purpose and length of stay"},
            {"id": "baggage_claim", **_t("提取行李", "Baggage Claim"),
             "hint": "carousel, suitcase, luggage cart, lost baggage counter, baggage tag"},
            {"id": "customs_declaration", **_t("海关申报", "Customs Declaration"),
             "hint": "customs officer, declaration form, red/green channel, food items, duty-free bag"},
        ],
        "countries": {
            "us": {"anchor": "US CBP", "title": _t("入境美国过海关", "US Customs & Immigration")},
            "uk": {"anchor": "UK Border Force", "title": _t("入境英国过边检", "UK Border Control")},
            "au": {"anchor": "Australian Border Force (strict biosecurity)", "title": _t("入境澳洲过海关", "Australian Customs")},
            "ca": {"anchor": "CBSA", "title": _t("入境加拿大过海关", "Canadian Customs")},
            "nz": {"anchor": "NZ Customs (strict biosecurity, declare all food)", "title": _t("入境新西兰过海关", "NZ Customs")},
            "sg": {"anchor": "ICA automated gates at Changi", "title": _t("入境新加坡过关卡", "Singapore Immigration")},
        },
    },
    {
        "slug": "sim_card", "category": "arrival", "icon": "simcard",
        "zones": [
            {"id": "carrier_store", **_t("运营商门店", "At the Carrier Store"),
             "hint": "storefront, phone display, SIM card, staff member, counter"},
            {"id": "choosing_plan", **_t("选套餐", "Choosing a Plan"),
             "hint": "plan brochure, prepaid vs contract, data allowance, price tag, ID/passport for registration"},
            {"id": "setting_up", **_t("激活手机", "Setting Up"),
             "hint": "inserting SIM, activation, top up, hotspot, coverage"},
        ],
        "countries": {
            "us": {"anchor": "T-Mobile / AT&T prepaid", "title": _t("办一张美国手机卡", "Getting a US SIM Card")},
            "uk": {"anchor": "EE / giffgaff pay-as-you-go", "title": _t("办一张英国手机卡", "Getting a UK SIM Card")},
            "au": {"anchor": "Telstra / Optus prepaid", "title": _t("办一张澳洲手机卡", "Getting an Aussie SIM")},
            "ca": {"anchor": "Rogers / Freedom Mobile", "title": _t("办一张加拿大手机卡", "Getting a Canadian SIM")},
            "nz": {"anchor": "Spark / One NZ prepay", "title": _t("办一张新西兰手机卡", "Getting a Kiwi SIM")},
            "sg": {"anchor": "Singtel / SIM at Changi 7-Eleven", "title": _t("办一张新加坡手机卡", "Getting a Singapore SIM")},
        },
    },
    {
        "slug": "rideshare", "category": "arrival", "icon": "car.fill",
        "zones": [
            {"id": "pickup_zone", **_t("找上车点", "The Pickup Zone"),
             "hint": "rideshare pickup sign, terminal exit, phone with app, license plate, waiting passengers"},
            {"id": "in_the_car", **_t("车上", "In the Car"),
             "hint": "back seat, seatbelt, trunk/boot for luggage, driver, small talk, route on GPS"},
            {"id": "dropoff", **_t("下车与评价", "Drop-off & Rating"),
             "hint": "curb drop-off, rating stars on app, tip screen, forgotten item"},
        ],
        "countries": {
            "us": {"anchor": "Uber/Lyft, tipping in app", "title": _t("在美国打 Uber", "Taking an Uber in the US")},
            "uk": {"anchor": "Uber / black cab", "title": _t("在英国打车", "Taxis & Ubers in the UK")},
            "au": {"anchor": "Uber / DiDi", "title": _t("在澳洲打车", "Rideshare in Australia")},
            "ca": {"anchor": "Uber / Lyft", "title": _t("在加拿大打车", "Rideshare in Canada")},
            "nz": {"anchor": "Uber / Ola", "title": _t("在新西兰打车", "Rideshare in NZ")},
            "sg": {"anchor": "Grab (not Uber)", "title": _t("在新加坡叫 Grab", "Taking a Grab in Singapore")},
        },
    },
    {
        "slug": "hotel_checkin", "category": "arrival", "icon": "bed.double.fill",
        "zones": [
            {"id": "front_desk", **_t("前台入住", "The Front Desk"),
             "hint": "reception counter, key card, credit card for deposit, luggage, lobby"},
            {"id": "in_the_room", **_t("客房", "In the Room"),
             "hint": "air conditioning, wifi card, kettle, towels, do-not-disturb sign, room service menu"},
            {"id": "airbnb_checkin", **_t("Airbnb 自助入住", "Airbnb Self Check-in"),
             "hint": "lockbox with code, house rules note, host messages, trash instructions, checkout time"},
        ],
        "countries": {
            "us": {"anchor": "hotel incidental deposit, resort fee", "title": _t("美国酒店与 Airbnb 入住", "Hotels & Airbnb in the US")},
            "uk": {"anchor": "B&B culture, kettle with tea", "title": _t("英国酒店与 B&B 入住", "Hotels & B&Bs in the UK")},
            "au": {"anchor": "motel / serviced apartment", "title": _t("澳洲酒店与民宿入住", "Hotels & Stays in Australia")},
            "ca": {"anchor": "hotel deposit, winter entrance", "title": _t("加拿大酒店入住", "Hotels in Canada")},
            "nz": {"anchor": "motel / holiday park", "title": _t("新西兰住宿入住", "Stays in New Zealand")},
            "sg": {"anchor": "hotel along Orchard, hostel", "title": _t("新加坡酒店入住", "Hotels in Singapore")},
        },
    },
    {
        "slug": "coffee_order", "category": "food", "icon": "cup.and.saucer.fill",
        "zones": [
            {"id": "the_menu", **_t("排队看菜单", "The Menu Board"),
             "hint": "menu board, barista, espresso machine, pastry case, queue"},
            {"id": "customizing", **_t("杯型与定制", "Sizes & Customization"),
             "hint": "cup sizes, milk options (oat/almond), shots, iced vs hot, sweetness"},
            {"id": "pickup_counter", **_t("取餐区", "The Pickup Counter"),
             "hint": "name called out, sleeve, lid, straw, napkins, wrong order"},
        ],
        "countries": {
            "us": {"anchor": "Starbucks (tall/grande/venti)", "title": _t("在 Starbucks 点单", "Ordering at Starbucks")},
            "uk": {"anchor": "Costa / Pret", "title": _t("在 Costa 点咖啡", "Coffee at Costa")},
            "au": {"anchor": "local café, flat white culture, 'regular or large'", "title": _t("在澳洲咖啡馆点 Flat White", "Café Culture in Australia")},
            "ca": {"anchor": "Tim Hortons (double double)", "title": _t("在 Tim Hortons 点单", "Ordering at Tim Hortons")},
            "nz": {"anchor": "local café, flat white & long black", "title": _t("在新西兰咖啡馆点单", "Café Culture in NZ")},
            "sg": {"anchor": "kopitiam kopi/teh ordering codes (kopi-o, teh-c siew dai)", "title": _t("在 Kopitiam 点咖啡", "Kopi at a Kopitiam")},
        },
    },
    {
        "slug": "supermarket", "category": "food", "icon": "cart.fill",
        "zones": [
            {"id": "getting_started", **_t("进店与购物车", "Getting Started"),
             "hint": "shopping cart/trolley, basket, aisle signs, weekly deals display"},
            {"id": "fresh_food", **_t("生鲜果蔬", "Fresh Food & Produce"),
             "hint": "produce scales, meat counter, deli, seafood on ice, expiration date"},
            {"id": "self_checkout", **_t("自助结账", "Self-Checkout"),
             "hint": "self-checkout machine, barcode scanner, bagging area, unexpected item alert, receipt"},
            {"id": "returns_desk", **_t("客服与退货", "Customer Service & Returns"),
             "hint": "customer service counter, receipt, refund, exchange, membership card"},
        ],
        "countries": {
            "us": {"anchor": "Target / Walmart", "title": _t("在 Target 购物", "Shopping at Target")},
            "uk": {"anchor": "Tesco / Sainsbury's (meal deal, clubcard)", "title": _t("在 Tesco 购物", "Shopping at Tesco")},
            "au": {"anchor": "Woolworths / Coles ('Woolies')", "title": _t("在 Woolworths 购物", "Shopping at Woolies")},
            "ca": {"anchor": "Loblaws / Walmart (bring your own bag)", "title": _t("在加拿大逛超市", "Grocery Runs in Canada")},
            "nz": {"anchor": "Countdown(Woolworths NZ) / PAK'nSAVE", "title": _t("在新西兰逛超市", "Supermarkets in NZ")},
            "sg": {"anchor": "NTUC FairPrice / Cold Storage", "title": _t("在 FairPrice 购物", "Shopping at FairPrice")},
        },
    },
    {
        "slug": "dining_out", "category": "food", "icon": "fork.knife",
        "zones": [
            {"id": "getting_a_table", **_t("等位入座", "Getting a Table"),
             "hint": "host stand, reservation, waitlist, booth vs table, high chair"},
            {"id": "ordering", **_t("点餐", "Ordering"),
             "hint": "menu, appetizer/starter, main/entree, server recommendations, allergies, how meat is cooked"},
            {"id": "during_meal", **_t("用餐服务", "During the Meal"),
             "hint": "refill, extra napkins, sauce on the side, flagging the server, to-go box"},
            {"id": "check_and_tip", **_t("买单", "The Check"),
             "hint": "check/bill, split the bill, card machine, tip line, receipt"},
        ],
        "countries": {
            "us": {"anchor": "casual dining, 18-20% tip expected", "title": _t("美式餐厅堂食与小费", "Dining Out in America")},
            "uk": {"anchor": "service charge on bill, Sunday roast", "title": _t("在英国下馆子", "Eating Out in the UK")},
            "au": {"anchor": "order at counter common, no tipping", "title": _t("在澳洲下馆子", "Eating Out in Australia")},
            "ca": {"anchor": "15-18% tip, debit machine at table", "title": _t("在加拿大下馆子", "Dining Out in Canada")},
            "nz": {"anchor": "order at counter, no tipping, BYO wine", "title": _t("在新西兰下馆子", "Eating Out in NZ")},
            "sg": {"anchor": "service charge ++, chope-ing seats with tissue", "title": _t("在新加坡餐厅吃饭", "Dining Out in Singapore")},
        },
    },
    {
        "slug": "fast_food", "category": "food", "icon": "takeoutbag.and.cup.and.straw.fill",
        "zones": [
            {"id": "ordering", **_t("点餐", "Ordering"),
             "hint": "counter or drive-thru speaker, menu board, combo/meal, size upgrade"},
            {"id": "customizing", **_t("加料与去料", "Customizing"),
             "hint": "no pickles, extra cheese, sauce packets, 'for here or to go'"},
            {"id": "pickup", **_t("取餐", "Picking Up"),
             "hint": "order number screen, pickup counter, tray, ketchup station, missing item"},
        ],
        "countries": {
            "us": {"anchor": "drive-thru at McDonald's / In-N-Out", "title": _t("美国 Drive-thru 点快餐", "Drive-thru Fast Food")},
            "uk": {"anchor": "Greggs / meal deal", "title": _t("在英国买快餐", "Grabbing Fast Food in the UK")},
            "au": {"anchor": "'Macca's' drive-thru, HSP", "title": _t("在澳洲买快餐", "Fast Food in Australia")},
            "ca": {"anchor": "Tim Hortons drive-thru / A&W", "title": _t("在加拿大买快餐", "Fast Food in Canada")},
            "nz": {"anchor": "fish and chips shop", "title": _t("在新西兰买 Fish & Chips", "Fish & Chips in NZ")},
            "sg": {"anchor": "hawker centre alternative: mall food court", "title": _t("在新加坡美食广场点餐", "Food Courts in Singapore")},
        },
    },
    {
        "slug": "otc_meds", "category": "health", "icon": "pills.fill",
        "zones": [
            {"id": "medicine_aisle", **_t("找药货架", "The Medicine Aisle"),
             "hint": "pharmacy shelves, painkiller boxes, aisle signs, shopping basket"},
            {"id": "cold_and_fever", **_t("感冒退烧", "Cold & Fever"),
             "hint": "cold medicine, fever reducer, thermometer, cough syrup, throat lozenges, tissues"},
            {"id": "allergy_stomach", **_t("过敏与肠胃", "Allergy & Stomach"),
             "hint": "allergy tablets/antihistamine, band-aids/plasters, antacid, motion sickness pills, vitamins"},
            {"id": "checkout", **_t("结账", "Checkout"),
             "hint": "pharmacist behind counter, asking for advice, rewards card, receipt with coupons"},
        ],
        "countries": {
            "us": {"anchor": "CVS / Walgreens (Tylenol, Advil, Benadryl)", "title": _t("在 CVS 买非处方药", "OTC Meds at CVS")},
            "uk": {"anchor": "Boots (paracetamol, chemist)", "title": _t("在 Boots 买非处方药", "OTC Meds at Boots")},
            "au": {"anchor": "Chemist Warehouse (Panadol, Nurofen)", "title": _t("在 Chemist Warehouse 买药", "The Chemist in Australia")},
            "ca": {"anchor": "Shoppers Drug Mart", "title": _t("在 Shoppers 买药", "OTC Meds at Shoppers")},
            "nz": {"anchor": "Chemist Warehouse / Unichem", "title": _t("在新西兰药房买药", "The Chemist in NZ")},
            "sg": {"anchor": "Guardian / Watsons", "title": _t("在 Guardian 买药", "OTC Meds at Guardian")},
        },
    },
    {
        "slug": "clinic_visit", "category": "health", "icon": "stethoscope",
        "zones": [
            {"id": "checkin_forms", **_t("前台与填表", "Check-in & Forms"),
             "hint": "reception window, clipboard with forms, insurance/health card, waiting room"},
            {"id": "describing_symptoms", **_t("描述症状", "Describing Symptoms"),
             "hint": "exam room, describing pain/fever/cough/rash, since when, scale of 1-10"},
            {"id": "the_exam", **_t("检查与处置", "The Exam"),
             "hint": "blood pressure cuff, stethoscope, prescription, referral, follow-up"},
        ],
        "countries": {
            "us": {"anchor": "urgent care, copay, insurance card", "title": _t("去 Urgent Care 看病", "Going to Urgent Care")},
            "uk": {"anchor": "registering with a GP, NHS number, walk-in centre", "title": _t("在英国看 GP", "Seeing a GP on the NHS")},
            "au": {"anchor": "GP clinic, Medicare card, bulk billing", "title": _t("在澳洲看 GP", "Seeing a GP in Australia")},
            "ca": {"anchor": "walk-in clinic, health card, long waits", "title": _t("在加拿大看 Walk-in Clinic", "Walk-in Clinics in Canada")},
            "nz": {"anchor": "GP visit fee, after-hours clinic", "title": _t("在新西兰看医生", "Seeing a Doctor in NZ")},
            "sg": {"anchor": "polyclinic vs private GP, MC (medical certificate)", "title": _t("在新加坡看医生", "Seeing a Doctor in Singapore")},
        },
    },
    {
        "slug": "bank_account", "category": "settling", "icon": "building.columns.fill",
        "zones": [
            {"id": "at_the_counter", **_t("柜台开户", "At the Counter"),
             "hint": "bank teller, ID documents, proof of address, application form"},
            {"id": "account_and_card", **_t("账户与卡", "Accounts & Cards"),
             "hint": "debit card, checking/savings account, monthly fee, minimum balance, PIN pad"},
            {"id": "mobile_banking", **_t("手机银行与转账", "Mobile Banking"),
             "hint": "banking app, transfer, direct deposit, statement, ATM"},
        ],
        "countries": {
            "us": {"anchor": "Chase / Bank of America, SSN or passport", "title": _t("去 Chase 开银行账户", "Opening a US Bank Account")},
            "uk": {"anchor": "Barclays / Monzo, proof of address", "title": _t("在英国开银行账户", "Opening a UK Bank Account")},
            "au": {"anchor": "CommBank / ANZ, 100-point ID check", "title": _t("在澳洲开银行账户", "Opening an Aussie Bank Account")},
            "ca": {"anchor": "RBC / TD, SIN number, interac", "title": _t("在加拿大开银行账户", "Opening a Canadian Bank Account")},
            "nz": {"anchor": "ANZ / ASB, IRD number", "title": _t("在新西兰开银行账户", "Opening a Kiwi Bank Account")},
            "sg": {"anchor": "DBS / OCBC, PayNow", "title": _t("在新加坡开银行账户", "Opening a Bank Account in SG")},
        },
    },
    {
        "slug": "renting", "category": "settling", "icon": "house.fill",
        "zones": [
            {"id": "the_tour", **_t("跟房东看房", "The Viewing"),
             "hint": "landlord/agent showing rooms, natural light, water pressure, closet space, asking questions"},
            {"id": "kitchen_appliances", **_t("厨房与家电", "Kitchen & Appliances"),
             "hint": "stove/hob, oven, fridge, dishwasher, washer dryer, microwave"},
            {"id": "lease_signing", **_t("签约与费用", "The Lease"),
             "hint": "lease document, deposit, utilities included or not, move-in date, keys"},
        ],
        "countries": {
            "us": {"anchor": "application + credit check, security deposit", "title": _t("在美国租公寓", "Renting an Apartment in the US")},
            "uk": {"anchor": "letting agent, council tax, deposit protection", "title": _t("在英国租房", "Renting a Flat in the UK")},
            "au": {"anchor": "rental inspection, bond, weekly rent", "title": _t("在澳洲租房", "Renting in Australia")},
            "ca": {"anchor": "first and last month, hydro bill", "title": _t("在加拿大租房", "Renting in Canada")},
            "nz": {"anchor": "flatting, bond lodged with Tenancy Services", "title": _t("在新西兰租房", "Flatting in NZ")},
            "sg": {"anchor": "HDB vs condo, agent fee, aircon servicing clause", "title": _t("在新加坡租房", "Renting in Singapore")},
        },
    },
    {
        "slug": "public_transport", "category": "settling", "icon": "tram.fill",
        "zones": [
            {"id": "buying_fare", **_t("购票与刷卡", "Fares & Cards"),
             "hint": "ticket machine, transit card, top up, tap on reader, fare gate"},
            {"id": "on_the_platform", **_t("站台", "On the Platform"),
             "hint": "platform sign, route map, arrival board, mind the gap, escalator"},
            {"id": "on_board", **_t("车上", "On Board"),
             "hint": "priority seat, next stop announcement, pull cord/press button, rush hour crowd"},
        ],
        "countries": {
            "us": {"anchor": "NYC subway / metro card", "title": _t("在美国坐地铁公交", "Getting Around by Transit (US)")},
            "uk": {"anchor": "the Tube, Oyster/contactless, mind the gap", "title": _t("在伦敦坐地铁", "Riding the Tube")},
            "au": {"anchor": "Opal card, tap on tap off, tram", "title": _t("在澳洲坐公共交通", "Public Transport in Australia")},
            "ca": {"anchor": "TTC / Presto card", "title": _t("在加拿大坐公共交通", "Transit in Canada")},
            "nz": {"anchor": "AT HOP card, bus-first city", "title": _t("在新西兰坐公交", "Buses in NZ")},
            "sg": {"anchor": "MRT, EZ-Link, no eating on train", "title": _t("在新加坡坐 MRT", "Riding the MRT")},
        },
    },
    {
        "slug": "campus", "category": "social", "icon": "graduationcap.fill",
        "zones": [
            {"id": "in_class", **_t("教室与课堂", "In Class"),
             "hint": "lecture hall, syllabus, slides, raising hand, group discussion, deadline"},
            {"id": "office_hours", **_t("教授办公时间", "Office Hours"),
             "hint": "professor's office, asking about assignment, extension, recommendation letter"},
            {"id": "campus_life", **_t("食堂与宿舍", "Dining Hall & Dorm"),
             "hint": "dining hall tray, meal plan, dorm room, roommate, laundry room, student ID"},
        ],
        "countries": {
            "us": {"anchor": "GPA, credits, midterms", "title": _t("美国大学校园", "On a US Campus")},
            "uk": {"anchor": "modules, tutorials, halls, freshers week", "title": _t("英国大学校园", "At a UK University")},
            "au": {"anchor": "units, tutorials ('tutes'), O-week", "title": _t("澳洲大学校园", "At an Aussie Uni")},
            "ca": {"anchor": "co-op programs, residence", "title": _t("加拿大大学校园", "On a Canadian Campus")},
            "nz": {"anchor": "halls of residence, course-related costs", "title": _t("新西兰大学校园", "At a Kiwi Uni")},
            "sg": {"anchor": "NUS/NTU, hall culture, bell curve", "title": _t("新加坡大学校园", "On Campus in Singapore")},
        },
    },
    {
        "slug": "office_life", "category": "social", "icon": "briefcase.fill",
        "zones": [
            {"id": "at_your_desk", **_t("工位", "At Your Desk"),
             "hint": "monitor, standing desk, headset, calendar invite, slack message"},
            {"id": "break_room", **_t("茶水间闲聊", "Break Room Small Talk"),
             "hint": "coffee machine, microwave, weekend plans chat, sports talk, snacks"},
            {"id": "after_work", **_t("下班社交", "After Work"),
             "hint": "happy hour, team lunch, farewell card, leaving on time"},
        ],
        "countries": {
            "us": {"anchor": "happy hour, PTO, watercooler talk", "title": _t("美国职场日常", "US Office Life")},
            "uk": {"anchor": "pub after work, tea rounds, annual leave", "title": _t("英国职场日常", "UK Office Life")},
            "au": {"anchor": "Friday drinks, flat hierarchy, 'how ya going'", "title": _t("澳洲职场日常", "Aussie Office Life")},
            "ca": {"anchor": "hockey talk, timbits in meetings", "title": _t("加拿大职场日常", "Canadian Office Life")},
            "nz": {"anchor": "morning tea shout, casual Fridays", "title": _t("新西兰职场日常", "Kiwi Office Life")},
            "sg": {"anchor": "lunch kakis, CBD hawker lunch", "title": _t("新加坡职场日常", "Office Life in Singapore")},
        },
    },
    {
        "slug": "friends_gathering", "category": "social", "icon": "party.popper.fill",
        "zones": [
            {"id": "what_to_bring", **_t("带什么去", "What to Bring"),
             "hint": "wine bottle, snacks to share, host gift, texting 'what can I bring'"},
            {"id": "arriving", **_t("进门寒暄", "Arriving"),
             "hint": "doorbell, taking shoes off or not, introductions, compliment the home"},
            {"id": "food_and_games", **_t("餐桌与游戏", "Food & Games"),
             "hint": "buffet table, board games, toast, group photo, saying goodbye politely"},
        ],
        "countries": {
            "us": {"anchor": "potluck, BYOB", "title": _t("参加美国朋友的 Party", "House Parties in the US")},
            "uk": {"anchor": "bring a bottle, cheeky takeaway", "title": _t("参加英国朋友的聚会", "Gatherings in the UK")},
            "au": {"anchor": "backyard BBQ, 'bring a plate'", "title": _t("参加澳洲后院 BBQ", "The Aussie BBQ")},
            "ca": {"anchor": "potluck, garage parties, poutine night", "title": _t("参加加拿大朋友的聚会", "Gatherings in Canada")},
            "nz": {"anchor": "BBQ, 'bring a plate' means food not empty plate", "title": _t("参加新西兰朋友的聚会", "Kiwi Gatherings")},
            "sg": {"anchor": "HDB potluck, steamboat night", "title": _t("参加新加坡朋友的聚会", "Gatherings in Singapore")},
        },
    },
    {
        "slug": "gym", "category": "social", "icon": "dumbbell.fill",
        "zones": [
            {"id": "front_desk", **_t("前台办卡", "The Front Desk"),
             "hint": "membership desk, free trial, monthly fee, cancellation policy, towel service"},
            {"id": "equipment", **_t("器械区", "The Equipment"),
             "hint": "treadmill, dumbbells, squat rack, 'how many sets left', wipe down the machine"},
            {"id": "locker_room", **_t("更衣室", "The Locker Room"),
             "hint": "locker with padlock, shower, sauna, hair dryer, lost key"},
        ],
        "countries": {
            "us": {"anchor": "Planet Fitness, annual fee trap", "title": _t("在美国健身房办卡", "Joining a US Gym")},
            "uk": {"anchor": "PureGym, no-contract", "title": _t("在英国健身房办卡", "Joining a UK Gym")},
            "au": {"anchor": "Anytime Fitness, direct debit", "title": _t("在澳洲健身房办卡", "Joining an Aussie Gym")},
            "ca": {"anchor": "GoodLife Fitness", "title": _t("在加拿大健身房办卡", "Joining a Canadian Gym")},
            "nz": {"anchor": "Les Mills (born in NZ)", "title": _t("在新西兰健身房办卡", "Joining a Kiwi Gym")},
            "sg": {"anchor": "ActiveSG public gyms (cheap!)", "title": _t("在新加坡健身房办卡", "Gyms in Singapore")},
        },
    },
]

# === 每国特色课堂（只此国家有）===
COUNTRY_EXTRAS = {
    "us": [
        {
            "slug": "pulled_over", "category": "settling", "icon": "light.beacon.max.fill",
            "title": _t("被警察拦下怎么办", "Getting Pulled Over"),
            "zones": [
                {"id": "pulling_over", **_t("靠边停车", "Pulling Over"),
                 "hint": "police lights in mirror, pulling to shoulder, hazard lights, staying in car, hands on wheel"},
                {"id": "documents", **_t("出示证件", "License & Registration"),
                 "hint": "driver's license, registration, insurance card, glove compartment, rolling down window"},
                {"id": "the_ticket", **_t("罚单与后续", "The Ticket"),
                 "hint": "speeding ticket, warning, fine, court date, contesting"},
            ],
            "anchor": "US traffic stop etiquette — safety-critical culture knowledge",
        },
        {
            "slug": "costco", "category": "food", "icon": "shippingbox.fill",
            "title": _t("在 Costco 采购", "The Costco Run"),
            "zones": [
                {"id": "membership", **_t("会员与入店", "Membership & Entry"),
                 "hint": "membership card at door, warehouse shelves, giant cart"},
                {"id": "bulk_shopping", **_t("大包装扫货", "Buying in Bulk"),
                 "hint": "bulk packs, pallet displays, free sample stations, rotisserie chicken"},
                {"id": "food_court", **_t("美食广场与离店", "Food Court & Exit"),
                 "hint": "$1.50 hot dog combo, pizza slice, receipt check at exit"},
            ],
            "anchor": "Costco membership warehouse culture",
        },
        {
            "slug": "chipotle", "category": "food", "icon": "takeoutbag.and.cup.and.straw",
            "title": _t("在 Chipotle 排队点餐", "Down the Line at Chipotle"),
            "zones": [
                {"id": "bowl_or_burrito", **_t("选主食", "Bowl or Burrito"),
                 "hint": "menu formats: burrito, bowl, tacos, quesadilla; the assembly line counter"},
                {"id": "down_the_line", **_t("一路选配料", "Choosing Toppings"),
                 "hint": "rice white or brown, beans, protein choices, salsa mild to hot, 'guac is extra'"},
                {"id": "checkout", **_t("结账", "Checkout"),
                 "hint": "chips and guac, drink cup, rewards app scan"},
            ],
            "anchor": "fast-casual assembly line ordering pressure",
        },
        {
            "slug": "dmv", "category": "settling", "icon": "car.badge.gearshape.fill",
            "title": _t("在 DMV 考驾照", "Surviving the DMV"),
            "zones": [
                {"id": "waiting", **_t("取号排队", "Taking a Number"),
                 "hint": "ticket number machine, waiting area, now serving screen, documents folder"},
                {"id": "the_tests", **_t("笔试与路考", "The Tests"),
                 "hint": "written test on screen, learner's permit, road test examiner, parallel parking"},
                {"id": "getting_license", **_t("拿证", "Getting Your License"),
                 "hint": "eye exam machine, photo booth, temporary paper license, renewal"},
            ],
            "anchor": "DMV bureaucracy culture",
        },
        {
            "slug": "laundromat", "category": "settling", "icon": "washer.fill",
            "title": _t("在自助洗衣店洗衣", "At the Laundromat"),
            "zones": [
                {"id": "washers", **_t("洗衣机与支付", "Washers & Payment"),
                 "hint": "coin machine, quarters, card reader, washer sizes, cycle settings"},
                {"id": "supplies", **_t("洗涤用品", "Detergent & Softener"),
                 "hint": "detergent pods, laundry detergent bottle, fabric softener, bleach, dryer sheets, stain remover, delicates bag"},
                {"id": "drying", **_t("烘干与折叠", "Drying & Folding"),
                 "hint": "dryer, lint trap, folding table, laundry basket, laundry cart, hangers, wall clock"},
            ],
            "anchor": "coin laundry culture in US apartments",
        },
    ],
    "uk": [
        {
            "slug": "pub", "category": "social", "icon": "wineglass.fill",
            "title": _t("去英国 Pub 社交", "Down the Pub"),
            "zones": [
                {"id": "ordering_at_bar", **_t("吧台点酒", "Ordering at the Bar"),
                 "hint": "ordering at the bar not table, pint, half pint, ale vs lager, tap handles"},
                {"id": "rounds", **_t("轮流请酒", "Buying Rounds"),
                 "hint": "'it's my round', cheers, splitting, crisps packets"},
                {"id": "pub_food", **_t("酒吧餐食", "Pub Grub"),
                 "hint": "fish and chips, Sunday roast, table number for food order, quiz night poster"},
            ],
            "anchor": "pub round-buying etiquette",
        },
        {
            "slug": "weather_chat", "category": "social", "icon": "cloud.rain.fill",
            "title": _t("英式聊天气", "Talking About the Weather"),
            "zones": [
                {"id": "the_smalltalk", **_t("天气开场白", "Weather Openers"),
                 "hint": "umbrella, wellington boots, grey clouds, drizzle, raincoat, bus stop, puddle"},
                {"id": "complaining_politely", **_t("礼貌吐槽", "Polite Complaints"),
                 "hint": "weather app, thermometer, TV weather forecast, electric fan, sunglasses, cup of tea"},
            ],
            "anchor": "weather as the universal British icebreaker",
        },
        {
            "slug": "charity_shop", "category": "food", "icon": "bag.fill",
            "title": _t("逛 Charity Shop 淘货", "Charity Shop Treasure Hunting"),
            "zones": [
                {"id": "browsing", **_t("淘货", "Browsing the Rails"),
                 "hint": "clothes rails, second-hand books, bric-a-brac shelf, price stickers"},
                {"id": "donating", **_t("捐赠与结账", "Donating & Paying"),
                 "hint": "donation bags, gift aid form, volunteer at till"},
            ],
            "anchor": "Oxfam / British Heart Foundation high-street charity shops",
        },
        {
            "slug": "trains", "category": "settling", "icon": "train.side.front.car",
            "title": _t("在英国坐火车", "Taking the Train"),
            "zones": [
                {"id": "tickets", **_t("买票", "Tickets & Railcards"),
                 "hint": "off-peak vs anytime, railcard discount, ticket machine, e-ticket QR"},
                {"id": "on_board", **_t("车上", "On Board"),
                 "hint": "seat reservation screen, quiet coach, trolley service, delay repay"},
            ],
            "anchor": "off-peak ticket money-saving culture",
        },
    ],
    "au": [
        {
            "slug": "bbq", "category": "social", "icon": "flame.fill",
            "title": _t("参加澳洲后院 BBQ", "The Backyard Barbie"),
            "zones": [
                {"id": "the_grill", **_t("烤架边", "At the Grill"),
                 "hint": "barbie grill, snags/sausages, tongs, onions, esky with drinks"},
                {"id": "bring_a_plate", **_t("带一份菜", "Bring a Plate"),
                 "hint": "salads, pavlova, 'bring a plate' custom, sunscreen"},
            ],
            "anchor": "'barbie' as core Aussie social ritual",
        },
        {
            "slug": "beach", "category": "social", "icon": "sun.max.fill",
            "title": _t("澳洲海滩生存指南", "A Day at the Beach"),
            "zones": [
                {"id": "sun_safety", **_t("防晒", "Sun Safety"),
                 "hint": "sunscreen SPF50, rashie, slip slop slap, UV index"},
                {"id": "swimming_flags", **_t("红黄旗之间游泳", "Between the Flags"),
                 "hint": "red and yellow flags, lifeguard, rip current, surf warnings"},
            ],
            "anchor": "swim between the flags — safety-critical",
        },
        {
            "slug": "op_shop", "category": "food", "icon": "bag.fill",
            "title": _t("逛澳洲 Op Shop", "Op Shopping"),
            "zones": [
                {"id": "browsing", **_t("淘货", "Browsing"),
                 "hint": "op shop racks, vintage finds, Vinnies/Salvos signs"},
                {"id": "paying", **_t("结账", "Paying"),
                 "hint": "gold coin donation, EFTPOS, volunteers"},
            ],
            "anchor": "Vinnies / Salvos op shop culture",
        },
        {
            "slug": "p_plates", "category": "settling", "icon": "car.badge.gearshape.fill",
            "title": _t("澳洲考驾照与 P 牌", "L-Plates to P-Plates"),
            "zones": [
                {"id": "learner", **_t("L 牌学车", "Learner Stage"),
                 "hint": "L plate on car, logbook hours, supervising driver"},
                {"id": "the_test", **_t("路考与 P 牌", "The Driving Test"),
                 "hint": "P plate red and green, demerit points, roundabout rules"},
            ],
            "anchor": "graduated licensing L→P1→P2 system",
        },
    ],
    "ca": [
        {
            "slug": "winter_survival", "category": "settling", "icon": "snowflake",
            "title": _t("加拿大冬天生存指南", "Surviving a Canadian Winter"),
            "zones": [
                {"id": "gearing_up", **_t("装备", "Gearing Up"),
                 "hint": "parka, toque, mittens, thermal layers, ice grips for boots"},
                {"id": "snow_duty", **_t("铲雪与车", "Snow & Your Car"),
                 "hint": "snow shovel, ice scraper, winter tires, block heater, snowplow"},
                {"id": "the_cold_talk", **_t("聊冷", "Talking About the Cold"),
                 "hint": "wind chill, -30 feels like, 'cold enough for ya', freezing rain"},
            ],
            "anchor": "winter as core Canadian shared experience",
        },
        {
            "slug": "hockey_talk", "category": "social", "icon": "figure.hockey",
            "title": _t("听懂加拿大人聊冰球", "Hockey Small Talk"),
            "zones": [
                {"id": "the_basics", **_t("基础词", "The Basics"),
                 "hint": "rink, puck, goalie, playoffs, jersey"},
                {"id": "joining_in", **_t("接话", "Joining the Conversation"),
                 "hint": "'did you catch the game', team loyalty, overtime"},
            ],
            "anchor": "hockey as national conversation currency",
        },
        {
            "slug": "tax_and_tip", "category": "food", "icon": "percent",
            "title": _t("加拿大账单：税和小费", "Tax & Tip on Every Bill"),
            "zones": [
                {"id": "the_bill", **_t("看懂账单", "Reading the Bill"),
                 "hint": "subtotal, GST/PST/HST lines, debit machine tip prompt 15/18/20%"},
                {"id": "paying", **_t("支付", "Paying"),
                 "hint": "tap to pay, interac, splitting bills"},
            ],
            "anchor": "price tags exclude tax — sticker shock",
        },
    ],
    "nz": [
        {
            "slug": "hiking", "category": "social", "icon": "mountain.2.fill",
            "title": _t("新西兰徒步（Tramping）", "Going Tramping"),
            "zones": [
                {"id": "gearing_up", **_t("装备与规划", "Gear & Planning"),
                 "hint": "hiking boots, layers, DOC track signs, weather check, intentions form"},
                {"id": "on_the_track", **_t("步道上", "On the Track"),
                 "hint": "trail markers, swing bridge, hut booking, summit views"},
            ],
            "anchor": "DOC tracks and hut system — tramping not hiking",
        },
        {
            "slug": "dairy", "category": "food", "icon": "storefront.fill",
            "title": _t("新西兰街角 Dairy", "The Corner Dairy"),
            "zones": [
                {"id": "at_the_dairy", **_t("买点小东西", "Grabbing Essentials"),
                 "hint": "corner shop counter, ice cream freezer, pie warmer, lotto tickets"},
                {"id": "kiwi_chat", **_t("跟老板闲聊", "Chatting with the Owner"),
                 "hint": "'how's it going', local news, eftpos minimum"},
            ],
            "anchor": "'dairy' means corner shop in NZ — classic confusion",
        },
        {
            "slug": "kiwi_slang", "category": "social", "icon": "quote.bubble.fill",
            "title": _t("听懂新西兰俚语", "Decoding Kiwi Slang"),
            "zones": [
                {"id": "everyday_slang", **_t("日常俚语", "Everyday Slang"),
                 "hint": "jandals, togs, chilly bin, bach, sweet as"},
                {"id": "maori_words", **_t("毛利语借词", "Māori Words in English"),
                 "hint": "kia ora, whānau, kai, aroha, marae — used in everyday NZ English"},
            ],
            "anchor": "Māori loanwords are everyday NZ English",
        },
    ],
    "sg": [
        {
            "slug": "hawker", "category": "food", "icon": "fork.knife.circle.fill",
            "title": _t("在 Hawker Centre 点餐", "Ordering at a Hawker Centre"),
            "zones": [
                {"id": "finding_a_stall", **_t("找摊位与占座", "Stalls & Chope-ing"),
                 "hint": "hawker stalls, queue at popular stall, tissue packet chope-ing seats, table numbers"},
                {"id": "ordering", **_t("点招牌菜", "Ordering the Classics"),
                 "hint": "chicken rice, laksa, char kway teow, 'dabao' takeaway, less spicy"},
                {"id": "drinks_and_paying", **_t("饮料与买单", "Drinks & Paying"),
                 "hint": "kopi/teh stall, sugarcane juice, cash or PayNow, tray return station"},
            ],
            "anchor": "hawker centre as Singapore's dining core, chope culture",
        },
        {
            "slug": "singlish", "category": "social", "icon": "quote.bubble.fill",
            "title": _t("听懂 Singlish", "Decoding Singlish"),
            "zones": [
                {"id": "particles", **_t("语气词", "The Particles"),
                 "hint": "lah, leh, lor usage feels, 'can' as full sentence, 'onz'"},
                {"id": "everyday_phrases", **_t("日常表达", "Everyday Phrases"),
                 "hint": "paiseh, shiok, makan, 'die die must try', blur"},
            ],
            "anchor": "Singlish comprehension for daily survival",
        },
        {
            "slug": "hdb_living", "category": "settling", "icon": "building.2.fill",
            "title": _t("住进新加坡组屋", "Living in an HDB"),
            "zones": [
                {"id": "the_flat", **_t("组屋内", "Inside the Flat"),
                 "hint": "void deck, corridor, bomb shelter room, aircon ledge, laundry poles"},
                {"id": "the_estate", **_t("楼下配套", "Around the Estate"),
                 "hint": "void deck gatherings, kopitiam downstairs, wet market, community centre"},
            ],
            "anchor": "HDB void deck community culture",
        },
        {
            "slug": "wet_market", "category": "food", "icon": "basket.fill",
            "title": _t("逛新加坡湿巴刹", "The Wet Market"),
            "zones": [
                {"id": "produce_stalls", **_t("菜摊鱼摊", "Produce & Fish Stalls"),
                 "hint": "fish on ice, vegetable piles, weighing scale, bargaining a little"},
                {"id": "paying", **_t("称重付款", "Weighing & Paying"),
                 "hint": "per kilo pricing, plastic bags, cash preferred, early morning hours"},
            ],
            "anchor": "wet market vs supermarket freshness culture",
        },
    ],
}

# === 每日更新种子池（更细的小场景，cron 逐个消费）===
DAILY_SCENE_BACKLOG = [
    {"country": "us", "slug": "ikea_run", "title": _t("在宜家买家具", "The IKEA Run"), "category": "settling",
     "hint": "showroom shortcuts, flat-pack warehouse aisle/bin numbers, checkout, meatballs"},
    {"country": "us", "slug": "black_friday", "title": _t("黑五扫货", "Black Friday Shopping"), "category": "food",
     "hint": "doorbuster deals, lines before opening, price match, gift receipts"},
    {"country": "us", "slug": "car_towed", "title": _t("车被拖走了怎么办", "My Car Got Towed"), "category": "settling",
     "hint": "no parking sign fine print, tow lot, release fee, contesting"},
    {"country": "us", "slug": "tipping_everything", "title": _t("到处都要小费？", "Tipping Culture Decoded"), "category": "food",
     "hint": "tip screens everywhere, when to skip, delivery vs pickup, tip fatigue"},
    {"country": "uk", "slug": "sunday_roast", "title": _t("周日烤肉聚餐", "Sunday Roast"), "category": "food",
     "hint": "roast beef, yorkshire pudding, gravy, carvery, booking ahead"},
    {"country": "uk", "slug": "boxing_day", "title": _t("Boxing Day 抢折扣", "Boxing Day Sales"), "category": "food",
     "hint": "post-Christmas sales, returns queue, gift cards"},
    {"country": "au", "slug": "medicare_signup", "title": _t("办澳洲 Medicare", "Signing Up for Medicare"), "category": "health",
     "hint": "eligibility, Medicare card, bulk billing explained"},
    {"country": "au", "slug": "magpie_season", "title": _t("躲避喜鹊俯冲的季节", "Magpie Swooping Season"), "category": "social",
     "hint": "swooping magpies, helmet zip ties, warning signs, spring only"},
    {"country": "ca", "slug": "double_double", "title": _t("Tim Hortons 黑话", "Speaking Tims"), "category": "food",
     "hint": "double double, timbits, roll up the rim, drive-thru speed"},
    {"country": "nz", "slug": "bach_weekend", "title": _t("去朋友的度假屋过周末", "A Weekend at the Bach"), "category": "social",
     "hint": "bach = holiday home, beach cricket, fish and chips night, jandals"},
    {"country": "sg", "slug": "ns_talk", "title": _t("听懂新加坡人聊 NS", "When Friends Talk About NS"), "category": "social",
     "hint": "national service references, army slang civilians hear, reservist"},
    {"country": "sg", "slug": "gss_shopping", "title": _t("大促季扫货", "Great Singapore Sale"), "category": "food",
     "hint": "Orchard Road sales, GST refund for tourists, queue culture"},
]


def all_lessons():
    """展开矩阵 → 全部课堂定义列表（不含每日 backlog）。"""
    lessons = []
    for tpl in SCENE_TEMPLATES:
        for cc, local in tpl["countries"].items():
            lessons.append({
                "id": "lesson_%s_%s" % (cc, tpl["slug"]),
                "slug": tpl["slug"],
                "country": cc,
                "category": tpl["category"],
                "category_zh": CATEGORIES[tpl["category"]]["zh"],
                "icon": tpl["icon"],
                "title_zh": local["title"]["zh"],
                "title_en": local["title"]["en"],
                "anchor": local["anchor"],
                "zones": tpl["zones"],
                "is_free": cc == FREE_COUNTRY and tpl["slug"] in FREE_SLUGS,
            })
    for cc, extras in COUNTRY_EXTRAS.items():
        for ex in extras:
            lessons.append({
                "id": "lesson_%s_%s" % (cc, ex["slug"]),
                "slug": ex["slug"],
                "country": cc,
                "category": ex["category"],
                "category_zh": CATEGORIES[ex["category"]]["zh"],
                "icon": ex["icon"],
                "title_zh": ex["title"]["zh"],
                "title_en": ex["title"]["en"],
                "anchor": ex["anchor"],
                "zones": ex["zones"],
                "is_free": False,
            })
    return lessons


if __name__ == "__main__":
    ls = all_lessons()
    by_cc = {}
    for l in ls:
        by_cc.setdefault(l["country"], []).append(l)
    print("Total lessons: %d" % len(ls))
    for cc in COUNTRIES:
        print("  %s %s: %d" % (COUNTRIES[cc]["flag"], cc, len(by_cc.get(cc, []))))
