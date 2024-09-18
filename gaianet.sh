#!/bin/bash

set -e

# 대상 이름 가져오기 (시스템 아키텍처 확인)
target=$(uname -m)

# 스크립트가 위치한 디렉터리
cwd=$(pwd)

# 버전 정보
repo_branch="main"
version="0.4.1"
rag_api_server_version="0.9.3"
llama_api_server_version="0.14.3"
wasmedge_version="0.14.0"
ggml_bn="b3613"
vector_version="0.38.0"
dashboard_version="v3.1"
assistant_version="0.2.2"

# 옵션 설정 (0: 비활성화, 1: 활성화)
reinstall=0
upgrade=0
unprivileged=0
config_url=""
gaianet_base_dir="$HOME/gaianet"
qdrant_version="v1.10.1"
tmp_dir="$gaianet_base_dir/tmp"
ggmlcuda=""
enable_vector=0

# 색상 정의
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[0;33m'
NC=$'\e[0m'

# 사용법 출력 함수
function print_usage {
    printf "사용법:\n"
    printf "  ./install.sh [옵션]\n\n"
    printf "옵션:\n"
    printf "  --config <Url>     설정 파일의 URL을 지정\n"
    printf "  --base <경로>      gaianet 기본 디렉터리 경로를 지정\n"
    printf "  --reinstall        모든 필수 종속성을 다시 설치 및 다운로드\n"
    printf "  --upgrade          gaianet 노드를 업그레이드\n"
    printf "  --tmpdir <경로>    임시 디렉터리 경로 지정 [기본값: $gaianet_base_dir/tmp]\n"
    printf "  --ggmlcuda [11/12] 특정 CUDA 버전의 GGML 플러그인 설치 [가능 값: 11, 12]\n"
    printf "  --enable-vector    Vector 로그 집계기 설치\n"
    printf "  --version          버전 출력\n"
    printf "  --help             도움말 출력\n"
}

# 명령어 인자 처리
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --config)
            config_url="$2"
            shift
            shift
            ;;
        --base)
            gaianet_base_dir="$2"
            shift
            shift
            ;;
        --reinstall)
            reinstall=1
            shift
            ;;
        --upgrade)
            upgrade=1
            shift
            ;;
        --tmpdir)
            tmp_dir="$2"
            shift
            shift
            ;;
        --ggmlcuda)
            ggmlcuda="$2"
            shift
            shift
            ;;
        --enable-vector)
            enable_vector=1
            shift
            ;;
        --version)
            echo "Gaianet-node 설치 프로그램 v$version"
            exit 0
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "알 수 없는 인자: $key"
            print_usage
            exit 1
            ;;
    esac
done

# 정보 메시지 출력 함수 (초록색)
info() {
    printf "${GREEN}$1${NC}\n\n"
}

# 오류 메시지 출력 함수 (빨간색)
error() {
    printf "${RED}$1${NC}\n\n"
}

# 경고 메시지 출력 함수 (노란색)
warning() {
    printf "${YELLOW}$1${NC}\n\n"
}

# 파일 다운로드 함수 (오류 시 종료)
check_curl() {
    curl --retry 3 --progress-bar -L "$1" -o "$2"

    if [ $? -ne 0 ]; then
        error "    * $1 다운로드 실패"
        exit 1
    fi
}

# 파일 다운로드 함수 (조용한 모드, 오류 시 종료)
check_curl_silent() {
    curl --retry 3 -s --progress-bar -L "$1" -o "$2"

    if [ $? -ne 0 ]; then
        error "    * $1 다운로드 실패"
        exit 1
    fi
}

# ASCII 아트 출력 (스크립트 제목)
printf "\n"
cat <<EOF
 ██████╗  █████╗ ██╗ █████╗ ███╗   ██╗███████╗████████╗
██╔════╝ ██╔══██╗██║██╔══██╗████╗  ██║██╔════╝╚══██╔══╝
██║  ███╗███████║██║███████║██╔██╗ ██║█████╗     ██║   
██║   ██║██╔══██║██║██╔══██║██║╚██╗██║██╔══╝     ██║   
╚██████╔╝██║  ██║██║██║  ██║██║ ╚████║███████╗   ██║   
 ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   
EOF

printf "\n\n"

# npm이 설치되어 있는지 확인
if ! command -v npm &> /dev/null; then
    echo "npm이 설치되어 있지 않습니다. 설치 중..."
    
    # npm 설치
    sudo apt update
    sudo apt install -y npm
else
    echo "npm이 이미 설치되어 있습니다."
fi

