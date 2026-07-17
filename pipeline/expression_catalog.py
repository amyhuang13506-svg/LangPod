# -*- coding: utf-8 -*-
"""
口语表达库（句型 tab）目录 —— 5 个大组 × 31 个功能分类（人工定稿）。

设计原则（用户确认）：
- 按功能分类，不按国家/场景（国家差异写进每条表达的 country_note_zh）
- 不分初中高难度，以实用性排序（最常用的在最前）
- 口语化、接地气、能直接使用
"""

GROUPS = [
    {
        # 今日句型：内容来自每日播客自动提取的句型（patterns），按级别 easy/medium/hard
        # 分初/中/高级，每级保留最近 15 天。由 build_pattern_expressions.py 产出（不走 GPT 造句）。
        "id": "daily", "zh": "今天", "icon": "sparkles",
        "desc": "每日播客同款句型",
        "categories": [
            {"id": "daily_easy", "zh": "初级", "hint": "(from podcast easy patterns — not GPT-generated)"},
            {"id": "daily_medium", "zh": "中级", "hint": "(from podcast medium patterns — not GPT-generated)"},
            {"id": "daily_hard", "zh": "高级", "hint": "(from podcast hard patterns — not GPT-generated)"},
        ],
    },
    {
        "id": "reactions", "zh": "日常", "icon": "bubble.left.and.bubble.right.fill",
        "desc": "脱口而出的短句",
        "categories": [
            {"id": "greetings", "zh": "寒暄开场",
             "hint": "greetings and casual openers: what's up, how's it going, long time no see; include how to actually respond to them"},
            {"id": "thanks", "zh": "感谢",
             "hint": "thanking beyond 'thank you': you're a lifesaver, I owe you one, I really appreciate it; and how to respond to thanks"},
            {"id": "apologies", "zh": "道歉与化解尴尬",
             "hint": "apologizing and smoothing awkward moments: my bad, no worries, it happens, don't sweat it"},
            {"id": "surprise", "zh": "惊讶与反应",
             "hint": "reacting to news: no way, you're kidding, that's insane, get out, seriously?"},
            {"id": "backchannel", "zh": "应和接话",
             "hint": "keeping conversation flowing: fair enough, tell me about it, totally, same here, that makes sense"},
            {"id": "goodbyes", "zh": "告别",
             "hint": "natural goodbyes: take care, catch you later, I'd better get going, it was great seeing you"},
        ],
    },
    {
        "id": "social", "zh": "玩梗", "icon": "face.smiling.fill",
        "desc": "年轻人怎么聊天",
        "categories": [
            {"id": "venting", "zh": "吐槽抱怨",
             "hint": "venting and complaining (mild, humorous register): cover exactly these: Ugh, not again / I can't even / This is ridiculous / You've got to be kidding me / I'm so done with this / What a pain / Why is it always me? / Today is not my day / That's the last thing I need"},
            {"id": "compliments", "zh": "彩虹屁夸人",
             "hint": "hyping people up, modern compliments: cover exactly these: You killed it! / You crushed it / You're a natural / I'm obsessed with this / You never miss / Chef's kiss / That's next level / You make it look easy / Looking sharp! (do NOT include 'that's fire', it lives in the slang category)"},
            {"id": "self_deprecating", "zh": "幽默自嘲",
             "hint": "humorous self-deprecation: cover exactly these: I'm a mess / Story of my life / Don't judge me / I have no idea what I'm doing / That's so me / I'm not a morning person / My brain isn't working today / Send help / It's fine, I'm fine"},
            {"id": "texting", "zh": "网络与短信用语",
             "hint": "internet & texting language young natives use, teach both the abbreviation and the spoken full form: cover exactly these: ngl (not gonna lie) / tbh (to be honest) / lowkey and highkey / no cap / it's giving ___ / fr (for real) / bet / I'm dead / it's a vibe"},
            {"id": "dating", "zh": "约会与暧昧",
             "hint": "dating and flirting: cover exactly these: We hit it off / I'm into you / Are you seeing anyone? / Wanna grab a drink sometime? / He's my type (or She's my type) / Things are getting serious / I got ghosted / It's not you, it's me / Playing hard to get"},
            {"id": "arguing", "zh": "争论与立场",
             "hint": "arguing and standing your ground (casual, not hostile): cover exactly these: Hear me out / That's not the point / Agree to disagree / Says who? / That's on you / You're missing the point / Where's this coming from? / Fine, you win / Let's just drop it"},
            {"id": "gossip", "zh": "八卦吃瓜",
             "hint": "gossiping and juicy news: cover exactly these: Guess what? / Spill the tea / You didn't hear this from me / My lips are sealed / Keep me posted / Word travels fast / Wait, back up / So much drama / I heard it through the grapevine"},
        ],
    },
    {
        "id": "express", "zh": "观点", "icon": "person.wave.2.fill",
        "desc": "把想法说出来",
        "categories": [
            {"id": "opinions", "zh": "表达观点",
             "hint": "giving opinions naturally: to be honest, if you ask me, the way I see it, personally I think"},
            {"id": "feelings", "zh": "描述感受与状态",
             "hint": "describing how you feel: I'm exhausted, I'm not feeling it, I'm over it, I'm stoked, I can't be bothered"},
            {"id": "suggestions", "zh": "提建议",
             "hint": "making suggestions: why don't we, you might want to, how about, it wouldn't hurt to"},
            {"id": "agree_disagree", "zh": "同意与委婉反对",
             "hint": "agreeing and politely disagreeing: I see your point but, I'm not so sure about that, you have a point, agreed"},
            {"id": "preferences", "zh": "偏好与选择",
             "hint": "expressing preference: I'd rather, I'm torn between, I'm leaning towards, either works for me"},
            {"id": "hedging", "zh": "猜测与不确定",
             "hint": "hedging and speculation: I guess, chances are, it depends, I could be wrong but, something like that"},
        ],
    },
    {
        "id": "skills", "zh": "会话技巧", "icon": "arrow.triangle.2.circlepath",
        "desc": "让对话顺畅进行",
        "categories": [
            {"id": "requests", "zh": "请求与帮忙",
             "hint": "asking for help and favors: could you do me a favor, do you mind if, would it be okay to, can you give me a hand"},
            {"id": "refusing", "zh": "委婉拒绝",
             "hint": "saying no politely: I'm good thanks, I'll pass, maybe next time, I wish I could but"},
            {"id": "interrupting", "zh": "打断与插话",
             "hint": "interrupting politely: sorry to cut in, can I jump in here, before I forget, real quick"},
            {"id": "clarifying", "zh": "澄清与确认",
             "hint": "checking understanding: just to double-check, what do you mean by, so you're saying, did I get that right; plus asking people to repeat"},
            {"id": "transitions", "zh": "转话题与收尾",
             "hint": "moving conversation along: anyway, long story short, that reminds me, where was I, speaking of which"},
            {"id": "encouragement", "zh": "鼓励与安慰",
             "hint": "encouraging and comforting: hang in there, it happens, you've got this, don't beat yourself up, it is what it is"},
        ],
    },
    {
        "id": "native", "zh": "进阶地道", "icon": "flame.fill",
        "desc": "母语者浓度最高",
        "categories": [
            {"id": "slang", "zh": "地道俚语",
             "hint": "current everyday slang natives actually use: it slaps, that's fire, I'm broke, salty, sketchy, hangry; note country differences (US/UK/AU) where relevant"},
            {"id": "fillers", "zh": "口头禅与填充词",
             "hint": "fillers and verbal habits: like, literally, you know, I mean, kind of, at the end of the day — teach what feeling each carries and how not to overuse"},
            {"id": "idioms", "zh": "习语与比喻",
             "hint": "high-frequency idioms in real speech: piece of cake, under the weather, hit the road, call it a day, on the same page"},
            {"id": "phrasal_verbs", "zh": "高频短语动词",
             "hint": "phrasal verbs natives use constantly: figure out, put up with, run into, end up, come up with, deal with"},
        ],
    },

    # ===== 商务英语区（section: business）=====
    # 每分类目标 25 条（TARGET_COUNT），密度是日常线的 2.5 倍 —— 靠 generate_expressions --top-up 累积生成
    {
        "id": "biz_meeting", "zh": "会议", "icon": "person.3.fill",
        "desc": "开会时怎么开口",
        "categories": [
            {"id": "biz_meeting_open", "zh": "开场与主持",
             "hint": "opening and chairing a meeting: let's get started, thanks everyone for joining, quick round of intros, let's run through the agenda, I'll keep this brief, can everyone hear me"},
            {"id": "biz_meeting_speak", "zh": "发言与插话",
             "hint": "taking the floor and interrupting politely in meetings: can I jump in here, building on that, if I could add one thing, sorry to interrupt, just to piggyback on that, let me finish my thought"},
            {"id": "biz_meeting_stance", "zh": "表态与异议",
             "hint": "agreeing, pushing back and hedging in a work setting: I'm on board with that, I see it differently, I have some reservations, let's park that, I'd push back on that slightly, that's a fair point but"},
            {"id": "biz_meeting_wrap", "zh": "收尾与行动项",
             "hint": "wrapping up with action items: let's recap the takeaways, who owns this, what's the timeline, I'll follow up with notes, let's take this offline, any blockers"},
        ],
    },
    {
        "id": "biz_email", "zh": "邮件", "icon": "envelope.fill",
        "desc": "写得专业又不生硬",
        "categories": [
            {"id": "biz_email_open", "zh": "开头与结尾",
             "hint": "email openers and sign-offs: I hope this finds you well, quick question for you, thanks for the quick turnaround, looking forward to hearing from you, best regards, happy to discuss further"},
            {"id": "biz_email_ask", "zh": "请求与跟进",
             "hint": "making requests and following up by email: would you be able to, just circling back on this, gentle nudge on the below, when you get a chance, any update on, per my last email"},
            {"id": "biz_email_delay", "zh": "延期与致歉",
             "hint": "apologizing and buying time professionally: apologies for the delay, this slipped through the cracks, we're running behind on, I take full responsibility, we're doing our best to expedite"},
            {"id": "formal", "zh": "正式与礼貌",
             "hint": "polite formal register: I'd appreciate it if, would it be possible to, I was wondering if, at your earliest convenience"},
        ],
    },
    {
        "id": "biz_negotiate", "zh": "谈判", "icon": "arrow.left.arrow.right",
        "desc": "把条件谈下来",
        "categories": [
            {"id": "biz_nego_price", "zh": "报价与议价",
             "hint": "quoting and haggling in business: our ballpark is, is there any flexibility on price, that's outside our budget, what would it take to get there, can you do better on that"},
            {"id": "biz_nego_concede", "zh": "让步与条件",
             "hint": "trading concessions: if you can do X, we can do Y, that works on one condition, I can meet you halfway, we'd need something in return, let's find a middle ground"},
            {"id": "biz_nego_refuse", "zh": "拒绝与守底线",
             "hint": "saying no and holding your ground professionally: that doesn't work for us, we're not in a position to, that's a hard no on our side, I'm afraid that's our final offer, we'd have to walk away"},
            {"id": "biz_nego_close", "zh": "推进与成交",
             "hint": "moving a deal forward: are we aligned on this, let's get this over the line, what are the next steps, I'll send over the paperwork, do we have a deal"},
        ],
    },
    {
        "id": "biz_interview", "zh": "面试", "icon": "person.badge.key.fill",
        "desc": "拿下这份 offer",
        "categories": [
            {"id": "biz_itv_intro", "zh": "自我介绍",
             "hint": "introducing yourself in interviews: thanks for having me, a bit about my background, I've spent the last X years, what drew me to this role, I'm currently based in"},
            {"id": "biz_itv_strength", "zh": "经历与优势",
             "hint": "presenting experience and strengths with STAR-ish framing: I led a team of, my biggest win was, what I bring to the table, I'd say my strength is, I thrive in environments where"},
            {"id": "biz_itv_ask", "zh": "反问面试官",
             "hint": "questions candidates ask interviewers: what does success look like in this role, how would you describe the team culture, what are the biggest challenges, what are the next steps in the process"},
            {"id": "biz_itv_salary", "zh": "薪资谈判",
             "hint": "discussing compensation: what's the range for this role, based on my experience I'm targeting, is there flexibility on the base, I'd like to consider the whole package, can I have a few days to think it over"},
        ],
    },
    {
        "id": "biz_present", "zh": "汇报", "icon": "chart.bar.fill",
        "desc": "讲清楚，讲得动人",
        "categories": [
            {"id": "biz_pre_open", "zh": "开场与结构",
             "hint": "opening a presentation and signposting: today I'll walk you through, here's what we'll cover, by the end you'll know, let me set the scene, I'll take questions at the end"},
            {"id": "biz_pre_data", "zh": "讲数据",
             "hint": "presenting numbers: as you can see here, this is up X percent quarter over quarter, the headline number is, what jumps out is, to put that in perspective"},
            {"id": "biz_pre_flow", "zh": "过渡与强调",
             "hint": "transitions and emphasis in talks: which brings me to, the key takeaway here is, I want to zoom in on, moving on to, if you remember one thing"},
            {"id": "biz_pre_qa", "zh": "Q&A 应对",
             "hint": "handling Q&A: great question, let me come back to you on that, I don't have that number offhand, to your point, does that answer your question"},
        ],
    },
    {
        "id": "biz_social", "zh": "职场社交", "icon": "briefcase.fill",
        "desc": "同事之间怎么处",
        "categories": [
            {"id": "biz_soc_smalltalk", "zh": "Small talk",
             "hint": "workplace small talk: how was your weekend, crazy week huh, how's the new role treating you, any plans for the long weekend, keeping busy"},
            {"id": "biz_soc_network", "zh": "Networking 破冰",
             "hint": "networking and breaking the ice at work events: what brings you here, what do you do at X, we should stay in touch, mind if I add you on LinkedIn, I'd love to pick your brain sometime"},
            {"id": "biz_soc_thanks", "zh": "感谢与致意",
             "hint": "professional thanks and credit-giving: I really appreciate you jumping on this, shout out to X for, couldn't have done it without you, thanks for having my back, kudos to the team"},
            {"id": "workplace", "zh": "职场黑话",
             "hint": "workplace English: let's circle back, I'll loop you in, take this offline, bandwidth, touch base, EOD"},
        ],
    },
]

