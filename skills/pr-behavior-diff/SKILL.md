---
name: pr-behavior-diff
description: PRや差分を読み、変更前と変更後で動作がどう変わるかを、Mermaid図つきのHTMLページで簡潔に説明する。PR URL・ブランチ・貼り付けた差分のどれでも使える。
---

# PR動作変更の解説(図解つきHTML)

PRの差分を読み、「変更前はこう動いていた → 変更後はこう動く」という観点で、動作の違いを短くわかりやすく説明する。結果は **Mermaid図を埋め込んだ1枚のHTMLページ** にまとめ、処理の流れや構造が変わる部分は変更前と変更後の図を左右に並べて見せる。コードレビュー(バグ探し)ではなく、**何が変わるのかを理解させること**が目的。

## 1. 差分を取得する

入力に応じて次のどれかで差分を手に入れる。

- **GitHub PR URL / 番号**:`gh pr view <番号> --json number,title,body,headRefName,baseRefName,files` と `gh pr diff <番号>` で取得する。
- **ブランチ指定**:`git diff <base>...<head>` で取得する(baseが不明なら main / master を使う)。
- **貼り付けられた差分**:そのまま使う。

PRの説明文やリンクされたIssueがあれば読み、意図を把握する。ただし説明文ではなく**実際のコード**を根拠にする。

## 2. 変更を分類する

変更点を次の3つに分ける。

1. **動作が変わる変更**:入力・出力・副作用・エラー時の挙動・UI表示・API仕様・設定のデフォルト値などが変わるもの。
2. **動作が変わらない変更**:リファクタ、リネーム、型の追加、コメント、フォーマット、テストのみの変更。
3. **判断できない変更**:差分だけでは影響がわからないもの。

動作が変わる変更については、変更されたコードの呼び出し元や関連するコードも必要な範囲で読み、実際にどこで影響が出るかを確かめる。差分の周辺だけで判断しない。図を描く前提として、変更前後それぞれの処理の流れを実際のコードから追っておく。

## 3. 図を選ぶ

動作の変更ごとに、図が理解を助けるかを判断する。文章1〜2行で伝わる変更(デフォルト値の変更、文言の修正など)には図を描かない。

| 変更の種類 | 使う図 | Mermaid |
|---|---|---|
| 分岐・条件・処理順序が変わる | フローチャート | `flowchart TD` |
| API・サービス・DB間の呼び出しが変わる | シーケンス図 | `sequenceDiagram` |
| ステータスや状態遷移が変わる | 状態遷移図 | `stateDiagram-v2` |
| モジュール構成・依存関係が変わる | 構成図 | `flowchart LR` |
| テーブル・カラム・リレーションが変わる | ER図 | `erDiagram` |

PR全体の概要図(どのコンポーネントに手が入ったか)は、変更が3つ以上のモジュールにまたがる場合だけ、「動作の変更」の前に1枚描く。

## 4. 図の描き方

- **変更前と変更後は別々の図にし、同じ向き・同じノード名・同じ並び順で描く**。読み手が2つを見比べて差分を見つけられるようにする。
- 変更後の図では、**追加・変更されたノードを色で強調**する。削除されたものは変更前の図で強調する。

  ```
  classDef added fill:#d4f8d4,stroke:#2e7d32,color:#000
  classDef changed fill:#fff3c4,stroke:#b8860b,color:#000
  classDef removed fill:#fde0e0,stroke:#c62828,color:#000,stroke-dasharray:4 3
  ```
- 図の下に凡例「🟩 追加 / 🟨 変更 / 🟥 削除」を置く(使った色だけでよい)。
- 1つの図はノード15個程度まで。関係ない処理は省略し、変更箇所とその前後だけを描く。
- ノードのラベルはコード上の名前ではなく**何をするか**を書く(例:`validateInput()` ではなく「入力チェック」)。関数名が必要なら `<br>` で改行して添える。
- Mermaidの構文エラーを避けるため、次を守る:
  - 日本語・記号・括弧を含むラベルは必ず `"..."` で囲む(例:`A["入力チェック<br>validateInput()"]`)。
  - ノードIDは英数字のみにし、`end`・`graph` などの予約語を使わない。
  - シーケンス図の参加者名に空白や記号があれば `participant API as "Order API"` のように別名を使う。
  - HTMLの中に書くので、ラベル内の `<` `>` `&` は `&lt;` `&gt;` `&amp;` にする(改行用の `<br>` と矢印 `-->` はそのままでよい)。
