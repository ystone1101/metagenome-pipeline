#!/bin/bash
#================================================
# 통합 메타지놈 분석 파이프라인 실행기 (Master Script)
#================================================
set -euo pipefail

FULL_COMMAND_RUN_ALL="$0 \"$@\""

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")

# --- 1. 사용법 안내 함수 ---
print_usage() {
    # 색상 코드 정의
    local RED=$'\033[0;31m'; local GREEN=$'\033[0;32m'; local YELLOW=$'\033[0;33m'
    local BLUE=$'\033[0;34m'; local CYAN=$'\033[0;36m'; local BOLD=$'\033[1m'; local NC=$'\033[0m'

    # ASCII Art Title
    echo -e "${GREEN}"
    echo '    ██████╗  ██████╗ ██╗  ██╗██╗  ██╗ █████╗ ███████╗██████╗ ██╗'
    echo '    ██╔══██╗██╔═══██╗██║ ██╔╝██║ ██╔╝██╔══██╗██╔════╝██╔══██╗██║'
    echo '    ██║  ██║██║   ██║█████╔╝ █████╔╝ ███████║█████╗  ██████╔╝██║'
    echo '    ██║  ██║██║   ██║██╔═██╗ ██╔═██╗ ██╔══██║██╔══╝  ██╔══██╗██║'
    echo '    ██████╔╝╚██████╔╝██║  ██╗██║  ██╗██║  ██║███████╗██████╔╝██║'
    echo '    ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝'
    echo -e "${YELLOW}"
    echo '                      █████╗ ██╗     ██╗'
    echo '                     ██╔══██╗██║     ██║'
    echo '                     ███████║██║     ██║'
    echo '                     ██╔══██║██║     ██║'
    echo '                     ██║  ██║███████╗███████╗'
    echo '                     ╚═╝  ╚═╝╚══════╝╚══════╝'
    echo -e "                   ${RED}${BOLD}--- ALL-IN-ONE PIPELINE ---${NC}"
    echo ""
    echo -e "${YELLOW}Runs the entire metagenome analysis workflow from raw reads to final MAGs.${NC}"
    echo "This command sequentially executes Pipeline 1 (QC & Taxonomy) and Pipeline 2 (MAG Assembly & Annotation)."
    echo ""
    echo -e "${CYAN}${BOLD}Usage:${NC}"
    echo "  $0 <mode> --input_dir <path> --output_dir <path> --kraken2_db <path> --gtdbtk_db <path> --bakta_db <path> [options...]"
    echo ""
    echo -e "${CYAN}${BOLD}Modes:${NC}"
    echo -e "  ${GREEN}host${NC}          - For host-associated samples (uses KneadData for QC)."
    echo -e "  ${GREEN}environmental${NC} - For environmental samples (uses fastp for QC)."
    echo ""
    echo -e "${CYAN}${BOLD}Required Options:${NC}"
    echo "  --input_dir PATH      - Path to the input directory with raw FASTQ files (for Pipeline 1)."
    echo "  --output_dir PATH     - Path to the main output directory for the entire project."
    echo "  --kraken2_db PATH     - Path to the Kraken2 database."
    echo "  --gtdbtk_db PATH      - Path to the GTDB-Tk database."
    echo "  --bakta_db PATH       - Path to the Bakta database."
    echo "  --host_db PATH        - (Required for 'host' mode) Path to the host reference database for KneadData."
    echo ""
    echo -e "${CYAN}${BOLD}Optional Options:${NC}"
    echo "  --threads INT         - Number of threads for all tools. (Default: 6)"
    echo "  --memory_gb INT       - Max memory in Gigabytes for KneadData and MEGAHIT. (Default: 60)"
    echo "  -h, --help            - Display this help message and exit."
    echo ""    
    echo ""
}

# --- 간단한 로깅 함수 ---
log_info() {
    echo -e "\033[0;32m[MASTER] $(date +'%Y-%m-%d %H:%M:%S') | $1\033[0m"
}
log_error() {
    echo -e "\033[0;31m[MASTER-ERROR] $(date +'%Y-%m-%d %H:%M:%S') | $1\033[0m" >&2
}

