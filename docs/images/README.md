# Localized Native screenshots / 本地化原生截图

The **en/** and **zh-CN/** directories now contain reviewed real windows from the integrated brand/LED Debug source on 2026-11-14. The capture copy uses a separate bundle identifier, empty runtime and disabled credential autoload. These are Unreleased development screenshots, not screenshots of the published v1.0.0 DMG. Existing flat PNG names remain historical.

**en/** 与 **zh-CN/** 目录现为 2026-11-14 品牌／状态灯最终整合源码的真实 Debug 窗口，已复核语言、标题换行、五张卡片和敏感信息。采集副本使用独立包标识、空运行目录并禁用凭据自动加载；未执行 Guest 操作。这些图展示未发布开发改动，不代表正式 v1.0.0 DMG。

Individual source baseline, dirty-source marker, capture timestamp, build, dimensions and SHA-256 are recorded in [manifest.json](manifest.json). The reviewed UI fingerprint identifies the exact UI source used for capture. The model matrix is isolated test evidence; the real captured homepage has no verified runtime and correctly displays gray indicators.

Capture uses macOS `screencapture -x -o -l <this App window ID>` after selecting the actual target language/page. PNG bytes are copied unchanged: no AI-generated UI, text overlays, compositing, cropping or resizing. Generated illustration assets are rendered by the real application itself. Visual inspection checked language, primary labels/buttons, sensitive data and viewport boundaries. Scrollable content naturally extends outside the viewport; supplemental captures show the lower performance and update controls.

## Reproduce safely

1. Build the current source once with `bash native-app/script/build_and_run.sh --build-only`.
2. For fully separate preference domains, copy the Debug App into ignored evidence storage with `ditto`; use a unique `com.lsjop.helldivers2fx.native.readme.*` bundle identifier and ad-hoc sign **only that copy** for capture isolation. Do not alter the original App or call this distribution signing.
3. Use `native-app/script/capture_readme.py COPY.app NEW_OUTPUT --language zh-CN` or `--language en`. The original Chinese run used process-only preference overrides on the Debug build; the English run used the isolated copy. The driver keeps the target runtime empty and credential autoload disabled via process arguments, performs only read-only host/preference reads, selects real pages and emits their window IDs. The driver attempts one native reopen event when no capture starts; failure to create a window remains a capture failure, never a fabricated result.
4. In this macOS session some cold launches produced no main window. The English run used `--bootstrap-chinese` on the isolated copy, then changed the real in-memory App language to English before capturing. That option is guarded to the unique capture bundle ID; it cannot change the production App's saved preferences. This is real UI localization, not post-processing. Standard menus are outside the captured window; their restart behavior is not acceptance-tested here.
5. Size the window/sidebars through actual AppKit window controls: 1180×850 points, Chinese FX 1180×620 / English FX 1180×700, English sidebar 250 points. These are capture-only window interactions and do not modify product layout code.
6. Inspect every exported image for correct language, readable primary text and secrets. Copy only reviewed original PNGs into the corresponding directory, then update the manifest hashes and both READMEs. Do not copy acknowledgements, raw logs or App bundles into Git.
7. Run `python3 -I -B native-app/script/check_readme_screenshots.py`. It checks local image existence, language directories, provenance/hash conventions, UI-source drift and relative language links. It **cannot identify the actual screenshot language or certify visual quality from a filename/hash**. Native checks run it plus eight negative/positive guard tests. UI-source drift also requires review: recapture visible changes; for a verified nonvisual refactor, retain the original capture hash/date and record the new reviewed source digest plus rationale.

No FX/Guest/game start, SSH connection, configuration write, update check/download/install or real credential read is part of capture. Settings deliberately shows credential auto-reuse restricted and the actual unconfigured installation service. The performance action image has no runtime selected, so write/restore controls remain honestly gated. Screenshots do not establish game/Guest health, effective performance, live apply/restore or update installation. Those interactive states remain separate acceptance work, not missing software-page images.

Future top-level pages, important settings and launch/performance/update UI changes must review ten-language translations, both READMEs, corresponding image freshness and documented status together (AGENTS.md). If real captures cannot be obtained, record missing/pending items explicitly and do not substitute another language or stale UI as current. Current required page captures: **none missing**.

中文：中英文各八张真实原生窗口截图，六个页面及性能操作／软件更新滚动区域均覆盖。仅在隔离 Debug 副本中设置语言、窗口尺寸和截图保护参数，不改产品布局、用户业务偏好或真实 FX 环境。图片原始像素未修改，已逐张检查语言和敏感信息；未选择运行目录，所以应用／恢复按钮仍显示真实受限状态。脚本只检查路径、语言目录和哈希，不能代替视觉检查。旧平铺图片仅为历史资料，不再用于 README 的当前界面展示。

Integration refresh: both language sets now include the shared FX selection state, scoped performance editor and guarded update UI. All captures use isolated process preferences; matching source digests and exact bytes are retained in the manifest. Settings detail images are scroll viewports; additional update controls remain below the visible region.

本次整合重拍覆盖共享 FX 选择、限定性能编辑与受保护更新界面。两套截图使用隔离进程偏好，来源摘要和原始图片哈希已记录。设置详情图为真实滚动视口，部分更新按钮在视口下方，不拼接或伪造状态。

2026-11-04 Codex takeover: `en/environment.png`, `en/settings.png`, `zh-CN/environment.png`, and `zh-CN/settings.png` refreshed from the actual Debug working snapshot (0.1.0 build 2026110401, baseline 0ba4e20 with uncommitted takeover changes). These capture the Environment SSH button and About section heading; offscreen values are not composited. Other images retain their original provenance and are described as historical in both READMEs. Final diagnostic state plumbing and isolated smoke harness changes do not change the pictured regions.

2026-11-04 global UI simplification: all sixteen current English/Chinese page and detail screenshots were recaptured from the real Debug App at source 34aaf40, build 2026110402. The global FXStatusBar is removed from the shared ContentView; native page content starts at the existing common margin. No backend or sidebar change. Actual pixels are retained, without overlays or compositing.

2026-11-04 全局 UI 精简：十六张中英文页面与详情截图均已使用真实 Debug App 重拍，来源34aaf40，构建2026110402。共享ContentView不再渲染FXStatusBar，页面从原有统一边距开始；后端与侧栏不变，截图保留原像素。

## First-run development captures · 2026-11-04

Build 2026110410: real isolated Debug windows for zh-CN/en First-Run Setup, Dashboard and Settings, including credential section. Unmodified pixels; capture bundle IDs recorded in manifest; metadata-only host refresh, no Guest connection or configuration writes. Visual review checked language, clipping, empty secure fields and honest unknown states. Other README images remain historical. Full ten-language human review and live wizard interaction remain NOT_TESTED.

2026-11-05 SSH settings update: only `en/settings*.png` and `zh-CN/settings*.png` were replaced from the actual dirty Debug candidate (base 6dd08fb, build 2026110501). Visible host, port and user fields reviewed in both languages. Other page captures remain from the prior unchanged layouts. No live SSH or interactive save acceptance.

2026-11-05: FX Manager only recaptured in zh-CN/en from the dirty Debug build2026110505 (base1879f33); both installed1.9.9 copies and the local-test marker are visible. No FX, SSH or game action. Other images retain individual provenance.

2026-11-13: Dashboard and First-Run Setup were recaptured in English and Simplified Chinese from clean Debug build 2026110602 at `8c63609`. The real windows show the current launcher entry and FEX review panel. The capture process disabled credential autoload and performed no Guest actions. Other images retain their individual provenance.

2026-11-14 provenance gate update: referenced screenshots require App version, build, capture bundle identifier, timezone-aware capture time and a source commit (per-image or manifest baseline). Missing provenance fails validation. Final v1.0.0 captures remain pending.

2026-11-14 来源门禁更新：README 引用截图必须包含 App 版本、构建号、采集包标识、带时区的时间和来源提交（逐图记录或清单基线）。缺失即校验失败。v1.0.0 正式构建截图仍待采集。

2026-11-14 integration review: seven pages per language were recaptured from the real integration Debug build (08e58e4 plus FEX changes subsequently committed as 34fff90). Correct-language page pairs were reviewed together. No Guest action or credential autoload occurred. Final v1.0.0 Release captures remain pending.

2026-11-14 整合审核：两种语言各七页已从真实整合 Debug 构建重拍（08e58e4 加随后提交为 34fff90 的 FEX 改动），逐对检查语言。未操作 Guest 或自动加载凭据。正式 Release 截图仍待完成。

2026-11-14 LED integration: only the two Dashboard images are presented in README and visually reviewed for language, clipping, sensitive data and honest unknown indicators. Captured from isolated Debug build 2026111401, base 58df1a8 plus the documented LED priority and title sizing edits; no Guest actions or credential autoload. Other page images remain historical and are not presented pending review. Fingerprint applies to the current source for the displayed Dashboard scope only.