- 図の中の推測部分は点線(`-.->`)で描き、ラベルに「(推測)」と付ける。
- 図だけで終わらせない。各図の下に、何が変わったかを1〜2文で言葉でも説明する。

## 5. HTMLページを作る

下の「HTMLテンプレート」をそのまま土台にして、1つのHTMLファイルを書く。

- `<title>` は「PR #<番号> 動作変更」(番号がなければブランチ名)。ヘッダーの `.meta` にPR番号とブランチ、`<h1>` にPRの内容を一言で。
- `.summary` に概要を1〜3文で。
- 動作の変更1件につき `<article class="change">` を1つ。重要なものから順に並べる。
  - `.ba` の変更前 / 変更後は**外から観測できる動作**で書く。
  - `.where` に該当箇所(`path/to/file:行`)。
  - 図があるときだけ `.diagrams` と `.legend` を入れる。図が1枚(概要図や、変更後にだけ存在する処理など)のときは `.diagrams` の中に `<figure>` を1つだけ置く。
- 「動作が変わらない変更」「影響範囲」「注意点」は箇条書き。該当なしの節は削る。
- スタイルやスクリプトはテンプレートのまま変えない。Mermaidは `cdn.jsdelivr.net` の `mermaid@11.4.1` を読み込む(バージョンを省略しない)。ライト / ダークモードと狭い画面にはテンプレート側で対応済み。

## 6. 届ける

1. **Artifactツールが使える環境なら**、HTMLファイルをアーティファクトとして公開する(アイコンは `code`)。
2. **使えない環境(Claude Code など)なら**、リポジトリ直下の `.pr-explanations/pr-<番号またはブランチ名>.html` に保存し、macOSなら `open <パス>` でブラウザに開く。`.pr-explanations/` が `.gitignore` に入っていなければ、追加してよいかユーザーに一言確認する。PhpStormで見る場合は、ファイルを右クリック →「Open In → Browser」でも開ける。
3. チャットには長い解説を書かない。概要1〜2文、動作の変更の見出し一覧、ページの場所(アーティファクトならリンク、ファイルならパス)だけを返す。

## 書き方のルール

- 「変更前 / 変更後」はコードの書き換え内容を言い直さず、**外から見える動作**で書く(例:「空文字を渡すとエラーになる → 空文字は無視される」)。
- 具体例があるとわかりやすい場合は、入力と結果の例を1つ添える。
- 根拠が確かでない内容は「(推測)」と明記する。推測を事実のように書かない。
- バグや改善点に気づいた場合は、「注意点」に1行で触れる程度にとどめる。主目的は解説。
- 大きなPR(変更ファイルが多い場合)は、まず機能単位にグループ化してから各グループを説明する。
- 文章はユーザーの言語で書く(既定は日本語)。

## HTMLテンプレート

以下は記入例つきのテンプレート。中身(ヘッダー、概要、各 `article`、各節の箇条書き)だけを差し替える。

