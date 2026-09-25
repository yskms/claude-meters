# Claude Meters 要件定義書

## 1. 概要

### 1.1 アプリ名

**Claude Meters**

### 1.2 コンセプト

Claude Code の使用量を、macOS のメニューバーから常時・瞬時に確認できる軽量ユーティリティ。

メニューバーには **2つの円形メーターだけ**を横並びで表示する。

- 左：5時間（Session）使用率
- 右：週間（Weekly）使用率

それぞれの円の中央に現在の使用率を数値で表示する。

Claude Code やブラウザを開いて Usage 画面を確認する必要をなくし、
「あとどれくらい使えるか」を常に視界に入れられることを目的とする。

---

## 2. 基本方針

Claude Meters は高機能なClaude管理アプリではなく、
**Usageを一瞬で確認するためのメニューバーメーター**に特化する。

重視するもの：

- 一目で分かる
- 常に表示される
- 小さい
- 軽い
- 操作不要
- Claude Codeの作業を邪魔しない

初期バージョンでは、使用量予測、履歴グラフ、複数アカウント管理などは実装しない。

---

# 3. メニューバー

## 3.1 基本表示

macOSメニューバーに2つの円形メーターを横並びで表示する。

イメージ：

    ◯  ◯
    16  5

実際には数字を円の中央に配置する。

概念図：

    ╭───╮ ╭───╮
    │ 16│ │  5│
    ╰───╯ ╰───╯

左：

    Session / 5h

右：

    Weekly / 7d

数字は使用率（%）。

「%」記号はメニューバーでは表示しない。

例：

    (16) (5)

= Session 16%、Weekly 5%

---

## 3.2 円形プログレス

円の外周そのものをProgress Ringとして使用する。

例：

0%

    ○
     0

25%

    ◔
    25

50%

    ◑
    50

75%

    ◕
    75

100%

    ●
    100

※ 上記は概念図。
実際にはSwiftUI等で滑らかな円形Progress Ringとして描画する。

中央には必ず使用率を表示する。

---

## 3.3 表示サイズ

macOSメニューバーに自然に収まるサイズを優先する。

目標：

- 円直径：約18〜20pt
- メーター間：約3〜5pt
- 数字：約8〜10pt

100の場合も円内に収まるよう調整する。

表示例：

    [ 16 ][ 5 ]

できるだけ横幅を取らない。

---

# 4. メーター仕様

## 4.1 左メーター

**Session**

Claudeの5時間枠の使用率を表示する。

例：

    16

→ 16%使用済み

詳細画面：

    Session
    16% used
    Resets in 1h 03m

日本語：

    セッション
    16% 使用
    1時間3分後にリセット

---

## 4.2 右メーター

**Weekly**

Claudeの週間使用率を表示する。

例：

    5

→ 5%使用済み

詳細画面：

    Weekly
    5% used
    Resets in 3d

日本語：

    週間
    5% 使用
    3日後にリセット

---

# 5. クリック時UI

メニューバーのメーターをクリックするとPopoverを表示する。

## English

    Claude Meters

    SESSION             WEEKLY

       ◔                   ◔
      16%                  5%

    Resets in 1h        Resets in 3d

    ─────────────────────────

    Last updated: 18:12

    Settings
    Quit Claude Meters

## 日本語

    Claude Meters

    セッション             週間

       ◔                   ◔
      16%                  5%

    1時間後にリセット      3日後にリセット

    ─────────────────────────

    最終更新: 18:12

    設定
    Claude Metersを終了

---

# 6. 色

基本的にはmacOS標準UIに馴染ませる。

初期案：

- 通常：システム標準色
- 背景：透明
- 未使用部分：薄いグレー
- 使用部分：Accent Color

ライトモード・ダークモードの両方に対応する。

色だけで使用量を判断させない。
必ず中央の数字でも確認可能にする。

将来的には使用率によって、

- Low
- Medium
- High
- Critical

を色で区別する設定も検討できるが、v1では必須ではない。

---

# 7. データ取得

## 7.1 基本方針

Claude Codeが取得・保持しているUsage情報を利用する。

可能な限り、

**Claudeの認証情報をClaude Meters自身が直接管理しない方式**

を優先する。

実装開始時に、現在のClaude Codeで利用可能なUsage取得方法を調査し、
最も安全かつ安定した方法を採用する。

優先順位：

1. Claude Codeが公式に提供するローカル情報
2. Claude Codeのstatusline等から取得可能なUsage情報
3. その他の安全なローカル取得方法

非公開APIや認証情報への直接アクセスは、
他の方法が利用できない場合にのみ検討する。

取得方式は将来変更できるよう、
UIとUsage取得処理を分離する。

例：

    UsageProvider
        ├── SessionUsage
        ├── WeeklyUsage
        ├── SessionResetAt
        └── WeeklyResetAt

---

# 8. 更新

Usage情報を定期的に更新する。

