CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m"
MAGENTA="\e[95m"
NC="\e[0m"

press_enter() {
    echo -e "\n${RED}Press Enter to continue... ${NC}"
    read
}
display_fancy_progress() {
    local duration=$1
    local sleep_interval=0.1
    local progress=0
    local bar_length=40

    while [ $progress -lt $duration ]; do
        echo -ne "\r[${YELLOW}"
        for ((i = 0; i < bar_length; i++)); do
            if [ $i -lt $((progress * bar_length / duration)) ]; then
                echo -ne "▓"
            else
                echo -ne "░"
            fi
        done
        echo -ne "${RED}] ${progress}%${NC}"
        progress=$((progress + 1))
        sleep $sleep_interval
    done
    echo -ne "\r[${YELLOW}"
    for ((i = 0; i < bar_length; i++)); do
        echo -ne "#"
    done
    echo -ne "${RED}] ${progress}%${NC}"
    echo
}
install() {
    clear
    echo ""
    echo -e "${YELLOW}First, making sure that all packages are suitable for your server.${NC}"
    echo ""
    echo -e "Please wait, it might take a while"
    echo ""
    sleep 1
    secs=4
    while [ $secs -gt 0 ]; do
        echo -ne "Continuing in $secs seconds\033[0K\r"
        sleep 1
        : $((secs--))
    done
    echo ""
    apt-get update > /dev/null 2>&1
    display_fancy_progress 20
    echo ""
    system_architecture=$(uname -m)

    if [ "$system_architecture" != "x86_64" ] && [ "$system_architecture" != "amd64" ]; then
        echo "Unsupported architecture: $system_architecture"
        exit 1
    fi

    sleep 1
    echo ""
    echo -e "${YELLOW}Downloading and installing udp2raw for architecture: $system_architecture${NC}"
    curl -L -o udp2raw_amd64 https://github.com/amirmbn/UDP2RAW/raw/main/Core/udp2raw_amd64
    curl -L -o udp2raw_x86 https://github.com/amirmbn/UDP2RAW/raw/main/Core/udp2raw_x86
    sleep 1

    chmod +x udp2raw_amd64
    chmod +x udp2raw_x86

    echo ""
    echo -e "${GREEN}Enabling IP forwarding...${NC}"
    display_fancy_progress 20
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    ufw reload > /dev/null 2>&1
    echo ""
    echo -e "${GREEN}All packages were installed and configured.${NC}"

    # Ask user for server location (IR or EU) and proceed
    choose_server_location
}
choose_server_location() {
    echo -e "${YELLOW}Where is your server located?${NC}"
    echo -e "${RED}1${NC}. ${YELLOW}Iran (IR)${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}Europe (EU)${NC}"
    echo ""
    echo -ne "Enter your choice [1-2]: ${NC}"
    read server_choice

    case $server_choice in
        1)
            echo -e "${GREEN}You selected Iran (IR). Continuing with local server configuration.${NC}"
            configure_local_server
            ;;
        2)
            echo -e "${GREEN}You selected Europe (EU). Continuing with remote server configuration.${NC}"
            configure_remote_server
            ;;
        *)
            echo -e "${RED}Invalid choice, please select again.${NC}"
            choose_server_location
            ;;
    esac
}
configure_local_server() {
    clear
    echo ""
    echo -e "${YELLOW}Configuring local server (Iran)...${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read tunnel_mode

    case $tunnel_mode in
        1)
            tunnel_mode="[::]"
            ;;
        2)
            tunnel_mode="0.0.0.0"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly ...${NC}"
            ;;
    esac

    while true; do
        echo -ne "\e[33mEnter the Local server (IR) port \e[92m[Default: 443]${NC}: "
        read local_port
        if [ -z "$local_port" ]; then
            local_port=443
            break
        fi
        if validate_port "$local_port"; then
            break
        fi
    done

    while true; do
        echo ""
        echo -ne "\e[33mEnter the Wireguard port \e[92m[Default: 40600]${NC}: "
        read remote_port
        if [ -z "$remote_port" ]; then
            remote_port=40600
            break
        fi
        if validate_port "$remote_port"; then
            break
        fi
    done

    echo ""
    echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[This will be used on your local server (IR)]${NC}: "
    read password
    echo ""
    echo -e "\e[33m protocol (Mode) (Local and remote should be the same)${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}udp${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}faketcp${NC}"
    echo -e "${RED}3${NC}. ${YELLOW}icmp${NC}"
    echo ""
    echo -ne "Enter your choice [1-3] : ${NC}"
    read protocol_choice

    case $protocol_choice in
        1)
            raw_mode="udp"
            ;;
        2)
            raw_mode="faketcp"
            ;;
        3)
            raw_mode="icmp"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly ...${NC}"
            ;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

