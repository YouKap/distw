#!/bin/bash

# --- 顏色定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 全域變數 ---
SCRIPT_URL="https://raw.githubusercontent.com/YouKap/distw/main/distw.sh"
CLIENT_YML_URL="https://raw.githubusercontent.com/YouKap/distw/main/zh_TW/client.zh_TW.yml"
SERVER_YML_URL="https://raw.githubusercontent.com/YouKap/distw/main/zh_TW/server.zh_TW.yml"

DISCOURSE_DIR="/var/discourse"
TRANS_DIR="/var/discourse/my_translations"
APP_YML="${DISCOURSE_DIR}/containers/app.yml"

# 確保以 Root 權限執行
[[ $EUID -ne 0 ]] && echo -e "${RED}錯誤: 必須以 root 執行！${PLAIN}" && exit 1

# 自我安裝與執行環境校正 (完美支援 curl | bash)
if [[ "$0" != "/usr/local/bin/distw" ]]; then
    echo -e "${BLUE}>>> 正在同步腳本至全域環境...${PLAIN}"
    curl -sSL "$SCRIPT_URL" -o /usr/local/bin/distw
    chmod +x /usr/local/bin/distw
    echo -e "${GREEN}>>> 安裝成功！未來可隨時輸入 'distw' 呼叫面板。${PLAIN}"
    exec /usr/local/bin/distw
fi

# ==========================================
# 核心功能模組
# ==========================================

install_env() {
    clear
    echo -e "${BLUE}=== 📦 1. 初始化環境並下載 Discourse ===${PLAIN}"
    echo -e "${YELLOW}正在更新系統並安裝必備套件...${PLAIN}"
    apt-get update && apt-get install -y git curl nano

    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}正在安裝 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | sh
    else
        echo -e "${GREEN}Docker 已安裝。${PLAIN}"
    fi

    if [ ! -d "$DISCOURSE_DIR" ]; then
        echo -e "${YELLOW}正在下載官方 Discourse 映像...${PLAIN}"
        git clone https://github.com/discourse/discourse_docker.git $DISCOURSE_DIR
        echo -e "${GREEN}Discourse 下載完成！${PLAIN}"
    else
        echo -e "${GREEN}Discourse 目錄已存在，跳過下載。${PLAIN}"
    fi

    mkdir -p $TRANS_DIR
    read -rp "環境初始化完成，按回車鍵返回..." dummy < /dev/tty
}

fetch_translations() {
    clear
    echo -e "${BLUE}=== 📂 2. 從 GitHub 自動下載自定義翻譯 ===${PLAIN}"
    mkdir -p $TRANS_DIR
    echo -e "目標目錄: ${CYAN}${TRANS_DIR}${PLAIN}"
    echo -e "-------------------------------------------------"
    
    echo -e "${YELLOW}正在下載 client.zh_TW.yml...${PLAIN}"
    curl -sSL "$CLIENT_YML_URL" -o "${TRANS_DIR}/client.zh_TW.yml"
    
    echo -e "${YELLOW}正在下載 server.zh_TW.yml...${PLAIN}"
    curl -sSL "$SERVER_YML_URL" -o "${TRANS_DIR}/server.zh_TW.yml"

    echo -e "-------------------------------------------------"
    if [[ -s "${TRANS_DIR}/client.zh_TW.yml" && -s "${TRANS_DIR}/server.zh_TW.yml" ]]; then
        echo -e "${GREEN}✅ 翻譯檔案下載成功！${PLAIN}"
    else
        echo -e "${RED}❌ 下載失敗或檔案為空，請檢查 GitHub 連結是否正確。${PLAIN}"
    fi
    
    read -rp "按回車鍵返回..." dummy < /dev/tty
}

