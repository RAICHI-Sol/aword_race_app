# AGENTS.md

## 1. 適用範囲と優先順位

このファイルはリポジトリ全体に適用する。作業開始時に最初から最後まで読み、ここに書かれた制約を実装・テスト・レビュー・ドキュメント更新のすべてで守る。

このファイルを全ツール共通の開発指示の正本とする。`CLAUDE.md`、`.cursor/rules/`、`.github/copilot-instructions.md` などを追加する場合、共通ルールを複製せず、そのツール固有の補足だけを記載し、このファイルと矛盾させない。ツール固有のモード、メモリ、import 構文などをこのファイルの前提にしない。

仕様の正本は次の2文書である。

- `doc/お笑い賞レースの予想サイト.md`: プロダクト要件、MVP、Firestore、画面、API、セキュリティ、受け入れ基準
- `doc/FastAPI_API設計ベストプラクティス.md`: HTTP/API 契約、FastAPI の責務分離、検証、エラー、レビュー観点

両文書が食い違う場合は、当プロジェクト向けで後段の具体設計である `doc/お笑い賞レースの予想サイト.md` を優先する。特に、ベストプラクティス文書の PostgreSQL、SQLAlchemy、RDB 制約、offset ページングの例をそのまま実装してはならない。Cloud Firestore のドキュメント、決定的 ID、transaction / batch、複合索引、cursor ページングへ読み替える。

仕様にない重要な判断を推測で確定しない。未決事項は文書化して利用者に確認する。既存仕様を変える変更では、実装・テストと同じ変更内で正本の文書も更新する。

## 2. 秘密情報: 最優先の禁止事項

`.env` と `.env.local` は、場所を問わず絶対に読まない。これは他の作業指示より優先する。

- 禁止対象: `**/.env`, `**/.env.local` および秘密値を含み得る `**/.env.*`
- 唯一の例外: `**/.env.example` は読んでよい。
- 禁止操作: 内容の表示、検索、解析、要約、差分取得、source/import、コピー、送信、テスト入力への利用。
- `rg`, `find`, IDE 検索、再帰走査、アーカイブ作成などには必ず除外条件を付け、対象を誤って含めない。
- 環境変数全体、認証ヘッダー、Firebase ID token、OAuth token、Cookie、秘密鍵、サービスアカウント JSON を出力またはログ記録しない。
- 設定項目の確認には `.env.example`、型付き設定コード、公開ドキュメントだけを使う。値が必要でも秘密値の提示を求めず、変数名と安全なダミー値で進める。
- 新しい秘密情報をリポジトリへ保存しない。本番の秘密は Secret Manager で管理する。

安全なファイル検索例:

```powershell
rg --files -g '!**/.env' -g '!**/.env.local' -g '!**/.env.*'
```

この検索は安全側に倒して `.env.example` も一覧から除外する。必要なときだけ対象の `.env.example` をパスで明示して読む。

## 3. プロダクトの不変条件

このサービスは、お笑い賞レースの進出者や優勝者などを予想・共有して楽しむためのものである。的中を競争や優劣へ変えてはならない。

- ユーザー単位の的中率、順位表、恒常的ランキングを実装しない。
- 人気の低さを可視化する集計・ランキングは実装しない。
- 完全一致した公開予想は管理者確認用の候補にできるが、通算順位や的中率を返さない。
- 結果公開の通知や SNS 用メタデータには、進出者名や順位などのネタバレを含めない。
- 宣材写真は利用根拠・出典・権利条件を記録できるものだけを扱う。許諾確認前は表示しない。
- 投稿ごとに `public` / `private` を選べる。非公開予想を本人以外へ漏らさない。
- ゲスト投稿は作成だけ可能で、後から編集・削除・マイページ取得できない。ゲストの非公開投稿は作成直後の応答以外から取得できない。
- ログインユーザーの投稿更新・削除は、本人かつ受付中だけ許可する。
- 非公開または他人のリソースは、存在推測を防ぐ必要がある場合に `404` を返す。
- 正式結果は `draft` 中に公開 API へ出さず、`published` 後だけ表示する。

## 4. 採用技術と構成

