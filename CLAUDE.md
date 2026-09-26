# CLAUDE.md

Claude Metersのプロジェクト固有の重要事項。詳細な経緯・調査結果は[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)を参照。

## Xcodeプロジェクトは生成物

`ClaudeMeters.xcodeproj`は`project.yml`から[XcodeGen](https://github.com/yonaskolb/XcodeGen)で生成している。`project.pbxproj`を直接編集しない。変更する場合は`project.yml`を編集し、`xcodegen generate`で再生成する。

## Usage取得の仕組み（変更前に必読）

`ClaudeUsageProvider`は、公式ドキュメント化されたstatusLineの`rate_limits`フィールドではなく、Claude Codeが保持するOAuthトークン（Keychainの`Claude Code-credentials`）を読み、Anthropicの非公開API（`/api/oauth/usage`）を直接叩いてSession/Weekly使用率を取得している。

- statusLine経由にしなかった理由：VS Code拡張版Claude Codeは`statusLine`フック自体を未サポート（ターミナル版のみ対応）。ターミナル版でも`rate_limits`が入らないバグが報告されている。詳細はREQUIREMENTS.mdの「開発前提・技術検証」参照
- `resets_at`（リセット日時）はAPIが返す値をそのまま使う。固定曜日かローリング7日かをアプリ側で計算・推測しない
- Keychainの値は`{"claudeAiOauth":{"accessToken": ...}}`というJSON構造。生の文字列をそのままBearerトークンにはできない
- `ClaudeUsageProvider.parseMeter`は`utilization`と`resets_at`の両方が揃わない限り`nil`を返し、呼び出し元は`fetchUsage()`全体を失敗させる。未ドキュメントAPIの形式変更を「取得成功だが値が空」ではなく明確な失敗として検知するための意図的な設計
- Keychainアクセス許可ダイアログは、Claude Code側がトークン更新時にKeychain項目を作り直している（と考えられる）ため、署名が同一でも数十分〜1時間程度の間隔で再表示される。アプリ側で回避する方法はない（バグではない）

## UsageViewModelの更新ループを単純化しない

`restartLoop()`の`currentGeneration`カウンタと`await previousTask?.value`は冗長に見えるが必須。`fetchUsage()`内のKeychainアクセスは同期処理でOSの許可ダイアログ待ちになることがあり、`Task.cancel()`では中断できない。世代チェックと「前のTaskの終了を待ってから次を開始する」処理の両方を外すと、古い取得処理と新しい取得処理が並行実行されたり、古い結果が新しい状態を上書きするレースコンディションが再発する（過去に複数回レビューで指摘・修正された箇所）。

## メニューバー表示がImageRenderer経由である理由

`MenuBarMetersView`は`MenuBarExtra`の`label`に直接SwiftUIのHStack/Shapeを渡していない。実際に試したところ、複数リングのうち1つしか描画されない・Circleのストロークが消えるという不具合が発生したため、`ImageRenderer`で一度`NSImage`に焼き込んでから渡している。

- この画像は`isTemplate = true`にしており、macOSがメニューバーの明暗に応じて自動で色を付ける（他の標準アイコンと同じ挙動）。テンプレート画像はアルファ値しか使えないため、`MenuBarRingGlyph`（`MenuBarMetersView.swift`内のprivate struct）は使用率の表現に`Color.accentColor`ではなく黒＋不透明度を使っている
- Popover側の`UsageRingView`はテンプレート画像化していないので通常通りaccentColorを使用。2つの見た目が違う実装なのは意図的で、統合すべきではない

## macOS 13が最低対応OS

`MenuBarExtra`と`SMAppService`（ログイン時起動）がmacOS 13以降必須のため。`SettingsLink`と`onChange(of:initial:_:)`の2引数版はmacOS 14以降限定なので使用不可（`PopoverView`・`SettingsView`で旧APIに置き換え済み）。新しいAPIを使う際はデプロイメントターゲットに注意する。

## App Sandboxはv1では無効（意図的）

Claude CodeのKeychain項目への他アプリからのアクセスと非互換になる可能性が高いため。Mac App Store配布はv1対象外。

## 配布ビルドの作り方

`xcodebuild build`ではなく、必ず`archive` → `-exportArchive`を使う。`build`のままだと`get-task-allow`権限が付与され、secure timestampも付かず、Apple公証（notarization）が失敗する（実際に一度失敗した）。

```sh
xcodebuild archive -project ClaudeMeters.xcodeproj -scheme ClaudeMeters -configuration Release -archivePath dist/ClaudeMeters.xcarchive
xcodebuild -exportArchive -archivePath dist/ClaudeMeters.xcarchive -exportPath dist/export -exportOptionsPlist Distribution/ExportOptions.plist
xcrun notarytool submit dist/ClaudeMeters-*.zip --keychain-profile "claude-meters-notary" --wait
xcrun stapler staple "dist/export/Claude Meters.app"
```

- 署名: Developer ID Application: Masashi Yasaka (3L2FPFG722)
- notarytoolの認証情報はKeychainに`claude-meters-notary`というプロファイル名で保存済み（Apple IDパスワードの再入力は不要）
