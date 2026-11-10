# 4D Quick Look

[English](README.md) | 日本語

Finder で 4D 独自形式のファイルを Quick Look プレビューするための拡張機能です。
ファイルを選択してスペースキーを押すと、汎用アイコンではなくファイルの中身が表示されます。

| ファイル | プレビューの内容 |
|---|---|
| `.4DD` データファイル | レコード数順のテーブル一覧（上位 8 件、残りは「Other」にまとめて表示）、フィールド型、ストラクチャと一致する必要のあるデータベース UUID、並べ替え・検索言語とワイルドカード規則、インデックスエンジンのバージョン、ジャーナルファイルのパス、ストレージ使用量、正常に閉じられたか修復が必要か、[暗号化されたデータファイル](https://developer.4d.com/docs/commands/encrypt-data-file)の場合はどのテーブルが暗号化されているか |
| `.4DB` バイナリストラクチャ | フィールド数順のテーブル一覧、フィールド型、リレーション数、データベース UUID、並べ替え・検索設定、ジャーナル |
| `.4DCatalog` XML カタログ | テーブル・フィールド型・主キー・非表示フィールド・リレーションを図で表示。件数、データベース UUID、並べ替え・検索言語、スキーマ、暗号化可能テーブルは「Catalog details」に格納 |
| `.4DSettings` 設定ファイル | インデントと改行を保持したシンタックスハイライト付き XML ソース |
| `.4si` 読み込み・書き出し設定 | 保存された読み込み・書き出し順のフィールド、読みやすいフィールド型、テーブルと形式の設定、テキストその他のオプションを表形式で表示 |
| `.4DProject` プロジェクトファイル | インデントと改行を保持したシンタックスハイライト付き JSON ソース |
| `.4df` 保存されたクエリ | テーブル・フィールド番号、比較演算子、AND/OR/EXCEPT の接続子、保存された値、セレクションの出力先を条件カードで表示。元の JSON は下に折りたたみ表示 |
| `.4dm` メソッド・クラスのソース | 行番号、行数、ファイルサイズ付きのシンタックスハイライトされた UTF-8 ソース |

ヘッダーブロックしか読まないため、220 MB のデータファイルでも約 30 ms でプレビューできます。

読み込み・書き出し設定のプレビューは、フィールドの順序（フィールド番号とは異なる場合があります）を保持し、
欠けている値は明示的に表示し、未知のフィールド型や追加オプションもそのまま残します。
XML は 4 MiB、20,000 要素、ネスト 32 階層までに制限されています。
不正な XML やカスタムエンティティは拒否され、外部エンティティは読み込まれません。
XML 宣言の前にある ASCII の空白は許容されます。書式に関する警告はプレビューではなく JSON 出力に残ります。
プレビューに表示されるのはフィールド 500 件、オプション行 500 件までで、省略された件数は明示されます。
JSON 出力には解析した設定がすべて含まれます。

メソッドのプレビューはプロセス内の正規表現レキサーを使用します。4D 本体、tool4d、
LSP サーバー、JavaScript、ネットワークアクセスはいずれも不要です。ハイライト対象は
コメント、属性ヘッダー、文字列、数値、日付・時間リテラル、キーワード、
変数、テーブル・フィールド参照、トークン化されたコマンド（`:C…`）と定数
（`:K…:…`）、呼び出し名です。トークン化されていないコマンドは経験則でハイライトされます。
意味解析や構文チェックではありません。トークンの分類は
[miyako/language-4dm-zed](https://github.com/miyako/language-4dm-zed)
とその [tree-sitter 文法](https://github.com/miyako/tree-sitter-fourd) を参考にしています。
プレビューは最大 256 KiB を読み込み、最大 1,000 行を表示します。切り詰めた場合は
（CLI の `--thorough` モードでも）その旨が表示されます。UTF-8 BOM と
Windows・クラシック Mac の改行コードに対応しています。不正な UTF-8 は報告されます。

### 表示されるもの、されないもの

保存されたクエリのプレビューは、バージョン 3 の UTF-8 JSON（BOM 付きを含む）を
4 MiB まで解析します。条件カードは最大 200 件まで表示されます。元の JSON と CLI の
JSON 出力には、未知の入力を含むすべての行とプロパティが残ります。
単独の `.4df` ファイルにはテーブル名・フィールド名や型が含まれていません。
そのため、型に依存する条件コードはフィールド型を推測せずに候補を並べて表示し、
未知のコードは保存された番号のまま表示します。
値は保存されたとおりに表示され、4D のフォーミュラとして実行・解釈されることはありません。
「Original JSON」の折りたたみ部分に添えられるのはバージョン番号だけです。その他の
メタデータは説明的な脚注ではなく JSON の中で確認できます。
他のバージョンの場合は注意書きと元の JSON を表示し、旧形式のバイナリクエリや
不正な JSON はエラーとして報告されます。

Quick Look の表示領域は限られているため、プレビューはユーザーや開発者にとって重要な情報を先頭に置き、
各ブロックは固定サイズになっています。テーブルが 500 あるファイルでも 5 つしかないファイルでも、
サマリーが占める領域は同じです（詳細はバーにマウスを重ねると表示されます）。

カタログのプレビューは図を先頭に表示し、サマリーチャートやリレーション一覧は表示しません。
メタデータは折りたたまれた **Catalog details** の中で確認できます。
カタログの図はスクリプトやネットワークリクエストを含まない自己完結した SVG です。
可能であればストラクチャエディターに保存された位置を再利用し、それ以外の場合は
決定的なレイアウトにフォールバックします。図の中はスクロールでき、名前や
接続線にマウスを重ねると詳細が表示されます。テーブル名は中央揃えです。図をすっきり保つため、
リレーション名は接続線のツールチップにのみ表示されます。
主キーのフィールド名には下線、インデックス付きフィールド名は太字、
非表示の名前は斜体で表示されます。複数のフラグがある場合はこれらのスタイルが組み合わされます。
プレビューに表示されるのはテーブル 24 件、テーブルごとにフィールド 8 件
（主キーと結合に使われるフィールドを優先）、リレーション 64 件までです。テーブルごとの
フィールドの省略はカード上に表示されます。省略の合計と凡例は、図の上ではなく
図のツールチップ・アクセシビリティ説明に含まれます。
JSON 出力には解析したテーブル、フィールド、リレーションがすべて含まれます。XML カタログは
32 MiB、200,000 要素、ネスト 128 階層までに制限されています。不正な XML や
カスタムエンティティ宣言は拒否されます。4D 標準の外部 DOCTYPE は、
DTD を読み込まずに受け付けます。

* **表示されるもの:** 中身（テーブル、レコード、フィールド）、ファイルが期待どおりに開き
  動作するかを左右する情報（データベース UUID、言語、`@` ワイルドカード規則、
  インデックスエンジンのマーカー、ジャーナル、暗号化）、そして若干の参考情報
  （フォーマットのバージョン、ストレージ、バイトオーダー）。
* **日本語の照合オプション**（ICU、二次・四次の比較強度、ひらがな優先など）は、
  それが適用される唯一のケースである「ICU を使わない日本語」の場合にのみ表示されます。
* **表示されないもの:** エンジン内部の情報（ブロックサイズ、フラッシュやヘッダーのカウンター、
  LCID、シーケンス数、フィールドごとの一覧）。これらは `fourdql --json` で確認できます。

## 構成

```
Sources/
  FourDFileKit/          analyzer layer: bytes -> typed Codable model (no UI)
    Core/                ByteSource (pread), BinaryReader (bounds-checked),
                         FileAnalyzer protocol, AnalyzerRegistry
    DB4D/                the shared .4DD/.4DB container format
    Catalog/             .4DCatalog XML definitions and relation references
    Text/                XML .4DSettings / JSON .4DProject source text,
                         structured .4si import/export settings
    Query/               JSON .4df saved query conditions and metadata
    Method/              bounded UTF-8 .4dm reader and regex lexer
  FourDRender/           rendering layer: model -> Report -> HTML
    Report.swift         generic page model (stats, badges, tables, bars, disclosures)
    *Presenter.swift     one presenter per model kind
    HTMLRenderer.swift   the only place that knows about HTML/CSS
    PreviewPipeline.swift
  FourDQuickLookExtension/  data-based QLPreviewProvider (returns HTML)
  FourDQuickLookHost/    minimal host app (extensions must live inside an app)
  fourdql/               CLI using the same pipeline
Support/                 Info.plist templates, entitlements
scripts/build.sh         builds and signs "4D Quick Look.app"
```

各レイヤーが接するのは次の 2 か所だけです。

* **アナライザー → プレゼンター**: `kind` 文字列（例: `db4d.data`）を持つ `AnalysisModel`。
* **プレゼンター → レンダラー**: `Report`。

つまり、表示を改善するには `HTMLRenderer`（すべてのファイルに効く）または
プレゼンター（1 つのファイル系統に効く）を編集すればよく、パーサーの修正がこれらに及ぶことはありません。

## ファイル形式の追加

1. `FourDFileKit` に、独自の `AnalysisModel` を返す `FileAnalyzer` を書きます。
   扱う UTI を列挙します（4D.app は多数の UTI を宣言しています: `com.4d.4d.catalog`、
   `com.4d.4d.method`、`com.4d.4d.form`、`com.4d.4d.journalFile`、
   `com.4d.4d.index-data` など）。
2. それを `AnalyzerRegistry.default` に登録します。
3. `FourDRender` に `ReportPresenter` を書き、`PresenterRegistry.default` に登録します。

拡張機能の Info.plist の `QLSupportedContentTypes` はビルド時にレジストリから
生成される（`fourdql --content-types`）ため、手動で同期させる一覧はありません。

## インストール

[Releases](https://github.com/miyako/4d-ql/releases) から `.dmg` をダウンロードし、
**4D Quick Look** をアプリケーションフォルダにドラッグして、macOS がプレビュー拡張機能を
登録するように一度起動してください。アプリは Developer ID で署名され、公証済みです。
Finder に古いプレビューが表示される場合は `qlmanage -r` を実行してください。

## ソースからのビルド

```bash
scripts/build.sh --register
```

ユニバーサル（arm64 + x86_64）のリリースビルドを作成し、アドホック署名して、
Launch Services と Quick Look に登録します。常用するには
`build/4D Quick Look.app` を `/Applications` にコピーして一度起動してください。
Finder に古いプレビューが表示される場合は `qlmanage -r` を実行してください。

ローカルで Developer ID 署名するには次のようにします（Hardened Runtime と
セキュアタイムスタンプは自動的に付与されます）。

```bash
SIGN_IDENTITY="Developer ID Application: …" scripts/build.sh
```

## リリース

リリースは GitHub がホストする macOS ランナーでビルドされます。

* `.github/workflows/ci.yml` は、プッシュとプルリクエストのたびにテストとアドホックビルドを実行します。
* `.github/workflows/release.yml` は `vX.Y.Z` タグで実行されます。テストを行い、
  タグのバージョンでビルドし、Developer ID で署名、アプリを公証してステープルし、
  `4D-QuickLook-X.Y.Z.dmg` と `.zip` を公開します。リリースするには:

  ```bash
  git tag v0.2.0 && git push origin v0.2.0
  ```

  既存のタグを再ビルドするには: `gh workflow run release.yml -f tag=v0.2.0`

リポジトリシークレットが 6 つ必要です: `APPLE_DEVELOPER_ID_CERTIFICATE`（base64 化した
.p12）、`APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`、`KEYCHAIN_PASSWORD`、
`NOTARYTOOL_APPLE_ID`、`NOTARYTOOL_TEAM_ID`、`NOTARYTOOL_PASSWORD`。

## 開発

```bash
swift build && .build/debug/fourdql file.4DD            # テキストのサマリー
.build/debug/fourdql --json file.4DD                    # アナライザーの出力
.build/debug/fourdql --html file.4DD > preview.html     # Quick Look の表示そのもの
.build/debug/fourdql --html catalog.4DCatalog > catalog.html
FOURD_SAMPLES=/path/to/samples swift test               # すべてのサンプルをパイプラインに通す
scripts/make-fixtures.sh                                # テストフィクスチャの再生成（tool4d が必要）
```

`Tests/FourDFileKitTests/Fixtures` のテストフィクスチャ（暗号化可能テーブルを持つデータファイルの、
`Encrypt data file` 実行前と実行後）は、`Tests/Fixtures/encfixture` の小さなプロジェクトから
`scripts/make-fixtures.sh` で作成されます。

## ファイル形式に関するメモ

コンテナ形式は
[miyako/DataAnalyzer](https://github.com/miyako/DataAnalyzer)（JPR による 2015 年の
テクニカルノートに基づく）に由来し、実際のファイルで検証しています。オフセットは、それを読む
コードの横にソースコード内で記述されています（`DB4DHeader.swift`、`DB4DContainer.swift`、
`DB4DCatalog.swift`）。知っておくべき点:

* `.4DB` は `.4DD` と同じコンテナを使用します。ユーザーテーブルはどちらでも TDEF
  ブロックで定義されます。`.4DB` 自身のストレージには 2 つのシステムテーブル
  （リソース用の `Res_DB4D_000000` とスキーマ用の `sch_DB4D_000000`）があります。
* データファイルにはテーブルの過去の定義がすべて残っています。最後に書き込まれたものが
  現在の定義で、これはテストの `catalog.4DCatalog` と一致します。
* フィールド型コードはカタログの `type` 属性です。型 10 は、文字数制限が設定されていれば
  文字（Alpha）、そうでなければテキストです。
* ヘッダーの言語（dialect）フィールドは Windows の LCID です（1041 = 日本語、1036 = フランス語）。
* ヘッダーのデータベース UUID は、ストラクチャファイルとそのデータファイルで同一です。
* 追加プロパティ（xDAT）はシリアライズされた値の集合です。`ValueBag.swift` のデコーダーは
  リバースエンジニアリングによるもので、認識できないものに出会うと安全に停止します。
* 暗号化（`Encrypt data file`、v17 R5 以降）は、暗号化可能に設定されたテーブル
  （テーブル定義の +202 バイト目）のレコードと BLOB にのみ適用されます。それらのブロックは
  平文のヘッダーを保持しますがタグが変わり（`rec1` → `recx`、`blob` → `blbx`）、
  プレビューは各テーブルの最初のレコードから実際の状態を読み取ります。テーブル定義、
  レコード数、ヘッダーは暗号化されません。暗号化されたファイルには
  `encryptedProofB64` 追加プロパティ（キーチェック値）も加わります。
  データキーが必要になることはなく、入力を求められることもありません。

リレーション（`[Table_1]Field_4 → [Table_2]ID`）はデコードされ、`.4DB` 内の
リソースタイプも数えられます（`fourdql --json --thorough`）が、プレビューには
どちらも表示されません。

未デコードの項目: 件数以外のインデックス定義、レコードの中身、
ほとんどのリソースタイプの意味。

カタログ XML の規約と図の表示は
[miyako/4d-catalog-diagram](https://github.com/miyako/4d-catalog-diagram) と
[miyako/4d-utility-structure-to-svg-converter-v2](https://github.com/miyako/4d-utility-structure-to-svg-converter-v2)
を参考にしています。
リレーションの端点と主キーは、まず UUID で、次に曖昧さのない名前で解決されます。
未知のフィールド型は `Type n` と表示され、未知の XML 要素は無視され、
解決できない参照はパーサーのメモに報告されます。カタログの `encryptable` フラグは
ストラクチャの設定を表すもので、特定のデータファイルの暗号化状態を表すものではありません。

## ライセンス

MIT。[LICENSE](LICENSE) を参照してください。