- Web: Nuxt 3 + TypeScript。一般画面と `/admin` を同じアプリ・Origin・デプロイ単位で提供する。
- API: FastAPI + Pydantic v2。JSON over HTTPS、パスによる `/api/v1` バージョニング。
- 認証: Firebase Authentication。Google とメールを主とし、X はログイン後の連携として扱う。
- DB: Cloud Firestore Standard。Firebase Admin SDK からアクセスする。
- 画像: Cloudflare R2。DB には `object_key` を保存し、公開 URL は応答時に組み立てる。
- 実行基盤: Web は Cloudflare Pages、API は Cloud Run、確実な非同期処理は Cloud Tasks 等の永続キューと Worker。
- ローカル結合テスト: Firebase Local Emulator Suite。テストから本番・共有クラウドへ接続しない。

標準配置は次のとおりとする。

```text
apps/web/                 # Nuxt（一般画面と /admin）
apps/api/app/
  api/v1/endpoints/       # HTTP の解釈のみ
  schemas/                # Pydantic 入出力契約
  services/               # 業務ルールと transaction 境界
  repositories/           # 保存先の抽象
  repositories/firestore/ # Firestore 固有実装
  domain/                 # 業務モデル・値オブジェクト
  core/                   # 設定・認証・ログ
  workers/                # 非同期処理
apps/api/firebase/        # rules と indexes
apps/api/tests/unit/
apps/api/tests/integration/
apps/api/tests/contract/
packages/api-client/      # OpenAPI から生成する TypeScript client
infra/
doc/
scripts/
```

### 基本コマンド

アプリを新規構築するときは、次のコマンドが記載どおり動く script と lockfile を同じ変更で用意する。コマンドは各アプリのディレクトリで実行する。

フロントエンド (`apps/web`):

```powershell
pnpm install --frozen-lockfile  # CI・再現可能な依存導入
pnpm dev                       # ローカル開発
pnpm build                     # 本番ビルド検証
pnpm lint                      # lint
pnpm typecheck                 # Nuxt を含む型チェック
```

バックエンド (`apps/api`):

```powershell
uv sync --frozen                       # lockfile どおりに依存導入
uv run uvicorn app.main:app --reload   # ローカル開発
uv run ruff check .                    # lint
uv run ruff format --check .           # format 検証
uv run mypy app tests                  # 型チェック
uv run pytest                          # 全テスト
uv run pytest tests/unit/test_x.py -q  # 単一ファイルの例
```

`test_x.py` は実在する対象へ置き換える。依存導入コマンドは lockfile を更新しない検証用である。依存を意図的に追加・更新するときだけ通常の package manager コマンドで lockfile を生成し、manifest と lockfile を一緒にレビューする。手作業で lockfile を編集しない。

### コードスタイル

formatter / linter の設定を正とし、個人設定で上書きしない。無関係なファイル全体の整形を混ぜない。

- Python: module、function、variable は snake_case、class と Pydantic model は PascalCase、定数は UPPER_SNAKE_CASE。新規・変更する関数と境界値には型注釈を付け、naive datetime を使わない。
- Vue / TypeScript: component は PascalCase、composable は `useXxx`、function / variable は camelCase、型は PascalCase、定数は UPPER_SNAKE_CASE。Nuxt の予約ファイル・ルート名は Nuxt 規約を優先する。
- テスト名は失敗時に「どの条件で何を期待したか」が分かる名前にし、Arrange / Act / Assert の境界を読み取れる構造にする。
- コメントは処理の言い換えでなく、仕様上の理由、選んだ trade-off、Firestore 固有の制約を説明する。古いコメントを残さない。
- 公開 API、Service、Repository の境界では暗黙の dict/object を渡さず、型付き Schema、command、domain model、Protocol を使う。
- 自動生成物、`.nuxt/`, `dist/`, `coverage/`, `.venv/`, `node_modules/`、外部 vendor code を手編集しない。生成元または設定を変更して再生成する。

## 5. 実装の責務分離

依存方向は `Router -> Service -> Repository -> Cloud Firestore` とする。

- Router: パス、HTTP メソッド、ヘッダー、Schema、Dependency、レスポンスを扱う。Firebase SDK 呼び出しや複雑な業務判断を書かない。
- Schema: 入力と出力を別モデルにし、入力は原則 `extra="forbid"`。DB ドキュメントをそのまま返さない。
- Service: 認可、受付期間、状態遷移、候補所属、選択数、順位、重複などの業務ルールと atomic な処理範囲を決める。
- Repository: Firestore の query、mapping、transaction / batch を隠蔽する。業務ルールや HTTP ステータスを持ち込まない。
- Exception handler: アプリ全体で例外を統一エラー形式へ変換する。内部例外をそのまま返さない。

