#!/bin/bash
#================================================
# PIPELINE 2: PER-SAMPLE MAG ANALYSIS (Smart Recovery Ready)
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

: "${GTDBTK_DATA_PATH:=}"

FULL_COMMAND_MAG="$0 \"$@\""

shopt -s nullglob
set -m

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")

# --- 사용법 안내 함수 ---
print_usage() {
    # 색상 코드 정의
    local RED=$'\033[0;31m'; local GREEN=$'\033[0;32m'; local YELLOW=$'\033[0;33m'
    local BLUE=$'\033[0;34m'; local CYAN=$'\033[0;36m'; local BOLD=$'\033[1m'; local NC=$'\033[0m'

    # ASCII Art Title (Dokkaebi + MAG)
    echo -e "${GREEN}"
    echo '    ██████╗  ██████╗ ██╗  ██╗██╗  ██╗ █████╗ ███████╗██████╗ ██╗'
    echo '    ██╔══██╗██╔═══██╗██║ ██╔╝██║ ██╔╝██╔══██╗██╔════╝██╔══██╗██║'
    echo '    ██║  ██║██║   ██║█████╔╝ █████╔╝ ███████║█████╗  ██████╔╝██║'
    echo '    ██║  ██║██║   ██║██╔═██╗ ██╔═██╗ ██╔══██║██╔══╝  ██╔══██╗██║'
    echo '    ██████╔╝╚██████╔╝██║  ██╗██║  ██╗██║  ██║███████╗██████╔╝██║'
    echo '    ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝'
    echo -e "${YELLOW}"
    echo '                   ███╗   ███╗ █████╗  ██████╗ '
    echo '                   ████╗ ████║██╔══██╗██╔════╝ '
    echo '                   ██╔████╔██║███████║██║  ███╗'
    echo '                   ██║╚██╔╝██║██╔══██║██║   ██║'
    echo '                   ██║ ╚═╝ ██║██║  ██║╚██████╔╝'
    echo '                   ╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ '
    echo -e "                       ${RED}${BOLD}--- MAG ANALYSIS ---${NC}"
    echo ""
    echo ""
    echo -e "   s         ${BOLD}--- MAG ANALYSIS WORKFLOW ---${NC}"
    echo ""
    echo -e "${YELLOW}Performs de novo assembly, binning, refinement, and annotation to generate MAGs from QC'd reads.${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}Usage:${NC}"
    echo "  dokkaebi mag <mode> [options...]"
    echo ""
    echo -e "${CYAN}${BOLD}Modes:${NC}"
    echo -e "  ${GREEN}all${NC}           - (Default) Runs all steps sequentially (Repair -> Assembly -> Binning -> Annotation)."
    echo -e "  ${GREEN}megahit${NC}       - Runs only up to the assembly and post-assembly analysis steps."
    echo -e "  ${GREEN}metawrap${NC}      - Runs only up to the binning/refinement and post-binning analysis steps."
    echo -e "  ${GREEN}binning${NC}      - Recovery mode: Runs from Binning to final annotation."
    echo -e "  ${GREEN}annotation${NC}   - Recovery mode: Runs ONLY Functional Annotation on existing bins."
    echo -e "  ${GREEN}post-process${NC}  - Runs only post-analysis steps on existing results."
    echo -e "  ${GREEN}--test${NC}         - Runs a quick, automated self-test of this pipeline."
    echo ""
    echo -e "${CYAN}${BOLD}Required Options:${NC}"
    echo "  --input_dir PATH         - (Required) Path to the input directory containing QC'd reads."
    echo "  --output_dir PATH        - Path to the main output directory. (Default: creates 'MAG_analysis' inside the input directory)"    
    echo "  --threads INT            - Number of threads to use. (Default: 6)"
    echo "  --memory_gb GB           - Max memory in Gigabytes for MEGAHIT. (Default: 60)"
    echo "  --parallel-jobs INT      - Number of parallel MAG jobs (Default: 1)"
    echo "                             (Light steps run in parallel, Heavy steps run sequentially)"
    echo "  --min_contig_len INT     - Minimum contig length for assembly. (Default: 1000)"
    echo "  --min_completeness INT   - Minimum completeness for refined bins. (Default: 50)"
    echo "  --max_contamination INT  - Maximum contamination for refined bins. (Default: 10)"
    echo "  --preset NAME            - MEGAHIT preset ('meta-sensitive' or 'meta-large'). (Default: meta-large)"
    echo "  --gtdbtk_db_dir PATH     - (Required) Path to the GTDB-Tk database."
    echo "  --bakta_db_dir PATH      - (Required for all modes) Path to the Bakta database."
    echo "  --eggnog_db_dir PATH     - (Required if using EggNOG) Path to the EggNOG database."
    echo "  --kraken2_db PATH        - (Required) Path to the Kraken2 database."    
    echo "  --tmp_dir PATH           - Path to a temporary directory. (Default: /home/kys/Desktop/tmp)"
    echo ""
    echo -e "${CYAN}${BOLD}Tool-specific Options (pass-through):${NC}"
    echo "  --annotation-tool STR   Tool for Contig annotation: 'eggnog' (default) or 'bakta'"
    echo "  --keep-temp-files        - Do not delete intermediate temporary files (for debugging)."
    echo "  --skip-contig-analysis   - Skip Kraken2 and Bakta analysis on assembled contigs."    
    echo "  --skip-annotation             - Skip ONLY Functional Annotation (Bakta/EggNOG) analysis on contigs."
    echo "  --verbose             - Show detailed logs in terminal instead of progress bar."      
    echo "  --megahit-opts OPTS     - Pass additional options to MEGAHIT (in quotes)."
    echo "  --metawrap-binning-opts OPTS   - Pass additional options to MetaWRAP's binning module."
    echo "  --metawrap-refinement-opts OPTS - Pass additional options to MetaWRAP's bin_refinement module."
    echo "  --kraken2-opts OPTS     - Pass additional options to Kraken2 on contigs (in quotes)."
    echo "  --gtdbtk-opts OPTS      - Pass additional options to GTDB-Tk (in quotes)."
    echo "  --bakta-opts OPTS       - Pass additional options to Bakta (in quotes)."
    echo "  --eggnog-opts OPTS    - Pass additional options to EggNOG-mapper (in quotes)."
    echo ""
    echo "  -h, --help              - Display this help message and exit."
    echo ""    
    echo ""
}

# --- 1. 실행 모드 및 옵션 파싱 ---
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_usage
    exit 0
fi

