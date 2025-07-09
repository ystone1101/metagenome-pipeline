#!/bin/bash
#===========================================
# Kraken2-Only Analysis Pipeline
# Assumes QC-ed files exist in CLEAN_DIR
#===========================================
set -euo pipefail

# 1. 환경 설정 및 함수 라이브러리 로드
# 기존 파이프라인의 설정을 그대로 사용합니다.
source "config/pipeline_config.sh"
source "lib/pipeline_functions.sh"

# 이 스크립트 전용 출력 경로 및 파일 변수 정의
KRAKEN_ONLY_OUT_DIR="${BASE_DIR}/kraken2_only_run"
mkdir -p "$KRAKEN_ONLY_OUT_DIR"

LOG_FILE="${KRAKEN_ONLY_OUT_DIR}/kraken2_only_pipeline_$(date +%Y%m%d_%H%M%S).log"
SUMMARY_TSV_KRAKEN_ONLY="${KRAKEN_ONLY_OUT_DIR}/kraken2_summary_k2_only.tsv"
> "$LOG_FILE" # 새 로그 파일 초기화

# 2. 에러 트랩 정의
_error_handler() {
    local exit_code="$?"; local command="${BASH_COMMAND}"; local script_name="${BASH_SOURCE[0]}"; local line_number="${LINENO}"
    local error_block="
---------------------------------
[ERROR] 스크립트 오류 발생!
  - 스크립트: ${script_name}
  - 라인 번호: ${line_number}
  - 종료 코드: ${exit_code}
  - 실패한 명령어: '${command}'
---------------------------------"
    printf "${RED}%s${NC}\n" "$error_block" >&2
    printf "%s\n" "$error_block" >> "$LOG_FILE"
    exit "${exit_code}"
}
trap '_error_handler' ERR

# 3. 소프트웨어 의존성 확인
check_conda_dependency() {
    local env_name=$1; local cmd=$2
    log_info "Conda 환경 '$env_name'에서 '$cmd' 명령어 존재 여부 확인 중..."
    if ! conda run -n "$env_name" command -v "$cmd" &> /dev/null; then
        local error_msg="[ERROR] Conda 환경 '$env_name'에 '$cmd'가 설치되지 않았습니다."
        printf "${RED}%s${NC}\n" "$error_msg" >&2; printf "%s\n" "$error_msg" >> "$LOG_FILE"; exit 1
    fi
    log_info "'$cmd @ $env_name' 명령어 확인 완료."
}
log_info "Kraken2 파이프라인 의존성을 확인합니다."
check_conda_dependency "$KRAKEN_ENV" "kraken2"
check_conda_dependency "$KRAKEN_ENV" "kreport2mpa.py"
log_info "의존성 확인 완료."


# 4. 파이프라인 시작 및 요약 파일 확인
log_info "--- Kraken2 단독 실행 파이프라인 시작 ---"
log_info "전용 결과물 저장 경로: ${KRAKEN_ONLY_OUT_DIR}"

# 이 스크립트 전용 요약 파일이 없으면 헤더와 함께 생성
if [[ ! -f "$SUMMARY_TSV_KRAKEN_ONLY" ]]; then
    log_info "전용 Kraken2 요약 통계 파일($SUMMARY_TSV_KRAKEN_ONLY)을 새로 생성합니다."
    echo -e "Sample\tTotal\tClassified\tClassified(%)\tUnclassified\tUnclassified(%)" > "$SUMMARY_TSV_KRAKEN_ONLY"
fi

log_info "분석 대상 폴더: ${CLEAN_DIR}"

# QC 방식에 따른 파일 처리를 위한 공통 함수
process_cleaned_files() {
    local file_pattern_r1=$1
    local file_pattern_r2=$2
    local suffix_to_remove=$3
    local qc_type=$4
    
    log_info "--- '${qc_type}' 모드 결과 파일 처리 시작 ---"
    
    # 해당 패턴의 파일이 하나도 없을 경우를 대비한 확인
    # shopt -s nullglob을 사용하면 파일이 없을 때 루프가 실행되지 않음
    shopt -s nullglob
    local files_found=("${CLEAN_DIR}"/*${file_pattern_r1})
    shopt -u nullglob

    if [ ${#files_found[@]} -eq 0 ]; then
        log_warn "처리할 ${qc_type} 결과 파일이 없습니다."
        return
    fi

    for R1_CLEAN in "${files_found[@]}"; do
        local SAMPLE=$(basename "$R1_CLEAN" | sed -e "s/${suffix_to_remove}//")
        local R2_CLEAN="${CLEAN_DIR}/${SAMPLE}${file_pattern_r2}"
        
        if [[ ! -f "$R2_CLEAN" ]]; then
            log_warn "페어 파일(${R2_CLEAN})을 찾을 수 없습니다. 건너<binary data, 2 bytes><binary data, 2 bytes><binary data, 2 bytes>니다."
            continue
        fi

        log_info "샘플 '${SAMPLE}'에 대한 Kraken2 분석/요약 작업을 시작합니다."
        # run_kraken2 함수는 내부적으로 이미 분석된 결과가 있으면 분류는 건너뛰고 요약만 수행함
        run_kraken2 "$SAMPLE" "$R1_CLEAN" "$R2_CLEAN" \
            "$KRAKEN_DB" "$KRAKEN_OUT" "$SUMMARY_TSV_KRAKEN_ONLY" "$MPA_OUT"
    done
}

# 'host' 모드 결과물(_kneaddata_) 처리
process_cleaned_files "_1_kneaddata_paired_1.fastq.gz" "_1_kneaddata_paired_2.fastq.gz" "_1_kneaddata_paired_1.fastq.gz" "host (kneaddata)"

# 'environmental' 모드 결과물(_fastp_) 처리
process_cleaned_files "_fastp_1.fastq.gz" "_fastp_2.fastq.gz" "_fastp_1.fastq.gz" "environmental (fastp)"

log_info "--- Kraken2 단독 실행 파이프라인 종료 ---"
