#!/bin/bash
#================================================
# 통합 메타지놈 분석 파이프라인 실행기 (Master Script)
#================================================
set -euo pipefail

FULL_COMMAND_RUN_ALL="$0 \"$@\""

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")

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
    echo "  --verbose             - Show detailed logs in terminal instead of progress bar."
    echo "  --skip-contig-analysis   - Skip Kraken2 and Bakta analysis on assembled contigs."    
    echo "  --skip-bakta             - Skip ONLY Bakta analysis on contigs."
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
INPUT_DIR=""; OUTPUT_DIR=""; KRAKEN2_DB=""; GTDBTK_DB=""; BAKTA_DB=""; HOST_DB="";
THREADS=6; MEMORY_GB="60"
# 모든 도구별 추가 옵션을 저장할 변수 초기화
KNEADDATA_OPTS=""; FASTP_OPTS=""; KRAKEN2_OPTS=""; MEGAHIT_OPTS=""; METAWRAP_BINNING_OPTS=""
METAWRAP_REFINEMENT_OPTS=""; GTDBTK_OPTS=""; BAKTA_OPTS=""

SKIP_CONTIG_ANALYSIS=false
SKIP_BAKTA=false
VERBOSE_MODE=false 

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
        --skip-contig-analysis) SKIP_CONTIG_ANALYSIS=true; shift ;;
        --skip-bakta) SKIP_BAKTA=true; shift ;;
        --gtdbtk-opts) GTDBTK_OPTS="$2"; shift 2 ;;
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
if [[ -z "$BAKTA_DB" ]]; then error_messages+=("  - --bakta_db is required."); fi
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

QC_RETRY_COUNT=0; VERIFY_RETRY_COUNT=0; MAG_RETRY_COUNT=0; MAX_RETRIES=2; LOOP_SLEEP_SEC=1800