# --- 2. 기본값 설정 및 인자 파싱 ---
if [[ $# -eq 0 || ("$1" == "-h" || "$1" == "--help") ]]; then print_usage; exit 0; fi

P1_MODE="$1"; shift
if [[ "$P1_MODE" != "host" && "$P1_MODE" != "environmental" ]]; then
    log_error "Invalid mode specified. Choose 'host' or 'environmental'."; print_usage; exit 1
fi

# 변수 초기화
INPUT_DIR=""; OUTPUT_DIR=""; KRAKEN2_DB=""; GTDBTK_DB=""; BAKTA_DB=""; HOST_DB="";
THREADS=6; MEMORY_GB="60"
# 모든 도구별 추가 옵션을 저장할 변수 초기화
KNEADDATA_OPTS=""; FASTP_OPTS=""; KRAKEN2_OPTS=""; MEGAHIT_OPTS=""; METAWRAP_BINNING_OPTS=""
METAWRAP_REFINEMENT_OPTS=""; GTDBTK_OPTS=""; BAKTA_OPTS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --input_dir) INPUT_DIR="${2%/}"; shift 2 ;;
        --output_dir) OUTPUT_DIR="${2%/}"; shift 2 ;;
        --kraken2_db) KRAKEN2_DB="$2"; shift 2 ;;
        --gtdbtk_db) GTDBTK_DB="$2"; shift 2 ;;
        --bakta_db) BAKTA_DB="$2"; shift 2 ;;
        --host_db) HOST_DB="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --memory_gb) MEMORY_GB="$2"; shift 2 ;;
        --kneaddata-opts) KNEADDATA_OPTS="$2"; shift 2 ;;
        --fastp-opts) FASTP_OPTS="$2"; shift 2 ;;
        --kraken2-opts) KRAKEN2_OPTS="$2"; shift 2 ;;
        --megahit-opts) MEGAHIT_OPTS="$2"; shift 2 ;;
        --metawrap-binning-opts) METAWRAP_BINNING_OPTS="$2"; shift 2 ;;
        --metawrap-refinement-opts) METAWRAP_REFINEMENT_OPTS="$2"; shift 2 ;;
        --gtdbtk-opts) GTDBTK_OPTS="$2"; shift 2 ;;
        --bakta-opts) BAKTA_OPTS="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# --- 3. 필수 인자 확인 ---
declare -a error_messages=()
if [[ -z "$INPUT_DIR" ]]; then error_messages+=("  - --input_dir is required."); fi
if [[ -z "$OUTPUT_DIR" ]]; then error_messages+=("  - --output_dir is required."); fi
if [[ -z "$KRAKEN2_DB" ]]; then error_messages+=("  - --kraken2_db is required."); fi
if [[ -z "$GTDBTK_DB" ]]; then error_messages+=("  - --gtdbtk_db is required."); fi
if [[ -z "$BAKTA_DB" ]]; then error_messages+=("  - --bakta_db is required."); fi
if [[ "$P1_MODE" == "host" && -z "$HOST_DB" ]]; then error_messages+=("  - --host_db is required for 'host' mode."); fi

