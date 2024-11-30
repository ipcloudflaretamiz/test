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

if [ "$EUID" -ne 0 ]; then
    echo -e "\n ${RED}This script must be run as root.${NC}"
    exit 1
fi

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

    if [ "$system_architecture" == "x86_64" ] || [ "$system_architecture" == "amd64" ]; then
        curl -L -o udp2raw https://github.com/yinghuocho/udp2raw/releases/download/v2020.07.09/udp2raw_amd64 -O
    fi

    chmod +x udp2raw
    echo -e "${GREEN}File udp2raw installed successfully!${NC}"

    press_enter

    echo ""
    echo -e "${GREEN}Enabling IP forwarding...${NC}"
    display_fancy_progress 20
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    ufw reload > /dev/null 2>&1
    echo ""
    echo -e "${GREEN}All packages were installed and configured.${NC}"
}

validate_port() {
    local port="$1"
    local exclude_ports=()
    local wireguard_port=$(awk -F'=' '/ListenPort/ {gsub(/ /,"",$2); print $2}' /etc/wireguard/*.conf)
    exclude_ports+=("$wireguard_port")

    if [[ " ${exclude_ports[@]} " =~ " $port " ]]; then
        return 0  
    fi

    if ss -tuln | grep -q ":$port "; then
        echo -e "${RED}Port $port is already in use. Please choose another port.${NC}"
        return 1
    fi

    return 0
}

enable_bbr() {
    echo -e "${GREEN}Enabling BBR (Bottleneck Bandwidth and RTT) for better performance...${NC}"
    sysctl -w net.ipv4.tcp_congestion_control=bbr
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    echo -e "${GREEN}BBR has been successfully enabled.${NC}"
}

optimize_for_gaming() {
    echo -e "${GREEN}Optimizing system for gaming and low-latency connections...${NC}"
    
    enable_bbr
    
    echo "net.ipv4.tcp_low_latency = 1" >> /etc/sysctl.conf
    echo "net.core.rmem_max = 16777216" >> /etc/sysctl.conf
    echo "net.core.wmem_max = 16777216" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem = 4096 87380 16777216" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_wmem = 4096 87380 16777216" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    
    echo "net.ipv4.tcp_timestamp = 0" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1

    echo "net.ipv4.tcp_no_metrics_save = 1" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1

    echo -e "${GREEN}System has been optimized for low-latency and gaming.${NC}"
}

remove_tunnel() {
    echo -e "${RED}Removing the UDP2RAW tunnel...${NC}"
    systemctl stop udp2raw-s.service
    systemctl disable udp2raw-s.service
    rm /etc/systemd/system/udp2raw-s.service
    systemctl daemon-reload
    echo -e "${GREEN}UDP2RAW tunnel removed successfully.${NC}"
}

remote_func() {
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

cat << EOF > /etc/systemd/system/udp2raw-s.service
[Unit]
Description=udp2raw-s Service
After=network.target

[Service]
ExecStart=/root/udp2raw -s -l $tunnel_mode:${local_port} -r 127.0.0.1:${remote_port} -k "${password}" --raw-mode ${raw_mode} -a

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

    echo -e "\e[92mRemote Server (EU) configuration has been adjusted and service started. Yours truly${NC}"
echo ""
}

local_func() {
    clear
    echo ""
    echo -e "\e[33mSelect IR Tunnel Mode${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read tunnel_mode

    case $tunnel_mode in
        1)
            tunnel_mode="IPV6"
            ;;
        2)
            tunnel_mode="IPV4"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly ...${NC}"
            ;;
    esac
    while true; do
        echo -ne "\e[33mEnter the Local server (IR) port \e[92m[Default: 443]${NC}: "
        read remote_port
        if [ -z "$remote_port" ]; then
            remote_port=443
            break
        fi
        if validate_port "$remote_port"; then
            break
        fi
    done

    while true; do
        echo ""
        echo -ne "\e[33mEnter the Wireguard port - installed on EU \e[92m[Default: 40600]${NC}: "
        read local_port
        if [ -z "$local_port" ]; then
            local_port=40600
            break
        fi
        if validate_port "$local_port"; then
            break
        fi
    done

    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[This will be used on your local server (IR)]${NC}: "
        read password
        if [ -n "$password" ]; then
            break
        else
            echo -e "${RED}Password cannot be empty! Please try again.${NC}"
        fi
    done

    echo ""
    echo -e "${CYAN}Starting UDP2RAW server with the following details:${NC}"
    echo -e "Protocol: $raw_mode"
    echo -e "Local server port: $remote_port"
    echo -e "Wireguard port: $local_port"
    echo -e "Password: $password"

cat << EOF > /etc/systemd/system/udp2raw-c.service
[Unit]
Description=udp2raw-c Service
After=network.target

[Service]
ExecStart=/root/udp2raw -c -l $tunnel_mode:$remote_port -r 127.0.0.1:$local_port -k "${password}" --raw-mode ${raw_mode} -a

Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    systemctl restart "udp2raw-c.service"
    systemctl enable --now "udp2raw-c.service"
    systemctl start --now "udp2raw-c.service"
    sleep 1

    echo -e "\e[92mLocal Server (IR) configuration has been adjusted and service started. Yours truly${NC}"
    echo ""
}

clear
echo -e "${CYAN}UDP2RAW Configuration Setup${NC}"
echo -e "${GREEN}-------------------------------------${NC}"
echo -e "${RED}1${NC}. ${YELLOW}Install UDP2RAW${NC}"
echo -e "${RED}2${NC}. ${YELLOW}Configure Remote Server (EU)${NC}"
echo -e "${RED}3${NC}. ${YELLOW}Configure Local Server (IR)${NC}"
echo -e "${RED}4${NC}. ${YELLOW}Remove UDP2RAW Tunnel${NC}"
echo -e "${RED}5${NC}. ${YELLOW}Optimize for Gaming${NC}"
echo -e "${RED}0${NC}. ${YELLOW}Exit${NC}"
echo -e "${GREEN}-------------------------------------${NC}"
echo -ne "${CYAN}Enter your choice [0-5]: ${NC}"

read choice

case $choice in
    1)
        install
        ;;
    2)
        remote_func
        ;;
    3)
        local_func
        ;;
    4)
        remove_tunnel
        ;;
    5)
        optimize_for_gaming
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice, please choose between 0-5.${NC}"
        ;;
esac