while true; do
    # =======================================================
    # [추가] 로그 로테이션 (10MB 초과 시 백업)
    # =======================================================
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(du -k "$LOG_FILE" | cut -f1)
        if [ "$LOG_SIZE" -gt 10240 ]; then # 10MB (10240KB)
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            mv "$LOG_FILE" "${LOG_FILE}.${TIMESTAMP}.bak"
            gzip "${LOG_FILE}.${TIMESTAMP}.bak" & # 백그라운드 압축
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
            ((QC_RETRY_COUNT++))
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
            ((VERIFY_RETRY_COUNT++))
            
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
        local status=$?

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
    # [2단계] MAG 분석 실행
    # -------------------------------------------------------
    log_info "--- [Phase 2] Running MAG Pipeline ---"
    MAG_RETRY_COUNT=0

    while [ "$MAG_RETRY_COUNT" -le "$MAX_RETRIES" ]; do
        log_info "--- [Phase 2] Running MAG Pipeline (Attempt: $((MAG_RETRY_COUNT+1))) ---"

        P2_CMD_ARRAY=(
            bash "${PROJECT_ROOT_DIR}/scripts/mag.sh"
            all --input_dir "${P1_CLEAN_READS_DIR}" --output_dir "${P2_OUTPUT_DIR}"
            --kraken2_db "${KRAKEN2_DB}" --gtdbtk_db_dir "${GTDBTK_DB}" --bakta_db_dir "${BAKTA_DB}"
            --threads "${THREADS}" --memory_gb "${MEMORY_GB}"
        )

        if [ "$SKIP_CONTIG_ANALYSIS" = true ]; then
            P2_CMD_ARRAY+=(--skip-contig-analysis)
        fi
        
        # [중요] Bakta 스킵 옵션 전달
        if [ "$SKIP_BAKTA" = true ]; then
            P2_CMD_ARRAY+=(--skip-bakta)
        fi

        if [[ -n "$MEGAHIT_OPTS" ]]; then P2_CMD_ARRAY+=(--megahit-opts "$MEGAHIT_OPTS"); fi
        if [[ -n "$METAWRAP_BINNING_OPTS" ]]; then P2_CMD_ARRAY+=(--metawrap-binning-opts "$METAWRAP_BINNING_OPTS"); fi
        if [[ -n "$METAWRAP_REFINEMENT_OPTS" ]]; then P2_CMD_ARRAY+=(--metawrap-refinement-opts "$METAWRAP_REFINEMENT_OPTS"); fi
        if [[ -n "$KRAKEN2_OPTS" ]]; then P2_CMD_ARRAY+=(--kraken2-opts "$KRAKEN2_OPTS"); fi
        if [[ -n "$GTDBTK_OPTS" ]]; then P2_CMD_ARRAY+=(--gtdbtk-opts "$GTDBTK_OPTS"); fi
        if [[ -n "$BAKTA_OPTS" ]]; then P2_CMD_ARRAY+=(--bakta-opts "$BAKTA_OPTS"); fi

        # 1. MAG 실행
        if "${P2_CMD_ARRAY[@]}"; then
            MAG_RETRY_COUNT=0 # 성공하면 카운터 리셋
            break # MAG 루프 탈출 (다음 단계로 이동)
        else
            # 2. 실패 또는 인터럽트 신호 처리
            MAG_RETURN_CODE=$? # 종료 코드 캡처
            
            if [ "$MAG_RETURN_CODE" -eq 99 ]; then
                log_warn "MAG run interrupted by new input. Restarting QC phase."
                MAG_RETRY_COUNT=0 # 카운트 리셋
                break # MAG 루프 탈출 (다음 단계로 이동)
            fi

            # 3. 영구 실패 처리 (기존 로직 유지)
            ((MAG_RETRY_COUNT++))
            log_error "Pipeline 2 failed (Failure Count: $MAG_RETRY_COUNT / $MAX_RETRIES)."
            
            if [ "$MAG_RETRY_COUNT" -gt "$MAX_RETRIES" ]; then
                log_error "CRITICAL: MAG failed $MAX_RETRIES times consecutively. Aborting."
                exit 1 
            fi
            
            log_info "Retrying MAG in 60s..."
            sleep 60
        fi
    done

    # =======================================================
    # [수정] 리포트 생성을 루프 안으로 이동 (매 사이클마다 갱신)
    # =======================================================
    log_info "--- Cycle Finished. Updating Summary Report... ---"

    if [ -f "${PROJECT_ROOT_DIR}/lib/reporting_functions.sh" ]; then
        source "${PROJECT_ROOT_DIR}/lib/reporting_functions.sh"
        if command -v create_summary_report &> /dev/null; then
            # 매번 최신 상태를 반영하여 리포트 덮어쓰기
            create_summary_report "$OUTPUT_DIR"
            log_info "Summary report updated."
        else
            log_error "'create_summary_report' function not found. Skipping."
        fi
    else
        log_warn "Reporting library not found. Skipping report generation."
    fi

    # log_info "Waiting for next cycle..."

    # =======================================================
    # [Pro 3.0] 종료 신호 감지 (Graceful Shutdown)
    # =======================================================
    # 입력 폴더에 'stop_pipeline'이라는 파일이 있으면 종료합니다.
    if [ -f "${INPUT_DIR}/stop_pipeline" ]; then
        rm -f "$P1_STATE_FILE"

        printf "\n"
        log_info "🛑 Stop signal detected ('stop_pipeline' file found)."
        log_info "Finishing current cycle and shutting down gracefully."
        rm -f "${INPUT_DIR}/stop_pipeline" # 신호 파일 삭제 (청소)
        break # 무한 루프 탈출! -> 프로그램 종료
    fi

    #log_info "Waiting for next cycle..."

    # -------------------------------------------------------
    # [5단계] CPU 과부하 방지를 위한 휴식 (Sleep)
    # -------------------------------------------------------
    # [설정] 대기 시간 (1800초 = 30분) - 필요에 따라 조절하세요
    # LOOP_SLEEP_SEC=1800 
    
    log_info "Cycle complete. Sleeping for ${LOOP_SLEEP_SEC} seconds before next check..."
    log_info "(To stop safely, create a file named 'stop_pipeline' in the input dir)"
    
    sleep "$LOOP_SLEEP_SEC"

done