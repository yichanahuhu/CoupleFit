# CoupleFit · 情侣运动打卡

一款 iOS 原生 App，供一对情侣使用。男方运动类型为「呼啦圈」，女方为「跳跃运动」。
双方独立记录自己的运动数据，实时查看对方的今日进度、历史与统计，互相督促鼓励。

| 项目 | 说明 |
|---|---|
| 平台 | iOS / iPadOS 17+（iPhone + iPad 通用，已针对 iPad mini 6 适配布局） |
| 语言 | Swift 5.9 + SwiftUI |
| 后端 | Firebase（Auth + Firestore + Cloud Messaging + Cloud Functions） |
| 状态管理 | `@Observable`（iOS 17） |
| 图表 | Swift Charts |
| 工程 | XcodeGen（`project.yml` → `.xcodeproj`） |

---

## 零、本地没有 Mac 怎么办

先说清楚一条硬约束：**iOS App 的打包和上架必须由 Xcode 完成，而 Xcode 只能运行在 macOS 上**。
这是 Apple 的限制，没有任何绕过的办法。没有 Mac 就无法真机调试、无法上传 TestFlight。

但这不妨碍你**现在就验证代码能不能编译**。本项目已配好 GitHub Actions，云端 macOS 免费帮你编译。

### 用 GitHub Actions 验证编译（免费）

1. 建一个 GitHub 仓库，把本目录推上去
   ```bash
   cd CoupleFit
   git init
   git add .
   git commit -m "init CoupleFit"
   git remote add origin git@github.com:<你的账号>/<仓库名>.git
   git push -u origin main
   ```
2. push 完成后，打开仓库的 **Actions** 标签页，会看到 `iOS Build Check` 正在跑
3. 首次约 15–25 分钟（主要是拉取 Firebase SDK），后续有缓存会快很多
4. 看结果：
   - **绿色 ✅** —— 代码编译通过
   - **红色 ❌** —— 点进去看 `汇总编译错误` 那一步，`error:` 行已被单独拎出来

> **费用**：公开仓库完全免费。私有仓库消耗额度，且 macOS 按 **10 倍**计费
> （每月免费 2000 分钟 ≈ 实际 200 分钟 macOS）。
> 想省钱：仓库设为 Public；或把触发方式改成纯手动
> （删掉 workflow 里的 `push` / `pull_request`，只留 `workflow_dispatch`）。

### 要真正装到手机上，你需要一次 Mac 访问

CI 只能告诉你"能不能编译"，签名的活儿还是得 Xcode。
本项目的定位是**自用、不上架**，所以通常只需一次 Mac 就够，详见第五节。

| 方式 | 成本 | 说明 |
|---|---|---|
| 云端编译 + 电脑端签名（方案 C） | 免费 | **首选**。完全不需要 Mac，见第五节 |
| 找朋友 / 公司的 Mac 借一次 | 免费 | 手边有 Mac 的话这条路最快，半小时搞定 |
| 云 Mac（MacinCloud / MacStadium） | 约 $30/月 | 仅方案 B（$99 付费账号）适用；免费 Apple ID 需要 USB 连真机，云 Mac 没有物理 USB |

> **Apple Developer Program（$99/年）不是必须的**：免费 Apple ID 也能装到真机，
> 代价是签名 7 天过期、没有远程推送。详见第五节的方案 A / B / C 对比。

---

## 一、在 Mac 上跑起来

### 1. 安装 XcodeGen

```bash
brew install xcodegen
```

### 2. 生成工程

```bash
cd CoupleFit
xcodegen generate
open CoupleFit.xcodeproj
```

> `.xcodeproj` 由 `project.yml` 生成，**不要手动修改**，也已在 `.gitignore` 中排除。
> 每次新增/删除 Swift 文件后，重新执行 `xcodegen generate` 即可。

### 3. 替换两个占位值

| 位置 | 占位内容 | 改成 |
|---|---|---|
| `project.yml` | `DEVELOPMENT_TEAM: YOUR_TEAM_ID` | 你的 Apple Developer Team ID |
| `CoupleFit/Resources/GoogleService-Info.plist` | 全部 `__XXX__` | Firebase 控制台下载的真实文件 |

**不做这两步，第三步 Firebase 配置没完成时 App 能启动到登录页，但所有云端功能不可用。**

### 4. 配置 Firebase

