# 上传 GitHub 与重新打包

## 上传内容

解压 `frontier-toolkit-*.zip` 后，进入其中含 `project.godot` 的目录。**这个目录就是仓库根目录**。不要再把整个目录嵌套上传为 GitHub 仓库内的一层，否则根目录操作会多一层。

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

已有仓库应按现有分支策略合入，不要重复 git init 或改写历史。GitHub 网页也可上传文件，但 Git 推送更容易完整保留隐藏文件和目录层级。打包本身不会创建远程仓库或自动推送。

仓库 Actions 包含纯 Node 编辑器检查。完整 Godot 和图形测试按 [首次运行](GETTING_STARTED.md) 本地执行。

## 再次生成发布包

在工作区根目录运行 PowerShell 7：

```powershell
./tools/Build-GitHub-Package.ps1
```

需要 Node.js 用于引用检查。脚本按白名单复制模块和必要文档到 `dist/frontier-toolkit-时间戳/`，生成同名 ZIP 和 `.zip.sha256`。可以传 `-Name frontier-toolkit-v1`，目标存在时会停止，不覆盖旧包。

白名单包含三个模块、integration、docs、tools、根配置与 .github；排除 `.godot`、`.tools`、`.git`、Node 依赖、临时文件、日志、Godot 生成的 `.import` 和测试运行 JSON。保留脚本 `.uid`、必要资源、地编工作集、转换示例以及已有渲染截图。测试结果 JSON 可执行测试重新生成。

`PACKAGE_MANIFEST.json` 列出包内每个文件的相对路径、字节数和 SHA-256（不包含清单自身），用于交接核对。包外 `.sha256` 用于检查整个 ZIP。

## 新克隆验收

```sh
node tools/Verify-Package.cjs
node editor/tests/model.test.cjs
node editor/tools/Validate-Level.cjs editor/examples/Frontier.mapproject.json
```

安装 Godot，执行资源导入和三个模块测试。确认 F5 大地图、F6 2.5D、城镇悬浮进入/返回、编辑器保存重开和转换输出均可使用。原生图形测试需要图形环境。