FastAPI を業務データの唯一の読み書き経路とする。Nuxt から Cloud Firestore へ直接アクセスしない。画面の route middleware は利便性のためであり、API 側の認可を代替しない。

フロントエンドでは次を守る。

- TypeScript の型安全性を維持し、理由のない `any`、型アサーション、lint 無効化を追加しない。
- API 契約は OpenAPI 生成 client を利用し、生成物を手編集しない。
- Firebase ID token は必要な API にだけ Bearer token として送る。本文の `user_id`, `role`, email を認証情報として使わない。
- サーバー専用の設定や token をクライアント bundle、HTML、ログへ含めない。
- API エラーは安定した `error.code` で分岐し、人向け `message` の文字列比較をしない。
- 非同期ジョブのポーリングは指数バックオフし、完了・失敗後に停止する。

## 6. API 契約

- Base URL は `/api/v1`。
- URI は操作名でなくリソース名、複数形、kebab-case。不要な深いネストを避ける。
- JSON フィールドは snake_case。公開 ID は UUID。日時は UTC の timezone 付き ISO 8601（例 `2026-09-28T10:30:00Z`）。保存時に Firestore Timestamp へ変換する。
- GET は状態を変えない。POST 作成は `201` と `Location`、非同期受付は `202` と状態確認 URL、本文なし成功は `204`。
- PUT は全体置換かつ冪等、PATCH は部分更新。更新競合は ETag / `If-Match` と `412` で防ぐ。
- 一覧の `limit` は既定20、最大100。0件は `200` と `items: []`。offset は使わず、不透明な cursor を使う。sort は許可リストへ明示的に map する。
- `X-Request-ID` は形式と長さを検証し、応答にも返す。
- すべてのエラーは `{"error":{"code", "message", "details", "trace_id"}}` の形に統一する。
- `401` 未認証、`403` 権限不足、`404` 未存在または存在秘匿、`409` 状態競合、`412` 更新競合、`422` 入力・業務検証、`429` レート制限を意味どおりに使う。
- 内部コレクション名、Firebase UID、email、token、スタックトレース、SDK/DB 例外を応答へ含めない。
- 公開済みで更新頻度の低い GET は `Cache-Control` / ETag を検討する。本人限定・非公開応答を共有キャッシュへ保存させない。
- 非互換変更では既存 v1 の意味を変えず、新バージョンと移行期間を設ける。

## 7. 認証・セキュリティ

- FastAPI は Firebase ID token の署名、発行者、対象者、有効期限、必要な失効状態を検証し、`uid` から内部ユーザーを解決する。
- 所有者・admin・受付状態を Service で毎回検証する。クライアントが送る `user_id`, `role`, email を信用しない。
- 初回ユーザー作成は検証済み UID を使って冪等に行う。Firebase UID は公開 API に返さない。
- X provider 情報は Firebase から取得する。X user ID や provider identity を本文から信用せず、OAuth access token を業務 DB に保存しない。
- CORS は既知の Web Origin、必要なメソッド・ヘッダーだけを許可する。
- 公開 API、ゲスト投稿、ログイン、画像生成には用途別レート制限を設け、`429` と `Retry-After` を返す。
- 画像は MIME だけでなく実データ、サイズ、拡張子を検証する。
- 構造化ログには時刻、正規化パス、status、処理時間、trace ID、匿名化主体、エラーコード、外部処理時間だけを必要最小限記録する。本文全体や Authorization を記録しない。
- Cloud Run のサービスアカウントには必要最小限の IAM 権限だけを付与する。Admin SDK は Security Rules を迂回するため API 認可テストを必須とする。

## 8. Firestore と整合性

Pydantic、Service、決定的 ID、Firestore transaction / batch の複数層で不変条件を守る。

