#!/bin/bash
#================================================
# 통합 메타지놈 분석 파이프라인 실행기 (Master Script)
#================================================
set -euo pipefail

# [scripts/run_all.sh 상단에 넣을 코드]
_term_handler() {
    # 1. [중요] 중복 신호 차단: 처리 도중 또 신호가 오면 무시함
    trap "" SIGINT SIGTERM

    echo -e "\n\033[0;33m[MASTER] Stop signal received! Stopping children gracefully...\033[0m" >&2
    
    # 2. [수정] 자식들에게 '정리할 시간' 부여 (SIGTERM -15 전송)
    # 이렇게 해야 qc.sh의 'trap cleanup_on_exit EXIT'이 발동되어 .processing 파일을 지움
    pkill -15 -P $$ 2>/dev/null || true
    
    # 3. [신규] 자식들이 청소할 시간을 줌 (5초 대기)
    echo -e "Waiting 5s for cleanup..." >&2
    sleep 5
    
    # 4. [확인 사살] 말 안 듣고 버티는 프로세스 강제 종료 (SIGKILL -9)
    echo -e "\033[0;31m[MASTER] Force killing remaining processes...\033[0m" >&2
    pkill -9 -P $$ 2>/dev/null || true

    # 5. 분석 툴 프로세스 정리 (기존 로직 유지)
    TOOLS_TO_KILL=("kneaddata" "fastp" "kraken2" "bracken" "megahit" "metawrap" "gtdbtk" "bakta" "diamond" "perl" "pigz" "java" "python")
    for tool in "${TOOLS_TO_KILL[@]}"; do
        pkill -9 -u "$(whoami)" -f "$tool" 2>/dev/null || true
    done

    # 6. 상태 파일 정리 (기존 유지)
    if [ -n "${OUTPUT_DIR:-}" ]; then
        find "$OUTPUT_DIR" -name "*.processing" -delete 2>/dev/null || true
    fi
    
    # 7. 마스터 종료
    kill -9 $$
}

trap _term_handler SIGINT SIGTERM

FULL_COMMAND_RUN_ALL="$0 \"$@\""

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")
LOG_FILE="/dev/null"

# [필수] 라이브러리 로드 (이게 없으면 오류남)
if [ -f "${PROJECT_ROOT_DIR}/lib/pipeline_functions.sh" ]; then
    source "${PROJECT_ROOT_DIR}/lib/pipeline_functions.sh"
else
    echo "Error: pipeline_functions.sh not found." >&2; exit 1
fi

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
    echo "  --input_dir PATH        - Input directory containing raw FASTQ files"
    echo "  --output_dir PATH       - Main output directory"
    echo "  --kraken2_db PATH       - Kraken2 database path"
    echo "  --gtdbtk_db PATH        - GTDB-Tk database path"
    echo "  --bakta_db PATH         - Bakta database path (Required if using Bakta)"
    echo "  --eggnog_db PATH        - EggNOG database path (Required if using EggNOG)"
    echo "  --host_db PATH          - Host reference database (Required for 'host' mode)"
    echo ""
    echo -e "${CYAN}${BOLD}Optional Options:${NC}"
    echo "  --threads INT         - Number of threads for all tools. (Default: 6)"
    echo "  --memory_gb INT       - Max memory in Gigabytes for KneadData and MEGAHIT. (Default: 60)"
    echo "  --parallel-jobs N     - Number of samples to process in parallel (Default: 1)"
    echo "                        (Resources will be divided by N automatically)"
    echo "  --annotation-tool STR   Tool for Contig annotation: 'eggnog' (default) or 'bakta'"
    echo "  --skip-contig-analysis  - Skip Kraken2/Annotation analysis on assembled contigs."    
    echo "  --skip-annotation       - Skip ONLY Functional Annotation (Bakta/EggNOG) analysis on contigs."
    echo "  --verbose             - Show detailed logs in terminal instead of progress bar."
    echo ""
    echo -e "${CYAN}Tool-specific Options (Pass-through):${NC}"
    echo "  --kneaddata-opts STR           - Pass options to KneadData (in quotes)"
    echo "  --fastp-opts STR               - Pass options to fastp (in quotes)"
    echo "  --kraken2-opts STR             - Pass options to Kraken2 (in quotes)"
    echo "  --megahit-opts STR             - Pass options to MEGAHIT (in quotes)"
    echo "  --metawrap-binning-opts STR    - Pass options to MetaWRAP Binning"
    echo "  --metawrap-refinement-opts STR - Pass options to MetaWRAP Refinement"
    echo "  --gtdbtk-opts STR              - Pass options to GTDB-Tk (in quotes)"
    echo "  --bakta-opts STR               - Pass options to Bakta (in quotes)"
    echo "  --eggnog-opts STR              - Pass options to EggNOG-mapper (in quotes)"
    echo ""
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
log_warn() {
    echo -e "\033[0;33m[MASTER-WARN] $(date +'%Y-%m-%d %H:%M:%S') | $1\033[0m" >&2
}