edit_app_yml() {
    clear
    echo -e "${BLUE}=== ⚙️ 3. 編輯 app 設定 (app.yml) ===${PLAIN}"
    if [ ! -d "$DISCOURSE_DIR" ]; then
        echo -e "${RED}錯誤: 找不到 Discourse 目錄，請先執行步驟 1。${PLAIN}"
        sleep 2 && return
    fi

    # 確保 containers 目錄存在
    mkdir -p "${DISCOURSE_DIR}/containers"

    if [ ! -f "$APP_YML" ]; then
        echo -e "${YELLOW}尚未生成 app.yml！${PLAIN}"
        echo -e "1. 執行官方 ./discourse-setup 自動生成 (推薦初學者)"
        echo -e "2. 直接創建空白檔案並使用 nano 編輯 (適合直接貼上完整設定檔)"
        read -rp "請選擇生成方式 [1-2]: " gen_choice < /dev/tty
        
        if [[ "$gen_choice" == "1" ]]; then
            cd $DISCOURSE_DIR
            echo -e "${YELLOW}即將啟動官方設定，請準備好您的網域與 SMTP 資訊...${PLAIN}"
            ./discourse-setup
        elif [[ "$gen_choice" == "2" ]]; then
            touch "$APP_YML"
            echo -e "${GREEN}已建立空白的 app.yml。${PLAIN}"
        else
            return
        fi
    fi

    echo -e "${CYAN}即將打開 nano 編輯器，請進行您需要的修改...${PLAIN}"
    sleep 1
    nano "$APP_YML" < /dev/tty
    
    echo -e "\n${GREEN}✅ app.yml 編輯/生成 完畢！${PLAIN}"
    read -rp "按回車鍵返回主選單..." dummy < /dev/tty
}

inject_config() {
    clear
    echo -e "${BLUE}=== 💉 4. 注入自定義翻譯配置 ===${PLAIN}"
    
    if [ ! -f "$APP_YML" ]; then
        echo -e "${RED}錯誤: 找不到 app.yml，請先執行步驟 3 進行設定。${PLAIN}"
        sleep 2 && return
    fi

    echo -e "${YELLOW}正在檢查並注入掛載配置...${PLAIN}"
    
    if grep -q "/src/my_translations" "$APP_YML"; then
        echo -e "${GREEN}配置已存在，跳過注入以保護 YAML 結構。${PLAIN}"
    else
        # 注入 volumes
        sed -i '/volumes:/a \
  - volume:\n\
      host: /var/discourse/my_translations\n\
      guest: /src/my_translations' "$APP_YML"

        # 注入 hooks
        sed -i '/after_code:/a \
    - exec:\n\
        cd: $home\n\
        cmd:\n\
          - cp /src/my_translations/client.zh_TW.yml config/locales/client.zh_TW.yml 2>/dev/null || true\n\
          - cp /src/my_translations/server.zh_TW.yml config/locales/server.zh_TW.yml 2>/dev/null || true' "$APP_YML"
        
        echo -e "${GREEN}✅ app.yml 掛載與覆蓋腳本注入成功！${PLAIN}"
        echo -e "${YELLOW}提示：您可以執行步驟 3 再次檢查 app.yml，確認無誤後再執行步驟 5 進行 Rebuild。${PLAIN}"
    fi

    read -rp "按回車鍵返回主選單..." dummy < /dev/tty
}

rebuild_discourse() {
    clear
    echo -e "${BLUE}=== 🏗️ 5. 執行重建 (Rebuild) ===${PLAIN}"
    
    if [ ! -f "$APP_YML" ]; then
        echo -e "${RED}錯誤: 找不到 app.yml，請先執行步驟 3 進行設定。${PLAIN}"
        sleep 2 && return
    fi

    echo -e "-------------------------------------------------"
    echo -e "${YELLOW}⚠️  注意：Rebuild 過程將中斷網站服務，並需要 10 ~ 15 分鐘的時間。${PLAIN}"
    read -rp "確認要開始 Rebuild 嗎？(y/N): " confirm < /dev/tty
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return
    fi
    
    cd $DISCOURSE_DIR
    ./launcher rebuild app
    
    echo -e "\n${GREEN}✅ 重建完成！前端與後端配置已更新。${PLAIN}"
    read -rp "按回車鍵返回主選單..." dummy < /dev/tty
}

clear_cache() {
    clear
    echo -e "${BLUE}=== 🧹 6. 清理快取並重啟服務 ===${PLAIN}"
    if [ ! -d "$DISCOURSE_DIR" ]; then
        echo -e "${RED}錯誤: Discourse 尚未安裝。${PLAIN}"
        sleep 2 && return
    fi

    cd $DISCOURSE_DIR
    echo -e "${YELLOW}正在進入容器清除 Rails 翻譯快取...${PLAIN}"
    ./launcher enter app -c "rails r 'Rails.cache.clear; I18n.backend.reload!'" 2>/dev/null || echo -e "${RED}清除快取失敗 (容器可能未運行)${PLAIN}"
    
    echo -e "${YELLOW}正在重啟 Discourse 容器...${PLAIN}"
    ./launcher restart app
    
    echo -e "\n${GREEN}✅ 快取已清除，服務已重啟！(請在瀏覽器按 Ctrl+F5 強制刷新)${PLAIN}"
    read -rp "按回車鍵返回主選單..." dummy < /dev/tty
}

