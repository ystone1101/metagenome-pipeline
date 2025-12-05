#!/bin/bash
#================================================
# 파이프라인 1: QC & Taxonomy (최종 수정 버전)
#================================================
set -euo pipefail

# [scripts/qc.sh 와 scripts/mag.sh 상단에 넣을 코드]
if [[ -z "${DOKKAEBI_MASTER_COMMAND:-}" ]]; then
    _term_handler() {
        echo "Local Abort."
        pkill -9 -P $$
        exit 1
    }
    trap _term_handler SIGINT SIGTERM
fi

FULL_COMMAND_QC="$0 \"$@\""

shopt -s nullglob

# 스크립트의 위치를 기준으로 프로젝트 최상위 폴더 경로를 찾습니다.
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")

# --- 1. 사용법 안내 함수 ---
print_usage() {
    # 색상 코드 정의
    local RED=$'\033[0;31m'; local GREEN=$'\033[0;32m'; local YELLOW=$'\033[0;33m'
    local BLUE=$'\033[0;34m'; local CYAN=$'\033[0;36m'; local BOLD=$'\033[1m'; local NC=$'\033[0m'

    # ASCII Art Title (Dokkaebi + QC)
    echo -e "${GREEN}"
    echo '    ██████╗  ██████╗ ██╗  ██╗██╗  ██╗ █████╗ ███████╗██████╗ ██╗'
    echo '    ██╔══██╗██╔═══██╗██║ ██╔╝██║ ██╔╝██╔══██╗██╔════╝██╔══██╗██║'
    echo '    ██║  ██║██║   ██║█████╔╝ █████╔╝ ███████║█████╗  ██████╔╝██║'
    echo '    ██║  ██║██║   ██║██╔═██╗ ██╔═██╗ ██╔══██║██╔══╝  ██╔══██╗██║'
    echo '    ██████╔╝╚██████╔╝██║  ██╗██║  ██╗██║  ██║███████╗██████╔╝██║'
    echo '    ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝'
    echo -e "${YELLOW}"
    echo '                         ██████╗   ██████╗'
    echo '                        ██╔═══██╗ ██╔════╝' 
    echo '                        ██║   ██║ ██║     '
    echo '                        ██║   ██╚╗██║     '
    echo '                        ╚████████║╚██████╗'
    echo '                               ██║ ╚═════╝ '
    echo '                               ╚═╝                '
    echo -e "                  ${RED}${BOLD}--- QC & TAXONOMY WORKFLOW ---${NC}"
    echo ""
    echo -e "${YELLOW}Performs Quality Control, host read removal, and read-based taxonomic classification.${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}Usage:${NC}"
    echo "  dokkaebi qc <mode> [options...]"
    echo ""
    echo -e "${CYAN}${BOLD}Modes:${NC}"
    echo -e "  ${GREEN}host${NC}          - For host-associated samples (uses KneadData for QC)."
    echo -e "  ${GREEN}environmental${NC} - For environmental samples (uses fastp for QC)."
    echo ""
    echo -e "${CYAN}${BOLD}Required Options:${NC}"
    echo "  --input_dir PATH      - Path to the input directory with raw FASTQ files."
    echo "  --output_dir PATH     - Path to the main output directory for this workflow."
    echo "  --kraken2_db PATH     - Path to the Kraken2 database."
    echo "  --host_db PATH        - (Required for 'host' mode) Path to the host reference database for KneadData."
    echo ""
    echo -e "${CYAN}${BOLD}Optional Options:${NC}"
    echo "  --threads INT         - Number of threads for all tools. (Default: 6)"
    echo "  --memory MB           - Max memory in Megabytes for KneadData (e.g., 80000). (Default: 60000)"
    echo "  --qc-only             - Run only QC (KneadData/fastp) and skip taxonomic analysis."
    echo "  --verbose             - Show detailed logs in terminal instead of progress bar."    
    echo ""
    echo -e "${CYAN}${BOLD}Tool-specific Options (pass-through):${NC}"    
    echo "  --kneaddata-opts OPTS - Pass additional options to KneadData (in quotes)."
    echo "  --fastp-opts OPTS     - Pass additional options to fastp (in quotes)."
    echo "  --kraken2-opts OPTS   - Pass additional options to Kraken2 (in quotes)."   
    echo "  -h, --help            - Display this help message and exit."
    echo ""    
    echo ""
}

