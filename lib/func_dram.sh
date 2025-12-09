#!/bin/bash
#================================================
# PIPELINE 4: METABOLIC PROFILING (DRAM)
#================================================
set -euo pipefail

# 1. 종료 시그널 핸들러 (안전 종료)
_term_handler() {
    echo -e "\n\033[0;31m[DRAM] Ctrl+C detected! Killing processes...\033[0m" >&2
    pkill -9 -P $$ 2>/dev/null || true
    exit 130
}
trap _term_handler SIGINT SIGTERM

FULL_COMMAND="$0 \"$@\""
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")

# --- 설정 (기본값) ---
DRAM_ENV="dram_env"  # DRAM이 설치된 Conda 환경 이름
THREADS=30
INPUT_DIR=""
OUTPUT_DIR=""
DRAM_DB_DIR=""

# [필수] 라이브러리 로드
if [ -f "${PROJECT_ROOT_DIR}/lib/pipeline_functions.sh" ]; then
    source "${PROJECT_ROOT_DIR}/lib/pipeline_functions.sh"
else
    echo "Error: pipeline_functions.sh not found." >&2; exit 1
fi

# --- 사용법 함수 ---
print_usage() {
    echo -e "${GREEN}Dokkaebi DRAM Analysis Pipeline${NC}"
    echo "Usage: $0 --input_dir <metawrap_out_dir> --output_dir <path> --dram_db_dir <path> [options]"
    echo ""
    echo "Required:"
    echo "  --input_dir PATH      Path to '05_metawrap' directory (containing sample subfolders)"
    echo "  --output_dir PATH     Output directory for DRAM results"
    echo "  --dram_db_dir PATH    Path to DRAM database"
    echo ""
    echo "Optional:"
    echo "  --threads INT         Number of threads (Default: 30)"
    echo "  --env NAME            Conda environment name for DRAM (Default: dram_env)"
    echo ""
}

# --- 인자 파싱 ---
if [[ $# -eq 0 ]]; then print_usage; exit 0; fi

while [ $# -gt 0 ]; do
    case "$1" in
        --input_dir) INPUT_DIR="${2%/}"; shift 2 ;;
        --output_dir) OUTPUT_DIR="${2%/}"; shift 2 ;;
        --dram_db_dir) DRAM_DB_DIR="${2%/}"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --env) DRAM_ENV="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$INPUT_DIR" || -z "$OUTPUT_DIR" || -z "$DRAM_DB_DIR" ]]; then
    echo "Error: Missing required arguments."
    print_usage; exit 1
fi

# --- 초기화 ---
mkdir -p "$OUTPUT_DIR"
LOG_FILE="${OUTPUT_DIR}/dram_analysis_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"

log_info "--- Starting DRAM Metabolic Profiling ---"
log_info "Input Dir: $INPUT_DIR"
log_info "Output Dir: $OUTPUT_DIR"
log_info "DRAM DB: $DRAM_DB_DIR"
check_conda_dependency "$DRAM_ENV" "DRAM.py"

# --- 메인 루프 (샘플별 처리) ---
for sample_dir in "${INPUT_DIR}"/*; do
    if [ ! -d "$sample_dir" ]; then continue; fi
    
    SAMPLE_NAME=$(basename "$sample_dir")
    
    # MetaWRAP 결과 중 Refined Bin 폴더 찾기
    # (bin_refinement 폴더 안에 있는 metawrap_*_bins 폴더를 찾음)
    BINS_DIR=$(find "${sample_dir}/bin_refinement" -type d -name "metawrap_*_bins" | head -n 1)
    
    if [[ -z "$BINS_DIR" || -z "$(ls -A "$BINS_DIR"/*.fa 2>/dev/null)" ]]; then
        log_warn "No refined bins found for $SAMPLE_NAME in $sample_dir. Skipping."
        continue
    fi

    log_info "Processing Sample: $SAMPLE_NAME"
    
    SAMPLE_OUT_DIR="${OUTPUT_DIR}/${SAMPLE_NAME}"
    mkdir -p "$SAMPLE_OUT_DIR"

    # --- 1. DRAM Annotate ---
    ANNOTATION_TSV="${SAMPLE_OUT_DIR}/annotations.tsv"
    
    if [ -f "$ANNOTATION_TSV" ]; then
        log_info "  - Annotation already exists. Skipping."
    else
        log_info "  - Running DRAM Annotate..."
        
        # Conda Activate & Run (서브쉘)
        (
            CONDA_BASE=$(conda info --base)
            if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then source "${CONDA_BASE}/etc/profile.d/conda.sh"; else source ~/miniconda3/etc/profile.d/conda.sh; fi
            conda activate "$DRAM_ENV"
            
            # DRAM Annotate 실행
            DRAM.py annotate \
                --input_fasta_dir "$BINS_DIR" \
                --output_dir "$SAMPLE_OUT_DIR" \
                --threads "$THREADS" \
                --verbose \
                --overwrite \
                >> "$LOG_FILE" 2>&1
        )
        
        if [ ! -f "$ANNOTATION_TSV" ]; then
            log_error "DRAM Annotate failed for $SAMPLE_NAME. Check logs."
            continue
        fi
        log_info "  - Annotation complete."
    fi

    # --- 2. DRAM Distill ---
    PRODUCT_HTML="${SAMPLE_OUT_DIR}/product.html"
    FINAL_REPORT="${SAMPLE_OUT_DIR}/${SAMPLE_NAME}_metabolism.html"
    
    if [ -f "$FINAL_REPORT" ]; then
        log_info "  - Distill report already exists. Skipping."
    else
        log_info "  - Running DRAM Distill..."
        
        (
            CONDA_BASE=$(conda info --base)
            if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then source "${CONDA_BASE}/etc/profile.d/conda.sh"; else source ~/miniconda3/etc/profile.d/conda.sh; fi
            conda activate "$DRAM_ENV"
            
            # DRAM Distill 실행
            DRAM.py distill \
                --input_file "$ANNOTATION_TSV" \
                --output_dir "${SAMPLE_OUT_DIR}/distill" \
                --rrna_path "${SAMPLE_OUT_DIR}/rrnas.tsv" \
                --trna_path "${SAMPLE_OUT_DIR}/trnas.tsv" \
                >> "$LOG_FILE" 2>&1
        )

        if [ -f "${SAMPLE_OUT_DIR}/distill/product.html" ]; then
            cp "${SAMPLE_OUT_DIR}/distill/product.html" "$FINAL_REPORT"
            log_info "  - Distill complete! Report: $FINAL_REPORT"
        else
            log_warn "DRAM Distill failed or produced no output for $SAMPLE_NAME."
        fi
    fi

done

log_info "--- DRAM Analysis Finished! ---"