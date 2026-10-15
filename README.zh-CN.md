# uYasoo: ASP 微博

<p align="center" id="uyasoo-top">
  <img src="assets/uyasoo-logo.png" alt="uYasoo" width="500">
</p>
<p align="center">
  <a href="https://github.com/asp-lang/openasp"><img src="assets/badge-runtime.png" alt="运行时：OpenASP 0.1.0" height="20"></a>
  <a href="https://spdx.org/licenses/MIT.html"><img src="assets/badge-license.png" alt="许可证：MIT" height="20"></a>
  <a href="#环境要求"><img src="assets/badge-storage.png" alt="存储：Redis" height="20"></a>
  <a href="#环境要求"><img src="assets/badge-platforms.png" alt="平台：Linux、MacOS 和 Unix" height="20"></a>
</p>
<p align="center">
  <a href="https://uyasoo.com">在线示例</a> |
  <a href="#系统架构">系统架构</a> |
  <a href="#环境要求">环境要求</a> |
  <a href="#1-安装系统依赖">安装</a> |
  <a href="#4-启动应用">启动</a> |
  <a href="https://asp-lang.org">OpenASP</a> |
  <a href="README.md">English</a>
</p>

线上示例：[https://uyasoo.com](https://uyasoo.com)。

uYasoo 是一个基于 [OpenASP](https://github.com/asp-lang/openasp) 构建的完整 Classic ASP 微博项目。它使用 Redis 存储应用数据、Session、持久登录令牌和图片缓存，并通过 `openasp-fpm` 接入 Nginx。

本项目包含注册与登录、用户资料、关注关系、个人时间线、话题、微博、评论、点赞、搜索、图片上传、机器人配置、AJAX 更新、分页，以及无 JavaScript 环境下的普通表单回退流程。

## 系统架构

```text
浏览器 -> Nginx :18081 -> FastCGI -> openasp-fpm :19000
                                      |
                                      +-> Redis :6379，数据库 9
                                      +-> assets/uploads/
                                      +-> .run/openasp-cache/
```

项目附带的 [`nginx.conf`](nginx.conf) 是自包含配置，使用项目内的 [`nginx/mime.types`](nginx/mime.types) 和 [`nginx/fastcgi_params`](nginx/fastcgi_params)。它不依赖 Homebrew 或特定 Linux 发行版的 Nginx 配置目录。

## 环境要求

| 依赖 | 用途 |
| --- | --- |
| OpenASP 0.1.0 完整构建 | Classic ASP 运行时、FastCGI、Redis、Crypto、Stream 和文件系统组件 |
| Redis | 应用数据存储，默认使用数据库 `9` |
| Nginx | 静态文件服务和 FastCGI 反向代理 |
| `curl` | 启动验证 |
| Python 3 | 可选的仓库工具 |

本项目使用 `OpenASP.Redis`、`OpenASP.Crypto`、`ADODB.Stream` 和 `Scripting.FileSystemObject`，因此必须使用 OpenASP 的**完整**构建。不要使用 `make minimal`。

OpenASP 0.1.0 为以下平台提供官方二进制发行包：

- Linux x86-64
- MacOS Apple Silicon

其他系统必须从源码编译 OpenASP。

## 1. 安装系统依赖

### MacOS

安装 Xcode 命令行工具和 Homebrew 软件包：

```sh
xcode-select --install
brew install nginx redis pkg-config pcre2 libxml2 curl sqlite json-c openssl@3 \
    mariadb-connector-c mdbtools
brew services start redis
```

如果已经安装 Xcode 命令行工具，`xcode-select --install` 会提示
无需安装。

### Ubuntu 24.04

```sh
sudo apt-get update
sudo apt-get install -y \
    nginx redis-server python3 curl git \
    build-essential pkg-config \
    libpcre2-dev libxml2-dev libcurl4-openssl-dev libsqlite3-dev \
    libjson-c-dev libssl-dev libmariadb-dev mdbtools-dev \
    libglib2.0-dev gettext
sudo systemctl enable --now redis-server
```

验证 Redis：

```sh
redis-cli ping
```

预期响应为 `PONG`。

## 2. 安装 OpenASP

如需了解 OpenASP 的更多信息，请访问其官方主页：[https://asp-lang.org](https://asp-lang.org)。

### 方案 A：从源码编译完整运行时

这是可移植性最好的安装方式，可以确保 OpenASP 链接当前机器上安装的依赖库：

```sh
git clone --depth 1 https://github.com/asp-lang/openasp.git
cd openasp
make clean
make all
make test
export OPENASP_HOME="$PWD"
export PATH="$OPENASP_HOME/build/bin:$PATH"
```

`make all` 会将以下程序写入 `build/bin/`：

- `openasp`
- `openasp-fpm`
- `openasp-cli`
- `openasp-dis`
- `openasp-dbg`

如需在新终端中继续使用，请将 `PATH` 导出配置加入 shell 配置文件。

### 方案 B：使用官方 0.1.0 发行包

发行文件发布在 [OpenASP Releases](https://github.com/asp-lang/openasp/releases/tag/v-0.1.0) 页面。

Linux x86-64：

```sh
mkdir -p "$HOME/.local/opt"
curl -fL \
    https://github.com/asp-lang/openasp/releases/download/v-0.1.0/openasp-0.1.0-linux-x86-64.tar.gz \
    -o /tmp/openasp-0.1.0-linux-x86-64.tar.gz
tar -xzf /tmp/openasp-0.1.0-linux-x86-64.tar.gz -C "$HOME/.local/opt"
export PATH="$HOME/.local/opt/openasp-0.1.0-linux-x86-64/bin:$PATH"
```

MacOS Apple Silicon：

```sh
mkdir -p "$HOME/.local/opt"
curl -fL \
    https://github.com/asp-lang/openasp/releases/download/v-0.1.0/openasp-0.1.0-macos-arm64.zip \
    -o /tmp/openasp-0.1.0-macos-arm64.zip
unzip -q /tmp/openasp-0.1.0-macos-arm64.zip -d "$HOME/.local/opt"
export PATH="$HOME/.local/opt/openasp-0.1.0-macos-arm64/bin:$PATH"
```

验证任一安装方式：

```sh
openasp --help
openasp-fpm --help
```

如果发行版二进制文件提示缺少动态链接库，请安装加载器指出的依赖，或改用上面的源码构建方式。

## 3. 准备应用

后续所有命令均从 `uyasoo-microblog` 目录执行：

```sh
cd uyasoo-microblog
mkdir -p .run/openasp-cache assets/uploads
chmod u+rwx .run .run/openasp-cache assets/uploads
redis-cli -n 9 ping
nginx -t -p "$PWD/" -c nginx.conf
```

继续操作前，以上两项检查都必须成功。

默认应用配置位于 [`config.asp`](config.asp)：

| 配置 | 默认值 | 含义 |
| --- | --- | --- |
| `REDIS_CONNECTION` | loopback、端口 `6379`、数据库 `9` | Redis 连接 |
| `REDIS_PREFIX` | `openasp:microblog:` | 应用键的命名空间 |
| `FEED_PAGE_SIZE` | `10` | 每页加载的微博数量 |
| `MAX_AVATAR_BYTES` | `1 MiB` | 头像上传限制 |
| `MAX_POST_IMAGE_BYTES` | `5 MiB` | 微博图片上传限制 |

如果 Redis 需要身份验证或使用其他端点，请修改 `REDIS_CONNECTION`。OpenASP 接受包含 `Host`、`Port`、`Username`、`Password`、`Database` 和 `Timeout` 的连接字符串。

## 4. 启动应用

### 终端 1：OpenASP FastCGI

从应用目录执行：

```sh
openasp-fpm \
    --root "$PWD" \
    --host 127.0.0.1 \
    --port 19000 \
    --workers 2 \
    --max-requests 10000 \
    --memory-limit 128M \
    --opcache-memory 64 \
    --opcache-dir "$PWD/.run/openasp-cache" \
    --opcache-validate-timestamps=on \
    --log-file stderr \
    --log-level info \
    --shell-enable=off \
    --process-enable=off
```

保持该终端运行。启动成功时会报告 FastCGI 正在监听 `127.0.0.1:19000`。

OpenASP 同时使用 opcache 目录保存持久化 Session 和
Application 状态，因此 FPM 运行账户必须始终拥有该目录的写权限。

### 终端 2：Nginx

```sh
cd uyasoo-microblog
nginx -p "$PWD/" -c nginx.conf
```

在浏览器中打开 <http://127.0.0.1:18081/>。

## 5. 验证部署

```sh
curl -fsS http://127.0.0.1:18081/ >/dev/null
curl -I http://127.0.0.1:18081/assets/app.css
redis-cli -n 9 ping
```

预期结果：

- 第一条命令以状态 `0` 退出；
- CSS 请求返回 `HTTP/1.1 200 OK`；
- Redis 返回 `PONG`。

在浏览器中创建两个账户，并验证发布、关注、评论和图片上传，以覆盖完整数据链路。

仓库中的历史脚本 `tests/test_microblog.py` 使用旧版 OpenASP 独立测试运行协议。它不是 OpenASP 0.1.0 的部署入口。当前版本请使用上面的 FastCGI 和 HTTP 检查。

## 停止应用

从应用目录停止 Nginx：

```sh
nginx -p "$PWD/" -c nginx.conf -s stop
```

在终端 1 中按 `Ctrl+C` 停止 `openasp-fpm`。

## 数据与运行文件

| 路径或键空间 | 内容 |
| --- | --- |
| Redis 数据库 `9` | 用户、微博、关系、令牌和图片缓存 |
| `assets/uploads/` | 上传的图片文件 |
| `.run/openasp-cache/` | OpenASP 字节码缓存和持久化 ASP 状态 |
| `.run/uyasoo-microblog-nginx-*.log` | 本地 Nginx 日志 |

如需重置本地开发数据，请先停止两个服务，然后执行：

```sh
redis-cli -n 9 FLUSHDB
rm -rf .run/openasp-cache
find assets/uploads -type f ! -name .gitignore -delete
mkdir -p .run/openasp-cache
```

`FLUSHDB` 会永久删除 Redis 数据库 `9` 中的所有键。如果该数据库与其他应用共享，请勿执行。

## 故障排查

### `openasp-fpm: command not found`

确认完整 OpenASP 二进制目录已加入 `PATH`：

```sh
command -v openasp-fpm
openasp-fpm --help
```

使用源码构建时，可执行文件位于 OpenASP 仓库内的 `build/bin/openasp-fpm`。

### Nginx 报告 `502 Bad Gateway`

FastCGI 进程无法访问。检查终端 1 并确认端口：

```sh
lsof -nP -iTCP:19000 -sTCP:LISTEN
```

如果 Linux 上没有 `lsof`，请使用 `ss -ltnp | grep 19000`。

### Redis 连接错误

```sh
redis-cli -h 127.0.0.1 -p 6379 -n 9 ping
```

检查 [`config.asp`](config.asp) 是否使用相同的主机、端口、凭据和数据库。

### 上传失败

确保 FPM 账户可以写入两个运行目录：

```sh
test -w assets/uploads
test -w .run/openasp-cache
```

Nginx 将完整请求体限制为 `6 MiB`；应用另外将头像限制为 `1 MiB`，微博图片限制为 `5 MiB`。

### Nginx 启动失败

```sh
nginx -t -p "$PWD/" -c nginx.conf
cat .run/uyasoo-microblog-nginx-error.log
```

检查端口 `18081` 和 `19000` 是否已被占用。

## 生产环境注意事项

附带配置用于 loopback 开发环境。生产环境应：

- 使用非特权服务账户运行 Nginx 和 `openasp-fpm`；
- 保持 FastCGI 监听 loopback，或使用 OpenASP Unix socket；
- 仅向上传、状态、缓存和日志目录授予写权限；
- 使用 systemd、launchd 或其他服务管理器守护 `openasp-fpm`；
- 在 Nginx 终止 TLS，并显式设置公网主机名；
- 保持 `shell-enable` 和 `process-enable` 关闭；
- 开发期间保持时间戳校验开启；不可变部署中可以关闭，但
  每次部署都必须重启所有 worker；
- 不要提交 Redis 密码、机器人 API Key 或其他生产机密；
- 同时备份 Redis 和 `assets/uploads/`。

FPM 的 `--root` 和 Nginx 的 `root` 必须解析到同一个物理应用目录。

## 安全行为

- 修改状态的表单使用 Session 级 CSRF token。
- 密码使用随机盐和多轮 SHA-256，以保持可移植性。生产部署应提供 Argon2id 或 scrypt 等原生密码哈希。
- 持久登录 Cookie 包含随机令牌；Redis 仅保存令牌哈希。
- 用户内容在渲染前进行 HTML 转义。
- 上传文件受到大小限制，并通过文件签名验证。
- Nginx 阻止直接访问内部 ASP include、测试和上传文件；
  图片通过经过验证的 `image.asp` 端点提供。
- 外部微博链接必须使用 `http://` 或 `https://`，并设置
  `noopener noreferrer`。
- OpenASP 进程和 Shell 组件保持禁用。

## OpenASP 参考资料

- [OpenASP 仓库](https://github.com/asp-lang/openasp)
- [OpenASP 0.1.0 发行版](https://github.com/asp-lang/openasp/releases/tag/v-0.1.0)
- [官方构建说明](https://github.com/asp-lang/openasp#build-from-source)
- [官方 Nginx 部署指南](https://github.com/asp-lang/openasp#deploy-with-nginx)