# --- 기본값 설정 ---
RUN_MODE="all"
RUN_TEST_MODE=false
KEEP_TEMP_FILES=false
SKIP_CONTIG_ANALYSIS=false
SKIP_ANNOTATION=false
SKIP_BAKTA=false
SKIP_GTDBTK=false
SKIP_EGGNOG=false
INPUT_DIR_ARG=""
RAW_INPUT_DIR=""
OUTPUT_DIR_ARG=""
THREADS=6
MEMORY_GB=60
PARALLEL_JOBS=1
MIN_CONTIG_LEN=1000
MIN_COMPLETENESS=50
MAX_CONTAMINATION=10
MEGAHIT_PRESET_TO_USE=""
GTDBTK_DB_DIR_ARG=""
BAKTA_DB_DIR_ARG=""
KRAKEN2_DB_ARG=""
TMP_DIR_ARG="" 
MEGAHIT_EXTRA_OPTS=""
METAWRAP_BINNING_EXTRA_OPTS=""
METAWRAP_REFINEMENT_EXTRA_OPTS=""
KRAKEN2_EXTRA_OPTS=""
GTDBTK_EXTRA_OPTS=""
BAKTA_EXTRA_OPTS=""
ANNOTATION_TOOL="eggnog"
EGGNOG_DB_DIR_ARG=""
EGGNOG_EXTRA_OPTS=""
SAMPLES_ARG=""  # 스마트 복구 타겟용 명단 변수 초기화

# --- 커맨드 라인 인자 파싱 ---
while [ $# -gt 0 ]; do
    case "$1" in
        --test) RUN_TEST_MODE=true; shift ;;
        --keep-temp-files) KEEP_TEMP_FILES=true; shift ;;
        --skip-contig-analysis) SKIP_CONTIG_ANALYSIS=true; shift ;;
        --skip-annotation) SKIP_ANNOTATION=true; shift ;;
        --skip-gtdbtk) SKIP_GTDBTK=true; shift ;;
        --skip-bakta) SKIP_BAKTA=true; shift ;;     
        megahit|metawrap|all|post-process|binning|annotation) RUN_MODE=$1; shift ;; # binning, annotation 모드 확장 수신
        --input_dir) INPUT_DIR_ARG="${2%/}"; shift 2 ;;
        --raw_input_dir) RAW_INPUT_DIR="${2%/}"; shift 2 ;;
        --output_dir) OUTPUT_DIR_ARG="${2%/}"; shift 2 ;;        
        --threads) THREADS="$2"; shift 2 ;;
        --memory_gb) MEMORY_GB="$2"; shift 2 ;;
        --parallel-jobs) PARALLEL_JOBS="$2"; shift 2 ;;
        --samples) SAMPLES_ARG="$2"; shift 2 ;; # --samples 옵션 수신구 추가
        --preset) MEGAHIT_PRESET_TO_USE="$2"; shift 2 ;;
        --gtdbtk_db_dir) GTDBTK_DB_DIR_ARG="$2"; shift 2 ;;
        --bakta_db_dir) BAKTA_DB_DIR_ARG="$2"; shift 2 ;;
        --kraken2_db) KRAKEN2_DB_ARG="$2"; shift 2 ;;
        --eggnog_db_dir) EGGNOG_DB_DIR_ARG="$2"; shift 2 ;;
        --tmp_dir) TMP_DIR_ARG="$2"; shift 2 ;;
        --annotation-tool) ANNOTATION_TOOL="$2"; shift 2 ;;
        --min_contig_len) MIN_CONTIG_LEN="$2"; shift 2 ;;
        --min_completeness) MIN_COMPLETENESS="$2"; shift 2 ;;
        --max_contamination) MAX_CONTAMINATION="$2"; shift 2 ;;
        --megahit-opts) MEGAHIT_EXTRA_OPTS="$2"; shift 2 ;;
        --metawrap-binning-opts) METAWRAP_BINNING_EXTRA_OPTS="$2"; shift 2 ;;
        --metawrap-refinement-opts) METAWRAP_REFINEMENT_EXTRA_OPTS="$2"; shift 2 ;;
        --kraken2-opts) KRAKEN2_EXTRA_OPTS="$2"; shift 2 ;;
        --gtdbtk-opts) GTDBTK_EXTRA_OPTS="$2"; shift 2 ;;
        --bakta-opts) BAKTA_EXTRA_OPTS="$2"; shift 2 ;;
        --eggnog-opts) EGGNOG_EXTRA_OPTS="$2"; shift 2 ;;
        --verbose) VERBOSE_MODE=true; shift ;;
        *) shift ;;
    esac
done

# --- 테스트 모드 실행 로직 ---
if [ "$RUN_TEST_MODE" = true ]; then
    if [[ -z "$GTDBTK_DB_DIR_ARG" || -z "$BAKTA_DB_DIR_ARG" ]]; then
        echo -e "\033[0;31mError: --gtdbtk_db_dir and --bakta_db_dir are required for --test mode.\033[0m" >&2
        exit 1
    fi
    TEST_BASE_DIR="test"
    export MAG_BASE_DIR="${TEST_BASE_DIR}/MAG_analysis"
    if [ -d "$TEST_BASE_DIR" ]; then
        echo "INFO: Removing previous test directory to ensure a fresh test."
        rm -rf "$TEST_BASE_DIR"
    fi
    if [ -d "MAG_analysis" ]; then 
        rm -rf "MAG_analysis"
    fi
    
    mkdir -p "$TEST_BASE_DIR"
    export LOG_FILE="${TEST_BASE_DIR}/pipeline_test_$(date +%Y%m%d_%H%M%S).log"
    > "$LOG_FILE"

    source "${PROJECT_ROOT_DIR}/config/pipeline_config.sh"
    source "${PROJECT_ROOT_DIR}/lib/pipeline_functions.sh"
    source "${PROJECT_ROOT_DIR}/config/mag_config.sh" 
    source "${PROJECT_ROOT_DIR}/lib/mag_functions.sh"        
    
    run_pipeline_test
    exit $? 
fi

if [ -z "$ANNOTATION_TOOL" ]; then
    ANNOTATION_TOOL="eggnog"
fi

# 2. 필수 인자 및 DB 유효성 검사
declare -a error_messages=()

# (1) 기본 필수 경로 체크 (스마트 복구 모드 가동 시 예외 허용 설계)
if [[ -z "$INPUT_DIR_ARG" && -z "$SAMPLES_ARG" ]]; then 
    if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "megahit" ]]; then
        error_messages+=("  - --input_dir is required."); 
    fi
fi
if [[ -z "$OUTPUT_DIR_ARG" ]]; then error_messages+=("  - --output_dir is required."); fi

