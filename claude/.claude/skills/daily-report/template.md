# Daily Report — {{DATE}}

**{{PROJECT}}**  ·  `{{BRANCH}}`

**TL;DR** — one- to two-line abstract of the day's outcome

---

<!-- 記入ガイド:
     ・🔬 Research / 🛠️ Engineering の2トラックに分割するのは5セクションのみ
       （Objective・Progress・Findings・Issues/Blockers・Next）。両ラベル必須。
       🔬 Research    = 仮説・実験設計・結果とその解釈・科学的結論・手法上の判断。
       🛠️ Engineering = コード・基盤・ツール・設定・パイプライン・ビルド/デプロイ・バグ修正。
     ・Hypotheses (Active/Archived)・Decisions・Yesterday's Next・Reproducibility は R/E 分割せず
       単一のテーブル/チェックリスト/リスト。空なら N/A（Reproducibility は None）。
     ・2階層の箇条書き: top-level bullet = その topic の結論を端的に1行（カテゴリ名で
       はなく takeaway そのもの）、その下に sub-bullet で根拠・詳細を1行ずつ。
       フラットな羅列にしない。結論が1行で完結するなら sub-bullet 無しでよい。
     ・TL;DR は header の1行（最大2行）。Findings から最後に蒸留して書く。
     ・Findings の top-level bullet 先頭に確信度 [confirmed]/[preliminary]/[refuted-prior]。
     ・数値・条件比較は Findings の sub-bullet へ（run名・条件を明記）。文中に散らさない。
       事前設定の閾値があった run は、その達成可否(pass/fail)も sub-bullet に書く。
     ・Hypotheses の status flip (どの方向でも) は対応する Findings bullet を必ず持つ。
       連続3日以上動かず status が open でない行は Archived テーブルに移す。
     ・thread tag は project の `.claude/daily-report-threads.txt` に列挙された短い識別子
       （例: #excite-data）。Hypotheses は thread 列で分類。Findings/Issues/Next の top-level
       bullet 末尾にも任意で `#thread-name` を付けられる。
     ・Yesterday's Next で連続2日以上 `[ ]` のまま carry された項目は `(carry × N — 理由)` を
       強制。N ≥ 3 は Issues/Blockers にも同期掲載。
     ・該当が無いトラックは "None"。pad しない。
     ・解析画像は専用セクションを作らず、該当する sub-bullet の下にネスト挿入される
       （worker が anchor 指定 → notion-upload-images.sh）。 -->

## 🎯 Objective

**🔬 Research**
- conclusion
  - detail
**🛠️ Engineering**
- conclusion
  - detail

## 🚀 Progress

**🔬 Research**
- conclusion
  - detail
**🛠️ Engineering**
- conclusion
  - detail

## 🔍 Findings

**🔬 Research**
- [confirmed | preliminary | refuted-prior] conclusion
  - detail
**🛠️ Engineering**
- [confirmed | preliminary | refuted-prior] conclusion
  - detail

## 🧠 Hypotheses — Active

| hypothesis | thread | status | evidence |
|---|---|---|---|
| hypothesis | #thread-tag | open / supported / refuted | run/finding (YYYY-MM-DD last touched) |

## 🧠 Hypotheses — Archived

| hypothesis | thread | status | evidence |
|---|---|---|---|
| resolved hypothesis | #thread-tag | supported / refuted | run/finding (YYYY-MM-DD last touched) |

## 🚧 Issues / Blockers

**🔬 Research**
- conclusion
  - detail
**🛠️ Engineering**
- conclusion
  - detail

## 🧭 Decisions

| decision | alternatives | rationale |
|---|---|---|
|  |  |  |

## 🔄 Yesterday's Next

- [x] prior item — done (where closed)
- [~] prior item — partial (what remains)
- [ ] prior item — carried over

## ⏭️ Next

**🔬 Research**
- conclusion
  - detail
**🛠️ Engineering**
- conclusion
  - detail

## 📌 Reproducibility

- <run label> — commit `<sha>` · ckpt `<path>` · seed `<n>` · ds `<version>` · pueue `<id>`
