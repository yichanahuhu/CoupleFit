#!/usr/bin/env bash
#
# CoupleFit 一键推送到 GitHub 并触发云端编译
#
# ============ 推荐用法（全自动，不用手动复制令牌）============
#
#   ./push.sh
#
#   脚本会自动：装 GitHub CLI → 打开浏览器让你点一下授权 → 建仓库 → 推送
#   你只需要在浏览器里登录 GitHub 并点一次「Authorize」
#
# ============ 后备用法（手动令牌）============
#
#   ./push.sh <GitHub用户名> <ghp_开头的令牌>
#
#   令牌获取：https://github.com/settings/tokens
#             Generate new token (classic) → 勾选 repo

set -euo pipefail

REPO="CoupleFit"
cd "$(dirname "$0")"

# ---------------------------------------------------------------
# 后备模式：手动提供令牌
# ---------------------------------------------------------------
if [[ $# -ge 2 ]]; then
    USERNAME="$1"
    TOKEN="$2"

    if [[ "$TOKEN" != ghp_* && "$TOKEN" != github_pat_* ]]; then
        echo "令牌格式不对，应以 ghp_ 或 github_pat_ 开头"
        echo "注意第二个参数是令牌，不是 GitHub 登录密码"
        exit 1
    fi

    echo "==> 1/4 创建 GitHub 仓库 $REPO（Public）"
    HTTP_CODE=$(curl -s -o /tmp/cf_repo.json -w "%{http_code}" \
        -X POST \
        -H "Authorization: token $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -d "{\"name\":\"$REPO\",\"private\":false,\"description\":\"CoupleFit · 情侣运动打卡\"}" \
        https://api.github.com/user/repos)

    case "$HTTP_CODE" in
        201) echo "    仓库已创建" ;;
        422) echo "    仓库已存在，继续推送" ;;
        401) echo "    令牌无效或已过期"; exit 1 ;;
        *)   echo "    创建失败（HTTP $HTTP_CODE）:"; cat /tmp/cf_repo.json; exit 1 ;;
    esac
    rm -f /tmp/cf_repo.json

    echo "==> 2/4 配置远端地址"
    git remote remove origin 2>/dev/null || true
    git remote add origin "https://${USERNAME}:${TOKEN}@github.com/${USERNAME}/${REPO}.git"

    echo "==> 3/4 推送"
    git push -u origin master

    echo "==> 4/4 清理凭证"
    git remote set-url origin "https://github.com/${USERNAME}/${REPO}.git"

    echo ""
    echo "完成。编译结果看这里（约 15-25 分钟）："
    echo "  https://github.com/${USERNAME}/${REPO}/actions"
    exit 0
fi

# ---------------------------------------------------------------
# 自动模式：GitHub CLI
# ---------------------------------------------------------------
echo "CoupleFit 一键推送"
echo "=================="
echo ""

# 1. 找 gh
find_gh() {
    if command -v gh >/dev/null 2>&1; then echo "gh"; return 0; fi
    local candidates=(
        "/c/Program Files/GitHub CLI/gh.exe"
        "/c/Program Files (x86)/GitHub CLI/gh.exe"
        "$LOCALAPPDATA/Programs/GitHub CLI/gh.exe"
        "$LOCALAPPDATA/GitHub CLI/gh.exe"
    )
    for p in "${candidates[@]}"; do
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done
    return 1
}

GH="$(find_gh || true)"

# 2. 没有就装
if [[ -z "$GH" ]]; then
    echo "==> GitHub CLI 未安装，正在安装"
    WINGET=""
    for p in "$LOCALAPPDATA/Microsoft/WindowsApps/winget.exe" \
             "/c/Program Files/WindowsApps/Microsoft.DesktopAppInstaller_1.29.290.0_x64__8wekyb3d8bbwe/winget.exe"; do
        [[ -f "$p" ]] && { WINGET="$p"; break; }
    done

    if [[ -z "$WINGET" ]]; then
        echo ""
        echo "没找到 winget，无法自动安装。两个选择："
        echo "  A. 手动装 GitHub CLI：https://cli.github.com  然后重跑本脚本"
        echo "  B. 改用手令牌模式：./push.sh <用户名> <ghp_令牌>"
        exit 1
    fi

    echo "    使用 winget: $WINGET"
    "$WINGET" install --id GitHub.cli --accept-package-agreements --accept-source-agreements

    # 装完重新找
    GH="$(find_gh || true)"
    if [[ -z "$GH" ]]; then
        echo ""
        echo "装完了但在 PATH 里找不到。重新打开一个 Git Bash 窗口再跑一次本脚本。"
        exit 1
    fi
fi

echo "==> GitHub CLI: $GH"
export PATH="$(dirname "$GH"):$PATH"

# 3. 登录
if ! "$GH" auth status >/dev/null 2>&1; then
    echo ""
    echo "==> 需要授权一次"
    echo "    接下来会显示一个 8 位代码，并在浏览器打开 GitHub 授权页"
    echo "    把代码填进去，点 Authorize，就完事了"
    echo ""
    read -r -p "    按回车继续..."
    "$GH" auth login --web --git-protocol https
fi

GH_USER="$("$GH" api user --jq '.login')"
echo "==> 已登录为: $GH_USER"

# 4. 建仓库并推送（已存在时 gh 会复用远端）
echo "==> 创建仓库并推送"
if "$GH" repo view "$REPO" >/dev/null 2>&1; then
    echo "    仓库已存在"
    if git remote get-url origin >/dev/null 2>&1; then
        git push -u origin master
    else
        "$GH" repo create "$REPO" --public --source=. --remote=origin --push
    fi
else
    "$GH" repo create "$REPO" --public --source=. --remote=origin --push
fi

ACTIONS_URL="$("$GH" repo view "$REPO" --json url --jq '.url')/actions"

echo ""
echo "=================="
echo "推送完成。"
echo ""

read -r -p "是否现在就盯着编译结果？大约 15-25 分钟 [Y/n] " WATCH
WATCH="${WATCH:-Y}"

if [[ "$WATCH" != "y" && "$WATCH" != "Y" ]]; then
    echo ""
    echo "随时用下面这条命令接着看："
    echo "  gh run watch"
    echo ""
    echo "或直接打开：$ACTIONS_URL"
    exit 0
fi

echo ""
echo "==> 等待 CI 启动"
RUN_ID=""
for _ in $(seq 1 36); do
    RUN_ID="$("$GH" run list --workflow=ios-build.yml --limit 1 \
              --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
    [[ -n "$RUN_ID" ]] && break
    sleep 5
done

if [[ -z "$RUN_ID" ]]; then
    echo "    三分钟了还没看到运行，可能没触发。手动打开看看：$ACTIONS_URL"
    exit 1
fi

echo "==> 运行中（#${RUN_ID}），开始盯进度"
echo "    （随时 Ctrl+C 中断，之后用 gh run watch 接着看）"
if "$GH" run watch "$RUN_ID"; then
    echo ""
    echo "=================="
    echo "编译通过。"
    echo "下一步：在 Actions 里手动 Run workflow 并勾选 build_ipa，就能拿到可安装的 ipa。"
else
    echo ""
    echo "=================="
    echo "编译失败。把上面的报错复制给我，我直接改。"
    echo "完整日志：$ACTIONS_URL"
    exit 1
fi