# (2) Annotation Tool에 따른 DB 경로 체크
if [[ "$SKIP_ANNOTATION" == "false" && "$SKIP_CONTIG_ANALYSIS" == "false" ]]; then
    if [[ "$ANNOTATION_TOOL" == "bakta" && -z "$BAKTA_DB_DIR_ARG" ]]; then
        error_messages+=("  - --bakta_db_dir is required when choosing 'bakta'.")
    fi
    if [[ "$ANNOTATION_TOOL" == "eggnog" && -z "$EGGNOG_DB_DIR_ARG" ]]; then
        error_messages+=("  - --eggnog_db_dir is required when choosing 'eggnog'.")
    fi
fi

if [ ${#error_messages[@]} -gt 0 ]; then
    echo "========================================================"
    echo " [ERROR] Missing required arguments for MAG pipeline:"
    for msg in "${error_messages[@]}"; do echo "$msg"; done
    echo "========================================================"
    exit 1
fi

# ==========================================================
# --- 일반 실행 모드 (NORMAL EXECUTION MODE) ---
# ==========================================================
if [[ -z "$MEGAHIT_PRESET_TO_USE" ]]; then MEGAHIT_PRESET_TO_USE="meta-large"; fi

declare -a error_messages=()

# Input 경로 확인 (복구 모드 유연성 확보)
if [[ -z "$INPUT_DIR_ARG" && -z "$SAMPLES_ARG" ]]; then
    error_messages+=("  - --input_dir: 입력 디렉토리는 필수입니다.")
elif [[ -n "$INPUT_DIR_ARG" && ! -d "$INPUT_DIR_ARG" ]]; then
    error_messages+=("  - --input_dir: '${INPUT_DIR_ARG}' 경로에 디렉토리가 없습니다.")
fi

# GTDB-Tk 데이터베이스 경로 확인
if [[ "$SKIP_GTDBTK" == "false" && ( "$RUN_MODE" == "all" || "$RUN_MODE" == "metawrap" || "$RUN_MODE" == "binning" || "$RUN_MODE" == "annotation" || "$RUN_MODE" == "post-process" ) ]]; then
    if [[ -z "$GTDBTK_DB_DIR_ARG" ]]; then
        error_messages+=("  - --gtdbtk_db_dir: GTDB-Tk를 사용하는 모드('${RUN_MODE}')에는 필수입니다.")
    elif [[ ! -d "$GTDBTK_DB_DIR_ARG" ]]; then
        error_messages+=("  - --gtdbtk_db_dir: '${GTDBTK_DB_DIR_ARG}' 경로에 디렉토리가 없습니다.")
    fi
fi

if [[ "$ANNOTATION_TOOL" == "eggnog" ]]; then
    if [[ "$SKIP_CONTIG_ANALYSIS" == "false" && "$SKIP_ANNOTATION" == "false" ]]; then
        if [[ -z "$EGGNOG_DB_DIR_ARG" ]]; then
            error_messages+=("  - --eggnog_db_dir: Annotation 도구로 'eggnog'를 선택했을 경우 필수입니다.")
        elif [[ ! -d "$EGGNOG_DB_DIR_ARG" ]]; then
            error_messages+=("  - --eggnog_db_dir: '${EGGNOG_DB_DIR_ARG}' 경로에 디렉토리가 없습니다.")
        fi
    fi
fi

if [[ -z "$BAKTA_DB_DIR_ARG" ]]; then
    error_messages+=("  - --bakta_db_dir: 모든 모드(MAG 분석 포함)에서 필수입니다.")
elif [[ ! -d "$BAKTA_DB_DIR_ARG" ]]; then
    error_messages+=("  - --bakta_db_dir: '${BAKTA_DB_DIR_ARG}' 경로에 디렉토리가 없습니다.")
fi

if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "megahit" || "$RUN_MODE" == "post-process" ]]; then
    if [[ -z "$KRAKEN2_DB_ARG" ]]; then
        error_messages+=("  - --kraken2_db: Kraken2를 사용하는 모드에는 필수입니다.")
    elif [[ ! -d "$KRAKEN2_DB_ARG" ]]; then
        error_messages+=("  - --kraken2_db: '${KRAKEN2_DB_ARG}' 경로에 디렉토리가 없습니다.")
    fi
fi

if [ ${#error_messages[@]} -gt 0 ]; then
    RED='\033[0;31m'; NC='\033[0m'
    echo -e "${RED}Error: 아래의 필수 옵션이 누락되었거나 잘못되었습니다.${NC}" >&2
    printf "${RED}%s\n${NC}" "${error_messages[@]}" >&2
    printf "\n" >&2; print_usage; exit 1
fi

export QC_READS_DIR="$INPUT_DIR_ARG"

if [[ -z "$OUTPUT_DIR_ARG" ]]; then
    export MAG_BASE_DIR="${INPUT_DIR_ARG}/MAG_analysis"
else
    export MAG_BASE_DIR="$OUTPUT_DIR_ARG"
fi

if [[ -z "$TMP_DIR_ARG" ]]; then
    SAFE_TMP_DIR="${MAG_BASE_DIR}/tmp_workspace"
    mkdir -p "$SAFE_TMP_DIR"
    TMP_DIR_ARG=$(mktemp -d -p "$SAFE_TMP_DIR")
    echo "INFO: Temporary workspace created at: $TMP_DIR_ARG"
else
    mkdir -p "$TMP_DIR_ARG"
fi

if [[ -n "$GTDBTK_DB_DIR_ARG" ]]; then
    export GTDBTK_DATA_PATH="$GTDBTK_DB_DIR_ARG"
fi

source "${PROJECT_ROOT_DIR}/config/pipeline_config.sh"
source "${PROJECT_ROOT_DIR}/lib/pipeline_functions.sh"
source "${PROJECT_ROOT_DIR}/config/mag_config.sh"
source "${PROJECT_ROOT_DIR}/lib/mag_functions.sh"

mkdir -p "$MAG_BASE_DIR" "$REPAIR_DIR" "$ASSEMBLY_DIR" "$ASSEMBLY_STATS_DIR" \
         "$KRAKEN_ON_CONTIGS_DIR" "$METAWRAP_DIR" \
         "$GTDBTK_ON_MAGS_DIR" "$BAKTA_ON_MAGS_DIR" "$TMP_DIR_ARG"

if [[ "$ANNOTATION_TOOL" == "bakta" ]]; then
    mkdir -p "$BAKTA_ON_CONTIGS_DIR"
elif [[ "$ANNOTATION_TOOL" == "eggnog" ]]; then
    mkdir -p "$EGGNOG_ON_CONTIGS_DIR"
fi

KRAKEN2_CONTIGS_SUMMARY_TSV="${MAG_BASE_DIR}/kraken2_contigs_summary.tsv"
if [ ! -f "$KRAKEN2_CONTIGS_SUMMARY_TSV" ]; then 
    echo -e "Sample\tTotal_Contigs\tClassified_Contigs\tClassified(%)\tUnclassified_Contigs\tUnclassified(%)" > "$KRAKEN2_CONTIGS_SUMMARY_TSV"
fi

EGGNOG_SUMMARY_CSV="${MAG_BASE_DIR}/eggnog_annotation_summary.csv"
if [ ! -f "$EGGNOG_SUMMARY_CSV" ]; then
    echo "Sample_ID,Total_Genes,Annotated_Genes,Ratio(%),Status" > "$EGGNOG_SUMMARY_CSV"
fi

LOG_FILE="${MAG_BASE_DIR}/3_mag_per_sample_$(date +%Y%m%d_%H%M%S).log"
> "$LOG_FILE"; trap '_error_handler' ERR

echo "INFO: Input directory set to: ${QC_READS_DIR}"
echo "INFO: Output directory set to: ${MAG_BASE_DIR}"
if [[ -n "$GTDBTK_DATA_PATH" ]]; then
    echo "INFO: GTDB-Tk database path set to: ${GTDBTK_DATA_PATH}"
fi
echo "INFO: Bakta database path set to: ${BAKTA_DB_DIR_ARG}"
echo "INFO: EggNOG database path set to: ${EGGNOG_DB_DIR_ARG}"

log_info "--- Pipeline Configuration ---"
if [[ -n "${DOKKAEBI_MASTER_COMMAND-}" ]]; then
    log_info "Master Command : ${DOKKAEBI_MASTER_COMMAND}"
fi
log_info "Execution Command: ${FULL_COMMAND_MAG}"
log_info "Input directory : ${QC_READS_DIR}"
log_info "Output directory: ${MAG_BASE_DIR}"
log_info "Run mode        : ${RUN_MODE}"
log_info "Threads         : ${THREADS}"
log_info "Memory for MEGAHIT: ${MEMORY_GB}G"
log_info "Skip Contigs    : ${SKIP_CONTIG_ANALYSIS}"
log_info "Skip Bakta      : ${SKIP_BAKTA}"
if [[ -n "$GTDBTK_DATA_PATH" ]]; then log_info "GTDB-Tk DB path : ${GTDBTK_DATA_PATH}"; fi
log_info "Bakta DB path   : ${BAKTA_DB_DIR_ARG}"
log_info "EggNOG DB path  : ${EGGNOG_DB_DIR_ARG}"
log_info "------------------------------"

log_info "Checking MAG pipeline dependencies for mode: ${RUN_MODE}"
if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "megahit" ]]; then
    check_conda_dependency "$BBMAP_ENV" "repair.sh"; check_conda_dependency "$MEGAHIT_ENV" "megahit";
