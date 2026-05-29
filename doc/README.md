# 文档总览

`doc/` 目录用于沉淀 Secure X 的产品方案、技术设计与迭代规划，作为后续实现前的统一依据。

## 文档目录

- [01-product-overview.md](01-product-overview.md)
  - 说明产品目标、用户场景、功能边界与 MVP 范围
- [02-architecture.md](02-architecture.md)
  - 说明客户端、服务端、存储层与同步层的整体架构
- [03-crypto-storage.md](03-crypto-storage.md)
  - 说明端到端加密、密钥层次、文件加密与存储策略
- [04-roadmap.md](04-roadmap.md)
  - 说明建议迭代顺序、里程碑与实现阶段拆分
- [05-open-questions.md](05-open-questions.md)
  - 汇总需要用户拍板的关键设计决策，避免实现阶段反复返工
- [06-release.md](06-release.md)
  - 说明 GitHub Actions 多端打包、Release 产物与签名边界

## 使用原则

- 新的设计决策优先追加到 `doc/`，再进入编码
- 安全相关变更需要同步更新架构与加密文档
- 所有已落地的重要改动都要同步更新 `CHANGELOG.md`
