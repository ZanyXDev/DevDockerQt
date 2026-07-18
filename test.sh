#!/usr/bin/env bash
set -Euo pipefail
#set -x  # Раскомментируйте только для отладки

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
    echo -e "${GREEN}✅${NC} Сообщение"
fi

check_deps() {
    local deps=(wget git cmake ninja-build openjdk-21-jdk)
    for pkg in "${deps[@]}"; do
        command -v "$pkg" >/dev/null 2>&1 || { echo -e "${RED}❌ ${NC} Требуется: $pkg"; exit 1; }
    done
}
check_deps