fi
if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "metawrap" || "$RUN_MODE" == "binning" ]]; then
    check_conda_dependency "$METAWRAP_ENV" "metawrap";
fi
if [[ "$RUN_MODE" != "megahit" ]]; then 
    check_conda_dependency "$KRAKEN_ENV" "kraken2"; check_conda_dependency "$BAKTA_ENV" "bakta";
    check_conda_dependency "$GTDBTK_ENV" "gtdbtk";
fi
log_info "All dependencies are satisfied."

if [[ "$PARALLEL_JOBS" -gt 1 ]]; then
    MAX_MAG_JOBS="$PARALLEL_JOBS"
    THREADS_PER_JOB=$(( THREADS / PARALLEL_JOBS ))
    if [[ "$THREADS_PER_JOB" -lt 1 ]]; then THREADS_PER_JOB=1; fi
    MEMORY_GB_PER_JOB=$(( MEMORY_GB / PARALLEL_JOBS ))
    if [[ "$MEMORY_GB_PER_JOB" -lt 1 ]]; then MEMORY_GB_PER_JOB=1; fi
    log_info "⚡ Auto-Scaling: $MAX_MAG_JOBS parallel jobs (Per job: $THREADS_PER_JOB threads, $MEMORY_GB_PER_JOB GB RAM)"
else
    MAX_MAG_JOBS=1
    THREADS_PER_JOB="$THREADS"
    MEMORY_GB_PER_JOB="$MEMORY_GB"
    log_info "⚡ Single Job Mode: Using full resources per job."
fi

LOCK_DIR="${MAG_BASE_DIR}/locks"; mkdir -p "$LOCK_DIR"
HEAVY_JOB_LOCK="${LOCK_DIR}/heavy_resource.lock"
rm -f "$HEAVY_JOB_LOCK"

log_info "--- (Step 2) Starting Per-Sample MAG Analysis (Mode: ${RUN_MODE}) ---"

if [[ -z "$SAMPLES_ARG" ]]; then
    if [ -z "$(ls -A "${QC_READS_DIR}"/*_1.fastq.gz 2>/dev/null)" ]; then
        log_warn "입력 폴더 '${QC_READS_DIR}'에 FASTQ 파일이 없습니다. 파이프라인 2를 종료합니다."
        exit 0
    fi
fi

RESTART_SIGNAL_FILE="${MAG_BASE_DIR}/.restart_required"
rm -f "$RESTART_SIGNAL_FILE"

