#!/bin/bash
# =================================================================
# PyTorch 自動インストールスクリプト
# =================================================================
# CUDAバージョンを自動検出し、適切なPyTorchをインストール
#
# 使用方法:
#   ./scripts/install_pytorch.sh              # 自動検出 (pip)
#   ./scripts/install_pytorch.sh --uv         # UV使用
#   ./scripts/install_pytorch.sh --cuda 11.8  # CUDA指定
#   ./scripts/install_pytorch.sh --cpu        # CPU版
#   ./scripts/install_pytorch.sh --dry-run    # 実行せず表示のみ
# =================================================================

set -e

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# デフォルト設定
TORCH_VERSION=""        # 空=最新
TORCHVISION_VERSION=""  # 空=最新
TORCHAUDIO_VERSION=""   # 空=最新
INSTALL_TORCH=true
INSTALL_TORCHVISION=true
INSTALL_TORCHAUDIO=true
DRY_RUN=false
FORCE_CPU=false
FORCE_CUDA=""
USE_UV=false
USE_SYSTEM=false
AUTO_VENV=false
VENV_PATH=".venv"

# ヘルプ表示
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Package Manager Options:
    --uv              UV を使用してインストール
    --system          システムPythonにインストール (pip --break-system-packages / uv --system)
    --venv [PATH]     仮想環境を自動作成 (デフォルト: .venv)

CUDA Options:
    --cuda VERSION    CUDAバージョンを指定 (例: 11.8, 12.1, 12.4)
    --cpu             CPU版をインストール

Package Options:
    --torch VERSION       torch バージョン指定 (例: 2.4.0)
    --torchvision VERSION torchvision バージョン指定
    --torchaudio VERSION  torchaudio バージョン指定
    --no-torch            torch をインストールしない
    --no-torchvision      torchvision をインストールしない
    --no-torchaudio       torchaudio をインストールしない
    --only-torch          torch のみインストール

Other Options:
    --dry-run         実行せずコマンドを表示
    -h, --help        ヘルプを表示

Examples:
    $(basename "$0") --venv                   # .venv 作成してインストール
    $(basename "$0") --uv --venv              # UV + .venv 自動作成
    $(basename "$0") --venv myenv             # myenv 作成してインストール
    $(basename "$0") --cuda 11.8              # CUDA 11.8指定
    $(basename "$0") --torch 2.4.0            # torch バージョン指定
    $(basename "$0") --only-torch             # torch のみ
    $(basename "$0") --cpu                    # CPU版

Virtual Environment:
    --venv        仮想環境を自動作成してインストール
    --system      システムPythonにインストール (非推奨)
    (なし)        既存の仮想環境が必要
EOF
}

# 引数パース
while [[ $# -gt 0 ]]; do
    case $1 in
        --cuda)
            FORCE_CUDA="$2"
            shift 2
            ;;
        --cpu)
            FORCE_CPU=true
            shift
            ;;
        --torch)
            TORCH_VERSION="$2"
            shift 2
            ;;
        --torchvision)
            TORCHVISION_VERSION="$2"
            shift 2
            ;;
        --torchaudio)
            TORCHAUDIO_VERSION="$2"
            shift 2
            ;;
        --no-torch)
            INSTALL_TORCH=false
            shift
            ;;
        --no-torchvision)
            INSTALL_TORCHVISION=false
            shift
            ;;
        --no-torchaudio)
            INSTALL_TORCHAUDIO=false
            shift
            ;;
        --only-torch)
            INSTALL_TORCHVISION=false
            INSTALL_TORCHAUDIO=false
            shift
            ;;
        --uv)
            USE_UV=true
            shift
            ;;
        --system)
            USE_SYSTEM=true
            shift
            ;;
        --venv)
            AUTO_VENV=true
            # 次の引数がオプションでなければパスとして扱う
            if [[ -n "$2" ]] && [[ ! "$2" =~ ^- ]]; then
                VENV_PATH="$2"
                shift
            fi
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# 仮想環境検出
detect_venv() {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo "$VIRTUAL_ENV"
    elif [[ -n "$CONDA_PREFIX" ]]; then
        echo "$CONDA_PREFIX"
    else
        echo ""
    fi
}