# 업그레이드 또는 재설치 옵션에 따라 디렉토리 정리 및 백업 처리
if [ -d "$gaianet_base_dir" ]; then
    if [ "$upgrade" -eq 1 ]; then

        # gaianet 버전 확인
        if ! command -v gaianet &> /dev/null; then
            current_version=""
        else
            current_version=$(gaianet --version)
        fi

        if [ -n "$current_version" ] && [ "GaiaNet CLI Tool v$version" = "$current_version" ]; then
            info "현재 버전 ($current_version)이 대상 버전 (GaiaNet CLI Tool v$version)과 동일합니다. 업그레이드 과정을 생략합니다."
            exit 0

        else
            info "Gaianet 노드가 v$version으로 업그레이드됩니다."
        fi

        printf "[+] v$version으로 업그레이드하기 전에 백업 중...\n\n"

        if [ ! -d "$gaianet_base_dir/backup" ]; then
            printf "    * $gaianet_base_dir/backup 디렉토리 생성 중\n"
            mkdir -p "$gaianet_base_dir/backup"
        fi

        # keystore 파일 백업
        keystore_filename=$(grep '"keystore":' $gaianet_base_dir/nodeid.json | awk -F'"' '{print $4}')
        if [ -z "$keystore_filename" ]; then
            error "keystore 필드를 $gaianet_base_dir/nodeid.json에서 읽지 못했습니다."
            exit 1
        else
            if [ -f "$gaianet_base_dir/$keystore_filename" ]; then
                printf "    * $keystore_filename을 $gaianet_base_dir/backup/에 복사 중\n"
                cp $gaianet_base_dir/$keystore_filename $gaianet_base_dir/backup/
            else
                error "keystore 파일 복사 실패. $gaianet_base_dir에 파일이 존재하지 않습니다."
                exit 1
            fi
        fi
        # config.json 파일 백업
        if [ -f "$gaianet_base_dir/config.json" ]; then
            printf "    * config.json을 $gaianet_base_dir/backup/에 복사 중\n"
            cp $gaianet_base_dir/config.json $gaianet_base_dir/backup/
        else
            error "config.json 복사 실패. 파일이 존재하지 않습니다."
            exit 1
        fi
        # nodeid.json 파일 백업
        if [ -f "$gaianet_base_dir/nodeid.json" ]; then
            printf "    * nodeid.json을 $gaianet_base_dir/backup/에 복사 중\n"
            cp $gaianet_base_dir/nodeid.json $gaianet_base_dir/backup/
        else
            error "nodeid.json 복사 실패. 파일이 존재하지 않습니다."
            exit 1
        fi
        # frpc.toml 파일 백업
        if [ -f "$gaianet_base_dir/gaia-frp/frpc.toml" ]; then
            printf "    * frpc.toml을 $gaianet_base_dir/backup/에 복사 중\n"
            cp $gaianet_base_dir/gaia-frp/frpc.toml $gaianet_base_dir/backup/
        else
            error "frpc.toml 복사 실패. 파일이 존재하지 않습니다."
            exit 1
        fi
        # deviceid.txt 파일 백업
        if [ -f "$gaianet_base_dir/deviceid.txt" ]; then
            printf "    * deviceid.txt을 $gaianet_base_dir/backup/에 복사 중\n"
            cp $gaianet_base_dir/deviceid.txt $gaianet_base_dir/backup/
        else
            error "deviceid.txt 복사 실패. 파일이 존재하지 않습니다."
            exit 1
        fi
    fi
fi

# 필요한 경우 디렉토리 생성
if [ ! -d "$gaianet_base_dir" ]; then
    printf "[+] $gaianet_base_dir 디렉토리가 없으므로 생성 중...\n"
    mkdir -p "$gaianet_base_dir"
fi

if [ ! -d "$tmp_dir" ]; then
    printf "[+] 임시 디렉토리가 없으므로 생성 중...\n"
    mkdir -p "$tmp_dir"
fi

# 기본 디렉토리로 이동
cd $gaianet_base_dir

# 로그 디렉토리가 존재하는지 확인합니다. gaianet이 로그에 쓸 수 있어야 합니다.
if [ ! -d "$gaianet_base_dir/log" ]; then
    mkdir -p -m777 $gaianet_base_dir/log
fi
log_dir=$gaianet_base_dir/log

# "$gaianet_base_dir/bin" 디렉토리가 존재하는지 확인합니다.
if [ ! -d "$gaianet_base_dir/bin" ]; then
    # 존재하지 않으면 생성합니다.
    mkdir -p -m777 $gaianet_base_dir/bin
fi
bin_dir=$gaianet_base_dir/bin

# 1. gaianet CLI 도구 설치
printf "\033[32m[+] gaianet CLI 도구 설치 중 ...\033[0m\n"
check_curl https://github.com/GaiaNet-AI/gaianet-node/releases/download/$version/gaianet $bin_dir/gaianet

if [ "$repo_branch" = "main" ]; then
    check_curl https://github.com/GaiaNet-AI/gaianet-node/releases/download/$version/gaianet $bin_dir/gaianet
else
    check_curl https://github.com/GaiaNet-AI/gaianet-node/raw/$repo_branch/gaianet $bin_dir/gaianet
fi

chmod u+x $bin_dir/gaianet
info "    * gaianet CLI 도구가 $bin_dir에 설치되었습니다."