if [ -d "/dev/shm" ]; then STATUS_DIR="/dev/shm/dokkaebi_status"; else STATUS_DIR="/tmp/dokkaebi_status"; fi
rm -f "${STATUS_DIR}"/*.status
export LAST_PRINT_LINES=0

# ==============================================================================
# 🎯 [스마트 필터망 이식] 전체 조사 vs 낙오자 저격 분기 수집 공정
# ==============================================================================
declare -a TARGET_SAMPLE_FILES=()
declare -a TARGET_SAMPLE_NAMES=()   # --samples 모드에서 run_all.sh가 넘겨준 "진짜" 샘플명을 보존 (파일명 재추출 방지)

if [[ -n "${SAMPLES_ARG:-}" ]]; then
    log_info "🎯 Targeted Recovery Mode Active. Filtering specific failed samples: $SAMPLES_ARG"
    IFS=',' read -r -a SPECIFIC_SAMPLES <<< "$SAMPLES_ARG"
    for s_id in "${SPECIFIC_SAMPLES[@]}"; do
        MATCH_FILE=$(find "${MAG_BASE_DIR}/../1_microbiome_taxonomy/01_clean_reads" -maxdepth 1 -name "${s_id}*_1.fastq.gz" 2>/dev/null | head -n 1)
        if [[ -z "$MATCH_FILE" && -n "$INPUT_DIR_ARG" ]]; then
            MATCH_FILE=$(find "${INPUT_DIR_ARG}" -maxdepth 1 -name "${s_id}*_1.fastq.gz" 2>/dev/null | head -n 1)
        fi
        if [[ -n "$MATCH_FILE" ]]; then
            TARGET_SAMPLE_FILES+=("$MATCH_FILE")
            TARGET_SAMPLE_NAMES+=("$s_id")
        fi
    done
else
    for f in "${QC_READS_DIR}"/*_1.fastq.gz; do
        [ -e "$f" ] && TARGET_SAMPLE_FILES+=("$f")
    done
fi

TOTAL_SAMPLES=${#TARGET_SAMPLE_FILES[@]}
CURRENT_PROGRESS=0

if [ "$TOTAL_SAMPLES" -eq 0 ]; then
    log_warn "처리할 대상 FASTQ 샘플 파일이 존재하지 않습니다. 종료합니다."
    exit 0
fi

if [[ -z "${DOKKAEBI_MASTER_COMMAND:-}" ]]; then
    export JOB_STATUS_DIR="$STATUS_DIR"; mkdir -p "$JOB_STATUS_DIR"
    echo "[INFO] Starting Dashboard in background..."
    show_progress_dashboard "${INPUT_DIR_ARG:-$MAG_BASE_DIR}" "$MAG_BASE_DIR" "$JOB_STATUS_DIR" &
    DASHBOARD_PID=$!
fi

# ==============================================================================
# 메인 루프 시동 (TARGET_SAMPLE_FILES 기반 배열 처리)
# ==============================================================================
for TARGET_IDX in "${!TARGET_SAMPLE_FILES[@]}"; do
    R1_QC_GZ="${TARGET_SAMPLE_FILES[$TARGET_IDX]}"
    PRESET_SAMPLE_NAME="${TARGET_SAMPLE_NAMES[$TARGET_IDX]:-}"

    if [ -f "$RESTART_SIGNAL_FILE" ]; then
        log_warn "Restart signal detected. Stopping new job submission."
        break
    fi

    while [ $(jobs -p | grep -v "${DASHBOARD_PID:-IGNORE}" | wc -l) -ge "$MAX_MAG_JOBS" ]; do
        if [ -f "$RESTART_SIGNAL_FILE" ]; then
            log_warn "Restart signal detected while waiting for slots."
            break 2 
        fi
        sleep 10
    done

    (
        export FULL_THREADS="$THREADS"
        THREADS="$THREADS_PER_JOB"
        MEMORY_GB="$MEMORY_GB_PER_JOB"

        if [[ ! -f "$R1_QC_GZ" ]]; then exit 0; fi

        SAMPLE_BASE=$(basename "$R1_QC_GZ")
        if [[ -n "$PRESET_SAMPLE_NAME" ]]; then
            # run_all.sh가 --samples로 넘긴 이름을 그대로 사용합니다. 파일명에서 다시 추출하면
            # 샘플명 자체에 "_1" 같은 패턴이 들어있을 때 잘못된 이름(예: 실제 존재하는
            # 01_assembly/KGDM_BDC_013_04 대신 KGDM_BDC_013_04_1)을 만들어내어, 이미 끝난
            # Assembly/Post-Assembly 결과를 못 찾고 엉뚱한 새 폴더를 만들게 됩니다.
            SAMPLE="$PRESET_SAMPLE_NAME"
        else
            SAMPLE=$(echo "$SAMPLE_BASE" | sed -E 's/(_1|_2|_R1|_R2)\.fastq\.gz$//' | sed -E 's/(_kneaddata|_paired|_unpaired|_fastp).*//')
        fi
        R2_QC_GZ="${R1_QC_GZ/_1.fastq.gz/_2.fastq.gz}"

        echo ">>> [CHECK] Sample ID: $SAMPLE"

        if [[ ! -f "$R2_QC_GZ" ]]; then 
            log_warn "Paired QC file for $SAMPLE not found. Expected: $(basename "$R2_QC_GZ")"
            exit 0
        fi

        CURRENT_PROGRESS=$((CURRENT_PROGRESS + 1))

        REPAIR_SUCCESS_FLAG="${REPAIR_DIR}/.${SAMPLE}.repair.success"
        ASSEMBLY_SUCCESS_FLAG="${ASSEMBLY_DIR}/.${SAMPLE}.assembly.success"
        POST_ASSEMBLY_SUCCESS_FLAG="${ASSEMBLY_STATS_DIR}/.${SAMPLE}.post_assembly.success"
        BINNING_SUCCESS_FLAG="${METAWRAP_DIR}/.${SAMPLE}.binning.success"
        GTDBTK_SUCCESS_FLAG="${GTDBTK_ON_MAGS_DIR}/.${SAMPLE}.gtdbtk.success"
        BAKTA_MAGS_SUCCESS_FLAG="${BAKTA_ON_MAGS_DIR}/.${SAMPLE}.bakta_mags.success"

        FINAL_SAMPLE_SUCCESS_FLAG="$BAKTA_MAGS_SUCCESS_FLAG"
        if [[ "$RUN_MODE" == "megahit" ]]; then FINAL_SAMPLE_SUCCESS_FLAG="$POST_ASSEMBLY_SUCCESS_FLAG"; fi
        
        if [ -f "$FINAL_SAMPLE_SUCCESS_FLAG" ] && [[ "$RUN_MODE" != "binning" && "$RUN_MODE" != "annotation" ]]; then 
            echo "[INFO] All MAG steps for ${SAMPLE} completed. Skipping." >> "$LOG_FILE"
            exit 0
        fi

        ASSEMBLY_OUT_DIR_SAMPLE="${ASSEMBLY_DIR}/${SAMPLE}"
        ASSEMBLY_FA="${ASSEMBLY_OUT_DIR_SAMPLE}/final.contigs.fa"
        FINAL_BINS_DIR="${METAWRAP_DIR}/${SAMPLE}/bin_refinement/metawrap_${MIN_COMPLETENESS}_${MAX_CONTAMINATION}_bins"
        REPAIR_DIR_SAMPLE="${REPAIR_DIR}/${SAMPLE}"
        
        echo ">>> [FINAL PATH CHECK] Output Dir: $ASSEMBLY_OUT_DIR_SAMPLE"

        set_job_status "$SAMPLE" "Initializing MAG Analysis..."

        if [[ "$RUN_MODE" == "post-process" ]]; then
            set_job_status "$SAMPLE" "Running Post-process Analysis..."
            log_info "Mode: post-process. Checking for existing results..."
            
            if [[ ! -f "$ASSEMBLY_FA" ]]; then
                log_warn "Assembly file not found for ${SAMPLE}. Skipping contig-level post-analysis."
            else
                if [ "$SKIP_CONTIG_ANALYSIS" = false ]; then
                    set_job_status "$SAMPLE" "Waiting for Kraken2 Slot..."
                    (
                        flock 9
                        set_job_status "$SAMPLE" "Running Kraken2 on Contigs..." 
                        KRAKEN_CONTIGS_OUT_DIR_SAMPLE="${KRAKEN_ON_CONTIGS_DIR}/${SAMPLE}"
                        run_kraken2_on_contigs "$SAMPLE" "$ASSEMBLY_FA" "$KRAKEN_CONTIGS_OUT_DIR_SAMPLE" "$KRAKEN2_DB_ARG" "$THREADS" "$KRAKEN2_CONTIGS_SUMMARY_TSV" "$KRAKEN2_EXTRA_OPTS" >> "$LOG_FILE" 2>&1
                    ) 9>"$HEAVY_JOB_LOCK"

                    if [ "$SKIP_ANNOTATION" = false ]; then
                        if [[ "$ANNOTATION_TOOL" == "bakta" ]]; then
                            set_job_status "$SAMPLE" "Running Bakta on Contigs..."
                            BAKTA_CONTIGS_OUT_DIR_SAMPLE="${BAKTA_ON_CONTIGS_DIR}/${SAMPLE}"; mkdir -p "$BAKTA_CONTIGS_OUT_DIR_SAMPLE"
                            run_bakta_for_contigs "$SAMPLE" "$ASSEMBLY_OUT_DIR_SAMPLE" "$BAKTA_CONTIGS_OUT_DIR_SAMPLE" "$BAKTA_DB_DIR_ARG" "$TMP_DIR_ARG" "$BAKTA_EXTRA_OPTS" >> "$LOG_FILE" 2>&1
                        elif [[ "$ANNOTATION_TOOL" == "eggnog" ]]; then
                            set_job_status "$SAMPLE" "Running EggNOG on Contigs..."
                            EGGNOG_CONTIGS_OUT_DIR_SAMPLE="${EGGNOG_ON_CONTIGS_DIR}/${SAMPLE}"
                            run_eggnog_on_contigs "$SAMPLE" "$ASSEMBLY_FA" "$EGGNOG_CONTIGS_OUT_DIR_SAMPLE" "$EGGNOG_DB_DIR_ARG" "$EGGNOG_EXTRA_OPTS" "$EGGNOG_SUMMARY_CSV" >> "$LOG_FILE" 2>&1
                        fi
                    else
                        echo "[INFO] Skipping Contig Annotation (--skip-annotation)." >> "$LOG_FILE"
                    fi
                else
                    echo "[INFO] Skipping ALL contig analysis." >> "$LOG_FILE"
                fi   
            fi

            if [[ ! -d "$FINAL_BINS_DIR" ]]; then
                log_warn "Final MAGs not found for ${SAMPLE}. Skipping MAG-level post-analysis."
            else
                GTDBTK_OUT_DIR_SAMPLE="${GTDBTK_ON_MAGS_DIR}/${SAMPLE}"; mkdir -p "$GTDBTK_OUT_DIR_SAMPLE"
                if [[ "$SKIP_GTDBTK" == "true" ]]; then
                    log_info "Skipping GTDB-Tk analysis for ${SAMPLE} (Post-process mode)."
                else
                    set_job_status "$SAMPLE" "Waiting for GTDB-Tk Slot..."
                    (
                        flock 9    
                        set_job_status "$SAMPLE" "Running GTDB-Tk..."
                        run_gtdbtk "$SAMPLE" "$FINAL_BINS_DIR" "$GTDBTK_OUT_DIR_SAMPLE" "$GTDBTK_EXTRA_OPTS" "$GTDBTK_DATA_PATH" >> "$LOG_FILE" 2>&1
                    ) 9>"$HEAVY_JOB_LOCK"
                fi

                if [[ "$SKIP_BAKTA" == "true" ]]; then
                    log_info "Skipping Bakta analysis for ${SAMPLE} (Post-process mode)."
                else
                    BAKTA_MAGS_OUT_DIR_SAMPLE="${BAKTA_ON_MAGS_DIR}/${SAMPLE}"; mkdir -p "$BAKTA_MAGS_OUT_DIR_SAMPLE"
                    run_bakta_for_mags "$SAMPLE" "$FINAL_BINS_DIR" "$BAKTA_MAGS_OUT_DIR_SAMPLE" "$BAKTA_DB_DIR_ARG" "$TMP_DIR_ARG" "$BAKTA_EXTRA_OPTS" >> "$LOG_FILE" 2>&1
                fi
            fi

        else
            # === 메인 공정 가동 회로 ===
            R1_REPAIRED_GZ="${REPAIR_DIR_SAMPLE}/${SAMPLE}_R1.repaired.fastq.gz"
            # 1. Read Pair Repair 단계 (all, megahit 모드일 때만 실행)
            if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "megahit" ]]; then
                if [ -f "$REPAIR_SUCCESS_FLAG" ]; then
                    echo "[INFO] Repair done for ${SAMPLE}" >> "$LOG_FILE"
                else
                    set_job_status "$SAMPLE" "Running Repair (BBMap)..."
                    mkdir -p "$REPAIR_DIR_SAMPLE"
                    repaired_files=($(run_pair_repair "$SAMPLE" "$R1_QC_GZ" "$R2_QC_GZ" "$REPAIR_DIR_SAMPLE"))
                    if [[ ! -s "${repaired_files[0]}" ]]; then log_warn "Read pair repairing failed."; exit 0; fi
                    touch "$REPAIR_SUCCESS_FLAG"
                fi
            fi
            R2_REPAIRED_GZ="${REPAIR_DIR_SAMPLE}/${SAMPLE}_R2.repaired.fastq.gz"
           
            # 2. Assembly 단계 (all, megahit 모드일 때만 실행 -- binning/annotation 복구 모드는
            # Repair 단계를 건너뛰므로 여기서 MEGAHIT을 재실행하면 복구된 리드 파일이 없어
            # 반드시 실패하고, 심지어 기존 (불완전한) assembly 폴더를 삭제해버립니다.
            # 그래서 Assembly 재실행 자체는 절대 binning/annotation 모드로 확장하면 안 됩니다.)
            if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "megahit" ]]; then
                if [ -f "$ASSEMBLY_SUCCESS_FLAG" ]; then
                    echo "[INFO] Assembly done for ${SAMPLE}" >> "$LOG_FILE"
                else
                    set_job_status "$SAMPLE" "Waiting for Assembly Solt..."
                    set_job_status "$SAMPLE" "Running Assembly (MEGAHIT)..."
                    run_megahit "$SAMPLE" "$R1_REPAIRED_GZ" "$R2_REPAIRED_GZ" "$ASSEMBLY_OUT_DIR_SAMPLE" "$MEGAHIT_PRESET_TO_USE" "$MEMORY_GB" "$MIN_CONTIG_LEN" "$THREADS" "$MEGAHIT_EXTRA_OPTS" >> "$LOG_FILE" 2>&1

                    if [ $? -eq 0 ]; then
                        touch "$ASSEMBLY_SUCCESS_FLAG"
                    else
                        log_warn "Assembly for ${SAMPLE} failed."
                        exit 0
                    fi
                fi
            fi

            # 3. Post-Assembly 분석 (Stats/Kraken2/Contig Annotation) -- all, megahit, binning,
            # annotation 모드 전부 포함. binning/annotation 복구 모드도 여기서 누락된 분석을
            # 채울 수 있어야 하므로, (예전 버전 흔적으로 없을 수 있는) ASSEMBLY_SUCCESS_FLAG
            # 대신 실제 조립 결과 파일(ASSEMBLY_FA)이 있는지로 안전하게 판단합니다.
            if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "megahit" || "$RUN_MODE" == "binning" || "$RUN_MODE" == "annotation" ]]; then
                if [ -f "$POST_ASSEMBLY_SUCCESS_FLAG" ]; then
                    echo "[INFO] Post-Assembly previously marked done for ${SAMPLE}. Re-verifying sub-steps..." >> "$LOG_FILE"
                fi
                if [ -f "$ASSEMBLY_FA" ]; then
                    STATS_SUCCESS_FLAG="${ASSEMBLY_STATS_DIR}/.${SAMPLE}.stats.success"
                    KRAKEN_CONTIGS_FLAG="${KRAKEN_ON_CONTIGS_DIR}/.${SAMPLE}.kraken.success"
                    if [[ "$ANNOTATION_TOOL" == "bakta" ]]; then
                        ANNO_CONTIGS_FLAG="${BAKTA_ON_CONTIGS_DIR}/.${SAMPLE}.anno.success"
                    else
                        ANNO_CONTIGS_FLAG="${EGGNOG_ON_CONTIGS_DIR}/.${SAMPLE}.anno.success"
                    fi

                    log_info "Starting post-assembly analysis for ${SAMPLE}..."

                    if [ ! -f "$STATS_SUCCESS_FLAG" ]; then
                        set_job_status "$SAMPLE" "Running Post-Assembly Stats..."
                        STATS_OUT_FILE="${ASSEMBLY_STATS_DIR}/${SAMPLE}_assembly_stats.txt"
                        conda run -n "$BBMAP_ENV" stats.sh in="$ASSEMBLY_FA" > "$STATS_OUT_FILE"
                        touch "$STATS_SUCCESS_FLAG"
                    fi

                    if [ "$SKIP_CONTIG_ANALYSIS" = false ]; then
                        if [ ! -f "$KRAKEN_CONTIGS_FLAG" ]; then
                            set_job_status "$SAMPLE" "Waiting for Kraken2 Slot..."
                            (
                                flock 9
                                set_job_status "$SAMPLE" "Running Kraken2 on Contigs..."
                                KRAKEN_CONTIGS_OUT_DIR_SAMPLE="${KRAKEN_ON_CONTIGS_DIR}/${SAMPLE}"
                                run_kraken2_on_contigs "$SAMPLE" "$ASSEMBLY_FA" "$KRAKEN_CONTIGS_OUT_DIR_SAMPLE" "$KRAKEN2_DB_ARG" "$THREADS" "$KRAKEN2_CONTIGS_SUMMARY_TSV" "$KRAKEN2_EXTRA_OPTS" >> "$LOG_FILE" 2>&1
                            ) 9>"$HEAVY_JOB_LOCK"
                            touch "$KRAKEN_CONTIGS_FLAG"
                        else
                            echo "[INFO] Kraken2 on contigs done for ${SAMPLE}" >> "$LOG_FILE"
                        fi

                        if [ "$SKIP_ANNOTATION" = false ]; then
                            if [ ! -f "$ANNO_CONTIGS_FLAG" ]; then
                                if [[ "$ANNOTATION_TOOL" == "bakta" ]]; then
                                    set_job_status "$SAMPLE" "Running Bakta on Contigs..."
                                    BAKTA_CONTIGS_OUT_DIR_SAMPLE="${BAKTA_ON_CONTIGS_DIR}/${SAMPLE}"; mkdir -p "$BAKTA_CONTIGS_OUT_DIR_SAMPLE"
                                    run_bakta_for_contigs "$SAMPLE" "$ASSEMBLY_OUT_DIR_SAMPLE" "$BAKTA_CONTIGS_OUT_DIR_SAMPLE" "$BAKTA_DB_DIR_ARG" "$TMP_DIR_ARG" "$BAKTA_EXTRA_OPTS" >> "$LOG_FILE" 2>&1
                                elif [[ "$ANNOTATION_TOOL" == "eggnog" ]]; then
                                    set_job_status "$SAMPLE" "Running EggNOG on Contigs..."
                                    EGGNOG_CONTIGS_OUT_DIR_SAMPLE="${EGGNOG_ON_CONTIGS_DIR}/${SAMPLE}"
                                    run_eggnog_on_contigs "$SAMPLE" "$ASSEMBLY_FA" "$EGGNOG_CONTIGS_OUT_DIR_SAMPLE" "$EGGNOG_DB_DIR_ARG" "$EGGNOG_EXTRA_OPTS" "$EGGNOG_SUMMARY_CSV" >> "$LOG_FILE" 2>&1
                                fi
                                touch "$ANNO_CONTIGS_FLAG"
                            else
                                echo "[INFO] Contig Annotation done for ${SAMPLE}" >> "$LOG_FILE"
                            fi
                        else
                            echo "[INFO] Skipping Contig Annotation (--skip-annotation enabled)." >> "$LOG_FILE"
                        fi
                    else
                        echo "[INFO] Skipping ALL contig analysis." >> "$LOG_FILE"
                    fi
                    touch "$POST_ASSEMBLY_SUCCESS_FLAG"
                else
                    log_warn "Assembly file (${ASSEMBLY_FA}) not found for ${SAMPLE}. Cannot run post-assembly analysis; sample needs a full 'all' mode re-run."
                fi
            fi

            # 🎯 [수정 4단계 이식망] 복구 분기를 포괄하도록 공정 마스킹 확장 (Binning 및 후속 공정 통합)
            if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "metawrap" || "$RUN_MODE" == "binning" || "$RUN_MODE" == "annotation" ]]; then
                if [[ ! -f "$ASSEMBLY_FA" ]]; then 
                    log_warn "Assembly file ($ASSEMBLY_FA) not found. Skipping binning/annotation.";
                else
                    # 4. MetaWRAP Binning 단계 (annotation 단독 복구 모드일 때는 비닝 스킵)
                    if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "metawrap" || "$RUN_MODE" == "binning" ]]; then
                        if [ -f "$BINNING_SUCCESS_FLAG" ]; then
                            echo "[INFO] Binning done for ${SAMPLE}" >> "$LOG_FILE"
                        else
                            set_job_status "$SAMPLE" "Running Binning (MetaWRAP)..." 
                            # 복구 모드 가동 시 중간 리페어 방이 박멸되었을 것을 대비해 원본 자동 연동 포백망 매칭
                            R1_IN="$R1_QC_GZ"; R2_IN="$R2_QC_GZ"
                            [ -f "${REPAIR_DIR_SAMPLE}/${SAMPLE}_R1.repaired.fastq.gz" ] && R1_IN="${REPAIR_DIR_SAMPLE}/${SAMPLE}_R1.repaired.fastq.gz"
                            [ -f "${REPAIR_DIR_SAMPLE}/${SAMPLE}_R2.repaired.fastq.gz" ] && R2_IN="${REPAIR_DIR_SAMPLE}/${SAMPLE}_R2.repaired.fastq.gz"
                            
                            run_metawrap_sample "$SAMPLE" "$ASSEMBLY_FA" "$R1_IN" "$R2_IN" "${METAWRAP_DIR}/${SAMPLE}" "$MIN_COMPLETENESS" "$MAX_CONTAMINATION" "$THREADS" "$METAWRAP_BINNING_EXTRA_OPTS" "$METAWRAP_REFINEMENT_EXTRA_OPTS" >> "$LOG_FILE" 2>&1
                            
                            if [[ -d "$FINAL_BINS_DIR" && -n "$(ls -A "$FINAL_BINS_DIR" 2>/dev/null)" ]]; then 
                                touch "$BINNING_SUCCESS_FLAG"; 
                            else 
                                log_warn "Binning finished but no MAGs found for ${SAMPLE}. (Not an error, just low quality)"
                            fi
                        fi
                    fi

                    # 5. GTDB-Tk 공정 (all, metawrap, binning, annotation 연쇄 가동 허용)
                    GTDBTK_OUT_DIR_SAMPLE="${GTDBTK_ON_MAGS_DIR}/${SAMPLE}"
                    GTDBTK_SUMMARY_FILE_BAC="${GTDBTK_OUT_DIR_SAMPLE}/gtdbtk.bac120.summary.tsv"
                    GTDBTK_SUMMARY_FILE_AR="${GTDBTK_OUT_DIR_SAMPLE}/gtdbtk.ar53.summary.tsv"
                    
                    if [[ "$SKIP_GTDBTK" == "true" ]]; then
                        log_info "Skipping GTDB-Tk analysis as requested."
                    else
                        if [ -f "$GTDBTK_SUCCESS_FLAG" ] && { [ -f "$GTDBTK_SUMMARY_FILE_BAC" ] || [ -f "$GTDBTK_SUMMARY_FILE_AR" ]; }; then
                            echo "[INFO] GTDB-Tk done for ${SAMPLE}" >> "$LOG_FILE"
                        elif [ -f "$BINNING_SUCCESS_FLAG" ] || [[ "$RUN_MODE" == "annotation" ]]; then
                            set_job_status "$SAMPLE" "Waiting for GTDB-Tk Slot..."
                            (
                                flock 9
                                set_job_status "$SAMPLE" "Running GTDB-Tk..."
                                run_gtdbtk "$SAMPLE" "$FINAL_BINS_DIR" "$GTDBTK_OUT_DIR_SAMPLE" "$GTDBTK_EXTRA_OPTS" "$GTDBTK_DATA_PATH" >> "$LOG_FILE" 2>&1
                            ) 9>"$HEAVY_JOB_LOCK"

                            if [[ -s "$GTDBTK_SUMMARY_FILE_BAC" || -s "$GTDBTK_SUMMARY_FILE_AR" ]]; then 
                                touch "$GTDBTK_SUCCESS_FLAG"
                                log_info "GTDB-Tk Classification Success."
                            else 
                                log_warn "GTDB-Tk finished but no summary file found (Classification Failed)."
                            fi
                        fi
                    fi
                    
                    # 6. Bakta on MAGs 공정
                    if [[ "$SKIP_BAKTA" == "true" ]]; then
                        log_info "Skipping Bakta for MAGs as requested."
                    else
                        if [ -f "$BAKTA_MAGS_SUCCESS_FLAG" ]; then 
                            echo "[INFO] Bakta on MAGs done for ${SAMPLE}" >> "$LOG_FILE"
                        elif [[ "$SKIP_GTDBTK" == "true" || -f "$GTDBTK_SUCCESS_FLAG" ]]; then
                            if [ -f "$BINNING_SUCCESS_FLAG" ] || [[ "$RUN_MODE" == "annotation" ]]; then
                                set_job_status "$SAMPLE" "Running Bakta on MAGs..."
                                run_bakta_for_mags "$SAMPLE" "$FINAL_BINS_DIR" "${BAKTA_ON_MAGS_DIR}/${SAMPLE}" "$BAKTA_DB_DIR_ARG" "$TMP_DIR_ARG" "$BAKTA_EXTRA_OPTS" >> "$LOG_FILE" 2>&1
                                touch "$BAKTA_MAGS_SUCCESS_FLAG"
                            fi
                        else
                            log_warn "Skipping Bakta because GTDB-Tk classification failed (No Success Flag)."
                        fi
                    fi
                fi
            fi
        fi

        if [ "$KEEP_TEMP_FILES" = false ]; then
            rm -rf "$REPAIR_DIR_SAMPLE"
        fi
    ) &
done

log_info "Waiting for all parallel MAG jobs to finish..."
wait
log_info "All MAG parallel jobs finished."

if [[ -n "${DASHBOARD_PID:-}" ]]; then
    kill "$DASHBOARD_PID" 2>/dev/null
fi

if [ -f "$RESTART_SIGNAL_FILE" ]; then
    log_warn "Restart required signal was caught. Exiting with code 99."
    rm -f "$RESTART_SIGNAL_FILE"
    exit 99
fi

log_info "Successfully updated MAG pipeline state."

if [[ -z "${DOKKAEBI_MASTER_COMMAND:-}" ]]; then
    if [ -f "${PROJECT_ROOT_DIR}/lib/reporting_functions.sh" ]; then
        log_info "Generating standalone Summary Report for MAG Analysis results..."
        source "${PROJECT_ROOT_DIR}/lib/reporting_functions.sh"
        if command -v create_summary_report &> /dev/null; then
            create_summary_report "$MAG_BASE_DIR"
            log_info "Summary report created at: ${MAG_BASE_DIR}/summary_report.html"
        fi
    fi
fi

log_info "--- (Step 2) All samples processed successfully! ---"
