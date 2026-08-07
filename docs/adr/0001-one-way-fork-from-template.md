# Forks of this template do not track upstream

`make init` 會對所有 git 追蹤的檔案做一次全域改名，並刪掉 `CLAUDE.md` 與 `docs/agents/`。
從那一刻起新專案與這個 template 永久分岔——**上游之後修的 bug 沒有任何機制能送到已經開出去的專案**。
這是刻意的：保留可回流的能力，要付的代價高過它的價值。

## Considered Options

- **保留 upstream remote，靠 `git merge upstream/main` 拉更新**——`make init` 的全域改名會讓幾乎每個
  檔案都衝突。實務上會退化成「不回流」，只是先浪費一次痛苦的嘗試。
- **把易變的部分抽出去**（reusable workflow、發佈成 base image），只有那部分能更新——對一到數人的
  規模是過度工程，而且抽出去的東西本身也要版本管理與相容性承諾。
- **一次性分岔**（採用）——新專案完全擁有自己的檔案。

## Consequences

- **template 的改動成本要乘上已經開出去的專案數。** 修好一個 nginx 或 CI 的 bug，得手動搬到每個
  專案，而且不會記得哪些專案有那個 bug。所以這個 repo 的改動要比一般專案更保守、更晚下手——
  能等到有第二個實例證實需求再做的，就等。
- 反過來，下游專案可以毫無顧慮地大改任何檔案，不存在「改了會讓之後的 merge 更痛」這回事。