# 2. 기본 config.json 다운로드
if [ "$upgrade" -eq 1 ]; then
    printf "\033[32m[+] config.json 복원 중 ...\033[0m\n"

    # config.json 복원
    if [ -f "$gaianet_base_dir/backup/config.json" ]; then
        cp $gaianet_base_dir/backup/config.json $gaianet_base_dir/config.json

        if ! grep -q '"chat_batch_size":' $gaianet_base_dir/config.json; then
            # JSON 객체의 시작 부분에 필드를 추가합니다.
            if [ "$(uname)" == "Darwin" ]; then
                sed -i '' '2i\
                "chat_batch_size": "16",
                ' "$gaianet_base_dir/config.json"

            elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
                sed -i '2i\
                "chat_batch_size": "16",
                ' "$gaianet_base_dir/config.json"

            elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
                error "    * Windows 사용자께서는 이 스크립트를 WSL에서 실행해주세요."
                exit 1
            else
                error "    * Linux, MacOS 및 Windows만 지원합니다."
                exit 1
            fi
        fi

        if ! grep -q '"embedding_batch_size":' $gaianet_base_dir/config.json; then
            # JSON 객체의 시작 부분에 필드를 추가합니다.
            if [ "$(uname)" == "Darwin" ]; then
                sed -i '' '2i\
                "embedding_batch_size": "512",
                ' "$gaianet_base_dir/config.json"

            elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
                sed -i '2i\
                "embedding_batch_size": "512",
                ' "$gaianet_base_dir/config.json"

            elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
                error "    * Windows 사용자께서는 이 스크립트를 WSL에서 실행해주세요."
                exit 1
            else
                error "    * Linux, MacOS 및 Windows만 지원합니다."
                exit 1
            fi
        fi

        info "    * config.json이 $gaianet_base_dir에 복원되었습니다."
    else
        error "    * config.json 복원 실패. 이유: $gaianet_base_dir/backup/에 config.json이 존재하지 않습니다."
        exit 1
    fi

else
    printf "\033[32m[+] 기본 config.json 다운로드 중 ...\033[0m\n"

    if [ ! -f "$gaianet_base_dir/config.json" ]; then
        if [ "$repo_branch" = "main" ]; then
            check_curl https://github.com/GaiaNet-AI/gaianet-node/releases/download/$version/config.json $gaianet_base_dir/config.json
        else
            check_curl https://github.com/GaiaNet-AI/gaianet-node/raw/$repo_branch/config.json $gaianet_base_dir/config.json
        fi

        info "    * 기본 설정 파일이 $gaianet_base_dir에 다운로드되었습니다."
    else
        warning "    * 캐시된 설정 파일을 $gaianet_base_dir에서 사용합니다."
    fi

    # 3. nodeid.json 다운로드
    if [ ! -f "$gaianet_base_dir/nodeid.json" ]; then
        printf "\033[32m[+] nodeid.json 다운로드 중 ...\033[0m\n"
        check_curl https://github.com/GaiaNet-AI/gaianet-node/releases/download/$version/nodeid.json $gaianet_base_dir/nodeid.json

        info "    * nodeid.json이 $gaianet_base_dir에 다운로드되었습니다."
    fi
fi

# 4. vector 설치 및 vector 설정 파일 다운로드
if [ "$enable_vector" -eq 1 ]; then
    # vector가 설치되어 있는지 확인
    if ! command -v vector &> /dev/null; then
        printf "\033[32m[+] vector 설치 중 ...\033[0m\n"
        if curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | VECTOR_VERSION=$vector_version bash -s -- -y; then
            info "    * vector가 설치되었습니다."
        else
            error "    * vector 설치 실패"
            exit 1
        fi
    fi
    # vector.toml이 존재하는지 확인
    if [ ! -f "$gaianet_base_dir/vector.toml" ]; then
        printf "\033[32m[+] vector 설정 파일 다운로드 중 ...\033[0m\n"

        check_curl https://github.com/GaiaNet-AI/gaianet-node/releases/download/$version/vector.toml $gaianet_base_dir/vector.toml

        info "    * vector.toml이 $gaianet_base_dir에 다운로드되었습니다."
    fi
fi

# 5. WasmEdge 및 ggml 플러그인 설치
printf "\033[32m[+] WasmEdge와 wasi-nn_ggml 플러그인 설치 중 ...\033[0m\n"
if [ -n "$ggmlcuda" ]; then
    if [ "$ggmlcuda" != "11" ] && [ "$ggmlcuda" != "12" ]; then
        error "Invalid argument to '--ggmlcuda' option. Possible values: 11, 12."
        exit 1
    fi

    if curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install_v2.sh | bash -s -- -v $wasmedge_version --tmpdir=$tmp_dir --ggmlcuda=$ggmlcuda; then
        source $HOME/.wasmedge/env
        wasmedge_path=$(which wasmedge)
        info "    * $wasmedge_version이 $wasmedge_path에 설치되었습니다."
    else
        error "    * WasmEdge 설치 실패"
        exit 1
    fi
