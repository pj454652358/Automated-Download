#!/bin/bash


# API请求获取插件信息
plugin_keyword="python"
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
echo "正在打开: $detail_url"

# 浏览器操作
if command -v xdg-open &> /dev/null; then
  xdg-open "$detail_url"
elif command -v open &> /dev/null; then
  open "$detail_url"
else
  echo "请手动访问: $detail_url"
fi

# 获取页面HTML
#HTML_CONTENT=$(curl -sL "$detail_url")

curl -sL "$detail_url" -o python.html

grep -Pazo '<div\s+class="ux-section-other"[^>]*>.*?</div>' python.html | 
  tr -d '\0' |  # 处理空字符
  sed -e 's/></>\n</g' -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g'