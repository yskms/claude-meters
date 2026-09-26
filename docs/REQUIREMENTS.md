# Claude Meters 要件定義書

## 開発前提・技術検証（本実装の着手条件）

本実装の着手前に、Claude CodeのUsage情報取得についての技術検証（PoC）を行う。
ここでの検証結果が、以降の章の仕様を左右する前提条件となる。

### 検証項目

- Session使用率を取得できるか
- Weekly使用率を取得できるか
- Sessionのリセット日時を取得できるか
- Weeklyのリセット日時を取得できるか
- 上記がアカウント単位の合算値になっているか（特定プロジェクト・特定ターミナルの値に限定されないか）
- Claude Codeを起動していない状態でも取得できるか
- Claude Codeの更新後も利用し続けられそうな、公式または安定した手段か
- Claude Meters側で認証情報を独自管理せずに取得できるか
- 取得値がClaudeのUsage画面の表示と実用上一致するか

### 合格基準

    Session/Weeklyの使用率とリセット日時を、
    認証情報を独自管理せずに取得でき、
    ClaudeのUsage画面と実用上同等の値になること。

### 基準を満たせない場合

以下のいずれかへ仕様を縮小する。

- 取得可能なメーターのみ表示する
- ユーザーによる追加設定（取得元への接続に必要な設定）を許容する
  （認証情報を扱う場合は、保存方式・保護・失効・削除を含むセキュリティ要件を別途定義する）
- 非公式な取得方法を採用し、制約をユーザーに明示する
- プロジェクト自体の前提を再検討する

### 検証結果に基づき確定する事項

- UsageProviderの実装方式
- App Sandboxの採否
- 必要な権限、および初回案内の要否
- 更新方式・更新間隔
- v1で提供するメーターとリセット表示の範囲

### Weeklyのリセットについて

Weeklyのリセット日時が固定曜日かローリング7日かは、Claude Meters側で判断・計算しない。
取得元（Claude Code）が返すリセット日時・期間の定義をそのまま採用し、表示する。

### PoC検証結果（中間）

**API取得検証：成功**

- Keychainの`Claude Code-credentials`にOAuth資格情報が格納されていることを確認
- そこから取り出したアクセストークンをBearer認証に使い、Usage APIからHTTP 200を確認
- 以下を取得できることを確認
  - Session（five_hour）の使用率とリセット日時
  - Weekly（seven_day）の使用率とリセット日時
- リセット日時はタイムゾーン付きISO 8601形式で返される
- レスポンス内の利用実態の記録（直近7日の利用元の内訳）が、実際の利用状況と一致していることも確認（Usage画面との直接比較ではなく、補助的な妥当性確認）
- トークン値はログ・検証結果のいずれにも記録していない

**アプリ統合検証：成功**

- 署名されたSwiftアプリ（Claude Meters.app、ad-hoc署名、Sandbox無効、`/Applications`にインストールして実行）から、Terminal経由ではなく実際に本番のUsageProvider実装を通してKeychainアクセス→API呼び出し→Session/Weekly使用率の表示までを実機で確認した
- 初回はmacOS標準の許可ダイアログ（キーチェーン"ログイン"のパスワード入力）が表示され、許可後は実際の数値（例：Session 11%、Weekly 12%）がメニューバーに表示されることを確認した
- ダイアログの表示頻度（今後のリビルドごとに再表示されるか等）や「常に許可」の永続化挙動の細部は、今回の確認範囲を超えるため別途注記（下記）

**未完了**

- App Sandbox有効時でのアクセス可否（現状はSandbox無効で確認済み。v1は非Sandbox・Developer ID配布を基本方針とするため必須ではない）
- ClaudeのUsage画面との同時刻比較

**制約・注記**