else
    if curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install_v2.sh | bash -s -- -v $wasmedge_version --tmpdir=$tmp_dir; then
        source $HOME/.wasmedge/env
        wasmedge_path=$(which wasmedge)
        info "    * $wasmedge_version이 $wasmedge_path에 설치되었습니다."
    else
        error "    * WasmEdge 설치 실패"
        exit 1
    fi
fi

# 6. Qdrant 바이너리 설치 및 디렉토리 준비

# 6.1 Qdrant 바이너리 설치
printf "[+] Qdrant 바이너리 설치 중...\n"
if [ ! -f "$gaianet_base_dir/bin/qdrant" ] || [ "$reinstall" -eq 1 ]; then
    printf "    * Qdrant 바이너리 다운로드\n"
    if [ "$(uname)" == "Darwin" ]; then
        # Qdrant 바이너리 다운로드
        if [ "$target" = "x86_64" ]; then
            check_curl https://github.com/qdrant/qdrant/releases/download/$qdrant_version/qdrant-x86_64-apple-darwin.tar.gz $gaianet_base_dir/qdrant-x86_64-apple-darwin.tar.gz

            tar -xzf $gaianet_base_dir/qdrant-x86_64-apple-darwin.tar.gz -C $bin_dir
            rm $gaianet_base_dir/qdrant-x86_64-apple-darwin.tar.gz

            printf "      Qdrant 바이너리가 $bin_dir에 다운로드되었습니다.\n"

        elif [ "$target" = "arm64" ]; then
            check_curl https://github.com/qdrant/qdrant/releases/download/$qdrant_version/qdrant-aarch64-apple-darwin.tar.gz $gaianet_base_dir/qdrant-aarch64-apple-darwin.tar.gz

            tar -xzf $gaianet_base_dir/qdrant-aarch64-apple-darwin.tar.gz -C $bin_dir
            rm $gaianet_base_dir/qdrant-aarch64-apple-darwin.tar.gz
            printf "      Qdrant 바이너리가 $bin_dir에 다운로드되었습니다.\n"
        else
            printf " * 지원하지 않는 아키텍처: $target, MacOS에서 x86_64와 arm64만 지원합니다.\n"
            exit 1
        fi

    elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
        # Qdrant 정적 링크 바이너리 다운로드
        if [ "$target" = "x86_64" ]; then
            check_curl https://github.com/qdrant/qdrant/releases/download/$qdrant_version/qdrant-x86_64-unknown-linux-musl.tar.gz $gaianet_base_dir/qdrant-x86_64-unknown-linux-musl.tar.gz

            tar -xzf $gaianet_base_dir/qdrant-x86_64-unknown-linux-musl.tar.gz -C $bin_dir
            rm $gaianet_base_dir/qdrant-x86_64-unknown-linux-musl.tar.gz

            printf "      Qdrant 바이너리가 $bin_dir에 다운로드되었습니다.\n"

        elif [ "$target" = "aarch64" ]; then
            check_curl https://github.com/qdrant/qdrant/releases/download/$qdrant_version/qdrant-aarch64-unknown-linux-musl.tar.gz $gaianet_base_dir/qdrant-aarch64-unknown-linux-musl.tar.gz

            tar -xzf $gaianet_base_dir/qdrant-aarch64-unknown-linux-musl.tar.gz -C $bin_dir
            rm $gaianet_base_dir/qdrant-aarch64-unknown-linux-musl.tar.gz
            printf "      Qdrant 바이너리가 $bin_dir에 다운로드되었습니다.\n"
        else
            printf " * 지원하지 않는 아키텍처: $target, Linux에서 x86_64와 aarch64만 지원합니다.\n"
            exit 1
        fi

    elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
        printf "    * Windows 사용자는 이 스크립트를 WSL에서 실행하십시오.\n"
        exit 1
    else
        printf "    * Linux, MacOS 및 Windows만 지원합니다.\n"
        exit 1
    fi

else
    printf "    * 캐시된 Qdrant 바이너리를 $gaianet_base_dir/bin에서 사용합니다.\n"
fi

# 6.2 Qdrant 디렉토리 초기화
if [ ! -d "$gaianet_base_dir/qdrant" ]; then
    printf "    * Qdrant 디렉토리 초기화 중...\n"
    mkdir -p -m777 $gaianet_base_dir/qdrant && cd $gaianet_base_dir/qdrant

    # Qdrant 바이너리 다운로드
    check_curl_silent https://github.com/qdrant/qdrant/archive/refs/tags/$qdrant_version.tar.gz $gaianet_base_dir/qdrant/$qdrant_version.tar.gz

    mkdir -p "$qdrant_version"
    tar -xzf "$gaianet_base_dir/qdrant/$qdrant_version.tar.gz" -C "$qdrant_version" --strip-components 1
    rm $gaianet_base_dir/qdrant/$qdrant_version.tar.gz

    cp -r $qdrant_version/config .
    rm -rf $qdrant_version

    printf "\n"

    # `config.yaml` 파일에서 텔레메트리 비활성화
    printf "    * 텔레메트리 비활성화\n"
    config_file="$gaianet_base_dir/qdrant/config/config.yaml"

    if [ -f "$config_file" ]; then
        if [ "$(uname)" == "Darwin" ]; then
            sed -i '' 's/telemetry_disabled: false/telemetry_disabled: true/' "$config_file"
        elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
            sed -i 's/telemetry_disabled: false/telemetry_disabled: true/' "$config_file"
        elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
            printf "Windows 사용자는 이 스크립트를 WSL에서 실행하십시오.\n"
            exit 1
        else
            printf "Linux, MacOS 및 Windows(WSL)만 지원합니다.\n"
            exit 1
        fi
    fi

    printf "\n"