# 每个分类的目标条数：日常线沿用生成器默认 8-12；商务线要 25（页面要填满）
TARGET_COUNT_DEFAULT = 10
TARGET_COUNT_BY_SECTION = {"business": 25}

# 闸门：只有第一个组（日常反应）的第一个分类（寒暄开场）免费体验，其余全部 Pro
FREE_CATEGORY_IDS = {"daily_easy"}  # 免费位移：今日句型·初级 的第一条免费，其余全部 Pro

# 双区块：句型 tab 顶部「日常社交 | 商务英语」。business 组 id 以 biz_ 开头。
BUSINESS_GROUP_IDS = {"biz_meeting", "biz_email", "biz_negotiate", "biz_interview", "biz_present", "biz_social"}


def section_of(group_id):
    return "business" if group_id in BUSINESS_GROUP_IDS else "social"


def target_count(group_id):
    """该组下每个分类的目标条数（商务线 25，日常线沿用生成器默认）。"""
    return TARGET_COUNT_BY_SECTION.get(section_of(group_id), TARGET_COUNT_DEFAULT)


def all_categories():
    out = []
    for group in GROUPS:
        for cat in group["categories"]:
            out.append({
                "group_id": group["id"],
                "group_zh": group["zh"],
                "section": section_of(group["id"]),
                "target_count": target_count(group["id"]),
                "id": cat["id"],
                "zh": cat["zh"],
                "hint": cat["hint"],
                "is_free": cat["id"] in FREE_CATEGORY_IDS,
            })
    return out


if __name__ == "__main__":
    cats = all_categories()
    print("groups: %d, categories: %d" % (len(GROUPS), len(cats)))
    for sec in ("social", "business"):
        gs = [g for g in GROUPS if section_of(g["id"]) == sec]
        n = sum(len(g["categories"]) for g in gs)
        print("\n[%s] %d 组 / %d 分类" % (sec, len(gs), n))
        for g in gs:
            print("  %s %s: %s" % (g["icon"], g["zh"], ", ".join(c["zh"] for c in g["categories"])))
