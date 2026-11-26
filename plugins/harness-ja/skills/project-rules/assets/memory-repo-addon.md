<!-- リポジトリのある案件だけに足すメモリの種。<...> を書き換える。 -->

## ops-devices-and-gates.md

```
---
name: ops-devices-and-gates
description: クラウドのスレッドと手元のマシンの使い分け、設定の書き換えに要る承認の行、決まりが効き始めるタイミング
metadata:
  type: reference
---
- 手元のマシンの <作業フォルダー> は、読むだけならフォルダーの共有で読む。コマンドの実行と未コミット分の読み取りは、手元のマシンのセッションで行う。
- `.claude/` の書き換えに要る `[harness-go]` の行は、依頼者がそのスレッドの中に書く(転送は効かない)。頼むときは、作業を止めてから、そのスレッドへのリンクを付けて、作業の最初にまとめて出す。
- 決まりや自動の検査を足したら、対象のスレッドを新しく起動し直すまで効かない(起動時に読み込むため)。
- クラウドのスレッドは、リポジトリの親のフォルダーで起動する。リポジトリの .claude/settings.json は起動時に読まれないため、harness-ja の中継(設定ファイルの projectHooksRelay.enabled)で流す。
- 送信のツールを通すかどうかは、設定ファイルの sendGate.mode で決まる("allow" のときだけ通す)。
```

## ops-repo-git.md

```
---
name: ops-repo-git
description: <リポジトリ名> のコミットと push の流れ
metadata:
  type: reference
---
- <コミットの流れ。個人のリポジトリなら「main 一本。PR を作らず main に直接 commit・push する。強制 push はしない」。そうでなければ PR の運用を書く>
- main と食い違って fast-forward できないときは、main を変えず、食い違うコミットを報告する。rebase と強制 push はしない。
- 手元の変更は捨てずに `git stash push -- <パス>` で退け、取り込みは `git pull --ff-only`。
```
