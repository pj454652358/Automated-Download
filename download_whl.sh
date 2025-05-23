#!/bin/bash

# 设置输出目录
OUTPUT_DIR="offline-packages"
mkdir -p "$OUTPUT_DIR"

# 检查 requirements.txt 是否存在
if [ ! -f "requirements.txt" ]; then
  echo "requirements.txt 不存在"
  exit 1
fi

# 逐行读取 requirements.txt
while IFS= read -r package; do
  if [ -n "$package" ]; then
    # 提取包名（去掉版本号）
    pkg_name=$(echo "$package" | cut -d'=' -f1)
    echo "处理包: $pkg_name"
    
    # 跳过 pip 包
    if [ "$pkg_name" = "pip" ]; then
      echo "跳过 pip 包"
      continue
    fi
    
    # 生成依赖树，排除 conda 和 conda-libmamba-solver
    pipdeptree -r -p "$pkg_name" | grep -v -E "conda|libmamba" > temp_deps.txt 2>/dev/null
    
    # 检查依赖树是否生成
    if [ ! -s temp_deps.txt ]; then
      echo "无法生成 $pkg_name 的依赖树，跳过"
      continue
    fi
    
    # 下载包及其依赖，适配 Windows 64 位和 Python 3.12.3
    pip download -r temp_deps.txt -d "$OUTPUT_DIR" --only-binary=:all: --platform win_amd64 --python-version 3.12.3
    
    # 验证下载
    if [ $? -eq 0 ]; then
      echo "$pkg_name 及其依赖已下载到 $OUTPUT_DIR"
    else
      echo "$pkg_name 下载失败"
    fi
    
    # 清理临时文件
    rm temp_deps.txt
  fi
done < requirements.txt

echo "所有包下载完成，保存在 $OUTPUT_DIR"