#!/usr/bin/env bash
# 把各镜像的 :latest 移到 mono main 上**最新的、全部镜像都已推了 sha-<提交> 的**那个提交。
#   用法: promote_latest.sh <mono 的 git 目录 (要有 origin/main 的历史)> <registry 前缀> <镜像名...>
#   第一个镜像是锚: 读它 :latest 的 org.opencontainers.image.revision 得出 latest 现在在哪个提交。
#
# 为什么不是"本次 run 建完就推 :latest": 连着合并两个提交时两个 run 并行, 先合并的那个后建完, 就把 :latest 拉回旧提交
# (2026-10 的构建一次 10 分钟到 2 小时不等)。这里不看本次 run 建的是谁, 只看 registry 里已经有了什么:
#   - 从 main 的头往回走 (--first-parent), 走到 latest 现在的提交为止, 第一个齐了的就是目标 —— latest 只会往前走;
#   - 比目标新、还在建的提交, 由它们自己 run 的这一步再推一次。
# 调用方 (dockerimage.yml 的 promote-latest job) 用 concurrency 把这一步排成串行: 并发的两次各自读、各自写,
# 先读的那次可能后写, 又会把 latest 拉回去。concurrency 会取消排队中较早的那次, 无妨 —— 后排的那次读到的只会更多。
set -euo pipefail
repo=$1 registry=$2
shift 2
images=("$@")
anchor=$registry/${images[0]}

has_all() {   # <提交>: 每个镜像都有 sha-<提交>
    local i
    for i in "${images[@]}"; do
        docker buildx imagetools inspect "$registry/$i:sha-$1" >/dev/null 2>&1 || return 1
    done
}

label=$(docker buildx imagetools inspect "$anchor:latest" \
    --format '{{index .Image.Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null || true)
# 旧 run 写的是短哈希 (取自触发提交的说明), 展开成完整 sha 才能与 rev-list 比; 展不开 (不在拉到的历史里) 就一路走到底
current=$(git -C "$repo" rev-parse -q --verify "${label:-none}^{commit}" 2>/dev/null || true)
echo "当前 $anchor:latest -> ${current:-未知 (revision 标签: ${label:-无})}"

target=
for c in $(git -C "$repo" rev-list --first-parent --max-count=50 origin/main); do
    [ "$c" != "$current" ] || break
    if has_all "$c"; then target=$c; break; fi
    echo "  $c 还没有全部镜像 (在建、建挂了或没触发), 往回看"
done

if [ -z "$target" ]; then
    echo "latest 不动: main 上比它新的提交还没有哪个全部建完 (在建的那些建完时各自再走这一步)"
    rev=$current
else
    for i in "${images[@]}"; do
        docker buildx imagetools create --tag "$registry/$i:latest" "$registry/$i:sha-$target"
    done
    echo "latest -> $target (${images[*]})"
    rev=$target
fi
[ -z "${GITHUB_OUTPUT:-}" ] || echo "revision=$rev" >> "$GITHUB_OUTPUT"
