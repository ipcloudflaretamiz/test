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
    apt-get install curl wget -y > /dev/null 2>&1 # added to ensure curl is installed
    echo -e "${GREEN}Packages installed successfully.${NC}"
}

remove_tunnel() {
    echo -e "\n${YELLOW}Removing UDP2RAW tunnel...${NC}"
    systemctl stop udp2raw-s.service udp2raw-c.service
    systemctl disable udp2raw-s.service udp2raw-c.service
    rm -f /etc/systemd/system/udp2raw-s.service /etc/systemd/system/udp2raw-c.service
    systemctl daemon-reload
    echo -e "${GREEN}UDP2RAW tunnel has been removed.${NC}"
}

view_status() {
    echo -e "\n${CYAN}Checking UDP2RAW service status...${NC}"
    systemctl status udp2raw-s.service
    systemctl status udp2raw-c.service
    echo ""
}

optimize_for_gaming() {
    echo -e "${YELLOW}Optimizing for gaming...${NC}"
    echo -e "${CYAN}Activating TCP BBR for better latency...${NC}"
    sysctl -w net.ipv4.tcp_congestion_control=bbr
    sysctl -w net.core.default_qdisc=fq
    sysctl -w net.ipv4.tcp_mtu_probing=1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216"
    sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216"
    sysctl -p
    echo -e "${GREEN}Gaming optimizations complete.${NC}"
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
        if [ ! -z "$password" ]; then
            break
        fi
    done

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
ExecStart=/root/udp2raw_amd64 -c -l ${tunnel_mode}:${remote_port} -r 127.0.0.1:${local_port} -k "${password}" --raw-mode ${raw_mode} -a

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
    press_enter
}

clear
echo -e "${CYAN}UDP2RAW Configuration Setup${NC}"
echo -e "${GREEN}-------------------------------------${NC}"
echo -e "${RED}1${NC}. ${YELLOW}Install UDP2RAW${NC}"
echo -e "${RED}2${NC}. ${YELLOW}Configure Remote Server (EU)${NC}"
echo -e "${RED}3${NC}. ${YELLOW}Configure Local Server (IR)${NC}"
echo -e "${RED}4${NC}. ${YELLOW}Remove UDP2RAW Tunnel${NC}"
echo -e "${RED}5${NC}. ${YELLOW}Optimize for Gaming${NC}"
echo -e "${RED}6${NC}. ${YELLOW}View UDP2RAW Service Status${NC}"
echo -e "${RED}0${NC}. ${YELLOW}Exit${NC}"
echo -e "${GREEN}-------------------------------------${NC}"
echo -ne "${CYAN}Enter your choice [0-6]: ${NC}"

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
    6)
        view_status
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice, please choose between 0-6.${NC}"
        ;;
esac
