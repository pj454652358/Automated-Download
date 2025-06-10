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

# 检查是否安装了curl
if ! command -v curl &> /dev/null; then
    echo "未找到 curl，正在尝试安装..."
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y curl
    elif command -v yum &> /dev/null; then
        sudo yum install -y curl
    else
        echo "无法自动安装 curl，请手动安装后重试"
        exit 1
    fi
fi

# 获取预期文件大小
echo "正在获取文件大小..."
response_headers=$(curl -s -D - -o /dev/null \
    -X GET \
    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36" \
    -H "Accept: */*" \
    -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8" \
    -H "Referer: https://marketplace.visualstudio.com/" \
    -H "Origin: https://marketplace.visualstudio.com" \
    -H "Sec-Fetch-Dest: empty" \
    -H "Sec-Fetch-Mode: cors" \
    -H "Sec-Fetch-Site: same-origin" \
    "$download_url")

echo "服务器响应头:"
echo "$response_headers"

expected_size=$(echo "$response_headers" | grep -i content-length | awk '{print $2}' | tr -d '\r')
echo "解析到的文件大小: $expected_size"

if [[ ! "$expected_size" =~ ^[0-9]+$ ]]; then
    echo "警告：无法获取有效的文件大小，将设置为0"
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
        echo -e "\n开始下载vsix文件..."
        # 使用curl下载，完全模拟浏览器行为
        curl -L \
             -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36" \
             -H "Accept: */*" \
             -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8" \
             -H "Referer: https://marketplace.visualstudio.com/" \
             -H "Origin: https://marketplace.visualstudio.com" \
             -H "Sec-Fetch-Dest: empty" \
             -H "Sec-Fetch-Mode: cors" \
             -H "Sec-Fetch-Site: same-origin" \
             --connect-timeout 60 \
             --compressed \
             --continue-at - \
             -o "$vsix_file" \
             "$download_url"

        # 检查下载结果
        if [ $? -ne 0 ]; then
            echo "下载失败，重试..."
            rm -f "$vsix_file"
            retry_count=$((retry_count+1))
            sleep 3
            continue
        fi

        file_size=$(stat -c%s "$vsix_file")
        file_size_kb=$((file_size/1024))
        file_size_mb=$((file_size_kb/1024))
        
        if [ "$expected_size" -gt 0 ]; then
            # 完全匹配文件大小
            if [ "$file_size" -eq "$expected_size" ]; then
                echo "文件大小完全匹配: ${file_size_kb}KB"
                success=1
                break
            elif [ "$file_size" -ge "$((expected_size - 1024))" ] && [ "$file_size" -le "$((expected_size + 1024))" ]; then
                echo "文件大小在可接受范围内: ${file_size_kb}KB (预期: $((expected_size/1024))KB)"
                success=1
                break
            else
                echo "文件大小不匹配（当前: ${file_size_kb}KB，预期: $((expected_size/1024))KB），重试..."
                rm -f "$vsix_file"
                retry_count=$((retry_count+1))
                sleep 3
                continue
            fi
        elif [ "$file_size" -ge $((10*1024*1024)) ]; then
            # 如果无法获取预期大小但文件大于10MB，认为下载成功
            echo "文件大小: ${file_size_mb}MB (${file_size_kb}KB)"
            success=1
            break
        else
            echo "文件过小（${file_size_mb}MB），可能未下载完整，重试..."
            rm -f "$vsix_file"
            retry_count=$((retry_count+1))
            sleep 3
            continue
        fi
    done

    if [ $success -ne 1 ]; then
        echo "多次尝试后仍未成功下载完整文件，请检查网络或稍后重试。"
        rm -f "$vsix_file"
        exit 1
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