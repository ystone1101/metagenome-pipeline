#!/bin/bash
#================================================
# PIPELINE 2: PER-SAMPLE MAG ANALYSIS
#================================================
set -euo pipefail

FULL_COMMAND_MAG="$0 \"$@\""

shopt -s nullglob

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
    echo -e "  ${GREEN}post-process${NC}  - Runs only post-analysis steps on existing results."
    echo -e "  ${GREEN}--test${NC}         - Runs a quick, automated self-test of this pipeline."
    echo ""
    echo -e "${CYAN}${BOLD}Required Options:${NC}"
    echo "  --input_dir PATH         - (Required) Path to the input directory containing QC'd reads."
    echo "  --output_dir PATH        - Path to the main output directory. (Default: creates 'MAG_analysis' inside the input directory)"    
    echo "  --threads INT            - Number of threads to use. (Default: 6)"
    echo "  --memory_gb GB              - Max memory in Gigabytes for MEGAHIT. (Default: 60)"
    echo "  --min_contig_len INT     - Minimum contig length for assembly. (Default: 1000)"
    echo "  --min_completeness INT   - Minimum completeness for refined bins. (Default: 50)"
    echo "  --max_contamination INT  - Maximum contamination for refined bins. (Default: 10)"
    echo "  --preset NAME            - MEGAHIT preset ('meta-sensitive' or 'meta-large'). (Default: meta-large)"
    echo "  --gtdbtk_db_dir PATH     - (Required) Path to the GTDB-Tk database."
    echo "  --bakta_db_dir PATH      - (Required for all modes) Path to the Bakta database."
    echo "  --kraken2_db PATH        - (Required) Path to the Kraken2 database."    
    echo "  --tmp_dir PATH           - Path to a temporary directory. (Default: /home/kys/Desktop/tmp)"
    echo ""
    echo -e "${CYAN}${BOLD}Tool-specific Options (pass-through):${NC}"
    echo "  --keep-temp-files        - Do not delete intermediate temporary files (for debugging)."
    echo "  --skip-contig-analysis   - Skip Kraken2 and Bakta analysis on assembled contigs."    
    echo "  --megahit-opts OPTS     - Pass additional options to MEGAHIT (in quotes)."
    echo "  --metawrap-binning-opts OPTS   - Pass additional options to MetaWRAP's binning module."
    echo "  --metawrap-refinement-opts OPTS - Pass additional options to MetaWRAP's bin_refinement module."
    echo "  --kraken2-opts OPTS     - Pass additional options to Kraken2 on contigs (in quotes)."
    echo "  --gtdbtk-opts OPTS      - Pass additional options to GTDB-Tk (in quotes)."
    echo "  --bakta-opts OPTS       - Pass additional options to Bakta (in quotes)."
    echo ""
    echo "  -h, --help              - Display this help message and exit."
    echo ""    
    echo ""
}

# --- 1. 실행 모드 및 옵션 파싱 ---
# --help 옵션이 있으면 사용법 출력 후 종료
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_usage
    exit 0
fi

# --- 기본값 설정 ---
RUN_MODE="all"
RUN_TEST_MODE=false
KEEP_TEMP_FILES=false
SKIP_CONTIG_ANALYSIS=false
INPUT_DIR_ARG=""
OUTPUT_DIR_ARG=""
THREADS=6
MEMORY_GB=60
MIN_CONTIG_LEN=1000
MIN_COMPLETENESS=50
MAX_CONTAMINATION=10
MEGAHIT_PRESET_TO_USE=""
GTDBTK_DB_DIR_ARG=""
BAKTA_DB_DIR_ARG=""
KRAKEN2_DB_ARG=""
TMP_DIR_ARG=$(mktemp -d) 
MEGAHIT_PRESET_TO_USE=""
MEGAHIT_EXTRA_OPTS=""
METAWRAP_BINNING_EXTRA_OPTS=""
METAWRAP_REFINEMENT_EXTRA_OPTS=""
KRAKEN2_EXTRA_OPTS=""
GTDBTK_EXTRA_OPTS=""
BAKTA_EXTRA_OPTS=""