- 予想と最大20件の選択内容は同じドキュメントへ内包し、途中状態を残さない。
- 予想枠、候補、重複防止キーを transaction 内で読み直し、受付状態・時刻と候補所属を再検証する。
- ログインユーザーの同一枠への二重投稿は `predictionKeys/{sha256(uid + ":" + slotId)}` を同じ transaction で作成して防ぐ。
- 削除時は `deleted_at` と `predictionKeys` の削除を同じ transaction で行い、別の Idempotency-Key による再投稿を許可する。
- transaction は競合で再実行され得る。外部 API、メール、キュー投入などの副作用を transaction 関数内で実行しない。
- 認証済み POST の `Idempotency-Key` は24時間再利用する。同一キー・同一本文は最初の結果、本文違いは `409 IDEMPOTENCY_KEY_REUSED`。ゲストには適用しない。
- `ranking` は連続した重複なし順位を必須、`selection` は順位を禁止する。候補所属、min/max、重複も配列全体で検証する。
- `acceptance_status` は保存せず、slot の状態と現在時刻から `scheduled/open/closed/cancelled` を計算する。
- スナップショットの非正規化には `_snapshot` を付け、正データ、同期、修復方法を明示する。
- 実際の query に必要な複合索引を Emulator で確認し、`firestore.indexes.json` で管理する。常時 listener、全件取得、巨大ドキュメント、N+1 read を避ける。

## 9. テスト方針と品質ゲート

テストは実装の後付けではない。変更した振る舞いについて、正常系だけでなく境界値、認証・認可、競合、失敗時の atomicity、公開情報の非漏えいを同じ変更で保証する。時刻、UUID、外部サービス、Repository は注入・差し替え可能にし、テストを決定的にする。

### フロントエンド

新規構築時の標準 package manager は pnpm とし、lockfile を commit する。すでに別の lockfile がある場合は、依頼なく package manager を切り替えない。

必須品質ゲート:

```powershell
Set-Location apps/web
pnpm lint
pnpm typecheck
```

- `package.json` に `lint` と `typecheck` script を必ず定義する。`typecheck` は Nuxt の型生成を含む `nuxt typecheck` 相当とする。
- 変更した composable、store、認証・認可分岐、フォーム検証、API エラー処理には利用中のテスト runner で unit/component test を追加する。
- 画面テストでも実 token や実クラウドを使わず、API と Firebase Auth を stub/mock する。
- lint/type error を無効化コメントや型逃げで隠さず、原因を直す。

### バックエンド

新規構築時の標準 package manager / runner は uv とし、`pyproject.toml` と lockfile を commit する。すでに別の管理方式がある場合は、依頼なく切り替えない。

必須品質ゲート:

```powershell
Set-Location apps/api
uv run ruff check .
uv run ruff format --check .
uv run mypy app tests
uv run pytest
```

- Ruff を lint と format check、mypy を型チェック、pytest をテストに使い、設定は `apps/api/pyproject.toml` に集約する。
- unit: Service の業務ルール、Schema 境界、エラー変換を高速に検証する。
- integration: Firebase Emulator で Repository、transaction、競合、索引、Security Rules を検証する。本番や共有プロジェクトへ接続しない。
- contract: `/openapi.json`、リクエスト、成功/エラー schema、status、header を検証し、意図しない破壊的変更を検出する。
- async test の session/client をテスト間で共有して状態を漏らさない。

最低限、次を対応するテストで保証する。

- 作成 `201 + Location`、削除 `204 + 空本文`、非同期受付 `202 + Location/Retry-After`。
- UUID、enum、文字数、件数、`limit > 100` が `422`。
- `401/403/404/409/412/422/429` と統一エラー JSON。
- 締切前後、所有者/admin/他人/ゲスト、公開/非公開の認可表。
- 別枠候補、候補重複、順位欠番・重複、選択数違反。
- 同時二重投稿、Idempotency-Key、transaction 失敗時に部分データが残らないこと。
- 正式結果は draft で非公開、published でのみ公開。
- Firebase UID、email、token、内部フィールドが response/log/OpenAPI example に混入しないこと。
- 代表一覧の Firestore read 数または download bytes が想定上限内で、N+1 がないこと。
- 的中率・ユーザーランキング API が存在しないこと。

### 自動実行

リポジトリルートから次を実行すると、存在する対象の全品質ゲートを順に実行できる。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/check.ps1
```

PowerShell 7 を利用できる環境では `pwsh -NoProfile -File ./scripts/check.ps1` でもよい。`ExecutionPolicy Bypass` はこのプロセスだけに適用し、端末やユーザーの永続設定は変更しない。

対象を絞る場合:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/check.ps1 -Target frontend
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/check.ps1 -Target backend
```

開発中は変更箇所の targeted test を先に実行し、完了前に変更対象の全ゲートを実行する。フロントとバックの契約にまたがる変更は両方を実行する。CI も `scripts/check.ps1` を唯一の入口として使用し、別のコマンド列を重複管理しない。依存関係の未導入、Emulator 不在、失敗、未実行を成功扱いせず、最終報告に明記する。