# --- 2. 기본값 설정 및 인자 파싱 ---
if [[ $# -eq 0 || ("${1:-}" == "-h" || "${1:-}" == "--help") ]]; then
    print_usage; exit 0;
fi

MODE="$1"; shift
if [[ "$MODE" != "host" && "$MODE" != "environmental" ]]; then
    RED='\033[0;31m'; NC='\033[0m'
    echo -e "${RED}Error: Invalid mode specified. Choose 'host' or 'environmental'.${NC}" >&2; print_usage; exit 1
fi

INPUT_DIR_ARG=""; OUTPUT_DIR_ARG=""; KRAKEN2_DB_ARG=""; HOST_DB_ARG="";
THREADS=6; MEMORY_MB="60000";
QC_ONLY_MODE=false 
KNEADDATA_EXTRA_OPTS=""
FASTP_EXTRA_OPTS=""
KRAKEN2_EXTRA_OPTS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --input_dir) INPUT_DIR_ARG="${2%/}"; shift 2 ;;
        --output_dir) OUTPUT_DIR_ARG="${2%/}"; shift 2 ;;
        --kraken2_db) KRAKEN2_DB_ARG="$2"; shift 2 ;;
        --host_db) HOST_DB_ARG="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --memory) MEMORY_MB="${2}m"; shift 2 ;;
        --kneaddata-opts) KNEADDATA_EXTRA_OPTS="$2"; shift 2 ;;
        --fastp-opts) FASTP_EXTRA_OPTS="$2"; shift 2 ;;
        --kraken2-opts) KRAKEN2_EXTRA_OPTS="$2"; shift 2 ;;
        --qc-only) QC_ONLY_MODE=true; shift ;;
        --verbose) VERBOSE_MODE=true; shift ;;
        *) shift ;;
    esac
done

# --- 3. 필수 인자 확인 (통합 검사) ---
declare -a error_messages=()
if [[ -z "$INPUT_DIR_ARG" ]]; then error_messages+=("  - --input_dir: 입력 디렉토리는 필수입니다."); fi
if [[ -z "$OUTPUT_DIR_ARG" ]]; then error_messages+=("  - --output_dir: 출력 디렉토리는 필수입니다."); fi
if [[ -z "$KRAKEN2_DB_ARG" ]]; then error_messages+=("  - --kraken2_db: Kraken2 데이터베이스 경로는 필수입니다."); fi
if [[ "$MODE" == "host" && -z "$HOST_DB_ARG" ]]; then error_messages+=("  - --host_db: 'host' 모드에는 호스트 DB 경로가 필수입니다."); fi

