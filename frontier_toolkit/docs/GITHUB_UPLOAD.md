# 上传 GitHub 与重新打包

## 上传内容

解压 `supremepoor-toolkit-*.zip` 后，外层含 README、BUILD、.github 和 `frontier_toolkit/` 的目录是仓库根。Godot 宿主入口为 `frontier_toolkit/project.godot`。上传这一层文件树，不要再嵌套成 frontier_toolkit/frontier_toolkit。

保留隐藏文件 `.gitignore`、`.gitattributes` 和 `.github/`。上传文件树中的源码、素材、示例与文档；不要上传整个 ZIP 来替代源码文件树。

## 用 Git 推送

在 GitHub 新建空仓库，再在解压目录执行（URL 换为自己的仓库）：

```sh
git init
git add .
git status --short
git commit -m "Initial import: world map, 2.5D scenes and map editor"
git branch -M main
git remote add origin https://github.com/YOUR_ACCOUNT/YOUR_REPOSITORY.git
git push -u origin main
```

合回 SupremePoorGuy 时，包内 frontier_toolkit 对应仓库同名目录；保留现有 it-is-time。根 README、BUILD、CI、忽略和换行规则需要与已有内容合并。外层 docs/INTEGRATING_IN_SUPREMEPOORGUY.md 给出逐项映射。已有仓库不要重复 git init 或改写历史；打包不自动推送。

根 Actions 检查交付结构、三个工程的静态引用、协议和编辑器模型；工作目录设置为 frontier_toolkit。Godot 和图形测试按 [BUILD](../BUILD.md) 本地执行。

## 再次生成发布包

在工作区根目录运行 PowerShell 7：

```powershell
./tools/Build-GitHub-Package.ps1
```

需要 Node.js。脚本读取 tools/github-package.config.json，将工具集、两版独立 UI、TA、来源/需求/文档复制到 `dist/<Name>/frontier_toolkit/`，再由 tools/github_repository 模板生成仓库外层，输出同名 ZIP 和 `.zip.sha256`。可以传 `-Name supremepoor-toolkit-v2`；目标存在时停止，不覆盖旧包。

排除 `.godot/.tools/.git/.runtime`、Node 依赖、引擎、历史压缩包、本机录屏、临时文件、日志、测试存档及备份。两个上游来源清单跟踪的 `.import` 元信息与原有小型 MP4 预览保留并校验，其他本机生成 .import 排除。保留 UID、必要素材、字体授权、关卡源文件、转换示例、截图和 docs 中的历史验证快照。

仓库根 PACKAGE_MANIFEST.json 列出交付文件路径、字节数和 SHA-256（不含清单自身），RELEASE_CONTENTS.json 记录来源和布局。包外 .sha256 检查 ZIP；首次解压加 --manifest 校验原始字节。Git 换行或 Godot 导入后使用普通源码检查，清单保留为原始交付记录。

## 新克隆验收

```sh
node frontier_toolkit/tools/Verify-GitHub-Repository.cjs .
cd frontier_toolkit
node tools/Verify-Package.cjs
node tools/Verify-Battle-Integration-Docs.cjs --contracts-only
node editor/tests/model.test.cjs
node editor/tools/Validate-Level.cjs editor/examples/Frontier.mapproject.json
```

安装 Godot，导入工具集宿主与新版 UI 两个开发工程并执行对应测试。确认 F5 带 UI 地图、F6 2.5D、城镇返回、两套 Shader 独立场景和地编转换可用。图形测试需要 GPU。边界与扩展步骤见 [整合指南](INTEGRATION_AND_EXTENSION.md) 和 [交付范围](RELEASE_CONTENTS.md)。