初期値：

    60秒

設定候補：

- 30秒
- 1分
- 5分

デフォルト：

    1分

Claude Code側からイベント的に更新を取得できる場合は、
将来的にポーリングを減らすことも検討する。

---

# 9. データ取得失敗時

Usageを取得できなかった場合でも、
メニューバーからアイコン自体を消さない。

例：

    (?) (?)

または

    (–) (–)

Popover：

    Unable to retrieve usage data.

日本語：

    使用量を取得できませんでした。

最後に正常取得した値がある場合は、
その値を保持した上で「更新失敗」であることをPopover内に表示してもよい。

---

# 10. 多言語対応

初期リリースから以下に対応する。

- English
- 日本語

macOSの言語設定に従って自動選択する。

SwiftUIの標準Localization機構を使用する。

メニューバー自体には基本的に数字しか表示しないため、
言語によるレイアウト差は発生しない。

アプリ名：

    Claude Meters

は全言語共通。

---

# 11. 設定

初期バージョンでは設定項目を最小限にする。

## General / 一般

### Launch at Login

English:

    Launch at Login

日本語:

    ログイン時に起動

Default:

    OFF

### Refresh Interval

English:

    Refresh Interval

日本語:

    更新間隔

選択肢：

    30 seconds
    1 minute
    5 minutes

デフォルト：

    1 minute

---

# 12. macOSアプリ仕様

## 対象

macOS専用。

## 技術候補

- Swift
- SwiftUI
- MenuBarExtra

ネイティブmacOSアプリとして実装する。

React Native / Electron等は使用しない。

理由：

- メニューバー専用アプリ
- UIが非常に小さい
- メモリ使用量を抑えたい
- macOSとの統合を優先
- SwiftUIのMenuBarExtraとの相性が良い

---

# 13. Dock

通常のアプリとしてDockには表示しない。

Claude Metersは

**Menu Bar Only**

のアプリとする。

起動後：

    Dock
      × 表示しない

    Menu Bar
      ○ 常駐

---

# 14. 起動フロー

初回起動時も大げさなオンボーディングは表示しない。

起動

    ↓

Usage取得

    ↓

メニューバーに

    (16) (5)

表示

    ↓

完了

追加設定が必要な場合のみ、
Popover内に案内を表示する。

---

# 15. アプリ構成案

    ClaudeMeters/
    ├── App/
    │   └── ClaudeMetersApp.swift
    │
    ├── Models/
    │   └── UsageData.swift
    │
    ├── Services/
    │   ├── UsageProvider.swift
    │   └── ClaudeUsageProvider.swift
    │
    ├── Views/
    │   ├── MenuBarMetersView.swift
    │   ├── UsageRingView.swift
    │   ├── PopoverView.swift
    │   └── SettingsView.swift
    │
    ├── Localization/
    │   ├── en
    │   └── ja
    │
    └── Assets.xcassets

Usage取得部分をProtocol化し、
将来的に取得方法が変わってもUI側に影響させない。

---

# 16. v1.0 スコープ

v1.0で実装するもの：

- macOSメニューバー常駐
- 円形メーター2個
- 円中央に使用率
- Session（5h）
- Weekly（7d）
- Progress Ring
- Usage自動更新
- リセット時刻表示
- Popover
- ライトモード
- ダークモード
- English
- 日本語
- ログイン時起動
- 更新間隔設定
- Usage取得失敗表示

---

# 17. v1.0では実装しないもの

以下は初期バージョンでは実装しない。

- Usage履歴
- グラフ
- 使用量予測
- AIによる分析
- 通知
- 複数アカウント
- Claude API利用料金
- 詳細なモデル別分析
- Webダッシュボード
- iOS版
- Windows版
- 自動アップデート機構

必要になった段階で検討する。

---

# 18. UX原則

Claude Metersで最も重要なのは、

**アプリを開かなくても分かること。**

ユーザーが確認する基本UIはPopoverではない。

メニューバーの

    (16) (5)

そのものがメイン画面である。

Popoverを開くのは、

「いつリセットされる？」

と確認したい場合だけでよい。

そのため、メニューバーの2つの数字の視認性を
すべてのUI要素より優先する。

---

# 19. 完成イメージ

macOS：

    Finder   File   Edit   View        ◯16 ◯5   Wi-Fi  Battery  18:12
                                      ↑   ↑
                                      │   │
                                      │   └─ Weekly
                                      └───── Session

実際には数字は円の横ではなく、
**円の中央に配置する。**

最終的な基本形：

             16    5
             ◯     ◯

ではなく、

           ╭──╮ ╭──╮
           │16│ │ 5│
           ╰──╯ ╰──╯

のように、数字とProgress Ringを一体化させる。

---

# 20. 一言で表すと

> Two meters. That's it.

Claude Metersは、
Claude Codeの5時間・週間Usageを
macOSメニューバーの2つの円だけで確認するためのアプリ。