if [ ${#error_messages[@]} -gt 0 ]; then
    RED='\033[0;31m'; NC='\033[0m'
    echo -e "${RED}Error: 아래의 필수 옵션이 누락되었습니다.${NC}" >&2
    printf "${RED}%s\n${NC}" "${error_messages[@]}" >&2
    printf "\n" >&2; print_usage; exit 1
fi

# --- 4. 경로 변수 설정 ---
BASE_DIR="${OUTPUT_DIR_ARG}"; RAW_DIR="$INPUT_DIR_ARG"
WORK_DIR="${BASE_DIR}/00_qc_tmp"; CLEAN_DIR="${BASE_DIR}/01_clean_reads"
KRAKEN_OUT="${BASE_DIR}/02_kraken2"; BRACKEN_OUT="${BASE_DIR}/03_bracken"
MPA_OUT="${BASE_DIR}/04_mpa_reports"; BRACKEN_MERGED_OUT="${BASE_DIR}/05_bracken_merged"; MULTIQC_OUT="${BASE_DIR}/06_multiqc_report"
KNEADDATA_LOG="${BASE_DIR}/logs/kneaddata_logs"; FASTP_REPORTS_DIR="${BASE_DIR}/logs/fastp_reports"
FASTQC_REPORTS_DIR="${BASE_DIR}/logs/fastqc_reports"; FASTQC_PRE_QC_DIR="${FASTQC_REPORTS_DIR}/pre_qc"; FASTQC_POST_QC_DIR="${FASTQC_REPORTS_DIR}/post_qc"
KRAKEN2_SUMMARY_TSV="${BASE_DIR}/kraken2_summary.tsv"; MISMATCH_FILE="${BASE_DIR}/mismatched_ids.txt"

# --- 5. 디렉토리 생성 및 초기화 ---
mkdir -p "$BASE_DIR" "$WORK_DIR" "$KRAKEN_OUT" "$MPA_OUT" "$CLEAN_DIR" "$KNEADDATA_LOG" \
         "$FASTP_REPORTS_DIR" "$FASTQC_PRE_QC_DIR" "$FASTQC_POST_QC_DIR" \
         "$BRACKEN_OUT" "$BRACKEN_MERGED_OUT" "$MULTIQC_OUT"
         
if [[ ! -f "$KRAKEN2_SUMMARY_TSV" ]]; then echo -e "Sample\tTotal\tClassified\tClassified(%)\tUnclassified\tUnclassified(%)" > "$KRAKEN2_SUMMARY_TSV"; fi

# --- 6. 설정 및 함수 파일 로드 ---
source "${PROJECT_ROOT_DIR}/config/pipeline_config.sh"
source "${PROJECT_ROOT_DIR}/lib/pipeline_functions.sh"
LOG_FILE="${BASE_DIR}/1_microbiome_analysis_$(date +%Y%m%d_%H%M%S).log"; > "$LOG_FILE"
trap '_error_handler' ERR

# --- 7. 의존성 및 설정 로그 기록 ---
log_info "--- Pipeline Configuration ---"
if [[ -n "${DOKKAEBI_MASTER_COMMAND-}" ]]; then
    log_info "Master Command : ${DOKKAEBI_MASTER_COMMAND}"
fi
log_info "Execution Command: ${FULL_COMMAND_QC}" 
log_info "Mode          : ${MODE}"
log_info "Input Dir     : ${RAW_DIR}"
log_info "Output Dir    : ${BASE_DIR}"
log_info "Kraken2 DB    : ${KRAKEN2_DB_ARG}"
if [[ "$MODE" == "host" ]]; then log_info "Host DB       : ${HOST_DB_ARG}"; fi
log_info "Threads       : ${THREADS}"
if [[ "$MODE" == "host" ]]; then log_info "KneadData Memory: ${MEMORY_MB}"; fi
log_info "------------------------------"
check_conda_dependency "$KRAKEN_ENV" "kraken2"; check_conda_dependency "$KRAKEN_ENV" "bracken"
if [[ "$MODE" == "host" ]]; then check_conda_dependency "$KNEADDATA_ENV" "kneaddata"; fi
if [[ "$MODE" == "environmental" ]]; then check_conda_dependency "$KNEADDATA_ENV" "fastqc"; check_conda_dependency "$FASTP_ENV" "fastp"; fi
check_conda_dependency "$KNEADDATA_ENV" "multiqc"
log_info "모든 소프트웨어 의존성 확인 완료."

# --- 8. 샘플별 루프 (KneadData 병렬 + Kraken2 순차 하이브리드 적용) ---
# [설정] 슬롯 개수 정의
MAX_KNEAD_JOBS=2   # KneadData 동시 실행 수
MAX_KRAKEN_JOBS=1  # Kraken2 동시 실행 수 (메모리 보호)
MAX_PENDING_JOBS=20 # 대기열 제한 

# 스레드 계산 (KneadData용)
THREADS_PER_JOB=$(( THREADS / MAX_KNEAD_JOBS ))
if (( THREADS_PER_JOB < 1 )); then THREADS_PER_JOB=1; fi

# 잠금 파일 저장할 임시 폴더 생성
LOCK_DIR="${WORK_DIR}/locks"
mkdir -p "$LOCK_DIR"
# KneadData용 슬롯 파일 생성 (1~4번)
for ((i=1; i<=MAX_KNEAD_JOBS; i++)); do touch "${LOCK_DIR}/knead_slot_${i}"; done

log_info "Starting Pipeline Loop..."
#log_info "Strategy: KneadData ($MAX_KNEAD_JOBS parallel) -> Release -> Kraken2 ($MAX_KRAKEN_JOBS serial)"

if [ -d "/dev/shm" ]; then STATUS_DIR="/dev/shm/dokkaebi_status"; else STATUS_DIR="/tmp/dokkaebi_status"; fi
rm -f "${STATUS_DIR}"/*.status

TOTAL_FILES=$(find "$RAW_DIR" -maxdepth 1 -name "*_1.fastq.gz" -o -name "*_R1.fastq.gz" | wc -l)
CURRENT_COUNT=0

for R1 in "$RAW_DIR"/*{_1,_R1,.1,.R1}.fastq.gz; do
    # --- 샘플 정보 파싱 --- 
    # [수정 1] R2 경로 생성 로직을 파일 끝에 고정된 단일 명령어로 단순화
    R2=$(echo "$R1" | sed -E 's/([._][Rr]?)1(\.fastq\.gz)$/\12\2/')
    # 2. R2 파일이 실제로 존재하는지 확인
    if [[ ! -f "$R2" ]]; then
        log_warn "R1 파일 '${R1}'에 대한 페어(R2)를 찾을 수 없습니다. 건너뜁니다."
        echo "$(basename "$R1")" >> "$MISMATCH_FILE"
        continue
    fi

    # [수정 2] 샘플 이름 추출 로직도 더 명확하고 안전한 단일 명령어로 변경
    SAMPLE=$(basename "$R1" .fastq.gz | sed -E 's/([._][Rr]?)1$//')

    # printf "\n" >&2; log_info "--- 샘플 '$SAMPLE' 분석 시작 ---"
    
    CURRENT_COUNT=$((CURRENT_COUNT + 1))
    #((CURRENT_COUNT++))
    print_progress_bar "$CURRENT_COUNT" "$TOTAL_FILES" "$SAMPLE"

    # 각 단계를 위한 성공 플래그 경로를 먼저 정의합니다.
    QC_SUCCESS_FLAG="${CLEAN_DIR}/.${SAMPLE}.qc.success"
    KRAKEN2_SUCCESS_FLAG="${KRAKEN_OUT}/.${SAMPLE}.kraken2.success"
    BRACKEN_MPA_SUCCESS_FLAG="${MPA_OUT}/.${SAMPLE}.bracken_mpa.success"

    # 최종 단계(Bracken/MPA)의 성공 플래그가 있다면, 샘플 전체를 빠르게 건너뜁니다.
    if [ -f "$BRACKEN_MPA_SUCCESS_FLAG" ]; then
        log_info "${SAMPLE}: 모든 단계가 이미 완료되었습니다. 건너뜁니다."
        continue
    fi

    # [신규 추가] 이미 처리 중인 샘플 건너뛰기
    PROCESSING_FLAG="${CLEAN_DIR}/.${SAMPLE}.processing"
    if [ -f "$PROCESSING_FLAG" ]; then continue; fi

    # [신규 추가] 대기열 관리 (서버 과부하 방지)
    while [ $(jobs -p | wc -l) -ge "$MAX_PENDING_JOBS" ]; do 
        sleep 60
        # 대기 중에도 화면 갱신 (상태 변화 반영)
        print_progress_bar "$CURRENT_COUNT" "$TOTAL_FILES" "Waiting..."
    done
    
    touch "$PROCESSING_FLAG"
    # log_info "[Queue] $SAMPLE added to pipeline queue."

    # ===========================================================
    #  [핵심 수정] 백그라운드 실행 그룹 (비동기 처리) 시작
    # ===========================================================
    (
        # [수정] 서브쉘 내부 에러 핸들링 강화
        set -euo pipefail
        cleanup_on_exit() {
            rm -f "$PROCESSING_FLAG"
            clear_job_status "$SAMPLE"
        }

        trap cleanup_on_exit EXIT
        
        set_job_status "$SAMPLE" "Initializing..."

        # --- 1. QC 단계 (KneadData 또는 fastp) ---
        r1_for_kraken2=""; r2_for_kraken2=""
    
        if [ -f "$QC_SUCCESS_FLAG" ]; then
            log_info "${SAMPLE}: QC Already Done."
        else

            set_job_status "$SAMPLE" "Waiting for QC slot..."

            log_info "${SAMPLE}: 신규 QC 분석을 시작합니다."

            MY_SLOT=""
            while true; do
                for ((i=1; i<=MAX_KNEAD_JOBS; i++)); do
                    exec 9>"${LOCK_DIR}/knead_slot_${i}"
                    if flock -n 9; then MY_SLOT=$i; break 2; fi # 성공 시 루프 탈출
                    exec 9>&-
                done
                sleep 5
            done
            
            log_info "  [KneadData START] $SAMPLE (Slot #$MY_SLOT)"
            
            #cleaned_files_str="" # 결과 경로를 담을 변수 초기화
            
            if [[ "$MODE" == "host" ]]; then
                set_job_status "$SAMPLE" "Running KneadData (QC)..."
                # KneadData에 사용할 스레드 수를 계산합니다. (입력된 스레드의 절반, 최소 1개 보장)
                #KNEADDATA_THREADS=$((THREADS / 2))
                #if (( KNEADDATA_THREADS < 1 )); then
                #KNEADDATA_THREADS=$((THREADS_PER_JOB / 1.5))
                #if (( KNEADDATA_THREADS < 1 )); then KNEADDATA_THREADS=1; fi
                KNEADDATA_THREADS="$THREADS_PER_JOB"
                if [[ "$KNEADDATA_THREADS" -lt 1 ]]; then KNEADDATA_THREADS=1; fi
                #log_info "Allocating ${KNEADDATA_THREADS} threads to KneadData (half of the requested ${THREADS})."
                
                decompressed_files=($(decompress_fastq "$SAMPLE" "$R1" "$R2" "$WORK_DIR"))
                r1_uncompressed="${decompressed_files[0]}"; r2_uncompressed="${decompressed_files[1]}"
            
            #cleaned_files_str=$(run_kneaddata "$SAMPLE" "$r1_uncompressed" "$r2_uncompressed" \
            #    "$HOST_DB_ARG" "$WORK_DIR" "$CLEAN_DIR" "$KNEADDATA_LOG" \
            #    "$FASTQC_PRE_QC_DIR" "$FASTQC_POST_QC_DIR" \
            #    "$THREADS" "$THREADS" "${MEMORY_MB}" "$TRIMMOMATIC_OPTIONS" \
            #    "$KNEADDATA_EXTRA_OPTS")
            
                run_kneaddata "$SAMPLE" "$r1_uncompressed" "$r2_uncompressed" \
                    "$HOST_DB_ARG" "$WORK_DIR" "$CLEAN_DIR" "$KNEADDATA_LOG" \
                    "$FASTQC_PRE_QC_DIR" "$FASTQC_POST_QC_DIR" \
                    "$KNEADDATA_THREADS" "$KNEADDATA_THREADS" "${MEMORY_MB}" "$TRIMMOMATIC_OPTIONS" \
                    "$KNEADDATA_EXTRA_OPTS" > /dev/null

                rm "$r1_uncompressed" "$r2_uncompressed"
            
            else # environmental 모드
                set_job_status "$SAMPLE" "Running fastp (QC)..."
                run_fastqc "$FASTQC_PRE_QC_DIR" "$THREADS_PER_JOB" "$R1" "$R2"
                cleaned_files_str=$(run_fastp "$SAMPLE" "$R1" "$R2" "$CLEAN_DIR" "$FASTP_REPORTS_DIR" "$THREADS_PER_JOB" "$FASTP_OPTIONS" "$FASTP_EXTRA_OPTS")

                # Post-QC FastQC 실행
                read -r r1_cleaned r2_cleaned <<< "$cleaned_files_str"
                if [[ -n "$r1_cleaned" && -f "$r1_cleaned" ]]; then
                     run_fastqc "$FASTQC_POST_QC_DIR" "$THREADS_PER_JOB" "$r1_cleaned" "$r2_cleaned"
                else
                     log_error "${SAMPLE}: fastp output not found."
                     flock -u 9; exec 9>&- # 슬롯 반납 필수
                     rm -f "$PROCESSING_FLAG"; exit 1
                fi
                # Environmental 모드 안에서 QC 결과물 확인
                #read -r -a cleaned_files <<< "$cleaned_files_str"
                #if [[ -z "${cleaned_files[0]}" ]]; then
                #    log_warn "fastp 결과 파일이 생성되지 않았습니다. 샘플을 건너뜁니다."
                #    continue
                #fi
            fi
      
            # QC 단계가 성공적으로 끝나면 성공 플래그를 생성합니다.
            touch "$QC_SUCCESS_FLAG"
            log_info "  [KneadData DONE] $SAMPLE (Slot #$MY_SLOT released)"

            # [신규 추가] 슬롯 반납 (중요!)
            flock -u 9
            exec 9>&-
        fi

        # --- QC-ONLY 모드 분기점 ---
        if [ "$QC_ONLY_MODE" = true ]; then
            #log_info "${SAMPLE}: QC-only mode enabled. Skipping Kraken2/Bracken analysis."
            rm -f "$PROCESSING_FLAG" 
            exit 0
        fi

        # QC를 건너뛰었든, 새로 실행했든, 다음 단계에 필요한 파일 경로를 확정합니다.
        if [[ "$MODE" == "host" ]]; then
            r1_for_kraken2="${CLEAN_DIR}/${SAMPLE}_1_kneaddata_paired_1.fastq.gz"
            r2_for_kraken2="${CLEAN_DIR}/${SAMPLE}_1_kneaddata_paired_2.fastq.gz"
        else
            r1_for_kraken2="${CLEAN_DIR}/${SAMPLE}_fastp_1.fastq.gz"
            r2_for_kraken2="${CLEAN_DIR}/${SAMPLE}_fastp_2.fastq.gz"
        fi
    
        if [[ ! -f "$r1_for_kraken2" ]]; then 
            log_error "QC output not found for $SAMPLE"; rm -f "$PROCESSING_FLAG"; exit 1;
        fi


        # --- 2. Kraken2 단계 (순차 실행 적용) ---
        final_kraken_report="${KRAKEN_OUT}/${SAMPLE}.k2report"
    
        #if [ -f "$KRAKEN2_SUCCESS_FLAG" ]; then
        #    log_info "${SAMPLE}: Kraken2 단계가 이미 완료되었습니다. 건너뜁니다."
        #else
        if [ ! -f "$KRAKEN2_SUCCESS_FLAG" ]; then

            set_job_status "$SAMPLE" "Waiting for Kraken2 lock..."
            
            log_info "  [Kraken2 WAIT] $SAMPLE is waiting for lock..."
            # [신규 추가] Kraken2 전용 잠금 (순차 실행 보장)
            exec 8>"${LOCK_DIR}/kraken_lock"
            flock 8 # 대기 (Blocking)
            
            set_job_status "$SAMPLE" "Running Kraken2 (Taxonomy)..."
            log_info "  [Kraken2 START] $SAMPLE (Serial)"
            
            # [수정] Kraken2 실행 (혼자 도니까 전체 $THREADS 사용 가능)
            run_kraken2 "$SAMPLE" "$r1_for_kraken2" "$r2_for_kraken2" "$KRAKEN2_DB_ARG" "$KRAKEN_OUT" "$KRAKEN2_SUMMARY_TSV" "$THREADS" "$KRAKEN2_EXTRA_OPTS"
            touch "$KRAKEN2_SUCCESS_FLAG"
            
            log_info "  [Kraken2 DONE] $SAMPLE"
            flock -u 8 # 잠금 해제
            exec 8>&-
        fi

        # --- 3. Bracken 및 MPA 변환 단계 ---
        #log_info "${SAMPLE}: Bracken & MPA 변환을 시작합니다."
        set_job_status "$SAMPLE" "Running Bracken/MPA..."

        run_bracken_and_mpa "$SAMPLE" "$final_kraken_report" "$KRAKEN2_DB_ARG" "$BRACKEN_OUT" "$MPA_OUT" "$BRACKEN_READ_LEN" "$BRACKEN_THRESHOLD"
        touch "$BRACKEN_MPA_SUCCESS_FLAG"
        log_info "${SAMPLE}: Bracken & MPA 단계 완료."
    
        log_info "--- [ALL DONE] $SAMPLE ---"
        rm -f "$PROCESSING_FLAG" # 처리 완료 깃발 내리기

        clear_job_status "$SAMPLE"

    ) &
done

# [신규 추가] 모든 작업 종료 대기
wait
log_info "All QC jobs finished."

# --- 모든 샘플 처리 후, Bracken 결과 통합 ---
if [ "$QC_ONLY_MODE" = false ]; then
    merge_bracken_outputs "$BRACKEN_OUT" "$BRACKEN_MERGED_OUT"
fi

# =================================================================
# --- Pre-QC 및 Post-QC 별도 MultiQC 리포트 생성 ---
# =================================================================
log_info "--- QC 전/후 비교를 위해 MultiQC 리포트를 모드별로 각각 생성합니다 ---"

# --- 1. Post-QC 리포트 생성 (모드별 분기) ---
MULTIQC_CL_CONFIG_HOST="fn_clean_exts:
  - _kneaddata_paired_1
  - _kneaddata_paired_2
  - _fastqc"

MULTIQC_CL_CONFIG_ENV="fn_clean_exts:
  - _fastp_1
  - _fastp_2
  - _fastqc
  - .fastp"

if [[ "$MODE" == "host" ]]; then
    log_info "MultiQC 리포트 생성 중 (Host Mode)..."
    conda run -n "$KNEADDATA_ENV" multiqc \
        --cl-config "$MULTIQC_CL_CONFIG_HOST" \
        --ignore-samples "*_unmatched_*" \
        "${FASTQC_POST_QC_DIR}" \
        "${KNEADDATA_LOG}" \
        --outdir "$MULTIQC_OUT" \
        --filename "multiqc_report_post_qc.html" \
        --title "Dokkaebi Pipeline :: POST-QC Report (Host)" \
        --force
else # environmental 모드
    log_info "MultiQC 리포트 생성 중 (Environmental Mode)..."
    conda run -n "$KNEADDATA_ENV" multiqc \
        --cl-config "$MULTIQC_CL_CONFIG_ENV" \
        "${FASTQC_POST_QC_DIR}" \
        "${FASTP_REPORTS_DIR}" \
        --outdir "$MULTIQC_OUT" \
        --filename "multiqc_report_post_qc.html" \
        --title "Dokkaebi Pipeline :: POST-QC Report (Environmental)" \
        --force
fi

log_info "Pre/Post QC 리포트 생성 완료. 경로: ${MULTIQC_OUT}"

# 9. 완료 메시지
#mv "$STATE_FILE_NEW" "$STATE_FILE"
log_info "--- 모든 샘플 분석 및 결과 통합 완료 ---"
log_info "파이프라인 종료 시간: $(date)"
printf "\n${GREEN}### 파이프라인 결과 요약 ###${NC}\n" >&2
printf "  - 전체 실행 로그: ${YELLOW}%s${NC}\n" "$LOG_FILE" >&2
printf "  - Kraken2 분류 요약: ${YELLOW}%s${NC}\n" "$KRAKEN2_SUMMARY_TSV" >&2
printf "  - 정제된 FASTQ 파일 (최종 보관): ${YELLOW}%s/${NC}\n" "$CLEAN_DIR" >&2
printf "  - Kraken2 분석 결과: ${YELLOW}%s/${NC}\n" "$KRAKEN_OUT" >&2
printf "  - Bracken 개별 결과: ${YELLOW}%s/${NC}\n" "$BRACKEN_OUT" >&2
printf "  - Bracken 통합 테이블: ${YELLOW}%s/${NC}\n" "$BRACKEN_MERGED_OUT" >&2
printf "  - MetaPhlAn 형식 보고서: ${YELLOW}%s/${NC}\n" "$MPA_OUT" >&2
printf "  - KneadData 상세 로그: ${YELLOW}%s/${NC}\n" "$KNEADDATA_LOG" >&2
printf "  - FastQC 보고서 (처리 전/후): ${YELLOW}%s/${NC}\n" "$FASTQC_REPORTS_DIR" >&2
printf "  - MultiQC 종합 리포트: ${YELLOW}%s/multiqc_report.html${NC}\n" "$MULTIQC_OUT" >&2
printf "  - 페어링 불일치 샘플 목록: ${YELLOW}%s${NC}\n" "$MISMATCH_FILE" >&2
printf "\n" >&2
summary_body_plain="
### 파이프라인 결과 요약 ###
  - 전체 실행 로그: $LOG_FILE
  - Kraken2 분류 요약: $KRAKEN2_SUMMARY_TSV
  - 정제된 FASTQ 파일 (최종 보관): $CLEAN_DIR/
  - Kraken2 분석 결과: $KRAKEN_OUT/
  - Bracken 결과: $BRACKEN_OUT/
  - Bracken 통합 테이블: $BRACKEN_MERGED_OUT/
  - MetaPhlAn 형식 보고서: $MPA_OUT/
  - KneadData 상세 로그: $KNEADDATA_LOG/
  - FastQC 보고서 (처리 전/후): $FASTQC_REPORTS_DIR/
  - 페어링 불일치 샘플 목록: $MISMATCH_FILE
"
printf "\n%s\n" "$summary_body_plain" >> "$LOG_FILE"