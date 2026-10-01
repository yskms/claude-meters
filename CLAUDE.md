# CLAUDE.md

Claude Metersのプロジェクト固有の重要事項。詳細な経緯・調査結果は[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)を参照。

## Xcodeプロジェクトは生成物

`ClaudeMeters.xcodeproj`は`project.yml`から[XcodeGen](https://github.com/yonaskolb/XcodeGen)で生成している。`project.pbxproj`を直接編集しない。変更する場合は`project.yml`を編集し、`xcodegen generate`で再生成する。

## Usage取得の仕組み（変更前に必読）

`ClaudeUsageProvider`は、公式ドキュメント化されたstatusLineの`rate_limits`フィールドではなく、Claude Codeが保持するOAuthトークン（Keychainの`Claude Code-credentials`）を読み、Anthropicの非公開API（`/api/oauth/usage`）を直接叩いてSession/Weekly使用率を取得している。

- statusLine経由にしなかった理由：VS Code拡張版Claude Codeは`statusLine`フック自体を未サポート（ターミナル版のみ対応）。ターミナル版でも`rate_limits`が入らないバグが報告されている。詳細はREQUIREMENTS.mdの「開発前提・技術検証」参照
- `resets_at`（リセット日時）はAPIが返す値をそのまま使う。固定曜日かローリング7日かをアプリ側で計算・推測しない
- Keychainの値は`{"claudeAiOauth":{"accessToken": ...}}`というJSON構造。生の文字列をそのままBearerトークンにはできない
- `ClaudeUsageProvider.parseMeter`は`utilization`と`resets_at`の両方が揃わない限り`nil`を返し、呼び出し元は`fetchUsage()`全体を失敗させる。未ドキュメントAPIの形式変更を「取得成功だが値が空」ではなく明確な失敗として検知するための意図的な設計。唯一の例外は`five_hour`の`resets_at: null`で、5時間枠が始まっていない間（夜間の未使用時など）に実際に返る正常な値のため受け付け、`MeterUsage.resetsAt = nil`（リセットによる非表示の対象外）にする。`seven_day`の`null`（意味が未確認）、キー欠落、日時として読めない文字列まで許容しないこと
- Keychainは`SecItemCopyMatching`ではなく`/usr/bin/security find-generic-password -w`をサブプロセスで実行して読む。Claude Codeはトークン更新のたびに`security add-generic-password -U`で項目を上書きしており（作成日時は変わらず更新日時だけが変わることを確認）、そのときACLが`/usr/bin/security`のみを信頼する状態に戻るため、直接読むと「常に許可」が1日数回リセットされてパスワードダイアログが再表示される、と考えられる（ACLの中身は未確認）。`security`経由ならトークン更新をまたいでもダイアログが再表示されないことを2026-09-30に実機で確認済み。直接呼び出しに戻さないこと
- `security`プロセスには60秒のタイムアウトを設けている（`security`自身がロック解除等のダイアログを出した場合にパスワード入力が間に合う長さ）。また、失敗時に`SecItemCopyMatching`へフォールバックしない。いずれも、`Task.cancel()`で止められない同期処理が無期限に止まると`UsageViewModel`の更新ループ全体が止まるため（下記参照）。キーチェーンのロックや`security`がACLに無い場合は、CLIが失敗せずダイアログを出すので、フォールバックしても得られるものはほぼ無い

## UsageViewModelの更新ループを単純化しない

`restartLoop()`の`currentGeneration`カウンタと`await previousTask?.value`は冗長に見えるが必須。`fetchUsage()`内のKeychainアクセスは同期処理でOSの許可ダイアログ待ちになることがあり、`Task.cancel()`では中断できない。世代チェックと「前のTaskの終了を待ってから次を開始する」処理の両方を外すと、古い取得処理と新しい取得処理が並行実行されたり、古い結果が新しい状態を上書きするレースコンディションが再発する（過去に複数回レビューで指摘・修正された箇所）。

## メーター表示の可否は`UsageDisplayState`だけで決める

取得失敗時に前回値を出すか「–」にするかは、`UsageDisplayState.make`（`Models/UsageData.swift`）の1箇所で判定し、メニューバー・Popover（リングとリセット時刻）・VoiceOverはすべてその結果だけを使う。Viewで`viewModel.snapshot`や`lastFetchFailed`を見てメーターの表示可否を個別に判定しないこと。過去に「失敗中は値を隠す」修正と「一時的な失敗では値を残す」修正が入れ違い、表示箇所ごとに挙動がずれる懸念があったため。規則の詳細はREQUIREMENTS.mdの「データ取得失敗時」を参照。

## メニューバー表示がImageRenderer経由である理由

`MenuBarMetersView`は`MenuBarExtra`の`label`に直接SwiftUIのHStack/Shapeを渡していない。実際に試したところ、複数リングのうち1つしか描画されない・Circleのストロークが消えるという不具合が発生したため、`ImageRenderer`で一度`NSImage`に焼き込んでから渡している。

- この画像は`isTemplate = true`にしており、macOSがメニューバーの明暗に応じて自動で色を付ける（他の標準アイコンと同じ挙動）。テンプレート画像はアルファ値しか使えないため、`MenuBarRingGlyph`（`MenuBarMetersView.swift`内のprivate struct）は使用率の表現に`Color.accentColor`ではなく黒＋不透明度を使っている
- Popover側の`UsageRingView`はテンプレート画像化していないので通常通りaccentColorを使用。2つの見た目が違う実装なのは意図的で、統合すべきではない

## macOS 13が最低対応OS

`MenuBarExtra`と`SMAppService`（ログイン時起動）がmacOS 13以降必須のため。`SettingsLink`と`onChange(of:initial:_:)`の2引数版はmacOS 14以降限定なので使用不可（`PopoverView`・`SettingsView`で旧APIに置き換え済み）。新しいAPIを使う際はデプロイメントターゲットに注意する。

## 設定ウィンドウはAppKitで自前管理している

`SettingsWindowController`（`App/SettingsWindowController.swift`）がSwiftUIの`Settings`シーンを使わず、`NSWindow(contentViewController:)`+`NSHostingController`で設定ウィンドウを直接生成・表示している。かつては`NSApp.sendAction(Selector(("showSettingsWindow:")), ...)`という非公開セレクタで`Settings`シーンを開こうとしていたが、このアプリは`LSUIElement`（Dockアイコンなし）のため実機では機能せず、設定ボタンを押しても何も起きなかった（Consoleに`Please use SettingsLink for opening the Settings scene.`という警告が出るのみでウィンドウは開かない）。`SettingsLink`はmacOS 14以降限定でmacOS 13をサポートできないため採用せず、自前のNSWindow管理に置き換えた。`ClaudeMetersApp.swift`に`Settings { }`シーンは存在しない。

- `NSWindow(contentRect: .zero, ...)`で作ってから`contentView`を設定し`center()`を呼ぶ、という順序にはしないこと。ウィンドウは原点（左下）を固定したままコンテンツに合わせて広がるため、サイズ確定前に`center()`すると、ウィンドウ中心ではなく左下角が画面中央に来た状態のまま広がり、見た目上センタリングされないおそれがある（推測であり、この崩れを実機のスクリーンショットで再現・確認したわけではない）。`NSWindow(contentViewController:)`はコンテンツのfitting sizeでウィンドウを先に確定させてから`center()`できるため、そちらを使う。
- ウィンドウは`isReleasedWhenClosed = false`で使い回すため、生成時のfitting sizeのまま固定される。言語によってラベル幅が変わる（多言語対応後）ので、`show()`のたびと言語切替のたびに`resizeToFitContent()`でウィンドウ幅をコンテンツに合わせ直している。言語切替の購読では`DispatchQueue.main.async`で1 runloop待ってから測っている。`LocalizationManager.language`は`@Published`で`willSet`のタイミングで通知されるため、待たずに測るとSwiftUIがまだ新しい言語で再描画する前の（古い）サイズを拾ってしまう。

## 文言は必ず`LocalizationManager`経由で取得する

アプリ内言語切替（設定画面の「言語」ピッカー）に対応する文言は、`NSLocalizedString`や`Text("key")`（`LocalizedStringKey`）、`String(localized:)`を直接使わず、`LocalizationManager.shared.string(_:)`（各Viewでは`@ObservedObject private var l10n = LocalizationManager.shared`ごしに`l10n.string(_:)`）を必ず経由すること。

- `LocalizationManager`はユーザーが選んだ言語のBundleを自前で解決しており、`NSLocalizedString`等のSwiftUI/Foundation標準の仕組みはOSの言語設定しか見ない。直接呼ぶと、システム言語と異なる言語を選んでいるときにその箇所だけ翻訳されずOS言語のまま表示される
- `Text("Claude Meters")`や`Text("–")`のような、そもそも翻訳不要な文字列リテラルは対象外
- 文言を表示するViewは`LocalizationManager.shared`を`@ObservedObject`で監視すること（`PopoverView`・`SettingsView`・`MenuBarMetersView`・`UsageRingView`を参照）。監視していないと、`l10n.string()`を使っていても言語切替時にViewが再描画されない
- 日付・相対時刻など`Locale`を扱うAPI（`RelativeDateTimeFormatter`、`Date.FormatStyle`等）は`LocalizationManager.shared.locale`（言語だけ差し替え、地域コードは引き継いだLocale、システム追従時は`nil`）を明示的に渡すこと。渡さないと`Locale.current`（システム言語）で書式化される。ただし引き継がれるのは地域コードの既定値のみで、「24時間表示」のようにシステム環境設定で個別に上書きした項目までは反映されない
- `LocalizationManager.$language`をCombineで購読するときは、クロージャが受け取った新しい値を使うこと。`@Published`は値が実際に書き換わる前（`willSet`）に新しい値を流すため、購読先で`LocalizationManager.shared.language`を読み直すと1回古い値を参照してしまう（`string(_:for:)`に新しい値を渡すこと）

## バージョン番号と「更新を確認」

設定画面の「更新を確認」（`UpdateChecker`）は、.appのバージョンとGitHub Releasesの最新タグを数値で比較する。

- バージョンの唯一の正は`project.yml`の`MARKETING_VERSION`（`CFBundleShortVersionString`になる）。リリース時にそのバージョンへ更新し、`xcodegen generate`してからarchiveする。`Distribution/build-dmg.sh <version>`は.appのバージョンと引数が違うと失敗する。ここが食い違ったまま公開すると、最新版を入れた人にも「更新あり」と出続ける。v0.1.7以前は`0.1`固定のまま配布されており、この仕組みはv0.1.8以降
- 採番は0.1.9の次を0.2.0とする（0.1.10にはしない）
- タグは`v`＋数値のドット区切り（`v0.1.8`）のみ。`-beta`のようなサフィックスは形式エラー（更新確認の失敗）として扱う。`AppVersion`は`0.1`と`0.1.0`を同一視する
- 「ダウンロード」ボタンはAPIレスポンスのURLではなく固定URL（`UpdateChecker.releasesPageURL`）を開く。通知のみで、自動ダウンロード・インストールはしない
- 結果の文言幅で設定ウィンドウの幅が変わるため、`SettingsWindowController`が`UpdateChecker.state`の変化でも`resizeToFitContent()`を呼んでいる。言語切替の購読と同様、`$state`は反映前に通知されるので1 runloop待ってから測っている

## App Sandboxはv1では無効（意図的）

Claude CodeのKeychain項目への他アプリからのアクセスと非互換になる可能性が高いため。Mac App Store配布はv1対象外。

## 配布ビルドの作り方

`xcodebuild build`ではなく、必ず`archive` → `-exportArchive`を使う。`build`のままだと`get-task-allow`権限が付与され、secure timestampも付かず、Apple公証（notarization）が失敗する（実際に一度失敗した）。

配布物はZIPではなくDMGにしている。ZIPだとFinderでダブルクリックした際にダウンロードフォルダ内でそのまま起動できてしまい、Applicationsフォルダへの移動を促す一般的なUIが出ないため。DMG化には`create-dmg`（Homebrew、`brew install create-dmg`で導入済み）を使い、`Distribution/build-dmg.sh`でウィンドウレイアウト・Applicationsへのシンボリックリンク配置・公証・stapleまでを一括で行う。

```sh
xcodebuild archive -project ClaudeMeters.xcodeproj -scheme ClaudeMeters -configuration Release -archivePath dist/ClaudeMeters.xcarchive
xcodebuild -exportArchive -archivePath dist/ClaudeMeters.xcarchive -exportPath dist/export -exportOptionsPlist Distribution/ExportOptions.plist
Distribution/build-dmg.sh <version>   # 例: Distribution/build-dmg.sh 0.1.2
```

`build-dmg.sh`は内部で`create-dmg --notarize claude-meters-notary`を使っており、DMG作成・Apple公証（notarization）・stapleまでを1コマンドで行う（`notarytool submit`・`stapler staple`を個別に叩く必要はない）。完了後、`dist/export`・`dist/ClaudeMeters.xcarchive`内の`.app`をLaunch Servicesから登録解除してディレクトリごと削除するところまでスクリプトが行う。これらの`.app`は登録解除しないと`/Applications`の本体と別アプリとしてSpotlight/Launchpadに重複表示され続けるため（過去に複数回発生）。

- 署名: Developer ID Application: Masashi Yasaka (3L2FPFG722)
- notarytoolの認証情報はKeychainに`claude-meters-notary`というプロファイル名で保存済み（Apple IDパスワードの再入力は不要）
- 署名証明書・notary認証情報はどちらもMac本体のキーチェーンに紐づくローカル情報で、iCloud Keychain等では自動同期されない。新しいMacで配布ビルドする場合は、証明書の`.p12`インポートまたはdeveloper.apple.comでの再発行と、`xcrun notarytool store-credentials "claude-meters-notary" --apple-id <Apple ID> --team-id 3L2FPFG722 --password <アプリ用パスワード>`によるnotary認証情報の再登録が別途必要（2026-09-28、Mac移行時に未設定で発覚）
