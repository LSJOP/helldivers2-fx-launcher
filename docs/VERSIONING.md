# 版本管理 / Versioning

[README](../README.md) · [CHANGELOG](../CHANGELOG.md)

## 简体中文

[`VERSION`](../VERSION) 是唯一版本值来源，当前已确认使用 `0.1.0-preview.1`。采用主版本.次版本.修复版本，可加 `-preview.N`、`-beta.N` 或 `-rc.N` 等预发布标识。当前处于 0.x 技术预览阶段；不把界面设计名称 UI 2.0 当作 v2.0.0。

`launcher_version.py` 读取并验证 VERSION；主界面、使用说明和各类导出报告均调用它。报告使用新增的 `launcher_version` 字段，原有 `version: 1` 格式字段保持原意。文件损坏或缺失显示 `unknown`，不伪造版本或阻止 UI。

README 的版本段落是生成内容。修改 VERSION 后运行：

```sh
python3 tools/update_version.py
python3 tools/update_version.py --check
```

维护者也可使用 `python3 tools/update_version.py --set 0.1.0-preview.2` 同时验证、写入 VERSION 和同步 README。这里的后续版本只是命令示例，不代表计划中的版本已经发布。CHANGELOG 的历史记录由维护者按实际改动补充。

准备未来 GitHub Release 时，先明确要发布的版本及范围，检查 README 同步、CHANGELOG、依赖／许可状态和离线测试，取得维护者确认后再操作 Tag / Release。预发布版本应标为 prerelease；Tag 建议用 `v` 加 VERSION。此工具不会提交、推送、创建 Tag、Release 或自动更新安装器。

## English

[`VERSION`](../VERSION) is the single authoritative version value. The approved initial source-preview identity is `0.1.0-preview.1`, using MAJOR.MINOR.PATCH plus optional prerelease identifiers. UI 2.0 is a design name, not release v2.0.0.

The version module supplies UI, help and exported `launcher_version` metadata while preserving existing report-schema versions. Invalid/missing metadata becomes `unknown`, not a fabricated version or a startup blocker.

README’s version block is generated. After editing VERSION, run `python3 tools/update_version.py` and `--check`, or use `--set` with an explicitly chosen SemVer. CHANGELOG remains a maintainer-reviewed history. Future tags should match `v` plus VERSION, and prereleases should be marked accordingly, only after release review and approval. The tooling performs no commits, pushes, tagging, GitHub publication or automatic updates.

规则参考：[Semantic Versioning](https://semver.org/)。 / Version format reference: [Semantic Versioning](https://semver.org/).
