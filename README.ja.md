<p align="center">
  <img src="docs/images/app-icon.png" alt="Claude Meters app icon" width="96">
</p>

<p align="center"><a href="README.md">English</a> | <b>日本語</b></p>

# Claude Meters

Claude Codeの **セッション（5時間）** と **週間** の使用率を、メニューバーの2つの円形メーターだけで確認できる、macOS用の小さなユーティリティです。

<p align="center">
  <img src="docs/images/menubar-demo.png" alt="Claude Meters メニューバー表示例（セッション11%、週間12%）" width="240">
</p>

> Two meters. That's it.

## 特徴

- メニューバーに2つの円形メーター（セッション5時間 / 週間）を使用率(%)で表示
- クリックするとPopoverで各メーターのリセットまでの時間を確認可能
- 自動更新（失敗時は指数バックオフ、スリープ復帰時は再取得）
- ログイン時起動、更新間隔の設定（2分 / 5分）、更新の確認
- システム言語に応じた日本語・英語対応
- VoiceOver対応
- ライトモード・ダークモード対応
- メニューバー常駐のみ（Dockアイコン・ウインドウなし）

## 動作環境

- macOS 13 (Ventura) 以降
- [Claude Code](https://claude.com/product/claude-code) がインストール・サインイン済みであること（Usage上限のあるPro/MaxプランまたはConsole課金）

## インストール

[Releases](../../releases) ページの **Assets** から `ClaudeMeters-v*-macOS.dmg`（例: `ClaudeMeters-v0.1.2-macOS.dmg`）をダウンロードしてください。「Source code (zip)」「Source code (tar.gz)」はソースコードなので不要です。

ダウンロードした`.dmg`ファイルを開き、表示されたウィンドウで `Claude Meters.app` を `Applications` フォルダにドラッグしてください。

v0.1.1以降のリリースはDeveloper ID証明書で署名し、Appleの公証（notarization）も済んでいるため、Gatekeeperの警告なく開けます。

## Usage情報の取得方法

Claude Meters自身は認証情報を要求・保存しません。代わりに、Claude Codeがすでに保存しているOAuthトークン（macOS Keychainの`Claude Code-credentials`）を読み取り、Claude Code自身が使っているのと同じUsage APIを呼び出します。v0.1.7以降は、Claude Code自身がこの項目の保存に使っている`/usr/bin/security`コマンド経由で読み取るため、通常はKeychainの許可ダイアログは表示されません。Claude Codeがトークンを更新した後も、再承認は不要です。キーチェーンがロックされている場合などにダイアログが表示されたときは、（ログインパスワードで）許可してください。

v0.1.6以前は、Claude Codeがトークンを更新するたびに「常に許可」の設定がリセットされ、1日に数回許可ダイアログが再表示されていました。該当する場合はv0.1.7以降に更新してください。

このAPIはAnthropicの**公開・ドキュメント化されたAPIではありません**。予告なく変更される可能性があります。調査の詳細、この方式を採用した理由、既知のリスク（レート制限・形式変更・Keychainアクセスの挙動）については[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)を参照してください。

## 開発

Xcodeプロジェクトは[XcodeGen](https://github.com/yonaskolb/XcodeGen)によって`project.yml`から生成しています（`.xcodeproj`を手動編集した状態ではコミットしていません）。

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project ClaudeMeters.xcodeproj -scheme ClaudeMeters build
```

テストの実行：

```sh
xcodebuild -project ClaudeMeters.xcodeproj -scheme ClaudeMeters -destination "platform=macOS" test
```

プロジェクト構成、要件、Keychain/Usage API方式に至る技術検証の詳細は[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)に記載しています。

## v1で実装しないもの

Usage履歴、グラフ、使用量予測、通知、複数アカウント、モデル別の内訳、Webダッシュボード、自動アップデート。詳細は[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)を参照してください。

## ライセンス

[MIT](LICENSE)
