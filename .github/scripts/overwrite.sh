#!/bin/bash
# A. 获取传入的特定 Commit/分支，未传入则默认使用 main
TARGET_COMMIT="${1:-main}"

# B. 彻底清空当前工作目录（包括隐藏文件和 .git 目录）
find . -mindepth 1 -delete

# C. 手动初始化并拉取特定的 Commit 节点
git init
git remote add origin https://x-access-token:${PAT_FOR_GOODOW_AD_SUBMODULES}@github.com/${MONO_REPO}.git

# 拉取远程所有分支的最近 50 个提交，以确保包含提取出来的短哈希
git fetch --depth 50 origin
git checkout "$TARGET_COMMIT"