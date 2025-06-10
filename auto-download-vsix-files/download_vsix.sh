#!/bin/bash

# 检查命令行参数
if [ $# -lt 1 ]; then
    echo "用法: $0 <plugin_name> [version]"
    exit 1
fi

# 获取插件名和版本号（如果提供）
plugin_keyword="$1"
specified_version="$2"

echo "正在搜索插件: $plugin_keyword"

post_data=$(jq -n \
  --arg keyword "$plugin_keyword" \
  '{"filters":[{"criteria":[{"filterType":8,"value":"Microsoft.VisualStudio.Code"},{"filterType":10,"value":$keyword}],"pageNumber":1,"pageSize":1}]}')

# API请求获取插件信息
api_response=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$post_data" \
  "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery")

# 解析插件ID
publisher=$(echo "$api_response" | jq -r '.results[0].extensions[0].publisher.publisherName')
extension=$(echo "$api_response" | jq -r '.results[0].extensions[0].extensionName')

if [ "$publisher" == "null" ] || [ -z "$extension" ]; then
  echo "未找到相关插件"
  exit 2
fi

# 获取版本号
if [ -n "$specified_version" ]; then
    version="$specified_version"
else
    version=$(echo "$api_response" | jq -r '.results[0].extensions[0].versions[0].version')
fi

echo -e "\n获取成功:"
echo "版本: $version"
echo "发布者: $publisher"
echo "插件名: $extension"

# 构造下载URL（extension转小写）
extension_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
download_url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${extension_lower}/${version}/vspackage"
echo -e "\n下载链接:"
echo "$download_url"

# 创建下载目录
download_dir="vscode-offline-vsix"
mkdir -p "$download_dir"

# 构造保存的文件名
vsix_file="${download_dir}/${publisher}.${extension}-${version}.vsix"

# 获取预期文件大小
expected_size=$(wget --user-agent="Mozilla/5.0" --spider --server-response "$download_url" 2>&1 | awk '/Content-Length/ {print $2}' | tail -1)
if [[ ! "$expected_size" =~ ^[0-9]+$ ]]; then
    expected_size=0
fi

# 下载vsix文件前先判断是否已存在
if [ -f "$vsix_file" ] || ls "${vsix_file}.part_"* 1>/dev/null 2>&1; then
    echo "已存在: $vsix_file 或分卷文件，跳过下载。"
else
    max_retry=3
    retry_count=0
    success=0
    while [ $retry_count -lt $max_retry ]; do
        echo -e "\n第 $((retry_count+1)) 次尝试下载vsix文件..."
        wget --user-agent="Mozilla/5.0" --tries=10 --timeout=30 --waitretry=2 -c -O "$vsix_file" "$download_url"
        # 检查是否为HTML错误页或下载不完整
        if file "$vsix_file" | grep -qi html || [ $(stat -c%s "$vsix_file") -lt 10240 ]; then
            echo "下载失败，返回的是网页或文件过小，可能不是vsix文件，请检查下载链接和参数"
            rm -f "$vsix_file"
            retry_count=$((retry_count+1))
            sleep 2
            continue
        fi
        file_size=$(stat -c%s "$vsix_file")
        if [ "$expected_size" -gt 0 ]; then
            min_size=$((expected_size * 99 / 100))
            if [ "$file_size" -ge "$min_size" ]; then
                success=1
                break
            else
                echo "下载文件过小（$file_size 字节），可能未下载完整，重试..."
                rm -f "$vsix_file"
                retry_count=$((retry_count+1))
                sleep 2
            fi
        else
            # 如果无法获取 expected_size，保留原有10MB判断
            if [ "$file_size" -ge $((10*1024*1024)) ]; then
                success=1
                break
            else
                echo "下载文件过小（$file_size 字节），可能未下载完整，重试..."
                rm -f "$vsix_file"
                retry_count=$((retry_count+1))
                sleep 2
            fi
        fi
    done
    if [ $success -ne 1 ]; then
        echo "多次尝试后仍未成功下载完整文件，请检查网络或稍后重试。"
        exit 9
    fi
    echo "下载成功，文件保存在: $vsix_file"
    # 检查文件大小是否超过100MB
    max_size=$((100*1024*1024))
    if [ "$file_size" -gt "$max_size" ]; then
        echo "文件大于100MB，正在分卷压缩..."
        split -b 99m "$vsix_file" "${vsix_file}.part_"
        echo "分卷完成，生成文件："
        ls -lh "${vsix_file}.part_"*
        echo "上传到GitHub时请上传所有分卷。下载后可用如下命令合并："
        echo "cat ${vsix_file}.part_* > ${vsix_file}"
        # 删除原始大文件
        rm -f "$vsix_file"
        echo "已删除原始大文件: $vsix_file"
    fi
fi