# --- 2. 기본값 설정 및 인자 파싱 ---
if [[ $# -eq 0 || ("$1" == "-h" || "$1" == "--help") ]]; then print_usage; exit 0; fi

P1_MODE="$1"; shift
if [[ "$P1_MODE" != "host" && "$P1_MODE" != "environmental" ]]; then
    log_error "Invalid mode specified. Choose 'host' or 'environmental'."; print_usage; exit 1
fi

# 변수 초기화
INPUT_DIR=""; OUTPUT_DIR=""; KRAKEN2_DB=""; GTDBTK_DB=""; BAKTA_DB=""; EGGNOG_DB=""; HOST_DB="";
THREADS=6; MEMORY_GB="60"; PARALLEL_JOBS=1
# 모든 도구별 추가 옵션을 저장할 변수 초기화
KNEADDATA_OPTS=""; FASTP_OPTS=""; KRAKEN2_OPTS=""; MEGAHIT_OPTS=""; METAWRAP_BINNING_OPTS=""
METAWRAP_REFINEMENT_OPTS=""; GTDBTK_OPTS=""; BAKTA_OPTS=""; EGGNOG_OPTS=""

SKIP_CONTIG_ANALYSIS=false
SKIP_ANNOTATION=false
VERBOSE_MODE=false 

while [ $# -gt 0 ]; do
    case "$1" in
        --input_dir) INPUT_DIR="${2%/}"; shift 2 ;;
        --output_dir) OUTPUT_DIR="${2%/}"; shift 2 ;;
        --kraken2_db) KRAKEN2_DB="$2"; shift 2 ;;
        --gtdbtk_db) GTDBTK_DB="$2"; shift 2 ;;
        --bakta_db) BAKTA_DB="$2"; shift 2 ;;
        --eggnog_db) EGGNOG_DB="$2"; shift 2 ;;
        --host_db) HOST_DB="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --memory_gb) MEMORY_GB="$2"; shift 2 ;;
        --parallel-jobs) PARALLEL_JOBS="$2"; shift 2 ;;
        --kneaddata-opts) KNEADDATA_OPTS="$2"; shift 2 ;;
        --fastp-opts) FASTP_OPTS="$2"; shift 2 ;;
        --kraken2-opts) KRAKEN2_OPTS="$2"; shift 2 ;;
        --megahit-opts) MEGAHIT_OPTS="$2"; shift 2 ;;
        --metawrap-binning-opts) METAWRAP_BINNING_OPTS="$2"; shift 2 ;;
        --metawrap-refinement-opts) METAWRAP_REFINEMENT_OPTS="$2"; shift 2 ;;
        --skip-contig-analysis) SKIP_CONTIG_ANALYSIS=true; shift ;;
        --skip-annotation) SKIP_ANNOTATION=true; shift ;;
        --annotation-tool) ANNOTATION_TOOL="$2"; shift 2 ;;    
        --gtdbtk-opts) GTDBTK_OPTS="$2"; shift 2 ;;
        --eggnog-opts) EGGNOG_OPTS="$2"; shift 2 ;;
        --bakta-opts) BAKTA_OPTS="$2"; shift 2 ;;

        --verbose) VERBOSE_MODE=true; shift ;;
        *) shift ;;
    esac