1. 打开 https://console.firebase.google.com，新建项目（建议命名 `CoupleFit`）
2. **Authentication** → Sign-in method → 启用
   - 「电子邮件/密码」
   - 「Apple」（App Store 上架含第三方登录时必填）
3. **Firestore Database** → 创建数据库
   - 生产模式 → 区域选 `asia-east1`（或离你最近的区域）
4. **Cloud Messaging** → 后续配置 APNs（见「推送配置」一节）
5. 项目设置 → 添加 iOS 应用
   - Bundle ID：`com.couplefit.app`（与 `project.yml` 中 `PRODUCT_BUNDLE_IDENTIFIER` 一致）
   - 下载 `GoogleService-Info.plist`，覆盖 `CoupleFit/Resources/GoogleService-Info.plist`
6. 部署安全规则与索引

```bash
npm install -g firebase-tools
firebase login
firebase init firestore    # 选已有项目，rules 用 firestore.rules，indexes 用 firestore.indexes.json
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

### 5. 首次编译

Xcode 打开后，`Cmd + B`。Swift Package Manager 会自动拉取 Firebase SDK（约 300MB，首次较慢）。
若 SPM 卡住，`File → Packages → Reset Package Caches`。

---

## 二、目录结构

```
CoupleFit/
├── project.yml                    # XcodeGen 配置（工程结构的唯一来源）
├── firestore.rules                # Firestore 安全规则
├── firestore.indexes.json         # 复合索引
├── firebase/
│   ├── firebase.json
│   └── functions/                 # Cloud Functions：代替客户端发 FCM 推送
│       ├── index.js
│       └── package.json
└── CoupleFit/
    ├── App/
    │   ├── CoupleFitApp.swift     # 入口，注入 AppState
    │   ├── AppDelegate.swift      # Firebase configure、推送注册、通知回调
    │   ├── AppState.swift         # 全局状态 + 所有监听器生命周期管理
    │   └── RootView.swift         # 登录态分发 + 主 Tab
    ├── Models/                    # UserProfile / PairCode / ExerciseRecord / Goal / Like
    ├── Services/                  # Auth / Firestore / Pairing / Notification / Messaging
    ├── Features/                  # 按页面划分：Auth Pairing Profile Home Timer Record History Stats Settings
    ├── Components/                # 通用 UI 组件
    ├── Utils/                     # DateHelper / CalorieEstimator / Constants
    └── Resources/                 # Info.plist / entitlements / Assets / GoogleService-Info.plist
```

### 分层约定

- **Models** 只描述数据结构，不含业务逻辑
- **Services** 只做 I/O（Firebase、通知、网络），不知道 UI 的存在
- **AppState** 是唯一的可变状态中心，持有所有 `addSnapshotListener` 并在登录态变化时重建
- **Features** 只做展示与交互，通过 `@Environment(AppState.self)` 读状态

---

## 三、数据模型（Firestore）

### `users/{userId}`
| 字段 | 类型 | 说明 |
|---|---|---|
| `email` | string | |
| `displayName` | string | 昵称，空表示尚未完成资料设置 |
| `partnerId` | string? | 对方 uid，`null` 表示未绑定 |
| `exerciseType` | string | `hula_hoop` / `jump` |
| `fcmTokens` | array? | 推送用的设备 token 列表。同账号登录多台设备时逐台累加，退出登录只移除本机那一个 |
| `createdAt` | timestamp | |

### `pairCodes/{code}`
`code` / `creatorUserId` / `expiresAt`，有效期 10 分钟，绑定成功后删除。

### `exerciseRecords/{autoId}`
| 字段 | 类型 | 说明 |
|---|---|---|
| `userId` | string | |
| `exerciseType` | string | |
| `dateString` | string | `yyyy-MM-dd`，**用户本地时区** |
| `startTime` / `endTime` | timestamp | |
| `durationSeconds` | int | |
| `count` | int | 圈数或次数 |
| `calories` | double? | 估算值，可手填 |
| `note` | string? | |
| `createdAt` | timestamp | |

### `goals/{userId}`
`dailyDurationSeconds` / `dailyCount` / `reminderEnabled` / `reminderHour` / `reminderMinute` / `remindPartner`

### `likes/{autoId}`
`fromUserId` / `toUserId` / `dateString` / `createdAt`

---

## 四、关键实现说明

### 日期处理
所有日期归属以**开始时间的本地日期**为准，存储为 `yyyy-MM-dd` 字符串（`DateHelper.dateString(from:)`）。
这样按天查询、按天分组、连续打卡计算都变成字符串/集合操作，避开时区陷阱。

### 跨天
`AppState.refreshDayBoundaryIfNeeded()` 会比较当前日期与上次记录的日期：
- `HomeView.onAppear`
- `MainTabView` 的 `willEnterForegroundNotification`

跨天时自动重建「今日」相关的监听器，无需重启 App。

### 实时同步
`AppState` 集中管理 10 个 `ListenerRegistration`：
- 自己的 user / 对方 user
- 双方今日记录 / 最近 90 天记录
- 双方目标 / 今日点赞

`partnerId` 变化时（`refreshPartnerListenersIfNeeded`）自动重建对方相关的全部监听。
Firestore 的本地持久化已开启，断网时仍可读取缓存，恢复网络后自动补提交。

### 计时器
采用「每秒累加」而非「时间差计算」，暂停/恢复能精确累计。
进入后台时记录时间戳（`scenePhase` → `.background`），回到前台一次性补上差值，
因此后台期间的时间不会丢。

### 卡路里
呼啦圈 5 kcal/分钟，跳跃运动 10 kcal/分钟，线性估算（`CalorieEstimator`）。
不足 1 分钟按比例折算，可在记录表单中手动覆盖。

### 提醒对方
客户端**不持有** Server Key，无法直接发 FCM。流程是：

```
App → POST /remindPartner (带 Firebase ID Token) → Cloud Function
    → 校验调用者身份 + 情侣关系 → 取对方 `fcmTokens`（可能多台设备）→ 一次性群发，并清理失效 token
