#!/bin/bash
#=========================
# 환경 설정 변수 정의 (단순화 버전)
#=========================

# --- ANSI Color Codes ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Conda 가상환경 이름 ---
KNEADDATA_ENV="KneadData_env"
KRAKEN_ENV="kraken_env"
FASTP_ENV="fastp_env"

# --- 도구별 세부 옵션 ---
# 이 값들은 자주 변경되지 않으므로 여기에 유지합니다.
TRIMMOMATIC_OPTIONS="SLIDINGWINDOW:4:20 MINLEN:151"
FASTP_OPTIONS="--length_required 30 --detect_adapter_for_pe"
BRACKEN_READ_LEN=100
BRACKEN_LEVELS="S G F O C P K"
BRACKEN_THRESHOLD=6