# 仮想環境作成
create_venv() {
    local venv_path="$1"

    if [[ -d "$venv_path" ]]; then
        echo -e "${YELLOW}Virtual environment already exists: ${venv_path}${NC}" >&2
        return 0
    fi

    echo -e "${BLUE}Creating virtual environment: ${venv_path}${NC}" >&2

    if [[ "$USE_UV" == true ]]; then
        if ! uv venv "$venv_path"; then
            echo -e "${RED}Failed to create virtual environment with uv${NC}" >&2
            return 1
        fi
    else
        if ! python3 -m venv "$venv_path"; then
            echo -e "${RED}Failed to create virtual environment${NC}" >&2
            return 1
        fi
    fi

    echo -e "${GREEN}Created: ${venv_path}${NC}" >&2
    return 0
}

# CUDAバージョン検出
detect_cuda_version() {
    local cuda_version=""
    
    # 方法1: nvcc
    if command -v nvcc &> /dev/null; then
        cuda_version=$(nvcc --version | grep "release" | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p')
        echo -e "${BLUE}Detected CUDA from nvcc: ${cuda_version}${NC}" >&2
    fi
    
    # 方法2: nvidia-smi
    if [[ -z "$cuda_version" ]] && command -v nvidia-smi &> /dev/null; then
        cuda_version=$(nvidia-smi | grep "CUDA Version" | sed -n 's/.*CUDA Version: \([0-9]*\.[0-9]*\).*/\1/p')
        echo -e "${BLUE}Detected CUDA from nvidia-smi: ${cuda_version}${NC}" >&2
    fi
    
    # 方法3: /usr/local/cuda
    if [[ -z "$cuda_version" ]] && [[ -d "/usr/local/cuda" ]]; then
        if [[ -f "/usr/local/cuda/version.txt" ]]; then
            cuda_version=$(cat /usr/local/cuda/version.txt | sed -n 's/CUDA Version \([0-9]*\.[0-9]*\).*/\1/p')
        elif [[ -f "/usr/local/cuda/version.json" ]]; then
            cuda_version=$(cat /usr/local/cuda/version.json | grep -o '"cuda" *: *"[^"]*"' | sed 's/.*"\([0-9]*\.[0-9]*\).*/\1/')
        fi
        if [[ -n "$cuda_version" ]]; then
            echo -e "${BLUE}Detected CUDA from /usr/local/cuda: ${cuda_version}${NC}" >&2
        fi
    fi
    
    # 方法4: ldconfig
    if [[ -z "$cuda_version" ]]; then
        local libcudart=$(ldconfig -p 2>/dev/null | grep libcudart.so | head -1)
        if [[ -n "$libcudart" ]]; then
            cuda_version=$(echo "$libcudart" | sed -n 's/.*libcudart.so.\([0-9]*\.[0-9]*\).*/\1/p')
            if [[ -n "$cuda_version" ]]; then
                echo -e "${BLUE}Detected CUDA from ldconfig: ${cuda_version}${NC}" >&2
            fi
        fi
    fi
    
    echo "$cuda_version"
}

# CUDAバージョンをPyTorchインデックスにマッピング
get_pytorch_index() {
    local cuda_version="$1"
    local major_minor
    
    if [[ -z "$cuda_version" ]]; then
        echo "cpu"
        return
    fi
    
    # メジャー.マイナーを抽出
    major_minor=$(echo "$cuda_version" | grep -oE '^[0-9]+\.[0-9]+')
    
    case "$major_minor" in
        11.8|11.7|11.6)
            echo "cu118"
            ;;
        12.0|12.1)
            echo "cu121"
            ;;
        12.2|12.3|12.4|12.5|12.6)
            echo "cu124"
            ;;
        11.*)
            echo -e "${YELLOW}CUDA $major_minor は古いため cu118 を使用${NC}" >&2
            echo "cu118"
            ;;
        *)
            echo -e "${YELLOW}CUDA $major_minor は未対応、cu124 を試行${NC}" >&2
            echo "cu124"
            ;;
    esac
}

