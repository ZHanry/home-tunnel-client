# HomeDesk 来源

- 暖居 Web：ymhaha/home-tunnel codex/hearth-web-ui，00d4719dfb33d4bef6b7fb290220d80d637ca6ef。
- 暖居 Client/RustDesk：ymhaha/home-tunnel codex/hearth-client-ui，6ba2383023d2851b394f13689054c31f4f8c39af，保留其父历史。
- RustDesk engine 来源版本 1.4.9；产品版本单独为 11.0.0-rc.1。
- hbb_common 精确 gitlink：7e1c392c62d39c364127307cd408421dd5f8cfb0。
- HomeTunnel Agent 10.1.0 原字节与 FRP 0.70.1 不随 UI 重写。

整合修改：认证加密的严格直连守卫、禁用 relay/vendor/proxy 回退，轻量 hbbs/账号目录，Go 穿透 helper，DPAPI/Android Keystore 凭据保护，暖居移动四页导航，以及精简候选打包流程。上游媒体/加密算法不重写。完整 diff 可由上述来源和本次 tag 检查。