done

export VERBOSE_MODE

# --- 3. 필수 인자 확인 ---
declare -a error_messages=()
if [[ -z "$INPUT_DIR" ]]; then error_messages+=("  - --input_dir is required."); fi
if [[ -z "$OUTPUT_DIR" ]]; then error_messages+=("  - --output_dir is required."); fi
if [[ -z "$KRAKEN2_DB" ]]; then error_messages+=("  - --kraken2_db is required."); fi
if [[ -z "$GTDBTK_DB" ]]; then error_messages+=("  - --gtdbtk_db is required."); fi
# if [[ -z "$BAKTA_DB" ]]; then error_messages+=("  - --bakta_db is required."); fi

if [[ "$SKIP_ANNOTATION" == "false" && "$SKIP_CONTIG_ANALYSIS" == "false" ]]; then
     if [[ "$ANNOTATION_TOOL" == "bakta" && -z "$BAKTA_DB" ]]; then
         error_messages+=("  - --bakta_db is required (unless --skip-annotation or --skip-contig-analysis is used).")
     fi
     if [[ "$ANNOTATION_TOOL" == "eggnog" && -z "$EGGNOG_DB" ]]; then
         error_messages+=("  - --eggnog_db is required (unless --skip-annotation or --skip-contig-analysis is used).")
     fi
fi

if [[ "$P1_MODE" == "host" && -z "$HOST_DB" ]]; then error_messages+=("  - --host_db is required for 'host' mode."); fi