fi

# 7. LlamaEdge API 서버 다운로드
printf "[+] LlamaEdge API 서버 다운로드 중...\n"
# rag-api-server.wasm 다운로드
check_curl https://github.com/LlamaEdge/rag-api-server/releases/download/$rag_api_server_version/rag-api-server.wasm $gaianet_base_dir/rag-api-server.wasm
# llama-api-server.wasm 다운로드
check_curl https://github.com/LlamaEdge/LlamaEdge/releases/download/$llama_api_server_version/llama-api-server.wasm $gaianet_base_dir/llama-api-server.wasm

printf "    * rag-api-server.wasm 및 llama-api-server.wasm이 $gaianet_base_dir에 다운로드되었습니다.\n"

# 8. 대시보드 다운로드
if ! command -v tar &> /dev/null; then
    printf "tar를 찾을 수 없습니다. 설치하십시오.\n"
    exit 1
fi
printf "[+] 대시보드 다운로드 중...\n"
if [ ! -d "$gaianet_base_dir/dashboard" ] || [ "$reinstall" -eq 1 ]; then
    if [ -d "$gaianet_base_dir/gaianet-node" ]; then
        rm -rf $gaianet_base_dir/gaianet-node
    fi

    check_curl https://github.com/GaiaNet-AI/chatbot-ui/releases/download/$dashboard_version/dashboard.tar.gz $gaianet_base_dir/dashboard.tar.gz
    tar xzf $gaianet_base_dir/dashboard.tar.gz -C $gaianet_base_dir
    rm -rf $gaianet_base_dir/dashboard.tar.gz

    printf "    * 대시보드가 $gaianet_base_dir에 다운로드되었습니다.\n"
else
    printf "    * 캐시된 대시보드를 $gaianet_base_dir에서 사용합니다.\n"
fi

# 9. registry.wasm 다운로드
if [ ! -f "$gaianet_base_dir/registry.wasm" ] || [ "$reinstall" -eq 1 ]; then
    printf "[+] registry.wasm 다운로드 중...\n"
    check_curl https://github.com/GaiaNet-AI/gaianet-node/raw/main/utils/registry/registry.wasm $gaianet_base_dir/registry.wasm
    printf "    * registry.wasm이 $gaianet_base_dir에 다운로드되었습니다.\n"
else
    printf "    * 캐시된 registry.wasm을 $gaianet_base_dir에서 사용합니다.\n"
fi

# 10. 노드 ID 생성
if [ "$upgrade" -eq 1 ]; then
    printf "\033[1;34m[+] 노드 ID 복구 중...\033[0m\n"

    # keystore 파일 복구
    if [ -f "$gaianet_base_dir/backup/$keystore_filename" ]; then
        cp $gaianet_base_dir/backup/$keystore_filename $gaianet_base_dir/
        info "\033[1;32m    * keystore 파일이 $gaianet_base_dir에 복구되었습니다.\033[0m"
    else
        error "\033[1;31mkeystore 파일 복구 실패. 이유: $gaianet_base_dir/backup/에 keystore 파일이 존재하지 않습니다.\033[0m"
        exit 1
    fi

    # nodeid.json 복구
    if [ -f "$gaianet_base_dir/backup/nodeid.json" ]; then
        cp $gaianet_base_dir/backup/nodeid.json $gaianet_base_dir/nodeid.json
        info "\033[1;32m    * 노드 ID가 $gaianet_base_dir에 복구되었습니다.\033[0m"
    else
        error "\033[1;31m노드 ID 복구 실패. 이유: $gaianet_base_dir/backup/에 nodeid.json이 존재하지 않습니다.\033[0m"
        exit 1
    fi

else
    printf "\033[1;34m[+] 노드 ID 생성 중...\033[0m\n"
    cd $gaianet_base_dir
    wasmedge --dir .:. registry.wasm
    printf "\n"
fi

# 11. gaia-frp 설치
printf "\033[1;34m[+] gaia-frp 설치 중...\033[0m\n"
# 디렉토리 존재 여부 확인, 없으면 생성
if [ ! -d "$gaianet_base_dir/gaia-frp" ]; then
    mkdir -p -m777 $gaianet_base_dir/gaia-frp
