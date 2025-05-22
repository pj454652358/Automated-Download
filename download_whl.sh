#!/bin/bash
# 下载Windows x64平台WHL包及其依赖的自动化脚本

# 配置区
TARGET_DIR="./offline-packages"    # 下载目录
INPUT_FILE="./requirements.txt"    # 输入文件路径
PYTHON_CMD="python3"              # Python命令路径
PIP_CMD="pip3"                    # Pip命令路径
PLATFORM="win_amd64"              # 目标平台（Windows 64位）

# 动态获取Python版本和ABI标签
PYTHON_VERSION=$($PYTHON_CMD -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')")
ABI_TAG="cp$PYTHON_VERSION"

# 创建下载目录
mkdir -p "$TARGET_DIR"

# 验证输入文件存在
if [ ! -f "$INPUT_FILE" ]; then
    echo "[错误] 输入文件 $INPUT_FILE 不存在"
    exit 1
fi

# 逐行处理WHL名称
while IFS= read -r package || [ -n "$package" ]
do
    if [[ -z "$package" || "$package" == \#* ]]; then
        continue
    fi
    
    echo "▸ 正在处理 $package ..."
    
    # 下载主包及其依赖（强制Windows x64）
    if ! $PIP_CMD download \
        --disable-pip-version-check \
        --platform "$PLATFORM" \
        --python-version "$PYTHON_VERSION" \
        --abi "$ABI_TAG" \
        --only-binary=:all: \
        --dest "$TARGET_DIR" \
        --no-cache-dir \
        --pre \
        --retries 3 \
        --timeout 60 \
        "$package" 2>&1 | grep -v "already satisfied"; then
        
        echo "[警告] $package 下载失败，尝试从Gohlke镜像重试..."
        $PIP_CMD download \
            --disable-pip-version-check \
            --platform "$PLATFORM" \
            --python-version "$PYTHON_VERSION" \
            --abi "$ABI_TAG" \
            --only-binary=:all: \
            --dest "$TARGET_DIR" \
            --no-cache-dir \
            --pre \
            --retries 1 \
            --timeout 30 \
            -i https://download.gohlke.de/python/ \
            "$package"
    fi
done < "$INPUT_FILE"

# 生成依赖清单
echo "生成依赖清单..."
$PIP_CMD freeze > "$TARGET_DIR/dependencies.lock"

echo "全部下载完成！文件保存在：$(realpath $TARGET_DIR)"