```

**未部署 Cloud Function 时自动降级**：`MessagingService` 检测不到端点就发一条本地模拟通知，
所以第 4 周不依赖后端也能验证交互。

部署后把端点 URL 填到 `Info.plist` 的 `RemindEndpoint`，或 `MessagingService.remindEndpoint` 的默认值。

---

## 五、装到手机上（自用分发，不上架）

本项目的定位是**两个人的自用 App**，不需要也不打算上架 App Store。
这一节讲怎么把它装到你和伴侣的两台 iPhone 上。

### 先认清一条底线：Xcode 的活儿得拆开干

Xcode 一次做完两件事：**编译** + **签名**。没有 Mac 就把它们拆开分别找替代品：

| 环节 | 没有 Mac 怎么办 |
|---|---|
| 编译 | 云端 macOS CI（GitHub Actions 免费） |
| 签名 | Windows 上的 Sideloadly / AltStore + 免费 Apple ID |

这就是下面的**方案 C，全程不需要 Mac，也不需要花钱**。
若你手边正好有 Mac，方案 A 会更快；若愿意花 $99/年，方案 B 连手动签名都省了。

### 方案 A：免费 Apple ID（当前默认配置）

**成本 $0，但代价很大。** 项目已默认按此配置，直接可用。

操作步骤：
1. 找一台能 USB 连 iPhone 的 Mac（借一次即可，全程半小时）
2. Xcode → Settings → Accounts → 用你的 Apple ID 登录（无需付费会员）
3. 打开 `CoupleFit.xcodeproj`，选 Target → Signing & Capabilities
4. Team 选 `你的名字 (Personal Team)`，勾 `Automatically manage signing`
5. iPhone 解锁后 USB 连上 Mac，信任此电脑，顶部设备列表选它
6. `Cmd + R`，App 装到手机。第二台重复一次

**免费账号的三个硬伤**：

| 限制 | 具体后果 |
|---|---|
| 签名有效期 **7 天** | 第 8 天 App 直接闪退打不开。要重新连 Mac、重新 `Cmd + R`，两台手机各来一遍 |
| 不支持 **Push Notifications** | 「提醒对方」失效。本地每日提醒不受影响，照常弹 |
| 不支持 **Sign in with Apple** | 只能用邮箱注册登录，Apple 按钮忽略即可 |

> 前两条是 Apple 的规则，无解。第三条若不处理会导致**签名失败、App 根本装不上**，
> 所以项目已默认使用 `CoupleFit-Free.entitlements`（移除了这两项 capability），
> 确保免费账号能顺利装上。详见 `project.yml` 中的注释。

**云 Mac 救不了这条路**：免费账号的设备注册依赖 Xcode 通过 USB 识别真机，
远程云 Mac 没有物理 USB，Codemagic / GitHub Actions 等云端 CI 同样做不到。

### 方案 B：Apple Developer Program（$99/年）

**一年一次，且完全不用碰 Mac。** 自用场景其实比方案 A 更省钱——
方案 A 每 7 天折腾一次，一年要折腾 52 次。

步骤：
1. 缴费开通 https://developer.apple.com/programs
2. 拿到两台 iPhone 的 UDID：Windows 上装 Microsoft Store 的
   **Apple Devices** App，连上手机即可看到 UDID
3. 在 Developer 网站 **Devices** 里登记这两台设备
4. 创建 **Ad Hoc** Distribution 描述文件，勾选这两台设备
5. 用 CI（Codemagic 免费额度 500 分钟/月即可）自动构建出签好名的 ipa
6. 你在 Windows 上下载 ipa，用 **Apple Devices** App 装到两台手机
7. 管 **1 年**，到期重复第 5–6 步，代码没大改的话十分钟搞定

切到方案 B 时，记得把 `project.yml` 里的 entitlements 换回
`CoupleFit/Resources/CoupleFit.entitlements`，恢复推送与 Apple 登录：

```yaml
entitlements:
  path: CoupleFit/Resources/CoupleFit.entitlements
  properties:
    aps-environment: development
    com.apple.developer.applesignin:
      - Default