if [ ${#error_messages[@]} -gt 0 ]; then
    log_error "The following required arguments are missing:"
    for msg in "${error_messages[@]}"; do
        log_error "$msg"
    done
    print_usage; exit 1
fi

# --- 4. 파이프라인 단계별 경로 정의 ---
P1_OUTPUT_DIR="${OUTPUT_DIR}/1_microbiome_taxonomy"
P2_OUTPUT_DIR="${OUTPUT_DIR}/2_mag_analysis"
P1_CLEAN_READS_DIR="${P1_OUTPUT_DIR}/01_clean_reads"
P1_STATE_FILE="${P1_OUTPUT_DIR}/.pipeline.state"

# ==========================================================
# --- 파이프라인 실행 ---
# ==========================================================
log_info "--- Starting FULL Metagenome Pipeline ---"
log_info "The pipeline will run in a loop, processing new samples until the input directory is stable."

export DOKKAEBI_MASTER_COMMAND="$FULL_COMMAND_RUN_ALL"

mkdir -p "$P1_OUTPUT_DIR" "$P2_OUTPUT_DIR"

while true; do
    # --- 1단계: QC 및 분류 파이프라인 실행 ---
    log_info "--- Starting Cycle: Running Pipeline 1 (QC & Taxonomy) ---"
    P1_CMD_ARRAY=(
        bash "${PROJECT_ROOT_DIR}/scripts/qc.sh"
        "${P1_MODE}" --input_dir "${INPUT_DIR}" --output_dir "${P1_OUTPUT_DIR}"
        --kraken2_db "${KRAKEN2_DB}" --threads "${THREADS}"
    )
    if [[ "$P1_MODE" == "host" ]]; then
        P1_MEMORY_MB=$((MEMORY_GB * 1024))
        P1_CMD_ARRAY+=(--host_db "${HOST_DB}" --memory "${P1_MEMORY_MB}")
    fi
    if [[ -n "$KNEADDATA_OPTS" ]]; then P1_CMD_ARRAY+=(--kneaddata-opts "$KNEADDATA_OPTS"); fi
    if [[ -n "$FASTP_OPTS" ]]; then P1_CMD_ARRAY+=(--fastp-opts "$FASTP_OPTS"); fi
    if [[ -n "$KRAKEN2_OPTS" ]]; then P1_CMD_ARRAY+=(--kraken2-opts "$KRAKEN2_OPTS"); fi

    if ! "${P1_CMD_ARRAY[@]}"; then
        log_error "Pipeline 1 failed. Aborting."
        exit 1
    fi
    log_info "--- Cycle Step: Pipeline 1 finished. ---"
    printf "\n"

    #  파이프라인 2 시작 전, 입력 데이터(P1의 결과물) 존재 여부 확인
    log_info "Verifying inputs for Pipeline 2..."
    # clean_reads 폴더가 비어 있고, 원본 입력 폴더에는 파일이 있는 경우에만 에러로 처리
    if [[ ! -d "$P1_CLEAN_READS_DIR" || -z "$(ls -A "$P1_CLEAN_READS_DIR" 2>/dev/null)" ]]; then
        if [[ -n "$(find "$INPUT_DIR" -maxdepth 1 -type f -name "*.fastq.gz" 2>/dev/null)" ]]; then
            log_error "Pipeline 2 input directory (${P1_CLEAN_READS_DIR}) is empty, but raw input files exist."
            log_error "This indicates an issue during Pipeline 1. Please check the logs in ${P1_OUTPUT_DIR}."
            log_error "To force Pipeline 1 to re-run, you can delete its state file: rm -f ${P1_STATE_FILE}"
            exit 1
        fi
    fi
    log_info "Inputs for Pipeline 2 verified."

    # --- 2단계: MAG 분석 파이프라인 실행 ---
    log_info "--- Starting Cycle: Running Pipeline 2 (MAG Analysis) ---"
    P2_CMD_ARRAY=(
        bash "${PROJECT_ROOT_DIR}/scripts/mag.sh"
        all --input_dir "${P1_CLEAN_READS_DIR}" --output_dir "${P2_OUTPUT_DIR}"
        --kraken2_db "${KRAKEN2_DB}" --gtdbtk_db_dir "${GTDBTK_DB}" --bakta_db_dir "${BAKTA_DB}"
        --threads "${THREADS}" --memory_gb "${MEMORY_GB}"
    )

    if [[ -n "$MEGAHIT_OPTS" ]]; then P2_CMD_ARRAY+=(--megahit-opts "$MEGAHIT_OPTS"); fi
    if [[ -n "$METAWRAP_BINNING_OPTS" ]]; then P2_CMD_ARRAY+=(--metawrap-binning-opts "$METAWRAP_BINNING_OPTS"); fi
    if [[ -n "$METAWRAP_REFINEMENT_OPTS" ]]; then P2_CMD_ARRAY+=(--metawrap-refinement-opts "$METAWRAP_REFINEMENT_OPTS"); fi
    if [[ -n "$KRAKEN2_OPTS" ]]; then P2_CMD_ARRAY+=(--kraken2-opts "$KRAKEN2_OPTS"); fi
    if [[ -n "$GTDBTK_OPTS" ]]; then P2_CMD_ARRAY+=(--gtdbtk-opts "$GTDBTK_OPTS"); fi
    if [[ -n "$BAKTA_OPTS" ]]; then P2_CMD_ARRAY+=(--bakta-opts "$BAKTA_OPTS"); fi

    if ! "${P2_CMD_ARRAY[@]}"; then
        log_error "Pipeline 2 failed. Aborting."
        exit 1
    fi
    log_info "--- Cycle Step: Pipeline 2 finished. ---"
    printf "\n"

    # --- 3단계: 최종 안정성 검사 ---
    log_info "Performing final stability check on input directory..."
    # 현재 이 순간의 입력 폴더 상태를 임시 파일로 다시 계산
    CURRENT_STATE_FILE=$(mktemp)
    if [[ -n "$(find "$INPUT_DIR" -maxdepth 1 -type f -name "*.fastq.gz" 2>/dev/null)" ]]; then
        find "$INPUT_DIR" -maxdepth 1 -type f -name "*.fastq.gz" -print0 | xargs -0 md5sum | sort -k 2 > "$CURRENT_STATE_FILE"
    else
        touch "$CURRENT_STATE_FILE" # 입력 폴더가 비어있을 경우, 빈 파일로 비교
    fi

    # P1_STATE_FILE 경로를 올바르게 사용합니다.
    if [ -f "$P1_STATE_FILE" ] && diff -q "$P1_STATE_FILE" "$CURRENT_STATE_FILE" >/dev/null; then
        log_info "Input directory is stable. All samples have been processed."
        rm -f "$CURRENT_STATE_FILE" # 임시 파일 삭제
        break # 상태가 안정되었으므로 while 루프를 종료합니다.
    else
        log_info "Input directory has changed or is not yet stable. Starting another cycle..."
        rm -f "$CURRENT_STATE_FILE" # 임시 파일 삭제
        sleep 15 # 다음 사이클 전에 15초 대기
    fi
done

# --- 4. 최종 리포트 생성 ---
log_info "--- All pipelines finished and input is stable. Generating final summary report. ---"
if [ -f "${PROJECT_ROOT_DIR}/lib/reporting_functions.sh" ]; then
    source "${PROJECT_ROOT_DIR}/lib/reporting_functions.sh"
    # create_summary_report 함수가 라이브러리 파일 안에 정의되어 있다고 가정합니다.
    if command -v create_summary_report &> /dev/null; then
        create_summary_report "$OUTPUT_DIR"
    else
        log_error "'create_summary_report' function not found in library file. Skipping."
    fi
else
    log_info "Reporting functions library not found, skipping final report generation."
fi

log_info "---  Metagenome Pipeline Run Completely Finished!  ---"
