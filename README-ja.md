# SLAHMR Docker テンプレート

[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-multi--file-blue?logo=docker)](#複数の-compose-ファイルを使う構成)
[![NVIDIA GPU](https://img.shields.io/badge/GPU-NVIDIA-76B900?logo=nvidia)](#前提条件)
[![Linux](https://img.shields.io/badge/Host-Linux-FCC624?logo=linux&logoColor=black)](#前提条件)
[![Environment File](https://img.shields.io/badge/config-.env-important)](#設定)
[![Makefile](https://img.shields.io/badge/workflow-Makefile-6C63FF)](#make-コマンド一覧)

このリポジトリは、[SLAHMR](https://github.com/vye16/slahmr) を GPU 対応の Docker + Docker Compose 環境で動かすためのテンプレートです。

2 つのモードを用意しています。

- **開発モード**: ホスト側の `workspace/slahmr` を bind-mount してコンテナ内に反映します。ViTPose と DROID-SLAM の初回インストールは起動時に自動実行され、以降の起動時には import 検証によりインストール済みかどうかを確認します。
- **本番再現モード**: ソースコードをイメージに焼き込み、ホスト側の bind-mount に依存しない形で動かします。

---

## 目次

- [特徴](#特徴)
- [ディレクトリ構成](#ディレクトリ構成)
- [前提条件](#前提条件)
- [クイックスタート](#クイックスタート)
- [make コマンド一覧](#make-コマンド一覧)
- [設定](#設定)
- [複数の Compose ファイルを使う構成](#複数の-compose-ファイルを使う構成)
- [開発モードと本番再現モード](#開発モードと本番再現モード)
- [前処理と推論の実行](#前処理と推論の実行)
- [ブートストラップの仕組み](#ブートストラップの仕組み)
- [トラブルシューティング](#トラブルシューティング)
- [リポジトリ運用のヒント](#リポジトリ運用のヒント)
- [ライセンス / 上流リポジトリ](#ライセンス--上流リポジトリ)

---

## 特徴

- ホスト側ソース編集を反映しやすい開発モードと、再現性重視の本番再現モードの 2 モード構成
- `.env` による コンテナ名・GPU アーキテクチャ・パス・イメージ設定の一元管理
- `setup.sh` によるホスト側の一括準備（clone・entrypoint コピー・SMPL + 重みダウンロード・プレースホルダー config 生成）
- `Makefile` によるビルド・起動・シェル・ログ・前処理・推論のショートカット
- import 検証ブートストラップ: スタンプファイルが存在しても `mmpose` / `droid_backends` の import に失敗した場合は自動再インストール
- ホスト側で生成された root 所有の `__pycache__` を一時 Alpine コンテナで削除する `clean-pycache` ターゲット
- Hydra の `custom.yaml` / `video.yaml` を単一ファイルとしてコンテナ内の `slahmr/confs/data/` へ bind-mount
- `.dockerignore` によるビルドコンテキストの最小化

---

## ディレクトリ構成

```text
.
├── README.md
├── README-ja.md
├── .env.example
├── .gitignore
├── .dockerignore
├── Dockerfile
├── Makefile
├── compose.yml
├── compose.dev.yml
├── compose.prod.yml
├── entrypoint.dev.sh
├── entrypoint.prod.sh
├── setup.sh
├── configs/
│   ├── custom.yaml        ← setup.sh / prepare_custom.sh が生成
│   └── video.yaml         ← setup.sh / prepare_video.sh が生成
├── data/
│   └── inputs/            ← 入力動画ファイルをここに置く
├── scripts/               ← 推論・前処理ラッパースクリプト
└── workspace/
    └── slahmr/            ← make init で git clone される
```

---

## 前提条件

- Linux ホスト
- Docker Engine
- Docker Compose プラグイン
- NVIDIA ドライバおよび Docker GPU ランタイム（NVIDIA Container Toolkit）
- `workspace/slahmr` への SLAHMR ソースコードの配置（`make init` で自動作成）

---

## クイックスタート

### 1. 環境ファイルを作成する

```bash
cp .env.example .env
```

必要に応じて GPU アーキテクチャやイメージ名などを編集します。

### 2. SLAHMR を clone してホスト側セットアップを実行する

```bash
make init
make setup
```

`make init` は SLAHMR ソースコードを `workspace/slahmr` へ clone します。  
`make setup` は entrypoint スクリプトのコピー・SMPL モデルと事前学習済み重みのダウンロード・`configs/` 以下のプレースホルダー Hydra config 生成を行います。

### 3. 開発モードでビルドして起動する

```bash
make dev-build
make dev-up
make dev-shell
```

初回起動時に `entrypoint.dev.sh` が ViTPose（editable インストール）と DROID-SLAM のビルドを自動実行します。

---

## make コマンド一覧

### セットアップ

```bash
make env-init        # .env が無ければ .env.example からコピー
make init            # workspace/slahmr に SLAHMR を clone
make setup           # setup.sh を実行（entrypoints + 重み + config）
make reinit          # workspace/slahmr を削除して再 clone
make clean-pycache   # 一時 Alpine コンテナで root 所有の __pycache__ を削除
```

### 開発モード

```bash
make dev-build       # 開発用イメージをビルド
make dev-up          # 開発コンテナをバックグラウンドで起動
make dev-down        # 開発コンテナを停止
make dev-shell       # 起動中の開発コンテナに bash で入る
make dev-logs        # 開発コンテナのログをテール表示
make dev-config      # dev 用マージ済み Compose 設定を表示
make dev-rebuild     # リビルドして再起動
make dev-restart     # ブートストラップスタンプをリセットして再起動
```

### 本番再現モード

```bash
make prod-build      # 本番再現用イメージをビルド
make prod-up         # 本番再現コンテナをバックグラウンドで起動
make prod-shell      # 起動中の本番再現コンテナに bash で入る
make prod-logs       # 本番再現コンテナのログをテール表示
make prod-config     # prod 用マージ済み Compose 設定を表示
make prod-rebuild    # リビルドして再起動
make prod-down       # 本番再現コンテナを停止
```

### 前処理と推論

```bash
make prepare-custom VIDEO=/workspace/data/inputs/sample.mp4 [SEQ=my_seq]
make prepare-video  VIDEO=/workspace/data/inputs/sample.mp4 [SEQ=my_seq] [FPS=30]
make run-custom
make run-video
```

### ユーティリティ

```bash
make ps              # コンテナの状態を確認
make clean           # コンテナと named volume を削除
```

---

## 設定

メインの設定は `.env.example` で定義されています。`.env` にコピーして必要な箇所を編集してください。

| 変数 | 説明 |
|---|---|
| `IMAGE_NAME` / `IMAGE_TAG` | Docker イメージ名とタグ |
| `CONTAINER_NAME` | 起動するコンテナに付ける名前 |
| `CONTAINER_SHM_SIZE` | 共有メモリサイズ（デフォルト: `16gb`） |
| `TORCH_CUDA_ARCH_LIST` | コンパイル対象の CUDA アーキテクチャ |
| `HOST_SLAHMR_DIR` | SLAHMR ソースツリーのホスト側パス |
| `HOST_SCRIPTS_DIR` | scripts ディレクトリのホスト側パス |
| `HOST_CUSTOM_CFG_FILE` | `configs/custom.yaml` のホスト側パス |
| `HOST_VIDEO_CFG_FILE` | `configs/video.yaml` のホスト側パス |
| `HOST_DATA_DIR` | data ディレクトリのホスト側パス |
| `CONTAINER_SLAHMR_DIR` | コンテナ内の SLAHMR ソースパス |
| `CONTAINER_CUSTOM_CFG_FILE` | コンテナ内 Hydra confs の `custom.yaml` パス |
| `CONTAINER_VIDEO_CFG_FILE` | コンテナ内 Hydra confs の `video.yaml` パス |
| `CONTAINER_DATA_DIR` | コンテナ内の data ディレクトリパス |
| `DATA_SPLIT` / `RUN_OPT` / `RUN_VIS` | 推論実行時のデフォルト値 |

---

## 複数の Compose ファイルを使う構成

このテンプレートはベースファイルとモード別オーバーレイファイルを組み合わせます。

- `compose.yml` — サービス定義・named volume・GPU ランタイム設定（共通）
- `compose.dev.yml` — 開発用オーバーレイ（bind-mount・dev ビルドステージ・dev entrypoint）
- `compose.prod.yml` — 本番再現用オーバーレイ（prod ビルドステージ・prod entrypoint）

Docker Compose は指定した順にファイルをマージします。後から指定したファイルが前のファイルを上書き・拡張します。

直接コマンドを実行する場合は次のようにします。

```bash
docker compose --env-file .env -f compose.yml -f compose.dev.yml up -d --build
docker compose --env-file .env -f compose.yml -f compose.prod.yml up -d --build
```

Compose ファイルを編集したら `make dev-config` や `make prod-config` でマージ結果を確認してから `up` するのがおすすめです。

---

## 開発モードと本番再現モード

### 開発モードを使う場面

- ホスト側で SLAHMR ソースコードを編集しながら作業したい
- コードの変更をコンテナ内に即座に反映したい
- リビルドを最小限に抑えて素早くイテレーションしたい

### 本番再現モードを使う場面

- 特定のソース状態の再現性を検証したい
- ホスト側の bind-mount に依存しないコンテナで動かしたい
- 配布可能なイメージに近い動作を確認したい

---

## 前処理と推論の実行

入力動画ファイルはホスト側の `data/inputs/` に置いてください（コンテナ内では `/workspace/data/inputs/` として bind-mount されます）。

### custom シーケンスパイプライン

```bash
# 1. 前処理（コンテナ内で docker compose run --rm として実行）
make prepare-custom VIDEO=/workspace/data/inputs/sample.mp4 SEQ=my_seq

# 2. SLAHMR 推論の実行
make run-custom
```

`VIDEO` は必須です。`SEQ` を省略した場合はビデオファイルのベース名が使われます。

### video パイプライン

```bash
# 1. 前処理（オプションで FPS を指定可能）
make prepare-video VIDEO=/workspace/data/inputs/sample.mp4 SEQ=my_seq FPS=30

# 2. SLAHMR 推論の実行
make run-video
```

`prepare-video` / `run-video` はともに `configs/video.yaml` を使用します。このファイルはコンテナ起動時に `slahmr/confs/data/video.yaml` として bind-mount されます。

---

## ブートストラップの仕組み

`entrypoint.dev.sh` はコンテナ起動のたびに **import ベースのブートストラップ検証** を実行します。

1. `configs/video.yaml` や `configs/custom.yaml` が存在しない場合は、先に `make setup` を実行してプレースホルダー config を生成してください。
2. コンテナ起動時に `preflight_hmr2()` が実行されます。`/workspace/data/models/hmr2_data.tar.gz` がホスト側に存在する場合はローカルから `/root/.cache/4DHumans` へ展開し、存在しない場合はリモートからダウンロードします。
3. モデルキャッシュの確認後、`need_bootstrap()` が `mmpose` と `droid_backends` の import を試みます。スタンプファイル `/var/lib/slahmr/.deps_installed` が存在していても、どちらかの import に失敗した場合は `bootstrap_dev()` が ViTPose の再インストールと DROID-SLAM の再ビルドを実行します。

この仕組みにより、既存の named volume に対して `docker compose run --rm` で新しいコンテナを起動した際も、壊れた環境を手動介入なしに自動修復できます。

ブートストラップを強制的にやり直す場合は次のコマンドを使います。

```bash
make dev-restart
```

---

## トラブルシューティング

### 1. ホスト側の変更がコンテナ内に反映されない

`.env` の `HOST_SLAHMR_DIR` が正しいホスト側ディレクトリを指しているか、サービスが **開発モード** で起動しているかを確認してください。開発モードでは bind-mount ディレクトリがイメージ内のファイルより優先されます。

### 2. 再起動後に ViTPose または DROID-SLAM が import できない

`entrypoint.dev.sh` が import 失敗を検出して自動的に再ブートストラップを実行します。繰り返し失敗する場合は、`workspace/slahmr/third-party/ViTPose` および `workspace/slahmr/third-party/DROID-SLAM` がホスト側に存在するかを確認してください（`make init` で自動配置されます）。

### 3. ホスト側で `__pycache__` ディレクトリが削除できない

コンテナ内で生成されたファイルは root 所有になります。次のコマンドで削除できます。

```bash
make clean-pycache
```

一時 Alpine コンテナを起動して root 権限で削除を行います。

### 4. Compose 内で `${VAR}` が展開されない

Compose の変数展開は `.env` または `--env-file` から読み込まれます。プロジェクトルートに `.env` が存在するか、`--env-file .env` を明示的に渡しているかを確認してください。

### 5. 起動時に Compose の bind-mount が「ファイルが見つからない」で失敗する

`configs/custom.yaml` と `configs/video.yaml` は単一ファイルの bind-mount のため、コンテナ起動前にホスト側に存在している必要があります。`make setup` を実行してプレースホルダーファイルを生成してください。

### 6. 開発モードは動くが本番再現モードがビルドに失敗する

`workspace/slahmr` がビルドコンテキストに含まれており、`.dockerignore` で除外されていないかを確認してください。本番再現イメージは `COPY workspace/slahmr /workspace/slahmr` に依存します。

### 7. コンテナ内で GPU が利用できない

ホスト側の NVIDIA ドライバと Docker GPU ランタイムの設定を確認し、`.env` の GPU 関連環境変数がコンテナに渡されているかを確認してください。

### 8. マージ後の Compose 設定を確認したい

```bash
make dev-config
make prod-config
```

マージ結果・変数の展開後の値・パスの解決状況を確認してから `up` するのがトラブル防止に効果的です。

---

## リポジトリ運用のヒント

- `.env.example` はコミットし、`.env` はコミットしない
- `.gitignore` と `.dockerignore` はコミットする
- 大容量データセット・チェックポイント・出力ファイル・モデルファイルは Git に含めない
- `workspace/slahmr` はユーザーが `make init` で作成する前提にし、Git には含めない
- `configs/custom.yaml` と `configs/video.yaml` はプレースホルダーとしてコミットし、実際の値は前処理スクリプトが実行時に上書きする運用にする
- `.env.example` に想定される GPU アーキテクチャ値をコメントで記載しておく
- Compose ファイルを変更したら必ず `make dev-config` / `make prod-config` でマージ結果を確認してから `up` する
- サービス名を変更する場合は、Compose ファイル・Makefile・README の各コマンド例を一括で置換する

---

## ライセンス / 上流リポジトリ

このテンプレートは SLAHMR のコンテナ化された開発・再現ワークフローを管理するためのものです。

プロジェクト本体のライセンス・利用条件・モデルの使用条件については、上流の SLAHMR リポジトリを確認してください。