fi
cd $gaianet_base_dir
gaia_frp_version="v0.1.2"
printf "    * gaia-frp 바이너리 다운로드 중\n"
if [ "$(uname)" == "Darwin" ]; then
    if [ "$target" = "x86_64" ]; then
        check_curl https://github.com/GaiaNet-AI/gaia-frp/releases/download/$gaia_frp_version/gaia_frp_${gaia_frp_version}_darwin_amd64.tar.gz $gaianet_base_dir/gaia_frp_${gaia_frp_version}_darwin_amd64.tar.gz

        tar -xzf $gaianet_base_dir/gaia_frp_${gaia_frp_version}_darwin_amd64.tar.gz --strip-components=1 -C $gaianet_base_dir/gaia-frp
        rm $gaianet_base_dir/gaia_frp_${gaia_frp_version}_darwin_amd64.tar.gz

        info "\033[1;32m      gaia-frp가 $gaianet_base_dir에 다운로드되었습니다.\033[0m"
    elif [ "$target" = "arm64" ] || [ "$target" = "aarch64" ]; then
        check_curl https://github.com/GaiaNet-AI/gaia-frp/releases/download/$gaia_frp_version/gaia_frp_${gaia_frp_version}_darwin_arm64.tar.gz $gaianet_base_dir/gaia_frp_${gaia_frp_version}_darwin_arm64.tar.gz

        tar -xzf $gaianet_base_dir/gaia_frp_${gaia_frp_version}_darwin_arm64.tar.gz --strip-components=1 -C $gaianet_base_dir/gaia-frp
        rm $gaianet_base_dir/gaia_frp_${gaia_frp_version}_darwin_arm64.tar.gz

        info "\033[1;32m      gaia-frp가 $gaianet_base_dir에 다운로드되었습니다.\033[0m"
    else
        error "\033[1;31m * 지원하지 않는 아키텍처: $target, MacOS에서 x86_64와 arm64만 지원합니다.\033[0m"
        exit 1
    fi

elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    # gaia-frp 정적 링크 바이너리 다운로드
    if [ "$target" = "x86_64" ]; then
        check_curl https://github.com/GaiaNet-AI/gaia-frp/releases/download/$gaia_frp_version/gaia_frp_${gaia_frp_version}_linux_amd64.tar.gz $gaianet_base_dir/gaia_frp_${gaia_frp_version}_linux_amd64.tar.gz

        tar --warning=no-unknown-keyword -xzf $gaianet_base_dir/gaia_frp_${gaia_frp_version}_linux_amd64.tar.gz --strip-components=1 -C $gaianet_base_dir/gaia-frp
        rm $gaianet_base_dir/gaia_frp_${gaia_frp_version}_linux_amd64.tar.gz

        info "\033[1;32m      gaia-frp가 $gaianet_base_dir에 다운로드되었습니다.\033[0m"
    elif [ "$target" = "arm64" ] || [ "$target" = "aarch64" ]; then
        check_curl https://github.com/GaiaNet-AI/gaia-frp/releases/download/$gaia_frp_version/gaia_frp_${gaia_frp_version}_linux_arm64.tar.gz $gaianet_base_dir/gaia_frp_${gaia_frp_version}_linux_arm64.tar.gz

        tar --warning=no-unknown-keyword -xzf $gaianet_base_dir/gaia_frp_${gaia_frp_version}_linux_arm64.tar.gz --strip-components=1 -C $gaianet_base_dir/gaia-frp
        rm $gaianet_base_dir/gaia_frp_${gaia_frp_version}_linux_arm64.tar.gz

        info "\033[1;32m      gaia-frp가 $gaianet_base_dir에 다운로드되었습니다.\033[0m"
    else
        error "\033[1;31m * 지원하지 않는 아키텍처: $target, Linux에서 x86_64와 arm64만 지원합니다.\033[0m"
        exit 1
    fi

elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
    error "\033[1;31mWindows 사용자는 이 스크립트를 WSL에서 실행하십시오.\033[0m"
    exit 1
else
    error "\033[1;31mLinux, MacOS 및 Windows만 지원합니다.\033[0m"
    exit 1
fi

# frpc 바이너리를 $gaianet_base_dir/gaia-frp에서 $gaianet_base_dir/bin으로 복사
printf "    * frpc 바이너리 설치 중\n"
cp $gaianet_base_dir/gaia-frp/frpc $gaianet_base_dir/bin/
info "\033[1;32m      frpc 바이너리가 $gaianet_base_dir/bin에 설치되었습니다.\033[0m"

# 12. frpc.toml 다운로드, 서브도메인 생성 및 출력
if [ "$upgrade" -eq 1 ]; then
    # frpc.toml 복구
    if [ -f "$gaianet_base_dir/backup/frpc.toml" ]; then
        printf "    * frpc.toml 복구 중\n"
        cp $gaianet_base_dir/backup/frpc.toml $gaianet_base_dir/gaia-frp/frpc.toml
        info "\033[1;32m      frpc.toml이 $gaianet_base_dir/gaia-frp에 복구되었습니다.\033[0m"
    else
        error "\033[1;31mfrpc.toml 복구 실패. 이유: $gaianet_base_dir/backup/에 frpc.toml이 존재하지 않습니다.\033[0m"
        exit 1
    fi
