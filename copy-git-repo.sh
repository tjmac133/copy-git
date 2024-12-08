#!/bin/bash

# 颜色定义（如果不是在终端中运行则禁用颜色）
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# 检测操作系统
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

OS_TYPE=$(detect_os)

# 错误处理函数
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# 创建临时目录（跨平台兼容）
create_temp_dir() {
    case "$OS_TYPE" in
        windows)
            # Windows 下使用用户临时目录
            TEMP_DIR=$(mktemp -d -t git-copy-XXXXXX 2>/dev/null || mktemp -d "$TEMP/git-copy-XXXXXX")
            ;;
        *)
            # Linux 和 macOS 使用标准 mktemp
            TEMP_DIR=$(mktemp -d)
            ;;
    esac

    if [ ! -d "$TEMP_DIR" ]; then
        error_exit "Failed to create temporary directory"
    fi
}

# 清理函数
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        echo -e "\n${YELLOW}Cleaning up temporary files...${NC}"
        rm -rf "$TEMP_DIR"
    fi
}

# 设置清理钩子
trap cleanup EXIT

# 检查 Git 安装
check_git() {
    if ! command -v git >/dev/null 2>&1; then
        case "$OS_TYPE" in
            windows)
                error_exit "Git is not installed. Please download and install Git from https://git-scm.com/download/win"
                ;;
            macos)
                error_exit "Git is not installed. Please install using Homebrew: brew install git"
                ;;
            linux)
                error_exit "Git is not installed. Please install using your package manager (apt-get install git or yum install git)"
                ;;
            *)
                error_exit "Git is not installed"
                ;;
        esac
    fi
}

# 检查必要的工具
check_git

# 检查参数数量
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <source_repo_http> <destination_repo_ssh>"
    echo "Example: $0 https://github.com/source/repo.git git@github.com:dest/repo.git"
    exit 1
fi

SOURCE_REPO=$1
DEST_REPO=$2
create_temp_dir

# 验证源仓库 URL 格式
if [[ ! $SOURCE_REPO =~ ^https?:// ]]; then
    error_exit "Source repository must use HTTP/HTTPS protocol"
fi

# 验证目标仓库 URL 格式（为 Windows 路径做特殊处理）
if [[ "$OS_TYPE" == "windows" ]]; then
    if [[ ! $DEST_REPO =~ ^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9/._-]+\.git$ && ! $DEST_REPO =~ ^https?:// ]]; then
        error_exit "Destination repository must use SSH protocol (git@host:user/repo.git) or HTTPS protocol"
    fi
else
    if [[ ! $DEST_REPO =~ ^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9/._-]+\.git$ ]]; then
        error_exit "Destination repository must use SSH protocol (git@host:user/repo.git)"
    fi
fi

# 获取 Git 认证信息
echo -e "${BLUE}Please enter your credentials for the source repository:${NC}"
read -p "Username: " GIT_USERNAME
read -s -p "Password/Token: " GIT_PASSWORD
echo

# 创建临时的 netrc 文件（考虑 Windows 的特殊情况）
if [ "$OS_TYPE" == "windows" ]; then
    NETRC_FILE="$TEMP_DIR/_netrc"
else
    NETRC_FILE="$TEMP_DIR/.netrc"
fi

REPO_HOST=$(echo "$SOURCE_REPO" | sed -e 's|^https\?://||' -e 's|/.*$||')

# 创建 netrc 文件
cat > "$NETRC_FILE" << EOF
machine $REPO_HOST
login $GIT_USERNAME
password $GIT_PASSWORD
EOF

# 设置权限（在 Unix-like 系统上）
if [ "$OS_TYPE" != "windows" ]; then
    chmod 600 "$NETRC_FILE"
fi

echo -e "${GREEN}Configuration:${NC}"
echo -e "Operating System: ${YELLOW}$OS_TYPE${NC}"
echo -e "Source repository (HTTP): ${YELLOW}$SOURCE_REPO${NC}"
echo -e "Destination repository (SSH): ${YELLOW}$DEST_REPO${NC}"
echo -e "Working directory: ${YELLOW}$TEMP_DIR${NC}"

# 设置 HOME 环境变量
export HOME="$TEMP_DIR"

# 克隆源仓库
echo -e "\n${GREEN}Cloning source repository...${NC}"
if ! git clone --mirror "$SOURCE_REPO" "$TEMP_DIR/repo"; then
    error_exit "Failed to clone source repository. Please check your credentials and repository URL."
fi

cd "$TEMP_DIR/repo" || error_exit "Failed to enter repository directory"

# 验证是否成功克隆
if [ ! -d "refs" ]; then
    error_exit "Source repository clone seems incomplete"
fi

# 列出源仓库的所有分支
echo -e "\n${GREEN}Source repository branches:${NC}"
git branch -r | grep -v '\->' | while read -r branch; do
    echo -e "${YELLOW}$(echo $branch | sed 's/origin\///')${NC}"
done

# 添加目标仓库作为远程仓库
echo -e "\n${GREEN}Adding destination repository as remote...${NC}"
git remote add destination "$DEST_REPO" || error_exit "Failed to add destination remote"

# 推送所有内容到目标仓库
echo -e "\n${GREEN}Pushing all branches and tags to destination...${NC}"
echo -e "${YELLOW}This may take a while depending on repository size...${NC}"

# 推送所有分支
if ! git push destination --all; then
    error_exit "Failed to push branches to destination"
fi

# 推送所有标签
if ! git push destination --tags; then
    error_exit "Failed to push tags to destination"
fi

# 删除临时的 netrc 文件
rm -f "$NETRC_FILE"

echo -e "\n${GREEN}Repository copying completed successfully!${NC}"

# 显示后续步骤（根据操作系统调整命令）
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Verify the destination repository has all branches:"
echo "   git clone $DEST_REPO"
if [ "$OS_TYPE" == "windows" ]; then
    echo "   cd $(basename "$DEST_REPO" .git | sed 's/\//\\/g')"
else
    echo "   cd $(basename "$DEST_REPO" .git)"
fi
echo "   git branch -a"
echo "2. Check if all tags were copied:"
echo "   git tag -l"