# パッケージ文字列生成
build_package_spec() {
    local pkg_name="$1"
    local pkg_version="$2"
    local cuda_tag="$3"

    if [[ -z "$pkg_version" ]]; then
        echo "$pkg_name"
    elif [[ "$cuda_tag" == "cpu" ]]; then
        echo "${pkg_name}==${pkg_version}"
    else
        # torchvision/torchaudio は +cu タグ不要な場合もあるが安全のため統一
        echo "${pkg_name}==${pkg_version}"
    fi
}

# インストールコマンド生成
generate_install_command() {
    local cuda_tag="$1"
    local venv="$2"
    local index_url
    local cmd
    local packages=""

    if [[ "$cuda_tag" == "cpu" ]]; then
        index_url="https://download.pytorch.org/whl/cpu"
    else
        index_url="https://download.pytorch.org/whl/${cuda_tag}"
    fi

    # パッケージリスト構築
    if [[ "$INSTALL_TORCH" == true ]]; then
        packages="$(build_package_spec torch "$TORCH_VERSION" "$cuda_tag")"
    fi

    if [[ "$INSTALL_TORCHVISION" == true ]]; then
        local tv_spec=$(build_package_spec torchvision "$TORCHVISION_VERSION" "$cuda_tag")
        if [[ -n "$packages" ]]; then
            packages="$packages $tv_spec"
        else
            packages="$tv_spec"
        fi
    fi

    if [[ "$INSTALL_TORCHAUDIO" == true ]]; then
        local ta_spec=$(build_package_spec torchaudio "$TORCHAUDIO_VERSION" "$cuda_tag")
        if [[ -n "$packages" ]]; then
            packages="$packages $ta_spec"
        else
            packages="$ta_spec"
        fi
    fi

    # パッケージが空の場合
    if [[ -z "$packages" ]]; then
        echo -e "${RED}Error: No packages selected for installation${NC}" >&2
        exit 1
    fi

    if [[ "$USE_UV" == true ]]; then
        # UV使用
        if ! command -v uv &> /dev/null; then
            echo -e "${RED}Error: uv not found. Install with: curl -LsSf https://astral.sh/uv/install.sh | sh${NC}" >&2
            exit 1
        fi

        if [[ -n "$venv" ]]; then
            # 仮想環境のPythonを指定
            cmd="uv pip install --python ${venv}/bin/python"
        elif [[ "$USE_SYSTEM" == true ]]; then
            cmd="uv pip install --system --break-system-packages"
        else
            # 仮想環境がない場合は作成を促す
            echo -e "${RED}Error: No virtual environment detected${NC}" >&2
            echo -e "${YELLOW}Use --venv to auto-create one, or activate an existing venv${NC}" >&2
            echo -e "${YELLOW}Or use --system to force system install (not recommended)${NC}" >&2
            exit 1
        fi
    else
        # pip使用
        if [[ -n "$venv" ]]; then
            # 仮想環境のpipを使用
            if [[ -f "${venv}/bin/pip" ]]; then
                cmd="${venv}/bin/pip install"
            else
                cmd="pip install"
            fi
        elif [[ "$USE_SYSTEM" == true ]]; then
            # システムインストール (Python 3.11+ では --break-system-packages が必要)
            local python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
            if [[ "$(echo "$python_version >= 3.11" | bc -l 2>/dev/null || echo 0)" == "1" ]]; then
                cmd="pip install --break-system-packages"
            else
                cmd="pip install"
            fi
        else
            # 仮想環境がない場合は作成を促す
            echo -e "${RED}Error: No virtual environment detected${NC}" >&2
            echo -e "${YELLOW}Use --venv to auto-create one, or activate an existing venv${NC}" >&2
            echo -e "${YELLOW}Or use --system to force system install (not recommended)${NC}" >&2
            exit 1
        fi
    fi

    echo "$cmd $packages --index-url $index_url"
}