else
    printf "    * frpc.toml 다운로드 중\n"
    check_curl_silent https://github.com/GaiaNet-AI/gaianet-node/releases/download/$version/frpc.toml $gaianet_base_dir/gaia-frp/frpc.toml
    info "\033[1;32m      frpc.toml이 $gaianet_base_dir/gaia-frp에 다운로드되었습니다.\033[0m"
fi

# config.json에서 주소 읽기
subdomain=$(awk -F'"' '/"address":/ {print $4}' $gaianet_base_dir/config.json)

# 서브도메인이 제대로 읽혔는지 확인
if [ -z "$subdomain" ]; then
    error "\033[1;31mconfig.json에서 주소를 읽어오는 데 실패했습니다.\033[0m"
    exit 1
fi

# config.json에서 도메인 읽기
gaia_frp=$(awk -F'"' '/"domain":/ {print $4}' $gaianet_base_dir/config.json)

# frpc.toml에서 serverAddr 및 subdomain 교체
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sed_i_cmd="sed -i"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    sed_i_cmd="sed -i ''"
else
    echo "\033[1;31m지원하지 않는 OS\033[0m"
    exit 1
fi

if [ "$upgrade" -eq 1 ]; then
    # deviceid.txt 복구
    if [ -f "$gaianet_base_dir/backup/deviceid.txt" ]; then
        cp $gaianet_base_dir/backup/deviceid.txt $gaianet_base_dir/deviceid.txt

        info "\033[1;32m    * deviceid.txt가 $gaianet_base_dir에 복구되었습니다.\033[0m"
    else
        warning "\033[1;33m    * deviceid.txt가 $gaianet_base_dir/backup/에 존재하지 않습니다. 새로 생성됩니다.\033[0m"
    fi
fi

device_id_file="$gaianet_base_dir/deviceid.txt"

# device_id 파일 존재 여부 확인
if [ -f "$device_id_file" ]; then
    # 파일이 존재하면 device_id 읽기
    device_id=$(cat "$device_id_file")
    # device_id가 비어있는지 확인
    if [ -z "$device_id" ]; then
        # device_id가 비어있으면 새로 생성
        device_id="device-$(openssl rand -hex 12)"
        echo "$device_id" > "$device_id_file"
    fi
else
    # 파일이 존재하지 않으면 새 device_id 생성 후 파일에 저장
    device_id="device-$(openssl rand -hex 12)"
    echo "$device_id" > "$device_id_file"
fi

# pulse API URL을 위한 서브도메인 교체
$sed_i_cmd "s/\$subdomain/$subdomain/g" $gaianet_base_dir/config.json

$sed_i_cmd "s/subdomain = \".*\"/subdomain = \"$subdomain\"/g" $gaianet_base_dir/gaia-frp/frpc.toml
$sed_i_cmd "s/serverAddr = \".*\"/serverAddr = \"$gaia_frp\"/g" $gaianet_base_dir/gaia-frp/frpc.toml
$sed_i_cmd "s/name = \".*\"/name = \"$subdomain.$gaia_frp\"/g" $gaianet_base_dir/gaia-frp/frpc.toml
$sed_i_cmd "s/metadatas.deviceId = \".*\"/metadatas.deviceId = \"$device_id\"/g" $gaianet_base_dir/gaia-frp/frpc.toml

# frpc 및 frpc.toml을 제외한 모든 파일 제거
find $gaianet_base_dir/gaia-frp -type f -not -name 'frpc.toml' -exec rm -f {} \;

# 13. 서버 어시스턴트 설치
printf "\033[1;34m[+] 서버 어시스턴트 설치 중...\033[0m\n"
if [ "$(uname)" == "Darwin" ]; then

    if [ "$target" = "x86_64" ]; then
        check_curl https://github.com/GaiaNet-AI/server-assistant/releases/download/$assistant_version/server-assistant-x86_64-apple-darwin.tar.gz $bin_dir/server-assistant.tar.gz

    elif [ "$target" = "arm64" ]; then
        check_curl https://github.com/GaiaNet-AI/server-assistant/releases/download/$assistant_version/server-assistant-aarch64-apple-darwin.tar.gz $bin_dir/server-assistant.tar.gz

    else
        error "\033[1;31m * 지원하지 않는 아키텍처: $target, MacOS에서 x86_64와 arm64만 지원합니다.\033[0m"
        exit 1
    fi

elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then

    if [ "$target" = "x86_64" ]; then
        check_curl https://github.com/GaiaNet-AI/server-assistant/releases/download/$assistant_version/server-assistant-x86_64-unknown-linux-gnu.tar.gz $bin_dir/server-assistant.tar.gz
    else
        error "\033[1;31m * 지원하지 않는 아키텍처: $target, Linux에서 x86_64만 지원합니다.\033[0m"
        exit 1
    fi