# --- 커맨드 라인 인자 파싱 ---
while [ $# -gt 0 ]; do
    case "$1" in
        --test) RUN_TEST_MODE=true; shift ;;
        --keep-temp-files) KEEP_TEMP_FILES=true; shift ;;
        --skip-contig-analysis) SKIP_CONTIG_ANALYSIS=true; shift ;;        
        megahit|metawrap|all|post-process) RUN_MODE=$1; shift ;;
        --input_dir) INPUT_DIR_ARG="${2%/}"; shift 2 ;;
        --output_dir) OUTPUT_DIR_ARG="${2%/}"; shift 2 ;;        
        --threads) THREADS="$2"; shift 2 ;;
        --memory_gb) MEMORY_GB="$2"; shift 2 ;;
        --preset) MEGAHIT_PRESET_TO_USE="$2"; shift 2 ;;
        --gtdbtk_db_dir) GTDBTK_DB_DIR_ARG="$2"; shift 2 ;;
        --bakta_db_dir) BAKTA_DB_DIR_ARG="$2"; shift 2 ;;
        --kraken2_db) KRAKEN2_DB_ARG="$2"; shift 2 ;;
        --tmp_dir) TMP_DIR_ARG="$2"; shift 2 ;;
        --min_contig_len) MIN_CONTIG_LEN="$2"; shift 2 ;;
        --min_completeness) MIN_COMPLETENESS="$2"; shift 2 ;;
        --max_contamination) MAX_CONTAMINATION="$2"; shift 2 ;;
        --megahit-opts) MEGAHIT_EXTRA_OPTS="$2"; shift 2 ;;
        --metawrap-binning-opts) METAWRAP_BINNING_EXTRA_OPTS="$2"; shift 2 ;;
        --metawrap-refinement-opts) METAWRAP_REFINEMENT_EXTRA_OPTS="$2"; shift 2 ;;
        --kraken2-opts) KRAKEN2_EXTRA_OPTS="$2"; shift 2 ;;
        --gtdbtk-opts) GTDBTK_EXTRA_OPTS="$2"; shift 2 ;;
        --bakta-opts) BAKTA_EXTRA_OPTS="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# --- 테스트 모드 실행 로직 ---
if [ "$RUN_TEST_MODE" = true ]; then
    # 1. 테스트에 필요한 DB 경로가 지정되었는지 먼저 확인합니다.
    if [[ -z "$GTDBTK_DB_DIR_ARG" || -z "$BAKTA_DB_DIR_ARG" ]]; then
        echo -e "\033[0;31mError: --gtdbtk_db_dir and --bakta_db_dir are required for --test mode.\033[0m" >&2
        exit 1
    fi
    
    # 2. 테스트를 위한 기본 폴더 이름을 'test'로 정의합니다.
    TEST_BASE_DIR="test"

    # 테스트의 분석 결과가 저장될 위치를 MAG_BASE_DIR 변수에 미리 정의합니다.
    export MAG_BASE_DIR="${TEST_BASE_DIR}/MAG_analysis"
    
    # 3. 이전 테스트 결과가 있다면 'test' 폴더를 통째로 삭제합니다.
    # (주의: 이전에 생성된 'MAG_analysis' 폴더도 있다면 함께 정리합니다.)
    if [ -d "$TEST_BASE_DIR" ]; then
        echo "INFO: Removing previous test directory to ensure a fresh test."
        rm -rf "$TEST_BASE_DIR"
    fi
    if [ -d "MAG_analysis" ]; then # 이전 실행의 잔재 정리
        rm -rf "MAG_analysis"
    fi
    
    # 4. 새로운 'test' 폴더와 그 안의 로그 파일을 생성합니다. 
    mkdir -p "$TEST_BASE_DIR"
    export LOG_FILE="${TEST_BASE_DIR}/pipeline_test_$(date +%Y%m%d_%H%M%S).log"
    > "$LOG_FILE"

    # 5. 모든 설정 및 함수 파일을 로드합니다.
    source "${PROJECT_ROOT_DIR}/config/pipeline_config.sh"
    source "${PROJECT_ROOT_DIR}/lib/pipeline_functions.sh"
    source "${PROJECT_ROOT_DIR}/config/mag_config.sh" 
    source "${PROJECT_ROOT_DIR}/lib/mag_functions.sh"        
    
    # 6. 모든 준비가 끝났으므로, 테스트 함수를 실행합니다.
    run_pipeline_test
    exit $? 