```html
<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PR #123 動作変更</title>
<style>
  :root {
    --bg: #f7f7f5; --surface: #ffffff; --text: #1f2328; --muted: #656d76;
    --border: #d8dee4; --accent: #0b6bcb;
    --before: #8a6d3b; --after: #1a7f37;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg: #15171a; --surface: #1d2024; --text: #e6e8eb; --muted: #9aa3ad;
      --border: #32373d; --accent: #58a6ff; --before: #d4a64a; --after: #4cc06a;
    }
  }
  :root[data-theme="dark"] {
    --bg: #15171a; --surface: #1d2024; --text: #e6e8eb; --muted: #9aa3ad;
    --border: #32373d; --accent: #58a6ff; --before: #d4a64a; --after: #4cc06a;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
    font: 15px/1.7 -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Noto Sans JP", "Yu Gothic UI", sans-serif; }
  main { max-width: 1080px; margin: 0 auto; padding: 32px 16px 64px; }
  header .meta { color: var(--muted); font-size: 13px; }
  h1 { font-size: 24px; line-height: 1.4; margin: 4px 0 12px; }
  h2 { font-size: 18px; margin: 40px 0 12px; padding-bottom: 6px; border-bottom: 1px solid var(--border); }
  h3 { font-size: 16px; margin: 0 0 8px; }
  a { color: var(--accent); }
  code { font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; background: color-mix(in srgb, var(--border) 45%, transparent); padding: 1px 5px; border-radius: 4px; }
  .summary { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 16px 20px; }
  .change { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 20px; margin-bottom: 20px; }
  .ba > *, .diagrams > * { min-width: 0; }
  code { overflow-wrap: anywhere; }
  .ba { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin: 12px 0; }
  .ba > div { border-left: 3px solid; padding: 4px 12px; }
  .ba .before { border-color: var(--before); }
  .ba .after { border-color: var(--after); }
  .label { font-size: 12px; font-weight: 600; letter-spacing: .04em; }
  .before .label { color: var(--before); }
  .after .label { color: var(--after); }
  .diagrams { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 12px; }
  figure { margin: 0; border: 1px solid var(--border); border-radius: 8px; padding: 12px; overflow-x: auto; background: var(--bg); }
  figcaption { font-size: 12px; font-weight: 600; margin-bottom: 8px; }
  .mermaid { display: flex; justify-content: center; }
  .mermaid svg { max-width: 100%; height: auto; }
  .legend { font-size: 13px; color: var(--muted); margin-top: 8px; }
  .where { font-size: 13px; color: var(--muted); }
  ul { padding-left: 1.3em; margin: 8px 0; }
  @media (max-width: 720px) { .ba, .diagrams { grid-template-columns: 1fr; } h1 { font-size: 20px; } }
</style>
</head>
<body>
<main>
  <header>
    <div class="meta">PR #123 · feature/upload-validation → main</div>
    <h1>図面アップロード時の入力エラーを400で返すように変更</h1>
  </header>

  <section class="summary">
    入力チェックで弾かれたリクエストが、500ではなく400とエラー詳細を返すようになります。あわせて、保存が完了すると通知が送られるようになります。
  </section>

  <h2>動作の変更</h2>

  <article class="change">
    <h3>1. 入力エラー時のレスポンスが変わる</h3>
    <div class="ba">
      <div class="before"><div class="label">変更前</div>不正な入力を送ると 500 エラーが返り、原因はわからない。</div>
      <div class="after"><div class="label">変更後</div>400 エラーと、どの項目が不正かを示すエラー詳細が返る。</div>
    </div>
    <div class="where">該当箇所:<code>app/Http/Controllers/DrawingController.php:42</code></div>
    <div class="diagrams">
      <figure><figcaption>変更前</figcaption>
<pre class="mermaid">
flowchart TD
  A["リクエスト受信"] --> B{"入力チェック"}
  B -- NG --> E["500エラーを返す"]
  B -- OK --> C["図面を保存"]
  C --> D["200を返す"]
  class E removed
  classDef removed fill:#fde0e0,stroke:#c62828,color:#000,stroke-dasharray:4 3
</pre>
      </figure>
      <figure><figcaption>変更後</figcaption>
<pre class="mermaid">
flowchart TD
  A["リクエスト受信"] --> B{"入力チェック"}
  B -- NG --> E["400エラーと<br>エラー詳細を返す"]
  B -- OK --> C["図面を保存"]
  C --> F["保存完了を通知"]
  F --> D["200を返す"]
  class E changed
  class F added
  classDef added fill:#d4f8d4,stroke:#2e7d32,color:#000
  classDef changed fill:#fff3c4,stroke:#b8860b,color:#000
</pre>
      </figure>
    </div>
    <div class="legend">🟩 追加 / 🟨 変更 / 🟥 削除</div>
    <p>入力NG時の分岐先が変わり、保存のあとに通知処理が1つ増えています。</p>
  </article>

  <h2>動作が変わらない変更</h2>
  <ul><li>リファクタ:バリデーションルールを <code>DrawingRequest</code> クラスに移動</li></ul>

  <h2>影響範囲</h2>
  <ul><li>図面アップロードAPIを呼ぶフロントエンド(エラー表示の処理)</li></ul>

  <h2>注意点</h2>
  <ul><li>500を前提にリトライしているクライアントがあれば挙動が変わる(推測)</li></ul>
</main>
<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs";
  const t = document.documentElement.dataset.theme;
  const dark = t ? t === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
  mermaid.initialize({ startOnLoad: false, theme: dark ? "dark" : "default", securityLevel: "strict",
    fontFamily: '-apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif' });
  await mermaid.run({ querySelector: ".mermaid" });
</script>
</body>
</html>
```
