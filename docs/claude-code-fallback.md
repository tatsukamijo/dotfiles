# Claude Code ローカルfallback

Anthropic API が落ちている / 繋がらないときに、**Claude Code とまったく同じ
インターフェース**（nvim の per-tab agent・`@mention`・diff・キーマップすべて）
のまま、裏のモデルだけローカルの Ollama に切り替えるための仕組み。

`claude` バイナリ自体はそのまま使うので、claudecode.nvim の MCP 連携は
一切壊れない。変わるのは `ANTHROPIC_BASE_URL` だけ。

## 構成

```
nvim  <leader>aF
  │  spawn: claude --enable-auto-mode   (env: ANTHROPIC_BASE_URL=127.0.0.1:3456)
  ▼
claude バイナリ ──HTTP──> claude-code-router  :3456
  ▲                         │  no-think transformer が thinking/effort を除去
  │ MCP WebSocket            ▼
  └─ claudecode.nvim       Ollama (CUDA)  :11435 ──> qwen3-coder-ccr  (GPU, ctx 65536)
```

| 部品 | 実体 | ポート | 備考 |
|---|---|---|---|
| claude-code-router | `npm -g @musistudio/claude-code-router` (`ccr`) | 3456 | Anthropic形式↔Ollama形式を変換 |
| Ollama (CUDA版) | `~/.ollama-cuda/bin/ollama` | 11435 | 公式tarball。pixi/システム版とは別 |
| モデル | `qwen3-coder-ccr` (Qwen3-Coder-30B-A3B) | — | `qwen3-coder:30b` に num_ctx を足したもの |
| ルータ設定 | `~/.claude-code-router/config.json` | — | |
| 変換プラグイン | `~/.claude-code-router/no-think.js` | — | thinking系フィールドを削除 |
| nvim連携 | `.submodules/nvim/lua/custom/plugins/claudecode.lua` | — | `<leader>aF` |

## 使い方

nvim で **`<leader>aF`** — "fallback" ラベルの agent タブが開く。

初回押下時に `ensure_fallback_services()` が Ollama (:11435) と `ccr` を
必要なら自動起動する。最初の応答はモデルのVRAMロードで20〜40秒かかるが、
以降は速い。通常の Claude Code (`<leader>ac` 等) は今まで通り本家 API を使う。

サービスの手動操作（`ollama-fb` は bashrc のラッパー = 正しいバイナリ + :11435 を叩く。
素の `ollama` は古いシステム版/サーバ:11434 に解決されるので使わない）:

```bash
ccr status / ccr stop / ccr restart
ollama-fb ps                      # GPUに載っているか
ollama-fb stop qwen3-coder-ccr    # VRAMを即解放 (ollama serve は残る)
```

## リソース使用量

`qwen3-coder-ccr` 使用中（RTX 6000 Ada / 48GB）:

- **VRAM**: 約25GB（重み18GB + KVキャッシュ ctx65536分 ~6GB）。残り ~23GB。
- **GPU演算**: 生成中のみ。MoE(実効3.3B)なので速い。ターン間は0%。
- **未使用時**: `OLLAMA_KEEP_ALIVE`（既定5分）でVRAMから自動アンロード → 0GB。
- **ディスク**: モデル ~18GB + CUDA版ollama ~3GB。
- **ネットワーク**: 全て localhost、外部通信ゼロ（= FortiGate 非依存）。

### コンテキスト長の調整

`num_ctx` を上げると長い対話に強くなるが VRAM を食う。GPU を他作業
（ロボティクスの学習等）と取り合うなら下げる。`qwen3-coder-ccr.Modelfile`
の `PARAMETER num_ctx` を変えて `ollama create` し直す:

```bash
ollama-fb create qwen3-coder-ccr -f ~/.claude-code-router/qwen3-coder-ccr.Modelfile
```

## ゼロから再構築する手順

```bash
# 1. router
npm install -g @musistudio/claude-code-router

# 2. CUDA対応 ollama（公式tarball、sudo不要）
#    conda-forge版はCPU専用、システムの/usr/local版は古すぎて不可。
curl -fL https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst \
  -o /tmp/o.tar.zst
mkdir -p ~/.ollama-cuda && tar --zstd -C ~/.ollama-cuda -xf /tmp/o.tar.zst && rm /tmp/o.tar.zst

# 3. ollama を :11435 で起動（システムの:11434とは別運用）
OLLAMA_HOST=127.0.0.1:11435 ~/.ollama-cuda/bin/ollama serve &

# 4. モデル取得 + 大コンテキスト版を作成
OLLAMA_HOST=127.0.0.1:11435 ~/.ollama-cuda/bin/ollama pull qwen3-coder:30b
OLLAMA_HOST=127.0.0.1:11435 ~/.ollama-cuda/bin/ollama create qwen3-coder-ccr \
  -f ~/.claude-code-router/qwen3-coder-ccr.Modelfile

# 5. 設定ファイルを配置（下記2つ）。nvim側は claudecode.lua に反映済み。
```

### `~/.claude-code-router/config.json`

```json
{
  "LOG": true,
  "LOG_LEVEL": "info",
  "API_TIMEOUT_MS": 600000,
  "transformers": [
    { "path": "/home/tatsuya.kamijo/.claude-code-router/no-think.js" }
  ],
  "Providers": [
    {
      "name": "ollama",
      "api_base_url": "http://127.0.0.1:11435/v1/chat/completions",
      "api_key": "ollama",
      "models": ["qwen3-coder-ccr"],
      "transformer": { "use": ["no-think"] }
    }
  ],
  "Router": {
    "default": "ollama,qwen3-coder-ccr",
    "background": "ollama,qwen3-coder-ccr",
    "think": "ollama,qwen3-coder-ccr",
    "longContext": "ollama,qwen3-coder-ccr",
    "longContextThreshold": 200000,
    "webSearch": "ollama,qwen3-coder-ccr"
  }
}
```

### `~/.claude-code-router/no-think.js`

Claude Code 2.x は `thinking:{type:"adaptive"}` と `output_config.effort` を
送るが、qwen3-coder は思考モデルではないため Ollama が 400 を返す。
これらを落とすカスタムtransformer。

```js
class NoThink {
  static TransformerName = 'no-think';
  name = 'no-think';
  async transformRequestIn(request) {
    delete request.thinking;
    delete request.output_config;
    delete request.reasoning;
    return request;
  }
}
module.exports = NoThink;
```

### `~/.claude-code-router/qwen3-coder-ccr.Modelfile`

```
FROM qwen3-coder:30b
PARAMETER num_ctx 65536
```

## ハマりどころ

- **conda-forge の `ollama` は CPU専用**。`lib/ollama/` に `libggml-cuda.so` が
  無く、GPUに 0/49 layer しかオフロードしない。必ず公式tarballを使う。
- **システムの `/usr/local/bin/ollama` (0.1.30) は古すぎ**て qwen3-coder を
  pull できない（`412 requires a newer version`）。:11434 で動き続けているが
  fallback では使わない。
- **num_ctx を明示しないと 4096** に切り詰められ、Claude Code の巨大な
  プロンプト（system + tool定義だけで ~15k tokens）が壊れる。
- 素の `ollama` コマンドは古いシステム版（:11434）に解決される。fallback の
  ollama を CLI で触るときは `ollama-fb`（bashrc のラッパー）を使う。
- 品質は本家 Claude には及ばない。あくまで API 障害時の応急用。
