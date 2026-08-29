#!/usr/bin/env bash
#
# CoupleFit 一键推送到 GitHub 并触发云端编译
#
# 用法（在 Git Bash 里执行）：
#   ./push.sh <GitHub用户名> <ghp_开头的令牌>
#
# 令牌获取：https://github.com/settings/tokens
#           Generate new token (classic) → 勾选 repo → Generate
#
# 脚本会依次做：
#   1. 用 GitHub API 创建公开仓库 CoupleFit（已存在则跳过）
#   2. 推送本地提交
#   3. 把 remote URL 里的令牌抹掉，避免明文留在 .git/config
#   4. 打印 Actions 页面链接

set -euo pipefail

USERNAME="${1:-}"
TOKEN="${2:-}"
REPO="CoupleFit"

if [[ -z "$USERNAME" || -z "$TOKEN" ]]; then
    echo "用法: ./push.sh <GitHub用户名> <ghp_开头的令牌>"
    echo ""
    echo "令牌在这里拿: https://github.com/settings/tokens"
    echo "  Generate new token (classic) -> 勾选 repo -> Generate token"
    exit 1
fi

if [[ "$TOKEN" != ghp_* && "$TOKEN" != github_pat_* ]]; then
    echo "令牌格式不太对，应该以 ghp_ 或 github_pat_ 开头"
    echo "注意第二个参数是令牌，不是你的 GitHub 登录密码"
    exit 1
fi

cd "$(dirname "$0")"

echo "==> 1/4 创建 GitHub 仓库 $REPO（Public）"

# 已存在时 GitHub 返回 422，属正常，不视为失败
HTTP_CODE=$(curl -s -o /tmp/cf_repo.json -w "%{http_code}" \
    -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"$REPO\",\"private\":false,\"description\":\"CoupleFit · 情侣运动打卡\"}" \
    https://api.github.com/user/repos)

case "$HTTP_CODE" in
    201) echo "    仓库已创建" ;;
    422) echo "    仓库已存在，继续推送" ;;
    401) echo "    令牌无效或已过期，请重新生成一个"; exit 1 ;;
    *)   echo "    创建失败（HTTP $HTTP_CODE）:"; cat /tmp/cf_repo.json; exit 1 ;;
esac

rm -f /tmp/cf_repo.json

echo "==> 2/4 配置远端地址"
git remote remove origin 2>/dev/null || true
git remote add origin "https://${USERNAME}:${TOKEN}@github.com/${USERNAME}/${REPO}.git"

echo "==> 3/4 推送"
git push -u origin master

echo "==> 4/4 清理凭证"
# 推送完成后把令牌从 remote URL 里摘掉，后续 pull/push 走系统凭据管理
git remote set-url origin "https://github.com/${USERNAME}/${REPO}.git"

echo ""
echo "推送完成。"
echo ""
echo "接下来打开这个链接看云端编译结果（约 15-25 分钟）："
echo "  https://github.com/${USERNAME}/${REPO}/actions"
echo ""
echo "绿色对勾 = 编译通过；红色叉 = 点进去看「汇总编译错误」那一步"