# メイン処理
main() {
    echo "=========================================="
    echo "PyTorch Auto Installer"
    echo "=========================================="
    
    # パッケージマネージャー表示
    if [[ "$USE_UV" == true ]]; then
        echo -e "${BLUE}Package manager: UV${NC}"
    else
        echo -e "${BLUE}Package manager: pip${NC}"
    fi
    
    # 仮想環境処理
    local venv=$(detect_venv)
    local venv_abs_path=""

    if [[ "$AUTO_VENV" == true ]]; then
        # 仮想環境を作成/使用
        venv_abs_path=$(realpath "$VENV_PATH" 2>/dev/null || echo "$PWD/$VENV_PATH")
        if ! create_venv "$venv_abs_path"; then
            exit 1
        fi
        venv="$venv_abs_path"
        echo -e "${GREEN}Virtual environment: ${venv}${NC}"
    elif [[ -n "$venv" ]]; then
        echo -e "${GREEN}Virtual environment: ${venv}${NC}"
    elif [[ "$USE_SYSTEM" == true ]]; then
        echo -e "${YELLOW}Installing to system Python (--system)${NC}"
    fi
    
    # CUDA検出
    local cuda_version
    if [[ "$FORCE_CPU" == true ]]; then
        echo -e "${BLUE}CPU版を使用${NC}"
        cuda_version=""
    elif [[ -n "$FORCE_CUDA" ]]; then
        echo -e "${BLUE}指定されたCUDA: ${FORCE_CUDA}${NC}"
        cuda_version="$FORCE_CUDA"
    else
        echo "CUDAバージョンを検出中..."
        cuda_version=$(detect_cuda_version)
        
        if [[ -z "$cuda_version" ]]; then
            echo -e "${YELLOW}CUDAが検出されませんでした。CPU版をインストールします。${NC}"
        else
            echo -e "${GREEN}検出されたCUDA: ${cuda_version}${NC}"
        fi
    fi
    
    # PyTorchインデックス取得
    local cuda_tag=$(get_pytorch_index "$cuda_version")
    echo -e "${BLUE}PyTorch CUDA tag: ${cuda_tag}${NC}"
    
    # パッケージ表示
    echo ""
    echo "Packages to install:"
    if [[ "$INSTALL_TORCH" == true ]]; then
        local tv="${TORCH_VERSION:-latest}"
        echo -e "  ${GREEN}torch${NC}: $tv"
    fi
    if [[ "$INSTALL_TORCHVISION" == true ]]; then
        local tvv="${TORCHVISION_VERSION:-latest}"
        echo -e "  ${GREEN}torchvision${NC}: $tvv"
    fi
    if [[ "$INSTALL_TORCHAUDIO" == true ]]; then
        local tav="${TORCHAUDIO_VERSION:-latest}"
        echo -e "  ${GREEN}torchaudio${NC}: $tav"
    fi

    # コマンド生成
    local cmd
    cmd=$(generate_install_command "$cuda_tag" "$venv") || exit 1

    echo ""
    echo "=========================================="
    echo -e "${GREEN}Install command:${NC}"
    echo "  $cmd"
    echo "=========================================="
    
    # 実行
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}(dry-run mode - not executing)${NC}"
    else
        echo ""
        echo "Installing..."
        eval "$cmd"
        
        echo ""
        echo -e "${GREEN}Installation complete!${NC}"

        # 仮想環境作成時のアクティベート案内
        if [[ "$AUTO_VENV" == true ]] && [[ -z "$(detect_venv)" ]]; then
            echo ""
            echo -e "${YELLOW}To activate the virtual environment:${NC}"
            echo -e "  source ${venv}/bin/activate"
        fi

        # 検証
        echo ""
        echo "Verifying installation..."
        local python_cmd="python3"
        if [[ -n "$venv" ]] && [[ -f "${venv}/bin/python" ]]; then
            python_cmd="${venv}/bin/python"
        fi
        $python_cmd -c "
import torch
print(f'PyTorch version: {torch.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'CUDA version: {torch.version.cuda}')
    print(f'cuDNN version: {torch.backends.cudnn.version()}')
    print(f'GPU: {torch.cuda.get_device_name(0)}')
"
    fi
}

main "$@"
