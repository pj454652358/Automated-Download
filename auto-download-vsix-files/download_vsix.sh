#!/bin/bash

# 检查命令行参数
if [ $# -lt 1 ]; then
    echo "用法: $0 <plugin_name> [version]"
    exit 1
fi

# 获取插件名和版本号（如果提供）
plugin_keyword="$1"
specified_version="$2"

# API请求获取插件信息
api_response=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{"filters":[{"criteria":[{"filterType":8,"value":"Microsoft.VisualStudio.Code"},{"filterType":10,"value":"'$plugin_keyword'"}],"pageNumber":1,"pageSize":1}]}' \
  "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery")

# 解析插件ID
publisher=$(echo "$api_response" | jq -r '.results[0].extensions[0].publisher.publisherName')
extension=$(echo "$api_response" | jq -r '.results[0].extensions[0].extensionName')

if [ "$publisher" == "null" ] || [ -z "$extension" ]; then
  echo "未找到相关插件"
  exit 2
fi

# 构造详情页URL
detail_url="https://marketplace.visualstudio.com/items?itemName=${publisher}.${extension}"
echo "正在获取: $detail_url"

# 用curl请求网页并保存到变量
page_content=$(curl -sL "$detail_url" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36" \
  -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8")

# 从页面中提取包含数据的div块
rhs_content=$(echo "$page_content" | perl -0777 -ne 'print $1 if /(<div[^>]*class="[^"]*rhs-content[^"]*"[^>]*>.*?<\/div>)/s')

if [ -z "$rhs_content" ]; then
  echo "错误：未能从页面获取插件信息"
  exit 3
fi

# 优先从application/json标签中提取数据
json_data=$(echo "$rhs_content" | perl -0777 -ne 'print $1 if /<script[^>]*application\/json[^>]*>(.*?)<\/script>/s')

if [ -z "$json_data" ]; then
  # 备选方案：尝试直接提取json对象
  json_data=$(echo "$rhs_content" | grep -oP '\{[\s\S]*\}' | head -1)
fi

if [ -z "$json_data" ]; then
  echo "错误：未能提取到插件详细信息"
  exit 4
fi

# 提取版本和唯一标识符
if [ -n "$specified_version" ]; then
    # 如果指定了版本号，直接使用
    version="$specified_version"
    unique_id=$(echo "$json_data" | jq -r '.MoreInfo.UniqueIdentifierValue')
    
    if [ -z "$unique_id" ] || [ "$unique_id" = "null" ]; then
        echo "错误：未能获取插件标识符"
        exit 5
    fi
else
    # 未指定版本号，使用最新版本
    version=$(echo "$json_data" | jq -r '.MoreInfo.VersionValue')
    unique_id=$(echo "$json_data" | jq -r '.MoreInfo.UniqueIdentifierValue')
    
    if [ -z "$version" ] || [ "$version" = "null" ] || [ -z "$unique_id" ] || [ "$unique_id" = "null" ]; then
        echo "错误：未能获取版本信息或唯一标识符"
        exit 5
    fi
fi

echo -e "\n获取成功:"
echo "版本: $version"
echo "标识符: $unique_id"

# 分割unique_id并构造下载URL
IFS='.' read -r publisher_id extension_id <<< "$unique_id"
if [ -n "$publisher_id" ] && [ -n "$extension_id" ]; then
    download_url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher_id}/vsextensions/${extension_id}/${version}/vspackage"
    echo -e "\n下载链接:"
    echo "$download_url"

    # 创建下载目录
    download_dir="​​vscode-offline-vsix"
    mkdir -p "$download_dir"

    # 构造保存的文件名
    vsix_file="${download_dir}/${publisher_id}.${extension_id}-${version}.vsix"
    
    # 下载vsix文件
    echo -e "\n正在下载vsix文件..."
    if curl -L "$download_url" -o "$vsix_file"; then
        echo "下载成功，文件保存在: $vsix_file"
    else
        echo "错误：下载失败"
        exit 7
    fi
else
    echo "错误：无法正确解析标识符"
    exit 6
fi