- 使用したUsage APIは未ドキュメント化された非公式な取得方法であり、エンドポイント・認証方式・レスポンス形式が予告なく変更される可能性がある
- レート制限を考慮し、短時間の頻繁なポーリングを行わない
- API・Keychain形式への依存はUsageProvider内に隔離し、他層に漏れ出させない
- ad-hoc署名は再ビルドのたびに実質的に別アプリ扱いとなり、Keychainの許可ダイアログが再度表示される可能性が高い。Developer ID署名に切り替えた後の挙動は未確認

**判定**

Session/Weeklyの使用率・リセット日時を、認証情報を独自管理せずに取得でき、実際に署名されたアプリのメニューバーに表示できることを実機で確認した。
未ドキュメント化APIである点は残るため「非公式方式を制約付きで採用する」という意思決定である点は変わらないが、
技術的な着手条件（0章）はこれで満たされたと判断する。

---

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

- 円直径：約18〜22pt（実機・Retina表示・ライト/ダークモードで試作比較のうえ確定する）
- メーター間：約3〜5pt
- 数字：約8〜10pt

数字表示：

- 表示値は整数 0〜100
- 桁数（1〜2桁／3桁）でフォントサイズを切り替える
- 100（3桁）はフォントサイズを縮小して円内に収める。「99+」等の省略表記は行わない
- 等幅数字（tabular figures）を使用し、桁数変化による見た目のガタつきを防ぐ

表示例：

    [ 16 ][ 5 ]

できるだけ横幅を取らない。

---

## 3.4 アクセシビリティ

メニューバー項目にVoiceOverラベルを付与する。

例：

    Session 16 percent used. Weekly 5 percent used.

日本語：

    セッション16パーセント使用。週間5パーセント使用。

取得失敗時は、その旨を読み上げ内容に含める。
色だけに依存せず、数値情報のみでも状態を判別できるようにする。

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

SessionResetAt / WeeklyResetAtは取得元が返すリセット日時を保持し、
Claude Meters側でリセット周期や日時を独自に算出しない。
表示に必要なタイムゾーンおよび形式への変換のみ行う
（詳細は冒頭「開発前提・技術検証」を参照）。

---

# 8. 更新

Usage情報を定期的に更新する。

更新方式・更新間隔は固定値をあらかじめ確定せず、
UsageProviderの取得コスト・更新頻度・レート制限に応じて決定する
（冒頭「開発前提・技術検証」の結果を踏まえて確定する）。

目安：

- ローカル情報の読み取りが中心の場合：60秒をデフォルトとする
- CLIプロセス実行を伴う場合：1〜5分程度とする
- ネットワークアクセスを伴う場合：提供元の制限に従う

そのほか、以下を基本方針とする。

- Popover表示時は必要に応じて即時更新する
- 取得失敗時は指数バックオフを行う
- 同時に複数の更新処理を重複実行しない
- スリープ復帰時に再取得する

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

    1 minute
    5 minutes

デフォルト：

    1 minute

未ドキュメント化APIのレート制限を考慮し、30秒間隔はv1では提供しない。

---

# 12. macOSアプリ仕様

## 対象

macOS専用。

最低対応OS：macOS 13 Ventura以降
（`MenuBarExtra` / `SMAppService` の利用を前提とするため）

## 配布方針

v1はDeveloper ID署名およびApple公証（Notarization）による直接配布を基本方針とする。

v0.1.1でDeveloper ID Application証明書による署名・Apple公証・ステープルまで実施済み。
`spctl -a -vvv --type execute`でGatekeeperの受理（`source=Notarized Developer ID`）を確認した。

- Mac App Store対応：v1対象外
- App Sandbox：v1では無効
  - Claude CodeのKeychain資格情報を利用する現在の取得方式との互換性を優先する
  - Sandbox対応は、将来Claude Codeが公式なUsage取得方式を提供した場合に再検討する

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
- 更新間隔設定（UsageProviderが任意間隔の指定を許容する場合）
- Usage取得失敗表示
- アクセシビリティ対応（VoiceOverラベル等）

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
