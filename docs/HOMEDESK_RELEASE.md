# NestLink 14.0.1

本维护版修复已发布 14.0.0 Linux 客户端正常首页没有版本入口的问题。Linux 桌面顶部显示与手机共用的 NestLink 品牌和偏好菜单，可切换主题、语言并打开“版本与下载”。Windows 继续使用原标题栏入口；账号、远控批准、设备撤权和穿透权限流程保持原实现。

This maintenance release restores the normal Linux desktop preferences and version entry. The shared dashboard menu opens the existing version/download dialog and provides theme and language controls. Windows keeps its existing titlebar entry.

客户端、共享 Flutter/Rust 源码与受管 Agent/穿透/浏览器助手的产品版本为 14.0.1；共享 Flutter build number 为 14000100。目标发行组合为 server/client/Android/Agent 14.0.1，最低服务端为 14.0.0。安装身份、配置命名空间、Logo、Android applicationId、发行证书、认证 API v2 和两份版本扩展契约均保持不变。

本文件目前记录维护源码，尚不代表正式发行或新产物验收。必须针对新的源码提交完成 Client CI、CodeQL 和 Secret scan，从成功的确切来源 CI 获取 Windows x64、Linux x64/ARM64 原产物；随后单独记录 14.0.1 的安装、GUI、原生联调、运行时摘要及对应源码，生成 `docs/release/acceptance-14.0.1.json` 后才能发布。14.0.0 标签、安装包和历史验收记录不替换，也不复用其结论作为本版验收。

新增 Linux 回归直接构建生产 Dashboard 与设备目录，在 Linux runner 上以四个独立实例覆盖已登录/未登录及中英文，点击真实偏好菜单打开原版本弹窗。手机与 Windows 标题栏版本检查读取当前产品版本。widget 结果不等同于新安装包的真实窗口验收；具体执行、CI、摘要和未测范围由本版验收补充。

依赖未在本维护修复中升级。14.0.0 的独立依赖审查记录了 18 个未关闭告警（3 high、7 medium、8 low）；本版不能以旧审查代替新来源检查。Linux `users` 0.10.0/0.11.0 仍未修复，既有消费者未发现相关组列表访问控制入口调用仅属静态范围判断，没有动态可达性或利用测试。受影响的 `libgit2-sys` 仍作为 Linux 构建元数据输入，构建依赖未修复；glib/users 的其他告警和 atty 风险仍保留。不宣称全部依赖漏洞已修复。

GitHub、下载站和更新信息随本版发行同步；正在运行的生产服务端保持原版本。

历史完整发行说明：[14.0.0 HOMEDESK_RELEASE.md](https://github.com/ZHanry/home-tunnel-client/blob/v14.0.0/docs/HOMEDESK_RELEASE.md)；原始验收索引：[acceptance-14.0.0.json](release/acceptance-14.0.0.json)。这些链接仅供历史追溯，不构成本维护版验收。

按本次用户要求，不重复执行本机 Windows 清装；Windows 新产物的 CI 检查与本机未重装范围分别记录。