fi

# ==========================================================
# --- 일반 실행 모드 (NORMAL EXECUTION MODE) ---
# ==========================================================

# --- 2. 최종 MEGAHIT 프리셋 결정 ---
if [[ -z "$MEGAHIT_PRESET_TO_USE" ]]; then MEGAHIT_PRESET_TO_USE="meta-large"; fi

# --- 3. 경로 확인 및 설정 ---
# GTDB-Tk를 사용하는 모드일 경우, DB 경로가 반드시 지정되었는지 확인
declare -a error_messages=()

# 3a. Input 경로 확인
if [[ -z "$INPUT_DIR_ARG" ]]; then
    error_messages+=("  - --input_dir: 입력 디렉토리는 필수입니다.")
elif [[ ! -d "$INPUT_DIR_ARG" ]]; then
    error_messages+=("  - --input_dir: '${INPUT_DIR_ARG}' 경로에 디렉토리가 없습니다.")
fi

# 3b. GTDB-Tk 데이터베이스 경로 확인
if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "metawrap" || "$RUN_MODE" == "post-process" ]]; then
    if [[ -z "$GTDBTK_DB_DIR_ARG" ]]; then
        error_messages+=("  - --gtdbtk_db_dir: GTDB-Tk를 사용하는 모드('${RUN_MODE}')에는 필수입니다.")
    elif [[ ! -d "$GTDBTK_DB_DIR_ARG" ]]; then
        error_messages+=("  - --gtdbtk_db_dir: '${GTDBTK_DB_DIR_ARG}' 경로에 디렉토리가 없습니다.")
    fi
fi

# 3c. Bakta 데이터베이스 경로 확인
if [[ -z "$BAKTA_DB_DIR_ARG" ]]; then
    error_messages+=("  - --bakta_db_dir: 모든 모드에서 필수입니다.")
elif [[ ! -d "$BAKTA_DB_DIR_ARG" ]]; then
    error_messages+=("  - --bakta_db_dir: '${BAKTA_DB_DIR_ARG}' 경로에 디렉토리가 없습니다.")
fi

# 3d. Kraken2 데이터베이스 경로 확인 로직 추가
if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "megahit" || "$RUN_MODE" == "post-process" ]]; then
    if [[ -z "$KRAKEN2_DB_ARG" ]]; then
        error_messages+=("  - --kraken2_db: Kraken2를 사용하는 모드에는 필수입니다.")
    elif [[ ! -d "$KRAKEN2_DB_ARG" ]]; then
        error_messages+=("  - --kraken2_db: '${KRAKEN2_DB_ARG}' 경로에 디렉토리가 없습니다.")
    fi
fi

