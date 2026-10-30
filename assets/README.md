# assets

这个目录只放**发布版专属**的图片，源码仓库里不放。

- `reward_qr.png` —— 赞赏收款码（微信支付）。**被 .gitignore 忽略**，
  只出现在 README 的「赞赏」章节里。
- 打发布版时由 `tools/publish_server.ps1` 从 `docs/reward_qr.png` 拷进来，
  构建完自动删掉，保证源码版 APK 里没有它。

在没有 `reward_qr.png` 的情况下，App 仍然能正常构建（这个目录里有本文件撑着），
只是在源码版里「赞赏」入口根本不显示（`kOfficialBuild == false`）。
