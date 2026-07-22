# RC 后台 Paywall 配置操作卡（10 分钟，照着贴）

> App 代码已全部接好，Offering 也已就绪。只剩这一件事：在 RC 后台搭一个模板 paywall 并 Publish。
> Publish 后手机上立即生效，不用发版。以后改样式/文案也不用发版。

---

## 第 1 步：进入编辑器

1. 打开 https://app.revenuecat.com → 登录 → 选 Castlingo 项目
2. 左侧菜单 **Paywalls** → **+ New paywall**
3. 弹窗里选择挂到 offering：**default**（✅ 已验证，里面 $rc_annual/$rc_monthly 都配好了）
4. 挑一个模板（建议选带「双方案对比 + 底部大按钮」的模板，和现在的付费墙布局最接近）

## 第 2 步：配置两个方案

- 模板里的 Packages 区选中 **Annual** 和 **Monthly** 两个包
- 把 **Annual 设为默认选中/高亮**（编辑器里通常叫 "default selected" 或拖到第一位）

方案文字直接贴（价格和试用会自动取 App Store 真实值）：

| 位置 | 贴这个 |
|---|---|
| 年付方案标题 | `年度会员` |
| 年付方案副文字 | `{{ product.price_per_period }} · 平均{{ product.price_per_day }}/天` |
| 年付角标（可选） | `省{{ product.relative_discount }}` |
| 月付方案标题 | `月度会员` |
| 月付方案副文字 | `{{ product.price_per_period }}` |

## 第 3 步：标题和卖点文案（从旧付费墙搬过来，直接贴）

| 位置 | 贴这个 |
|---|---|
| 大标题 | `坚持一整年，流利说英语` |
| 副标题 | `每天 6 分钟，随时随地` |
| 小字 | `内容免费看，解锁发音 · 收藏 · 练习` |

卖点列表（模板的 feature list，逐行贴）：

```
6国60+课，发音收藏全解锁
227条地道表达，全部能听能存
集数不限，完整5遍磨耳朵
双语字幕，点哪个词查哪个
整集生词一个不落
配对造句，想练就练
```

## 第 4 步：试用文案（只对有试用资格的用户显示）

编辑器里给文字组件设置「仅试用资格用户可见」（Intro offer eligibility），然后贴：

| 位置 | 贴这个 |
|---|---|
| CTA 按钮（试用资格用户） | `开启免费试用` |
| CTA 按钮（无资格用户） | `立即订阅` |
| CTA 下方小字 | `{{ product.offer_period }}免费试用，{{ product.offer_end_date }}起 {{ product.price_per_period }}，可随时取消` |

## 第 5 步：三个必加组件（苹果审核必需，别漏）

1. **关闭按钮**：编辑器里加 Close button 组件（代码里的参数对 v2 模板无效，必须在编辑器加，否则用户关不掉付费墙）
2. **底部链接**，两条：
   - `使用条款` → `https://amyhuang13506-svg.github.io/LangPod/docs/terms.html`
   - `隐私政策` → `https://amyhuang13506-svg.github.io/LangPod/docs/privacy.html`
3. **恢复购买按钮**：加 Restore purchases 组件，文字 `恢复购买`

## 第 6 步：语言

- 编辑器 Localization 里确认默认语言填的就是中文内容（上面贴的都是中文，一般不用再加语言）
- 如果模板默认生成了英文占位文字，逐个替换成上面的中文

## 第 7 步：发布 + 验证

1. 右上角 **Publish**
2. 手机上打开 Castlingo → 随便点一个 Pro 锁 → 应该看到新模板（如果还是白底旧样式/英文默认样式，杀掉 app 重开一次，offering 有缓存）
3. 检查：价格显示 ¥298/¥48、关闭按钮能关、底部三个链接都在

---

## 常见问题

- **打开还是英文默认样式** → 后台没 Publish，或 paywall 没挂到 default offering
- **价格显示不对/空白** → 检查方案文字里的变量拼写（必须是 `{{ product.price_per_period }}` 这种双花括号）
- **想暂时切回旧付费墙对比** → 手机 App「我的」页调试区打开「[DEV] 使用旧付费墙」开关（仅 DEBUG 包有）