# 3e. 모든 오류를 종합하여 한 번에 출력
if [ ${#error_messages[@]} -gt 0 ]; then
    RED='\033[0;31m'
    NC='\033[0m'

    echo -e "${RED}Error: 아래의 필수 옵션이 누락되었거나 잘못되었습니다.${NC}" >&2
    printf "${RED}%s\n${NC}" "${error_messages[@]}" >&2
    
    printf "\n" >&2
    print_usage
    exit 1
fi

# --- 4. 최종 입출력 경로 설정 ---
# 4a. 입력 경로 설정
export QC_READS_DIR="$INPUT_DIR_ARG"

# 4b. 출력 경로 설정
if [[ -z "$OUTPUT_DIR_ARG" ]]; then
    export MAG_BASE_DIR="${INPUT_DIR_ARG}/MAG_analysis"
else
    export MAG_BASE_DIR="$OUTPUT_DIR_ARG"
fi

# 모든 검사를 통과한 경우, 변수 설정
if [[ -n "$GTDBTK_DB_DIR_ARG" ]]; then
    export GTDBTK_DATA_PATH="$GTDBTK_DB_DIR_ARG"
fi

# --- 6. 설정 및 함수 파일 로드 ---
source "${PROJECT_ROOT_DIR}/config/pipeline_config.sh"
source "${PROJECT_ROOT_DIR}/lib/pipeline_functions.sh"
source "${PROJECT_ROOT_DIR}/config/mag_config.sh"
source "${PROJECT_ROOT_DIR}/lib/mag_functions.sh"

# --- 5. 디렉토리 및 로그 파일 설정 ---
mkdir -p "$MAG_BASE_DIR"
mkdir -p "$ASSEMBLY_STATS_DIR"
mkdir -p "$TMP_DIR_ARG"
LOG_FILE="${MAG_BASE_DIR}/3_mag_per_sample_$(date +%Y%m%d_%H%M%S).log"
> "$LOG_FILE"; trap '_error_handler' ERR

echo "INFO: Input directory set to: ${QC_READS_DIR}"
echo "INFO: Output directory set to: ${MAG_BASE_DIR}"
if [[ -n "$GTDBTK_DATA_PATH" ]]; then
    echo "INFO: GTDB-Tk database path set to: ${GTDBTK_DATA_PATH}"
fi
echo "INFO: Bakta database path set to: ${BAKTA_DB_DIR_ARG}"

# --- 7. 최종 설정값 로그 기록 ---
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
if [[ -n "$GTDBTK_DATA_PATH" ]]; then log_info "GTDB-Tk DB path : ${GTDBTK_DATA_PATH}"; fi
log_info "Bakta DB path   : ${BAKTA_DB_DIR_ARG}"
log_info "------------------------------"

# --- 8. 의존성 확인 ---
log_info "Checking MAG pipeline dependencies for mode: ${RUN_MODE}"
if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "megahit" ]]; then
    check_conda_dependency "$BBMAP_ENV" "repair.sh"; check_conda_dependency "$MEGAHIT_ENV" "megahit";
fi
if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "metawrap" ]]; then
    check_conda_dependency "$METAWRAP_ENV" "metawrap";
fi
if [[ "$RUN_MODE" != "megahit" ]]; then # megahit 모드가 아닐 때만 후속 분석 도구 확인
    check_conda_dependency "$KRAKEN_ENV" "kraken2"; check_conda_dependency "$BAKTA_ENV" "bakta";
    check_conda_dependency "$GTDBTK_ENV" "gtdbtk";
fi
log_info "All dependencies are satisfied."

# 체크섬 기반의 입력 파일 변경 감지 로직
STATE_FILE="${MAG_BASE_DIR}/.pipeline.state"
STATE_FILE_NEW="${STATE_FILE}.new"
log_info "Checking for input file changes using checksums..."
find "$QC_READS_DIR" -maxdepth 1 -type f -name "*.fastq.gz" -print0 2>/dev/null | xargs -0 md5sum | sort -k 2 > "$STATE_FILE_NEW"

if [ -f "$STATE_FILE" ] && diff -q "$STATE_FILE" "$STATE_FILE_NEW" >/dev/null; then
    log_info "No changes detected in input files. MAG pipeline is up-to-date."
    rm -f "$STATE_FILE_NEW"
    exit 0 # 변경사항이 없으면 여기서 성공적으로 종료
fi
log_info "Input file changes detected. Proceeding with MAG analysis..."