show_status() {
    clear
    echo -e "${BLUE}=== 📊 7. 運行狀態總覽 ===${PLAIN}"
    docker ps --filter "name=app" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo -e "-------------------------------------------------"
    echo -e "硬碟空間使用狀況:"
    df -h /var/discourse | awk 'NR==1 || NR==2'
    echo -e "-------------------------------------------------"
    read -rp "按回車鍵返回..." dummy < /dev/tty
}

nuke_discourse() {
    clear
    echo -e "${RED}=================================================${PLAIN}"
    echo -e "      ⚠️  警告：徹底毀滅 Discourse 所有數據"
    echo -e "${RED}=================================================${PLAIN}"
    echo -e "這將會："
    echo -e " 1. 停止並刪除 Discourse 容器"
    echo -e " 2. 徹底刪除 /var/discourse 目錄 (包含所有資料庫與上傳檔案！)\n"
    
    read -rp "您確定要執行此毀滅性操作嗎？請輸入 'DESTROY' 確認: " confirm < /dev/tty
    if [[ "$confirm" == "DESTROY" ]]; then
        cd /var/discourse 2>/dev/null && ./launcher destroy app 2>/dev/null || true
        docker rm -f app 2>/dev/null || true
        rm -rf /var/discourse
        echo -e "\n${GREEN}✅ Discourse 已從此伺服器徹底抹除！${PLAIN}"
    else
        echo -e "\n${BLUE}已取消操作。${PLAIN}"
    fi
    read -rp "按回車鍵返回主選單..." dummy < /dev/tty
}

# ==========================================
# 主介面循環
# ==========================================
while true; do
    clear
    [[ -d "$DISCOURSE_DIR" ]] && ICON1="${GREEN}(已安裝)${PLAIN}" || ICON1=""
    [[ -f "${TRANS_DIR}/client.zh_TW.yml" ]] && ICON2="${GREEN}(已下載)${PLAIN}" || ICON2=""
    [[ -f "$APP_YML" ]] && ICON3="${GREEN}(已配置)${PLAIN}" || ICON3=""
    [[ $(grep -q "/src/my_translations" "$APP_YML" 2>/dev/null; echo $?) -eq 0 ]] && ICON4="${GREEN}(已注入)${PLAIN}" || ICON4=""
    
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "  🚀 ${GREEN}Discourse TW (distw) 部署與翻譯管理面板${PLAIN}"
    echo -e "      快捷指令: distw  |  版本: 1.0.5"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW} 1.${PLAIN} 初始化環境並下載 Discourse $ICON1"
    echo -e "${YELLOW} 2.${PLAIN} 📂 ${CYAN}從 GitHub 自動拉取最新翻譯檔${PLAIN} $ICON2"
    echo -e "${YELLOW} 3.${PLAIN} 編輯 app 設定 (生成/修改 app.yml) $ICON3"
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW} 4.${PLAIN} 💉 注入自定義翻譯配置 (寫入 app.yml) $ICON4"
    echo -e "${YELLOW} 5.${PLAIN} ${GREEN}🏗️ 執行重建 (Rebuild Discourse)${PLAIN}"
    echo -e "${YELLOW} 6.${PLAIN} 🧹 清理 Rails 翻譯快取並重啟 (免 Rebuild)"
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW} 7.${PLAIN} 📊 查看 Discourse 運行狀態"
    echo -e "${RED} 8.${PLAIN} 💥 徹底刪除 Discourse 所有數據"
    echo -e "-------------------------------------------------"
    echo -e "${YELLOW} 0.${PLAIN} 退出腳本"
    echo -e "${BLUE}=================================================${PLAIN}"
    
    read -rp "請選擇數字 [0-8]: " choice < /dev/tty
    [[ -z "$choice" ]] && continue

    case $choice in
        1) install_env ;;
        2) fetch_translations ;;
        3) edit_app_yml ;;
        4) inject_config ;;
        5) rebuild_discourse ;;
        6) clear_cache ;;
        7) show_status ;;
        8) nuke_discourse ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}無效選擇${PLAIN}"; sleep 1 ;;
    esac
done
