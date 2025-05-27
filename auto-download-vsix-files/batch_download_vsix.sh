#!/bin/bash

# 检查参数
if [ ! -f "vscode_extensions.txt" ]; then
    echo "错误: 未找到 vscode_extensions.txt 文件"
    exit 1
fi

# 确保download_vsix.sh有执行权限
chmod +x download_vsix.sh

# 读取配置文件并处理每一行
while IFS= read -r line || [[ -n "$line" ]]; do
    # 跳过空行和注释
    [[ -z "${line// }" || "${line:0:1}" == "#" ]] && continue
    
    # 解析插件名和版本号
    read -r plugin_name version <<< "$line"
    
    echo -e "\n=========================================="
    echo "开始处理插件: $plugin_name"
    if [ -n "$version" ]; then
        echo "指定版本: $version"
    else
        echo "使用最新版本"
    fi
    echo "==========================================\n"
    
    # 调用下载脚本
    if [ -n "$version" ]; then
        # 如果指定了版本号，传递版本参数
        ./download_vsix.sh "$plugin_name" "$version"
    else
        # 未指定版本号，使用最新版本
        ./download_vsix.sh "$plugin_name"
    fi
    
    # 检查上一个命令的退出状态
    if [ $? -ne 0 ]; then
        echo "警告: $plugin_name 下载失败"
    fi
    
    # 等待一下，避免请求过快
    sleep 2
    
done < "vscode_extensions.txt"

echo -e "\n所有插件处理完成！"
