#!/bin/bash
# 下载WHL包及其依赖的自动化脚本

# 配置区（按需修改）
TARGET_DIR="./offline-packages"    # 下载目录
INPUT_FILE="./requirements.txt" # 输入文件路径
PYTHON_CMD="python3"           # Python命令路径
PIP_CMD="pip3"                 # Pip命令路径

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
    # 跳过空行和注释行
    if [[ -z "$package" || "$package" == \#* ]]; then
        continue
    fi
    
    echo "▸ 正在处理 $package ..."
    
    # 下载主包及其依赖
    if ! $PIP_CMD download \
        --disable-pip-version-check \
        --dest "$TARGET_DIR" \
        --no-cache-dir \
        --pre \
        --retries 3 \
        --timeout 60 \
        "$package" 2>&1 | grep -v "already satisfied"; then
        
        echo "[警告] $package 下载失败，尝试从备选源下载..."
        # 尝试从阿里云镜像重试
        $PIP_CMD download \
            --disable-pip-version-check \
            --dest "$TARGET_DIR" \
            --no-cache-dir \
            --pre \
            --retries 1 \
            --timeout 30 \
            -i https://mirrors.aliyun.com/pypi/simple/ \
            "$package"
    fi
done < "$INPUT_FILE"

# 生成依赖清单
echo "生成依赖清单..."
$PIP_CMD freeze > "$TARGET_DIR/dependencies.lock"

echo "全部下载完成！文件保存在：$(realpath $TARGET_DIR)"