else
    error "\033[1;31mLinux, MacOS 및 Windows(WSL)만 지원합니다.\033[0m"
    exit 1
fi

tar -xzf $bin_dir/server-assistant.tar.gz -C $bin_dir
rm $bin_dir/server-assistant.tar.gz
if [ -f $bin_dir/SHA256SUM ]; then
    rm $bin_dir/SHA256SUM
fi

info "\033[1;32m    * 서버 어시스턴트가 $bin_dir에 설치되었습니다.\033[0m"

if [ "$upgrade" -eq 1 ]; then
    printf "\033[1;34m[+] 완료! gaianet 노드가 v$version으로 업그레이드되었습니다.\033[0m\n\n"
    info "\033[1;36m>>> 다음으로 'gaianet init' 명령어를 실행하여 GaiaNet 노드를 초기화해야 합니다.\033[0m"

else
    printf "\033[1;34m[+] 완료! gaianet 노드가 성공적으로 설치되었습니다.\033[0m\n\n"
    info "\033[1;36m당신의 노드 ID는 $subdomain입니다. 포털 계정에 등록하여 보상을 받으세요!\033[0m"

    # 추가할 명령어
    cmd="export PATH=\"$bin_dir:\$PATH\""

    shell="${SHELL#${SHELL%/*}/}"
    shell_rc=".""$shell""rc"

    # 셸이 zsh 또는 bash인지 확인
    if [[ $shell == *'zsh'* ]]; then
        # zsh인 경우 .zprofile에 추가
        if ! grep -Fxq "$cmd" $HOME/.zprofile
        then
            echo "$cmd" >> $HOME/.zprofile
        fi

        # zsh인 경우 .zshrc에 추가
        if ! grep -Fxq "$cmd" $HOME/.zshrc
        then
            echo "$cmd" >> $HOME/.zshrc
        fi

    elif [[ $shell == *'bash'* ]]; then
        # bash인 경우 .bash_profile에 추가
        if ! grep -Fxq "$cmd" $HOME/.bash_profile
        then
            echo "$cmd" >> $HOME/.bash_profile
        fi

        # bash인 경우 .bashrc에 추가
        if ! grep -Fxq "$cmd" $HOME/.bashrc
        then
            echo "$cmd" >> $HOME/.bashrc
        fi
    fi
fi

# CLI 설정
echo -e "${YELLOW}CLI설정을 진행중입니다.${NC}"
source /root/.bashrc

# 기본 포트 설정
starting_port=8080  # 시작 포트를 8080으로 설정
max_port=8090       # 최대 포트 번호

# 포트가 사용 중인지 확인하는 함수
check_port() {
    if lsof -i :$1 > /dev/null; then
        return 1  # 포트 사용 중
    else
        return 0  # 포트 사용 가능
    fi
}

# 포트 확인
desired_port=$starting_port
while [ $desired_port -le $max_port ]; do
    if check_port $desired_port; then
        echo -e "${GREEN}사용 가능한 포트를 찾았습니다: $desired_port${NC}"
        break
    fi
    desired_port=$((desired_port + 1))
done

# 포트가 사용 중인 경우 처리
if [ $desired_port -gt $max_port ]; then
    echo -e "${RED}사용 가능한 포트를 찾을 수 없습니다.${NC}"
    exit 1
fi

# config.json 파일에서 포트 변경
sed -i "s/\"llamaedge_port\": \".*\"/\"llamaedge_port\": \"$desired_port\"/" $gaianet_base_dir/config.json

# UFW에서 포트 개방
echo -e "${YELLOW}UFW에서 포트 $desired_port 를 개방합니다...${NC}"
ufw allow $desired_port/tcp

# 노드 시작
cd $gaianet_base_dir
gaianet start

# 노드 시작
cd $gaianet_base_dir
gaianet init
gaianet start

echo -e "${YELLOW}설치가 종료되면 해당 명령어를 입력하세요: cd "$gaianet_base_dir"${NC}"
echo -e "${YELLOW}다음으로 이 명령어를 입력하세요: gaianet init${NC}"
echo -e "${YELLOW}다음으로 이 명령어를 입력하세요: gaianet start${NC}"
echo -e "${YELLOW}위 명령어까지 모두 입력하고 나면 URL이 하나가 나올겁니다. 해당 URL로 접속해주세요.${NC}"
echo -e "${YELLOW}접속한 URL에서 Chat with this node 버튼을 클릭해주세요${NC}"
echo -e "${GREEN}노드ID는 $subdomain 입니다. 기억해주세요${NC}"
echo -e "${GREEN}모든 작업이 완료되었습니다. 컨트롤 A+D로 스크린을 나가주세요.${NC}"
echo -e "${GREEN}스크립트 작성자: https://t.me/kjkresearch${NC}"
