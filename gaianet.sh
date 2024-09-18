#!/bin/bash

# 색깔 변수 정의
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[36m'
NC='\033[0m' # No Color

echo -e "${GREEN}Pingpong 노드 설치 및 설정 스크립트입니다.${NC}"
echo ""

# 사용자에게 선택지를 제공
echo -e "${BOLD}${CYAN}1. Pingpong Node 설치${NC}"
echo -e "${BOLD}${CYAN}2. Pingpong Depin 설정${NC}"
echo -e "${YELLOW}1번을 선택하여 새로 설치할시 로그가 계속 나오기때문에 컨트롤A+D로 스크립트를 종료해주세요.${NC}"
echo -e "${YELLOW}컨트롤A+D로 종료후 스크립트를 재실행하여 2번을 선택하고 Depin 설정을 마무리해주세요.${NC}"
read -p "원하는 작업의 번호를 입력하세요: " CHOICE

if [[ "$CHOICE" -eq 1 ]]; then
    # Pingpong Node 설치 단계
    echo -e "${GREEN}Pingpong 노드 설치를 시작합니다.${NC}"
    echo ""

    command_exists() {
        command -v "$1" &> /dev/null
    }

    # 도커 설치 확인
    echo -e "${BOLD}${CYAN}Docker 설치 확인 중...${NC}"
    if ! command_exists docker; then
        echo -e "${RED}Docker가 설치되어 있지 않습니다. Docker를 설치하는 중입니다...${NC}"
        sudo apt update && sudo apt install -y curl net-tools
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        echo -e "${GREEN}Docker가 성공적으로 설치되었습니다.${NC}"
    else
        echo -e "${GREEN}Docker가 이미 설치되어 있습니다.${NC}"
    fi

    # pingpong 패키지 설치
    echo -e "${BOLD}${CYAN}pingpong 패키지 설치 중...${NC}"
    wget https://pingpong-build.s3.ap-southeast-1.amazonaws.com/linux/latest/PINGPONG

    # pingpong 노드 설정 안내
    echo -e "${BOLD}${CYAN}pingpong 노드를 설정 중...${NC}"
    echo -e "${YELLOW}해당 사이트에 방문하세요${NC}"
    echo -e "${YELLOW}https://app.pingpong.build/mining/devices${NC}"
    echo -e "${YELLOW}Add device를 누른 후 Device key를 복사하세요.${NC}"

    # 사용자로부터 Device key를 입력받음
    read -p "Device key를 입력하세요: " DEVICE_KEY

    # 패키지에 실행 권한을 부여하고 실행
    chmod +x ./PINGPONG
    ./PINGPONG --key "$DEVICE_KEY"

elif [[ "$CHOICE" -eq 2 ]]; then
    # Pingpong Depin 설정 단계
    echo -e "${GREEN}${CYAN}Pingpong Depin 설정을 시작합니다.${NC}"
    echo ""

    echo -e "${BOLD}1.0G 노드 설정 중...${NC}"
    read -p "EVM 지갑 프라이빗키를 입력하세요 (0G 노드용): " OGPRIVATE_KEY
    ./PINGPONG config set --0g="$OGPRIVATE_KEY"
    ./PINGPONG stop --depins=0g
    ./PINGPONG start --depins=0g
    echo ""

    echo -e "${BOLD}2. AIOZ 노드 설정 중...${NC}"
    curl -LO https://github.com/AIOZNetwork/aioz-dcdn-cli-node/files/13561211/aioznode-linux-amd64-1.1.0.tar.gz
    tar xzf aioznode-linux-amd64-1.1.0.tar.gz
    mv aioznode-linux-amd64-1.1.0 aioznode
    ./aioznode keytool new --save-priv-key privkey.json
    echo -e "${BOLD}${CYAN}privkey.json 파일의 내용은 다음과 같습니다:${NC}"
    cat privkey.json
    echo ""
    read -p "privkey.json 안에서 개인키로 보이는 내용만 복사해서 적으세요 (\"\"는 제외): " OZPRIVATE_KEY
    ./PINGPONG config set --aioz="$OZPRIVATE_KEY"
    ./PINGPONG stop --depins=aioz
    ./PINGPONG start --depins=aioz
    echo ""

    echo -e "${BOLD}3. Grass 노드 설정 중...${NC}"
    echo -e "${YELLOW}해당 사이트로 이동하세요: https://app.getgrass.io/dashboard${NC}"
    echo -e "${YELLOW}F12를 누른 후 상단 메뉴바에서 애플리케이션을 클릭하세요${NC}"
    echo -e "${YELLOW}왼쪽 카테고리바에서 저장용량 - 로컬스토리지를 클릭하세요${NC}"
    read -p "userID라고 표기된 구문을 복사해서 적으세요 (\"\"는 제외): " GRASSID
    ./PINGPONG config set --grass.access="$GRASSID" --grass.refresh="$GRASSID"
    ./PINGPONG stop --depins=grass
    ./PINGPONG start --depins=grass
    echo ""

    echo -e "${BOLD}4. BlockMesh 노드 설정 중...${NC}"
    echo -e "${YELLOW}해당 사이트로 이동하여: https://app.blockmesh.xyz/register?invite_code=kangjk${NC}"
    read -p "회원가입을 진행한 Email을 적으세요: " BMEMAIL
    read -p "패스워드를 입력하세요: " BMPW
    ./PINGPONG config set --blockmesh.email="$BMEMAIL" --blockmesh.pwd="$BMPW"
    ./PINGPONG stop --depins=blockmesh
    ./PINGPONG start --depins=blockmesh
    echo ""

    echo -e "${BOLD}5. DAWN 노드 설정 중...${NC}"
    echo -e "${YELLOW}크롬 익스텐션을 다운하여 회원가입을 진행하세요: Ref=i4r46rfl${NC}"
    read -p "회원가입을 진행한 Email을 적으세요: " DWEMAIL
    read -p "패스워드를 입력하세요: " DWPW
    ./PINGPONG config set --dawn.email="$DWEMAIL" --dawn.pwd="$DWPW"
    ./PINGPONG stop --depins=dawn
    ./PINGPONG start --depins=dawn
fi

echo -e "${GREEN}모든 작업이 완료되었습니다. https://app.pingpong.build/mining/devices 에서 확인하세요${NC}"
echo -e "${GREEN}스크립트 작성자: https://t.me/kjkresearch${NC}"
