#!/bin/bash

# cai.sh
# 整合了调用DeepSeek API和执行返回命令的功能，并添加了用户交互

# 配置文件路径
CONFIG_FILE="config.json"
REQUEST_TEMPLATE="request_template.json"
REQUEST_FILE="request.json"
RESPONSE_FILE="response.json"
LOG_FILE="cai.log"

# 日志函数
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# 检查是否提供了用户命令
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 \"your command\""
    exit 1
fi

USER_COMMAND="$1"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    log "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# 检查请求模板文件是否存在
if [ ! -f "$REQUEST_TEMPLATE" ]; then
    log "Error: Request template file not found: $REQUEST_TEMPLATE"
    exit 1
fi

# 读取API密钥
API_KEY=$(jq -r '.api_key' "$CONFIG_FILE")
if [ -z "$API_KEY" ]; then
    log "Error: API key not found in config file."
    exit 1
fi

# 使用jq追加用户指令到请求模板
jq --arg cmd "$USER_COMMAND" '.messages += [{"role": "user", "content": ($cmd)}]' "$REQUEST_TEMPLATE" > "$REQUEST_FILE"

# 检查是否成功更新请求文件
if [ $? -ne 0 ]; then
    log "Failed to update request file."
    exit 1
fi

log "Updated request file with user command: $USER_COMMAND"
log "Request file created: $REQUEST_FILE"

# 函数：执行命令
execute_command() {
    local last_command
    while true; do  # 使用无限循环来重复询问步骤
        # 打印请求的JSON内容
        log "Sending request to DeepSeek API with JSON:"
        cat "$REQUEST_FILE" | tee -a "$LOG_FILE"

        # 使用curl发送请求到DeepSeek API
        curl_response=$(curl -s -X POST 'https://api.deepseek.com/chat/completions' \
            -H "Authorization: Bearer $API_KEY" \
            -H 'Content-Type: application/json' \
            --data-binary @"$REQUEST_FILE")

        # 检查curl响应状态
        if [ $? -ne 0 ]; then
            log "Failed to send request to DeepSeek API."
            break
        fi

        # 打印完整的API响应
        log "Received API response:"
        echo "$curl_response" | tee -a "$LOG_FILE"

        # 将响应保存到文件
        echo "$curl_response" > "$RESPONSE_FILE"

        # 检查响应是否为空
        if [ -z "$curl_response" ]; then
            log "Error: Empty response from API."
            break
        fi

        # 解析响应并获取命令
        last_command=$(echo "$curl_response" | jq -r '.choices[0].message.content | fromjson? | .command?')
        if [ -z "$last_command" ]; then
            log "No assistant command found in the API response."
            break  # 如果没有命令，退出循环
        fi

        log "Received command from API: $last_command"
        read -p "Do you want to execute this command? (y/r/n) " user_choice

        case "$user_choice" in
            [Yy]* )
                log "Executing command: $last_command"
                eval "$last_command"
                return  # 执行命令后退出函数
                ;;
            [Rr]* )
                log "Re-fetching command from API..."
                # 循环继续，重新获取命令
                ;;
            [Nn]* )
                log "Command execution aborted by user."
                return  # 不执行命令并退出函数
                ;;
            * )
                log "Invalid response. Please answer y, r, or n."
                # 循环继续，等待有效输入
                ;;
        esac
    done
}

# 调用函数执行命令
log "Starting script with command: $USER_COMMAND"
execute_command
log "Script execution completed."