# --- 9. 메인 루프 시작 ---
log_info "--- (Step 2) Starting Per-Sample MAG Analysis (Mode: ${RUN_MODE}) ---"
if [ -z "$(ls -A "${QC_READS_DIR}"/*_1.fastq.gz 2>/dev/null)" ]; then
    log_warn "입력 폴더 '${QC_READS_DIR}'에 FASTQ 파일이 없습니다. 파이프라인 2를 종료합니다."
    rm -f "$STATE_FILE_NEW"
    exit 0
fi

for R1_QC_GZ in "${QC_READS_DIR}"/*_1.fastq.gz; do
#    if [[ ! -f "$R1_QC_GZ" ]]; then continue; fi
    # --- 샘플 정보 설정 ---
    SAMPLE_BASE=$(basename "$R1_QC_GZ")
    SAMPLE=""; R2_QC_GZ=""
    if [[ "$SAMPLE_BASE" == *"_kneaddata_paired_"* ]]; then
        SAMPLE=$(echo "$SAMPLE_BASE" | sed -e 's/_1_kneaddata_paired_1\.fastq\.gz//')
        R2_QC_GZ="${QC_READS_DIR}/${SAMPLE}_1_kneaddata_paired_2.fastq.gz"
    elif [[ "$SAMPLE_BASE" == *"_fastp_"* ]]; then
        SAMPLE=$(echo "$SAMPLE_BASE" | sed -e 's/_1_fastp_1\.fastq\.gz//')
        R2_QC_GZ="${QC_READS_DIR}/${SAMPLE}_fastp_2.fastq.gz"
    elif [[ "$SAMPLE_BASE" == *"_1.fastq.gz" ]]; then
        SAMPLE=$(echo "$SAMPLE_BASE" | sed -e 's/_1\.fastq\.gz//')
        R2_QC_GZ="${QC_READS_DIR}/${SAMPLE}_2.fastq.gz"
        
    else 
        continue; 
    fi
    
    if [[ ! -f "$R2_QC_GZ" ]]; then log_warn "Paired QC file for $SAMPLE not found."; continue; fi

    printf "\n" >&2; log_info "--- Processing sample '$SAMPLE' ---"

    # 체크포인트 방식을 모두 .success 성공 플래그로 통일
    REPAIR_SUCCESS_FLAG="${REPAIR_DIR}/.${SAMPLE}.repair.success"
    ASSEMBLY_SUCCESS_FLAG="${ASSEMBLY_DIR}/.${SAMPLE}.assembly.success"
    POST_ASSEMBLY_SUCCESS_FLAG="${ASSEMBLY_STATS_DIR}/.${SAMPLE}.post_assembly.success"
    BINNING_SUCCESS_FLAG="${METAWRAP_DIR}/.${SAMPLE}.binning.success"
    GTDBTK_SUCCESS_FLAG="${GTDBTK_ON_MAGS_DIR}/.${SAMPLE}.gtdbtk.success"
    BAKTA_MAGS_SUCCESS_FLAG="${BAKTA_ON_MAGS_DIR}/.${SAMPLE}.bakta_mags.success"

    FINAL_SAMPLE_SUCCESS_FLAG="$BAKTA_MAGS_SUCCESS_FLAG"
    if [[ "$RUN_MODE" == "megahit" ]]; then FINAL_SAMPLE_SUCCESS_FLAG="$POST_ASSEMBLY_SUCCESS_FLAG"; fi
    if [ -f "$FINAL_SAMPLE_SUCCESS_FLAG" ]; then log_info "All MAG analysis steps for ${SAMPLE} are already complete. Skipping."; continue; fi

    # --- 각 단계에서 사용할 경로 정의 ---
    ASSEMBLY_OUT_DIR_SAMPLE="${ASSEMBLY_DIR}/${SAMPLE}"
    ASSEMBLY_FA="${ASSEMBLY_OUT_DIR_SAMPLE}/final.contigs.fa"
    FINAL_BINS_DIR="${METAWRAP_DIR}/${SAMPLE}/bin_refinement/metawrap_${MIN_COMPLETENESS}_${MAX_CONTAMINATION}_bins"
    REPAIR_DIR_SAMPLE="${REPAIR_DIR}/${SAMPLE}"
    
    # --- 모드별 실행 로직 ---
    if [[ "$RUN_MODE" == "post-process" ]]; then
        # === Post-process 모드 ===
        log_info "Mode: post-process. Checking for existing results..."
        
        # Contig 분석
        if [[ ! -f "$ASSEMBLY_FA" ]]; then
            log_warn "Assembly file not found for ${SAMPLE}. Skipping contig-level post-analysis."
        else
            KRAKEN_CONTIGS_OUT_DIR_SAMPLE="${KRAKEN_ON_CONTIGS_DIR}/${SAMPLE}"
            run_kraken2_on_contigs "$SAMPLE" "$ASSEMBLY_FA" "$KRAKEN_CONTIGS_OUT_DIR_SAMPLE" "$KRAKEN2_DB_ARG" "$THREADS" "$KRAKEN2_EXTRA_OPTS"
            
            BAKTA_CONTIGS_OUT_DIR_SAMPLE="${BAKTA_ON_CONTIGS_DIR}/${SAMPLE}"; mkdir -p "$BAKTA_CONTIGS_OUT_DIR_SAMPLE"
            run_bakta_for_contigs "$SAMPLE" "$ASSEMBLY_OUT_DIR_SAMPLE" "$BAKTA_CONTIGS_OUT_DIR_SAMPLE" "$BAKTA_DB_DIR_ARG" "$TMP_DIR_ARG" "$BAKTA_EXTRA_OPTS"
        fi

        # MAG 분석
        FINAL_BINS_DIR="${METAWRAP_DIR}/${SAMPLE}/bin_refinement/metawrap_${MIN_COMPLETENESS}_${MAX_CONTAMINATION}_bins"
        if [[ ! -d "$FINAL_BINS_DIR" ]]; then
            log_warn "Final MAGs not found for ${SAMPLE}. Skipping MAG-level post-analysis."
        else
            GTDBTK_OUT_DIR_SAMPLE="${GTDBTK_ON_MAGS_DIR}/${SAMPLE}"; mkdir -p "$GTDBTK_OUT_DIR_SAMPLE"
            run_gtdbtk "$SAMPLE" "$FINAL_BINS_DIR" "$GTDBTK_OUT_DIR_SAMPLE" "$GTDBTK_EXTRA_OPTS"
            
            BAKTA_MAGS_OUT_DIR_SAMPLE="${BAKTA_ON_MAGS_DIR}/${SAMPLE}"; mkdir -p "$BAKTA_MAGS_OUT_DIR_SAMPLE"
            run_gtdbtk "$SAMPLE" "$FINAL_BINS_DIR" "$GTDBTK_OUT_DIR_SAMPLE" "$GTDBTK_EXTRA_OPTS"
        fi

    else
        # === megahit, metawrap, all 모드 ===
#    if [[ "$RUN_MODE" != "post-process" ]]; then
        # 1. Read Pair Repair 단계
        R1_REPAIRED_GZ="${REPAIR_DIR_SAMPLE}/${SAMPLE}_R1.repaired.fastq.gz"
        # .success 플래그와 실제 결과 파일(.fastq.gz) 존재 여부를 함께 확인
        if [ -f "$REPAIR_SUCCESS_FLAG" ] && [ -s "$R1_REPAIRED_GZ" ]; then
            log_info "Read pair repair for ${SAMPLE} already complete. Skipping."
        else
            mkdir -p "$REPAIR_DIR_SAMPLE"
            repaired_files=($(run_pair_repair "$SAMPLE" "$R1_QC_GZ" "$R2_QC_GZ" "$REPAIR_DIR_SAMPLE"))
            if [[ ! -s "${repaired_files[0]}" ]]; then log_warn "Read pair repairing failed."; continue; fi
            touch "$REPAIR_SUCCESS_FLAG"
        fi
        R2_REPAIRED_GZ="${REPAIR_DIR_SAMPLE}/${SAMPLE}_R2.repaired.fastq.gz"
       
        if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "megahit" ]]; then
            # 2. Assembly 단계
            # .success 플래그와 실제 결과 파일(final.contigs.fa) 존재 및 크기(-s)를 함께 확인
            if [ -f "$ASSEMBLY_SUCCESS_FLAG" ] && [ -s "$ASSEMBLY_FA" ]; then
                log_info "Assembly for ${SAMPLE} already exists. Skipping."
            else
                run_megahit "$SAMPLE" "$R1_REPAIRED_GZ" "$R2_REPAIRED_GZ" "$ASSEMBLY_OUT_DIR_SAMPLE" "$MEGAHIT_PRESET_TO_USE" "$MEMORY_GB" "$MIN_CONTIG_LEN" "$THREADS" "$MEGAHIT_EXTRA_OPTS"
                if [ -s "$ASSEMBLY_FA" ]; then touch "$ASSEMBLY_SUCCESS_FLAG"; else log_warn "Assembly for ${SAMPLE} failed."; continue; fi
            fi
            
            # Assembly 성공 여부와 관계없이 후속 분석 실행 (내부에서 파일 존재 여부 확인)
            if [ -f "$POST_ASSEMBLY_SUCCESS_FLAG" ]; then log_info "Post-assembly analysis for ${SAMPLE} already exists. Skipping."; else
                if [ -f "$ASSEMBLY_SUCCESS_FLAG" ]; then
                    log_info "Starting post-assembly analysis for ${SAMPLE}..."
                    STATS_OUT_FILE="${ASSEMBLY_STATS_DIR}/${SAMPLE}_assembly_stats.txt"
                    conda run -n "$BBMAP_ENV" stats.sh in="$ASSEMBLY_FA" > "$STATS_OUT_FILE"
                    
                    if [ "$SKIP_CONTIG_ANALYSIS" = false ]; then
                        log_info "Running post-assembly taxonomic analysis (Kraken2 & Bakta)..."
                        
                        KRAKEN_CONTIGS_OUT_DIR_SAMPLE="${KRAKEN_ON_CONTIGS_DIR}/${SAMPLE}"
                        run_kraken2_on_contigs "$SAMPLE" "$ASSEMBLY_FA" "$KRAKEN_CONTIGS_OUT_DIR_SAMPLE" "$KRAKEN2_DB_ARG" "$THREADS" "$KRAKEN2_EXTRA_OPTS"
                        
                        BAKTA_CONTIGS_OUT_DIR_SAMPLE="${BAKTA_ON_CONTIGS_DIR}/${SAMPLE}"; mkdir -p "$BAKTA_CONTIGS_OUT_DIR_SAMPLE"
                        run_bakta_for_contigs "$SAMPLE" "$ASSEMBLY_OUT_DIR_SAMPLE" "$BAKTA_CONTIGS_OUT_DIR_SAMPLE" "$BAKTA_DB_DIR_ARG" "$TMP_DIR_ARG" "$BAKTA_EXTRA_OPTS"
                    else
                        log_info "--skip-contig-analysis enabled. Skipping Kraken2 and Bakta on contigs."
                    fi
                    
                    touch "$POST_ASSEMBLY_SUCCESS_FLAG"
                fi
            fi
        fi
        
        if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "metawrap" ]]; then
            if [ ! -f "$ASSEMBLY_SUCCESS_FLAG" ]; then log_warn "Assembly must be completed first. Skipping binning."; else
                # 4. Binning 단계
                # .success 플래그와 실제 결과 폴더(FINAL_BINS_DIR) 존재 및 내용물(-n)을 함께 확인
                if [ -f "$BINNING_SUCCESS_FLAG" ] && [ -d "$FINAL_BINS_DIR" ] && [ -n "$(ls -A "$FINAL_BINS_DIR" 2>/dev/null)" ]; then
                    log_info "Binning for ${SAMPLE} already exists. Skipping."
                else
                    run_metawrap_sample "$SAMPLE" "$ASSEMBLY_FA" "$R1_REPAIRED_GZ" "$R2_REPAIRED_GZ" "${METAWRAP_DIR}/${SAMPLE}" "$MIN_COMPLETENESS" "$MAX_CONTAMINATION" "$METAWRAP_BINNING_EXTRA_OPTS" "$METAWRAP_REFINEMENT_EXTRA_OPTS"
                    if [[ -d "$FINAL_BINS_DIR" && -n "$(ls -A "$FINAL_BINS_DIR" 2>/dev/null)" ]]; then touch "$BINNING_SUCCESS_FLAG"; else log_warn "Binning for ${SAMPLE} failed."; continue; fi
                fi

                # 5. GTDB-Tk 단계
                # .success 플래그와 실제 결과 파일(summary.tsv) 존재 여부를 함께 확인
                GTDBTK_OUT_DIR_SAMPLE="${GTDBTK_ON_MAGS_DIR}/${SAMPLE}"
                GTDBTK_SUMMARY_FILE_BAC="${GTDBTK_OUT_DIR_SAMPLE}/gtdbtk.bac120.summary.tsv"
                GTDBTK_SUMMARY_FILE_AR="${GTDBTK_OUT_DIR_SAMPLE}/gtdbtk.ar53.summary.tsv"
                
                if [ -f "$GTDBTK_SUCCESS_FLAG" ] && { [ -f "$GTDBTK_SUMMARY_FILE_BAC" ] || [ -f "$GTDBTK_SUMMARY_FILE_AR" ]; }; then
                    log_info "GTDB-Tk for ${SAMPLE} already exists. Skipping."
                else
                    if [ -f "$BINNING_SUCCESS_FLAG" ]; then
                        run_gtdbtk "$SAMPLE" "$FINAL_BINS_DIR" "$GTDBTK_OUT_DIR_SAMPLE" "$GTDBTK_EXTRA_OPTS"
                        if [[ -f "$GTDBTK_SUMMARY_FILE_BAC" || -f "$GTDBTK_SUMMARY_FILE_AR" ]]; then touch "$GTDBTK_SUCCESS_FLAG"; else log_warn "GTDB-Tk for ${SAMPLE} failed."; fi
                    fi
                fi
                
                # 6. Bakta on MAGs 단계 (이 단계는 여러 파일을 생성하므로 .success 플래그만으로 확인)
                if [ -f "$BAKTA_MAGS_SUCCESS_FLAG" ]; then log_info "Bakta on MAGs for ${SAMPLE} already exists. Skipping."; else
                    if [ -f "$GTDBTK_SUCCESS_FLAG" ]; then
                        run_bakta_for_mags "$SAMPLE" "$FINAL_BINS_DIR" "${BAKTA_ON_MAGS_DIR}/${SAMPLE}" "$BAKTA_DB_DIR_ARG" "$TMP_DIR_ARG" "$BAKTA_EXTRA_OPTS"
                        touch "$BAKTA_MAGS_SUCCESS_FLAG"
                    fi
                fi
            fi
        fi
        if [ "$KEEP_TEMP_FILES" = false ]; then
            rm -rf "$REPAIR_DIR_SAMPLE"
        fi
    fi
    log_info "--- Finished processing for sample '$SAMPLE' ---"
done

# --- 모든 작업이 성공적으로 끝나면, 새로운 상태를 공식 상태로 저장합니다. ---
mv "$STATE_FILE_NEW" "$STATE_FILE"
log_info "Successfully updated MAG pipeline state."
log_info "--- (Step 2) All samples processed successfully! ---"