```

### 方案 C：免费 Apple ID + 云端编译 + 电脑端签名（★ 推荐，全程不需要 Mac）

方案 A 的痛点不是"免费"，而是"每 7 天要找 Mac"。把**编译**和**签名**拆开就能绕开：

- **编译** → 交给云端 CI（GitHub Actions），产出未签名的 ipa
- **签名** → 交给 Windows 上的 Sideloadly / AltStore，配合免费 Apple ID

两者都不需要 Mac，也不需要 Xcode。

操作步骤：

1. 仓库 → **Actions** → `iOS Build Check` → 右上角 **Run workflow**
   → 勾选 `build_ipa` → 绿色按钮运行
2. 跑完（约 20 分钟）在页面底部 **Artifacts** 下载 `CoupleFit-unsigned-ipa`
3. Windows 上安装 [Sideloadly](https://sideloadly.io)（免费，也有开源替代：AltStore 的 AltServer）
4. iPhone 用数据线连电脑，Sideloadly 里选下载好的 ipa，填入你的 Apple ID，点 **Start**
5. 手机上首次安装后需要手动信任：
   **设置 → 通用 → VPN与设备管理 →** 点你的 Apple ID → 信任
6. 第二台 iPhone 重复第 4–5 步

**限制与方案 A 完全一致**（7 天过期、无远程推送、无 Apple 登录），
但**重签不再需要 Mac**：7 天后在 Windows 上再点一次 Sideloadly 即可，两分钟的事。

需要注意：

- Sideloadly 是第三方工具，需要你自行判断可信度；在意的话可用开源替代品
- 免费 Apple ID 每 7 天最多签名 3 个 App ID，自用绰绰有余
- 项目已默认使用 `CoupleFit-Free.entitlements`，
  确保 Sideloadly 用免费账号签名时不会因为不支持的 capability 而失败

### 建议的节奏

先用**方案 C** 跑通，两个人真实用一两周。全程零成本、零 Mac，最多就是每周点一次重签。

如果觉得这个 App 确实天天都会打开、值得长期用，再升级**方案 B**（$99/年），
换来一年一次的省心、远程推送、以及 Apple 登录。

若觉得一般，那你已经零成本验证过了，随时停下。

---

## 六、推送配置（仅方案 B 需要）

> **免费 Apple ID（方案 A）不支持远程推送，本节可跳过。**
> 「提醒对方」会自动降级为本地模拟通知（标题带「本地模拟」字样），其余功能不受影响。

本地通知（每日提醒）无需额外配置，模拟器也能触发。
远程推送（提醒对方）需要：

1. Apple Developer → 创建 **Apple Push Notification service (APNs) 密钥**（`.p8`）
2. Firebase 控制台 → 项目设置 → Cloud Messaging → 上传 APNs 密钥，填 Key ID 与 Team ID
3. Xcode → Target → Signing & Capabilities → 确认 `Push Notifications` 已添加
4. entitlements 中 `aps-environment` 需与打包方式匹配：
   - Xcode 直连调试 / Ad Hoc → `development`
   - App Store → `production`
5. 部署 Cloud Function：见 `firebase/functions/index.js` 顶部注释

> **模拟器无法接收远程推送**，需真机验证。

---

## 七、验收清单

对照需求文档第八节，逐项验证：

- [ ] 两个测试账号完成配对，互相看到对方昵称和运动类型
- [ ] 一方保存记录后，另一方首页 **2 秒内**自动更新
- [ ] 双方设置各自目标，进度环正确显示
- [ ] 本地通知在设定时间触发
- [ ] 历史记录、统计数据准确；点赞功能正常
- [ ] 断网时顶部出现橙色提示条，数据不丢失
- [ ] 杀进程后重进，数据完整
- [ ] 跨天（23:59 → 00:00）记录归属正确
- [ ] 配对码 10 分钟后过期并提示
- [ ] 深色模式下所有页面正常
- [ ] iPhone SE（小屏）与 iPhone 15 Pro Max 布局无截断

---

## 八、常见问题

**Q：编译报 `No such module 'FirebaseCore'`**
首次打开需要等待 SPM 拉取依赖。若长时间无响应：`File → Packages → Resolve Package Versions`，
或检查网络能否访问 `github.com/firebase/firebase-ios-sdk`。

**Q：启动崩溃，日志出现 `Default app has not been configured yet`**
`GoogleService-Info.plist` 未被打包。检查它是否在 Target → Build Phases → Copy Bundle Resources 中。
用 XcodeGen 重新生成工程可自动修复。

**Q：Firestore 报 `Missing or insufficient permissions`**
先确认已部署 `firestore.rules`。再检查本地是否登录（`Auth.auth().currentUser` 不为 nil）。
规则里情侣关系依赖 `users/{uid}.partnerId`，若绑定失败会出现「自己能看到、对方看不到」。

**Q：Firestore 报 `The query requires an index`**
控制台的错误日志里有一条直达链接，点一下自动创建索引；
或执行 `firebase deploy --only firestore:indexes` 用本项目配置。

**Q：「提醒对方」点了没反应**
未部署 Cloud Function 时会退化为本地模拟通知（标题带「本地模拟」字样），属预期行为。
部署后仍无推送：检查 users 文档的 `fcmTokens` 数组里是否有内容（App 启动时会写入），以及是否真机运行。

**Q：Preview 崩溃**
`AppState` 与 `AuthService` 都已做惰性初始化，Preview 应可用。
若某个 Preview 仍崩溃，多半是该 View 直接访问了 Firebase，改成在 `.task` 中访问即可。

---

## 九、iPad 支持

工程已设为 iPhone + iPad 通用（`TARGETED_DEVICE_FAMILY = "1,2"`），
并针对 **iPad mini 6**（8.3 英寸，逻辑分辨率 744×1133pt）做了布局适配：

| 位置 | iPhone | iPad |
|---|---|---|
| 首页 | 我的卡片、对方卡片纵向堆叠 | 宽度 ≥ 680pt 时左右并排 |
| 首页内容宽度 | 撑满 | 上限 900pt 居中，避免拉成横幅 |
| 统计图表高度 | 220 / 140pt | 300 / 200pt |
| 计时器数字 | 72pt | 112pt |
| 登录 / 配对 / 资料设置 | 撑满 | 上限 560pt 居中 |

其余页面（历史 List、设置 Form、记录编辑 Form）在 iPad 上由 SwiftUI 自动限宽，无需额外处理。

> 若日后要支持更大的 iPad（12.9 英寸），建议首页改用 `NavigationSplitView` 做侧边栏布局。

---

## 十、已知限制

- 图表只覆盖本周数据，未做更长时间范围的选择
- `exerciseRecords` 的 list 查询依赖 `userId` 过滤，安全规则按此设计；改动查询方式时需同步改规则
- 未做单元测试与 UI 测试
- 卡路里为粗略估算，未接入 HealthKit
- **使用免费 Apple ID 时**（项目默认配置）：
  签名 7 天过期、「提醒对方」降级为本地模拟通知、Sign in with Apple 不可用。
  这三项是 Apple 对免费账号的限制，不是代码缺陷。付费后按第五节切换 entitlements 即可恢复。
- 计时器页面在长时间锁屏下依赖 `scenePhase` 补时，
  若系统因内存压力终止了 App，本次计时会丢失（未做本地持久化草稿）