if [ ${#error_messages[@]} -gt 0 ]; then
    log_error "Missing arguments:"
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
log_info "Logic: Run QC -> Check Inputs -> (If new) Repeat QC -> (If stable) Run MAG"
log_info "The pipeline will run in a loop, processing new samples."

export DOKKAEBI_MASTER_COMMAND="$FULL_COMMAND_RUN_ALL"
mkdir -p "$P1_OUTPUT_DIR" "$P2_OUTPUT_DIR"

LOG_FILE="${OUTPUT_DIR}/master_pipeline.log"
touch "$LOG_FILE"

QC_RETRY_COUNT=0; VERIFY_RETRY_COUNT=0; MAG_RETRY_COUNT=0; MAX_RETRIES=2; LOOP_SLEEP_SEC=10

while true; do
    # =======================================================
    # [추가] 로그 로테이션 (10MB 초과 시 백업)
    # =======================================================
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(du -k "$LOG_FILE" | cut -f1)
        if [ "$LOG_SIZE" -gt 10240 ]; then # 10MB (10240KB)
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            mv "$LOG_FILE" "${LOG_FILE}.${TIMESTAMP}.bak"
            gzip "${LOG_FILE}.${TIMESTAMP}.bak" # 백그라운드 압축
            touch "$LOG_FILE"
            log_info "Log file rotated due to size limit (>10MB)."
        fi
    fi

    QC_RETRY_COUNT=0; VERIFY_RETRY_COUNT=0; MAG_RETRY_COUNT=0


    # -------------------------------------------------------
    # [1단계] QC 무한 루프
    # -------------------------------------------------------
    while true; do
        log_info "--- [Phase 1] Running QC Pipeline (Attempt: $((QC_RETRY_COUNT+1))) ---"

        P1_CMD_ARRAY=(
            bash "${PROJECT_ROOT_DIR}/scripts/qc.sh"
            "${P1_MODE}" --input_dir "${INPUT_DIR}" --output_dir "${P1_OUTPUT_DIR}"
            --kraken2_db "${KRAKEN2_DB}" --threads "${THREADS}"
            --parallel-jobs "${PARALLEL_JOBS}"
        )
        if [[ "$P1_MODE" == "host" ]]; then
            P1_MEMORY_MB=$((MEMORY_GB * 1024))
            P1_CMD_ARRAY+=(--host_db "${HOST_DB}" --memory "${P1_MEMORY_MB}")
        fi
        if [[ -n "$KNEADDATA_OPTS" ]]; then P1_CMD_ARRAY+=(--kneaddata-opts "$KNEADDATA_OPTS"); fi
        if [[ -n "$FASTP_OPTS" ]]; then P1_CMD_ARRAY+=(--fastp-opts "$FASTP_OPTS"); fi
        if [[ -n "$KRAKEN2_OPTS" ]]; then P1_CMD_ARRAY+=(--kraken2-opts "$KRAKEN2_OPTS"); fi

        # 2. QC 실행 및 에러 핸들링
        if "${P1_CMD_ARRAY[@]}"; then
            QC_RETRY_COUNT=0
        else
            # [실패 시] 카운터 증가
            QC_RETRY_COUNT=$((QC_RETRY_COUNT + 1))
            #((QC_RETRY_COUNT++))
            log_error "QC Pipeline failed (Failure Count: $QC_RETRY_COUNT / $MAX_RETRIES)."
        
            # 2번 연속 실패하면 종료
            if [ "$QC_RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
                log_error "CRITICAL: QC execution failed $MAX_RETRIES times consecutively."
                exit 1 
            fi
            sleep 60; continue # 재시도
            
        fi

        # 3. [고속 감지] QC 직후, stat 명령어로 입력 폴더 재검사 (0.1초 컷)
        log_info "QC finished. Checking for NEW files immediately..."
        
        CURRENT_STATE_FILE=$(mktemp)
        # md5sum 대신 stat 사용 (파일명, 크기, 수정시간만 확인)
        if [[ -n "$(find "$INPUT_DIR" -maxdepth 1 -type f -name "*.fastq.gz" 2>/dev/null)" ]]; then
            find "$INPUT_DIR" -maxdepth 1 -type f -name "*.fastq.gz" -printf "%f\t%s\t%T@\n" | sort > "$CURRENT_STATE_FILE"
        else
            touch "$CURRENT_STATE_FILE"
        fi

        # 상태 파일이 없으면(첫 실행) 초기화 후 MAG 진행
        if [ ! -f "$P1_STATE_FILE" ]; then
            mv "$CURRENT_STATE_FILE" "$P1_STATE_FILE"
            break # 첫 사이클이므로 MAG 단계로 이동
        fi

        # 변화 비교: 새 파일 있으면 QC 다시! 없으면 MAG로!
        if diff -q "$P1_STATE_FILE" "$CURRENT_STATE_FILE" >/dev/null; then
            log_info "Input directory is stable. Moving to Safety Check."
            rm -f "$CURRENT_STATE_FILE"
            break # QC 루프 탈출 -> 안전성 검사로 이동
        else
            log_info "🚨 New files detected! Skipping MAG to run QC on new files first."
            mv "$CURRENT_STATE_FILE" "$P1_STATE_FILE"
            # continue -> 다시 위쪽 QC 실행으로 돌아감 (MAG 실행 보류)
        fi
    done

    # ==============================================================================
    # [1.2단계] 자가 치유 (Auto-Repair) :: QC/Taxonomy 누락분 즉시 복구 🚑
    # ==============================================================================
    # Phase 1 종료 후, MAG로 넘어가기 전에 누락된 Taxonomy 결과를 복구합니다.
    if [ -f "${PROJECT_ROOT_DIR}/scripts/auto_repair.sh" ]; then
        log_info "--- [Phase 1.2] Verifying Phase 1 Completeness & Auto-Repairing ---"
        # 현재 설정된 출력 경로, DB 경로, 스레드 수를 넘겨줍니다.
        bash "${PROJECT_ROOT_DIR}/scripts/auto_repair.sh" "$OUTPUT_DIR" "$KRAKEN2_DB" "$THREADS"
    else
        log_warn "Auto-repair script not found. Skipping repair."
    fi


    # -------------------------------------------------------
    # [1.5단계] 안전장치: Pipeline 2 입력(Clean Reads) 검증
    # -------------------------------------------------------
    log_info "Verifying inputs for Pipeline 2..."

    RAW_FILE_COUNT=$(find "$INPUT_DIR" -maxdepth 1 -type f -name "*.fastq.gz" 2>/dev/null | wc -l)
    CLEAN_FILE_COUNT=$(find "$P1_CLEAN_READS_DIR" -maxdepth 1 -type f -name "*_1.fastq.gz" 2>/dev/null | wc -l) # R1 파일만 카운트
    
    # Clean Reads 폴더가 비어있는데 원본 파일은 있는 경우
    if [[ ! -d "$P1_CLEAN_READS_DIR" || -z "$(ls -A "$P1_CLEAN_READS_DIR" 2>/dev/null)" ]]; then
        if [[ -n "$(find "$INPUT_DIR" -maxdepth 1 -type f -name "*.fastq.gz" 2>/dev/null)" ]]; then
            # [수정] 여기도 카운터를 적용합니다!
            VERIFY_RETRY_COUNT=$((VERIFY_RETRY_COUNT + 1))
            #((VERIFY_RETRY_COUNT++))
            
            log_error "CRITICAL: Clean reads directory is empty (Failure Count: $VERIFY_RETRY_COUNT / $MAX_RETRIES)."
            
            if [ "$VERIFY_RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
                log_error "ABORTING: Pipeline 1 finished without error, but NO output was generated $MAX_RETRIES times."
                log_error "Check disk space, permissions, or input file integrity."
                exit 1 # 결과물 안 나옴 -> 종료
            fi

            log_error "Restarting QC Phase in 60 seconds..."
            rm -f "$P1_STATE_FILE"
            sleep 60
            continue
        else
            # 파일이 아예 없는 대기 상태는 카운트하지 않음
            log_info "No input files found yet. Waiting..."
            sleep 60
            continue
        fi
    else
        # [성공] 결과물이 잘 있으면 카운터 리셋!
        VERIFY_RETRY_COUNT=0
    fi

    # -------------------------------------------------------
    # [1.7단계] Pair File 존재 유무 확인 (최종 무결성 검사)
    # -------------------------------------------------------
    log_info "Checking R1/R2 pairing integrity..."
    MISSING_PAIR_FOUND=0
    for R1_CLEAN in "${P1_CLEAN_READS_DIR}"/*_1.fastq.gz; do

        # local BASE_NAME=$(basename "$R1_CLEAN")
        # R1 파일명 패턴을 R2 파일명 패턴으로 변환 (mag.sh의 로직과 동일해야 함)
        # R2_CLEAN=$(echo "$R1_CLEAN" | sed -E 's/([._][Rr]?)1(\.fastq\.gz)$/\12\2/')
        
        # if [[ ! -f "$R2_CLEAN" ]]; then
        #    log_error "FATAL ERROR: Missing paired R2 file for $(basename "$R1_CLEAN")!"
        #    MISSING_PAIR_FOUND=1
        #    break
        #fi

        R2_CLEAN=$(get_r2_path "$R1_CLEAN") 
        status=$?

        # 1. 파일명 패턴 오류 검사 (함수가 0이 아닌 코드 반환 시)
        if [ "$status" -ne 0 ]; then
            log_error "FATAL ERROR: Unknown R1 filename format for $(basename "$R1_CLEAN")!"
            MISSING_PAIR_FOUND=1
            break
        fi

        # 2. R2 파일 존재 유무 확인 (무결성 검사)
        if [[ ! -f "$R2_CLEAN" ]]; then
            log_error "FATAL ERROR: Missing paired R2 file for $(basename "$R1_CLEAN")!"
            log_error "   Expected R2 path: $R2_CLEAN"
            MISSING_PAIR_FOUND=1
            break
        fi
    done

    if [ "$MISSING_PAIR_FOUND" -eq 1 ]; then
        log_error "ABORTING: Pipeline cannot proceed with broken paired-end data."
        exit 1
    fi
    
    log_info "Inputs for Pipeline 2 verified. Proceeding to MAG..."

    # -------------------------------------------------------
    # [2단계] MAG 분석 실행 (Batch Processing Mode)
    # -------------------------------------------------------
    log_info "--- [Phase 2] Checking for pending MAG jobs ---"
    
    # 1. 미완료 샘플 싹 긁어모으기
    PENDING_SAMPLES=()
    for clean_r1 in "${P1_CLEAN_READS_DIR}"/*_1.fastq.gz; do
        [ -e "$clean_r1" ] || continue
        # 샘플명 추출 (사용자 환경에 맞춘 패턴)
        s_name=$(basename "$clean_r1" | sed 's/_1_kneaddata_paired_1.fastq.gz//' | sed 's/_1.fastq.gz//')
        
        # Annotation 결과 폴더가 없으면 '할 일'로 추가
        if [ ! -d "${P2_OUTPUT_DIR}/05_annotation/${s_name}" ]; then
            PENDING_SAMPLES+=("$s_name")
        fi
    done

    # 2. 작업이 있다면? -> 다 털어낼 때까지 여기서 못 나갑니다! (집중 처리)
    if [ ${#PENDING_SAMPLES[@]} -gt 0 ]; then
        
        REAL_BATCH_SIZE=${PARALLEL_JOBS:-1}
        TOTAL_PENDING=${#PENDING_SAMPLES[@]}
        
        log_info "🚀 Detected ${TOTAL_PENDING} pending samples. Switching to BATCH MODE."
        log_info "   (Will process ALL pending samples before checking raw data again)"

        # [핵심 변경] 전체 대기열을 배치 크기만큼 잘라서 반복문 실행
        for ((i=0; i<TOTAL_PENDING; i+=REAL_BATCH_SIZE)); do
            
            # 배열 자르기 (Slicing): i번째부터 BATCH_SIZE만큼 가져옴
            TARGETS=("${PENDING_SAMPLES[@]:i:REAL_BATCH_SIZE}")
            
            CURRENT_BATCH_NUM=$((i/REAL_BATCH_SIZE + 1))
            TOTAL_BATCH_NUM=$(( (TOTAL_PENDING + REAL_BATCH_SIZE - 1) / REAL_BATCH_SIZE ))

            log_info ">>> [Batch ${CURRENT_BATCH_NUM}/${TOTAL_BATCH_NUM}] Processing: ${TARGETS[*]}"

            # 임시 폴더 생성 (Batch마다 새로 만듦)
            TEMP_MAG_INPUT="/tmp/dokkaebi_mag_run_$$"
            rm -rf "$TEMP_MAG_INPUT" && mkdir -p "$TEMP_MAG_INPUT"

            # 타겟 파일만 임시 폴더로 링크
            for s in "${TARGETS[@]}"; do
                find "${P1_CLEAN_READS_DIR}" -name "${s}*_1.fastq.gz" -exec ln -s {} "${TEMP_MAG_INPUT}/${s}_1.fastq.gz" \;
                find "${P1_CLEAN_READS_DIR}" -name "${s}*_2.fastq.gz" -exec ln -s {} "${TEMP_MAG_INPUT}/${s}_2.fastq.gz" \;
            done

            # 3. MAG 파이프라인 실행 (재시도 로직 포함)
            MAG_RETRY_COUNT=0
            while [ "$MAG_RETRY_COUNT" -le "$MAX_RETRIES" ]; do
                
                P2_CMD_ARRAY=(
                    bash "${PROJECT_ROOT_DIR}/scripts/mag.sh" all 
                    --input_dir "${TEMP_MAG_INPUT}" 
                    --output_dir "${P2_OUTPUT_DIR}"
                    --raw_input_dir "${INPUT_DIR}"
                    --kraken2_db "${KRAKEN2_DB}" --gtdbtk_db_dir "${GTDBTK_DB}" --bakta_db_dir "${BAKTA_DB}" --eggnog_db_dir "${EGGNOG_DB}"
                    --threads "${THREADS}" --memory_gb "${MEMORY_GB}"
                    --parallel-jobs "${REAL_BATCH_SIZE}"
                    --annotation-tool "${ANNOTATION_TOOL:-eggnog}"
                )

                # 옵션 추가
                if [ "$SKIP_CONTIG_ANALYSIS" = true ]; then P2_CMD_ARRAY+=(--skip-contig-analysis); fi
                if [ "$SKIP_ANNOTATION" = true ]; then P2_CMD_ARRAY+=(--skip-annotation); fi
                [[ -n "$MEGAHIT_OPTS" ]] && P2_CMD_ARRAY+=(--megahit-opts "$MEGAHIT_OPTS")
                [[ -n "$KRAKEN2_OPTS" ]] && P2_CMD_ARRAY+=(--kraken2-opts "$KRAKEN2_OPTS")
                [[ -n "$METAWRAP_BINNING_OPTS" ]] && P2_CMD_ARRAY+=(--metawrap-binning-opts "$METAWRAP_BINNING_OPTS")
                [[ -n "$METAWRAP_REFINEMENT_OPTS" ]] && P2_CMD_ARRAY+=(--metawrap-refinement-opts "$METAWRAP_REFINEMENT_OPTS")
                [[ -n "$GTDBTK_OPTS" ]] && P2_CMD_ARRAY+=(--gtdbtk-opts "$GTDBTK_OPTS")
                [[ -n "$BAKTA_OPTS" ]] && P2_CMD_ARRAY+=(--bakta-opts "$BAKTA_OPTS")
                [[ -n "$EGGNOG_OPTS" ]] && P2_CMD_ARRAY+=(--eggnog-opts "$EGGNOG_OPTS")

                if "${P2_CMD_ARRAY[@]}"; then
                    MAG_RETRY_COUNT=0
                    break 
                else
                    MAG_RETURN_CODE=$?
                    if [ "$MAG_RETURN_CODE" -eq 99 ]; then 
                        log_warn "MAG run interrupted (Signal 99)."
                        break 2 # 전체 배치 루프 탈출
                    fi
                    MAG_RETRY_COUNT=$((MAG_RETRY_COUNT + 1))
                    log_error "MAG Batch Failed ($MAG_RETRY_COUNT/$MAX_RETRIES). Retrying..."
                    sleep 60
                fi
            done
            
            # 임시 폴더 청소
            rm -rf "$TEMP_MAG_INPUT"
            
            # 중간에 멈춤 신호 확인 (안전장치)
            if [ -f "${INPUT_DIR}/stop_pipeline" ]; then
                log_warn "Stop signal detected. Halting batch processing."
                break
            fi

        done # 배치 루프 종료
        
        log_info "✅ All pending batches completed."

    else
        log_info "No pending MAG jobs. Everything is up to date."
    fi

    # =======================================================
    # [리포트 생성] 배치 처리가 다 끝난 뒤 한 번만 실행 (효율적)
    # =======================================================
    log_info "--- Cycle Finished. Updating Summary Report... ---"

    if [ -f "${PROJECT_ROOT_DIR}/lib/reporting_functions.sh" ]; then
        source "${PROJECT_ROOT_DIR}/lib/reporting_functions.sh"
        if command -v create_summary_report &> /dev/null; then
            create_summary_report "$OUTPUT_DIR"
            log_info "Summary report updated."
        fi
    else
        log_warn "Reporting library not found. Skipping."
    fi

    # =======================================================
    # [종료 신호 감지]
    # =======================================================
    if [ -f "${INPUT_DIR}/stop_pipeline" ]; then
        rm -f "$P1_STATE_FILE"
        printf "\n"
        log_info "🛑 Stop signal detected. Shutting down gracefully."
        rm -f "${INPUT_DIR}/stop_pipeline"
        break
    fi

    # [설정] 대기 시간 (5초 추천 - 배치로 다 털었으니 금방 다시 봐도 됨)
    # LOOP_SLEEP_SEC=5 
    
    log_info "Cycle complete. Sleeping for ${LOOP_SLEEP_SEC} seconds..."
    sleep "$LOOP_SLEEP_SEC"

done