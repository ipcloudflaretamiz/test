CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m "
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

    echo -e "\e[92mRemote Server (EU) configuration has been adjusted and service started. Yours truly${NC}"
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
    echo ""
    echo -ne "\e[33mEnter the Remote server (EU) IPV6 / IPV4 (Based on your tunnel preference)\e[92m[This will be used on your server]${NC}: "
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

cat << EOF > /etc/systemd/system/udp2raw-c.service
[Unit]
Description=udp2raw-c Service
After=network.target

[Service]
ExecStart=/root/udp2raw_amd64 -c -l $tunnel_mode:$local_port -r $password:$remote_port -k "${password}" --raw-mode ${raw_mode} -a

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
    echo -e "\e[92mYour local (IR) server is running successfully!${NC}"
}

optimize_for_ping() {
    clear
    echo -e "\n${CYAN}Optimizing for Low Ping and Gaming Performance...${NC}"
    echo ""

    # Disabling unnecessary services for network optimization
    echo -e "${YELLOW}Disabling unnecessary services for better performance...${NC}"
    
    # Check if the service exists before trying to stop/disable it
    for service in avahi-daemon bluetooth apache2; do
        if systemctl list-units --type=service | grep -q "$service"; then
            systemctl stop "$service"
            systemctl disable "$service"
            echo -e "${GREEN}$service service stopped and disabled.${NC}"
        fi
    done

    # Adjusting MTU size for better gaming performance
    echo -e "${YELLOW}Optimizing MTU size for gaming...${NC}"
    # Use `ip` command instead of `ifconfig`
    ip link set dev eth0 mtu 1450

    # Enabling TCP/UDP optimizations for lower latency
    echo -e "${YELLOW}Optimizing TCP congestion control algorithm...${NC}"
    sysctl -w net.ipv4.tcp_congestion_control=bbr

    # Clear any previous QoS settings to avoid conflicts
    echo -e "${YELLOW}Clearing previous QoS settings...${NC}"
    tc qdisc del dev eth0 root 2>/dev/null

    # Apply QoS to prioritize gaming traffic
    echo -e "${YELLOW}Setting up QoS for gaming traffic...${NC}"
    tc qdisc add dev eth0 root handle 1: htb default 12
    tc class add dev eth0 parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev eth0 parent 1:1 classid 1:10 htb rate 100mbit

    # Save changes to sysctl
    sysctl -p > /dev/null 2>&1

    echo -e "${GREEN}Ping and gaming optimizations applied successfully!${NC}"
    echo -e "\n${GREEN}You may need to restart your server for some changes to take effect.${NC}"
}



# Main menu for the script
clear
echo -e "${CYAN}Select an option from the menu:${NC}"
echo -e "1) Install udp2raw"
echo -e "2) Setup Remote Tunnel"
echo -e "3) Setup Local Tunnel"
echo -e "4) Uninstall udp2raw"
echo -e "5) Optimize for Low Ping & Gaming Performance"
echo -e "0) Exit"
echo -ne "Enter your choice [0-5]: "
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
        uninstall
        ;;
    5)
        optimize_for_ping
        ;;
    0)
        echo -e "\n ${RED}Exiting...${NC}"
        exit 0
        ;;
    *)
        echo -e "\n ${RED}Invalid choice. Please enter a valid option.${NC}"
        ;;
esac