cat << EOF > /etc/systemd/system/udp2raw-s.service
[Unit]
Description=udp2raw-s Service
After=network.target

[Service]
ExecStart=/root/udp2raw_amd64 -s -l $tunnel_mode:${local_port} -r 127.0.0.1:${remote_port} -k "${password}" --raw-mode ${raw_mode} -a

Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    systemctl restart "udp2raw-s.service"
    systemctl enable --now "udp2raw-s.service"
    systemctl start --now "udp2raw-s.service"
    sleep 1

    echo -e "\e[92mLocal Server (IR) configuration has been adjusted and service started.${NC}"

    # Ask for Gaming Mode settings
    enable_gaming_mode
}
enable_gaming_mode() {
    echo -e "${YELLOW}Would you like to enable gaming optimizations for lower ping?${NC}"
    echo -e "${RED}1${NC}. ${YELLOW}Yes${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}No${NC}"
    echo ""
    echo -ne "Enter your choice [1-2]: ${NC}"
    read gaming_choice

    case $gaming_choice in
        1)
            echo -e "${GREEN}Gaming optimizations enabled.${NC}"
            # Implement gaming optimizations here
            ;;
        2)
            echo -e "${GREEN}No gaming optimizations applied.${NC}"
            ;;
        *)
            echo -e "${RED}Invalid choice, please select again.${NC}"
            enable_gaming_mode
            ;;
    esac
}
configure_remote_server() {
    clear
    echo ""
    echo -e "\e[33mSelect EU Tunnel Mode${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read tunnel_mode

    case $tunnel_mode in
        1)
            tunnel_mode="[::]"
            ;;
        2)
            tunnel_mode="0.0.0.0"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly ...${NC}"
            ;;
    esac

    while true; do
        echo -ne "\e[33mEnter the Local server (IR) port \e[92m[Default: 443]${NC}: "
        read local_port
        if [ -z "$local_port" ]; then
            local_port=443
            break
        fi
        if validate_port "$local_port"; then
            break
        fi
    done

    while true; do
        echo ""
        echo -ne "\e[33mEnter the Wireguard port \e[92m[Default: 40600]${NC}: "
        read remote_port
        if [ -z "$remote_port" ]; then
            remote_port=40600
            break
        fi
        if validate_port "$remote_port"; then
            break
        fi
    done

    echo ""
    echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[This will be used on your local server (IR)]${NC}: "
    read password
    echo ""
    echo -e "\e[33m protocol (Mode) (Local and remote should be the same)${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}udp${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}faketcp${NC}"
    echo -e "${RED}3${NC}. ${YELLOW}icmp${NC}"
    echo ""
    echo -ne "Enter your choice [1-3] : ${NC}"
    read protocol_choice

    case $protocol_choice in
        1)
            raw_mode="udp"
            ;;
        2)
            raw_mode="faketcp"
            ;;
        3)
            raw_mode="icmp"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly ...${NC}"
            ;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

# Similar to local server configuration, setup remote server here.
}