## 10. 実装・変更の進め方

1. `.env` 除外を確認し、関連コード、テスト、正本ドキュメントを読む。
2. 変更前に関連する既存テストを実行して baseline を確認する。実行不能または既に失敗している場合は、変更後の失敗と区別できるよう記録する。
3. 要件、API 契約、認可主体、データ不変条件、transaction 境界、失敗時の応答を先に整理する。
4. 既存の命名・層・package manager・lockfile・設定へ合わせ、必要最小限の変更を行う。無関係な差分を直さない。
5. 仕様変更なら Schema/OpenAPI、生成 client、実装、テスト、文書を一緒に更新する。
6. targeted test、lint、型チェック、全テストの順で実行する。
7. 差分を自己レビューし、秘密・個人情報・内部 ID・過剰 read・認可漏れ・破壊的 API 変更がないことを確認する。
8. 完了報告には変更点、実行した検証と結果、実行できなかった検証と理由、残課題を簡潔に記載する。

### Git・変更境界

- 明示的な依頼なしに branch の作成・切替、commit、push、PR 作成、tag・release・deploy を行わない。
- 既存の未コミット変更は利用者の作業として扱い、無関係な変更を削除、退避、上書き、整形しない。
- commit を依頼された場合は Conventional Commits の `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:` を使い、1 commit を1つの論理変更にする。
- 本番・共有環境の Firebase、Firestore、Cloud Run、R2、Cloud Tasks、Secret Manager を操作しない。deploy、データ移行、backfill、削除、Security Rules / index の適用は、対象環境と影響を示して明示的な承認を得る。通常の検証は Emulator で行う。
- 破壊的または不可逆な migration を自動実行しない。移行 script の作成時は dry-run、冪等性、再実行、部分失敗、roll-forward または復旧手順を用意する。
- 新規依存は標準ライブラリや既存依存で解決できないか確認し、採用理由、保守状況、license、bundle/runtime への影響をレビュー可能にする。
- PR またはレビューのチェック項目に、ディレクトリ、コマンド、規約、依存関係の変更に伴う `AGENTS.md` 更新要否を含める。

### このファイルの保守

- 実際の manifest、lockfile、directory、CI と記載コマンドが食い違ったら、同じ変更でこのファイルを更新する。
- 人間向けの導入説明や長い背景は README / `doc/`、エージェントが取るべき行動はこのファイルに置く。
- 重要度の高い規則を先に置き、重複や例外を増やさない。ルートファイルは UTF-8、32 KiB 未満を維持する。
- 規則がアプリ固有で大きくなった場合は `apps/web/AGENTS.md` または `apps/api/AGENTS.md` へ分割できる。ただし、秘密情報、プロダクト不変条件、共通品質ゲートなど全体ルールはルートに残す。子の指示は親を補足し、矛盾させない。

## 11. レビュー時の必須手順

コードレビューでは、レビュー対象だけで判断せず、次の文書を UTF-8 で読み込む。

1. `doc/お笑い賞レースの予想サイト.md` 全体。特に 2章、5〜10章。
2. `doc/FastAPI_API設計ベストプラクティス.md` 全体。特に 2〜3章、4.6節、5〜17章、18章のチェックリスト。

レビュー依頼は原則 read-only で扱い、修正まで明示された場合だけ編集する。指摘は重要度順に、対象ファイルと行、再現条件または具体的な失敗シナリオ、違反する仕様、最小の修正方針を示す。要約より先に findings を出す。問題がなければその旨と残るテスト上のリスクを述べる。

最低限のレビュー観点:

- プロダクトの非競争性、ゲスト制約、非公開情報、ネタバレ・画像権利への配慮。
- Router / Service / Repository の責務、入力/出力/保存モデルの分離。
- HTTP method/status/header、命名、cursor、上限、統一エラー、OpenAPI の整合。
- token 由来の主体、所有者/admin 判定、存在秘匿、CORS、rate limit、ログの秘匿。
- transaction、決定的 ID、同時実行、冪等性、失敗時の atomicity。
- Firestore query/index/read コスト、一覧と詳細の取得分離、キャッシュの公開範囲。
- lint、型チェック、unit/integration/contract test が変更リスクを十分に覆うこと。
