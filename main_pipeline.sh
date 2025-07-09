#!/bin/bash
#=========================
# 메인 파이프라인 스크립트
#=========================
set -euo pipefail

# --- 스크립트 실행 모드 설정 ---
PIPELINE_MODE="host"
if [[ "$1" == "--mode" && -n "$2" ]]; then
    PIPELINE_MODE="$2"; shift 2
fi
if [[ "$PIPELINE_MODE" != "host" && "$PIPELINE_MODE" != "environmental" ]]; then
    echo "[ERROR] Invalid mode: '$PIPELINE_MODE'. Use 'host' or 'environmental'." >&2; exit 1
fi

# 1. 환경 설정 및 함수 라이브러리 로드
source "config/pipeline_config.sh"
source "lib/pipeline_functions.sh"
LOG_FILE="${BASE_DIR}/pipeline_$(date +%Y%m%d_%H%M%S).log"
> "$LOG_FILE"

# 2. 에러 트랩 정의
_error_handler() {
    local exit_code="$?"; local command="${BASH_COMMAND}"; local script_name="${BASH_SOURCE[0]}"; local line_number="${LINENO}"
    local error_block=$'\n'"---------------------------------\n[ERROR] 스크립트 오류 발생!\n  - 스크립트: ${script_name}\n  - 라인 번호: ${line_number}\n  - 종료 코드: ${exit_code}\n  - 실패한 명령어: '${command}'\n---------------------------------"
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
check_system_dependency() {
    local cmd=$1
    log_info "시스템 기본 명령어 '$cmd' 존재 여부 확인 중..."
    if ! command -v "$cmd" &> /dev/null; then
        local error_msg="[ERROR] '$cmd' 명령어를 찾을 수 없습니다. PATH를 확인해주세요."
        printf "${RED}%s${NC}\n" "$error_msg" >&2; printf "%s\n" "$error_msg" >> "$LOG_FILE"; exit 1
    fi
    log_info "'$cmd' 명령어 확인 완료."
}
log_info "필요한 모든 소프트웨어 의존성을 확인합니다."
check_conda_dependency "$KRAKEN_ENV" "kraken2"
check_conda_dependency "$KRAKEN_ENV" "kreport2mpa.py"
if [[ "$PIPELINE_MODE" == "host" ]]; then
    check_conda_dependency "$KNEADDATA_ENV" "kneaddata"
    check_conda_dependency "$KNEADDATA_ENV" "fastqc"
elif [[ "$PIPELINE_MODE" == "environmental" ]]; then
    check_conda_dependency "$KNEADDATA_ENV" "fastqc"
    check_conda_dependency "$FASTP_ENV" "fastp"
fi
for cmd in pigz cut grep awk cp mv rm; do check_system_dependency "$cmd"; done
log_info "모든 소프트웨어 의존성 확인 완료."

# 4. 초기 설정
log_info "스크립트 시작 시간: $(date)"
log_info "파이프라인 실행 모드: ${PIPELINE_MODE}"
log_info "KneadData Conda 환경: $KNEADDATA_ENV"
log_info "Kraken/Tools Conda 환경: $KRAKEN_ENV"
if [[ "$PIPELINE_MODE" == "environmental" ]]; then
    log_info "fastp Conda 환경: $FASTP_ENV"
fi
mkdir -p "$WORK_DIR" "$KRAKEN_OUT" "$MPA_OUT" "$CLEAN_DIR" "$KNEADDATA_LOG" \
         "$FASTP_REPORTS_DIR" "$FASTQC_REPORTS_DIR" "$FASTQC_PRE_QC_DIR" "$FASTQC_POST_QC_DIR"
if [[ ! -f "$MISMATCH_FILE" ]]; then touch "$MISMATCH_FILE"; fi
if [[ ! -f "$KRAKEN2_SUMMARY_TSV" ]]; then echo -e "Sample\tTotal\tClassified\tClassified(%)\tUnclassified\tUnclassified(%)" > "$KRAKEN2_SUMMARY_TSV"; fi
if [[ ! -f "$KNEADDATA_SUMMARY_TSV" ]]; then echo -e "Sample\tInitial_Reads\tHost_Reads\tHost_Reads(%)\tClean_Reads\tClean_Reads(%)" > "$KNEADDATA_SUMMARY_TSV"; fi

# 5. 샘플별 루프
for R1 in "$RAW_DIR"/*_1.fastq.gz; do
    SAMPLE=$(basename "$R1" | sed 's/_1.fastq.gz//')
    R2="$RAW_DIR/${SAMPLE}_2.fastq.gz"
    if [[ ! -f "$R2" ]]; then log_warn "$SAMPLE 페어링 안됨..."; echo "$SAMPLE" >> "$MISMATCH_FILE"; continue; fi

    log_info "--- 샘플 '$SAMPLE' 분석 시작 ---"
    
    final_kraken_report="${KRAKEN_OUT}/${SAMPLE}.k2report"
    if [[ -f "$final_kraken_report" ]]; then log_info "${SAMPLE}: 모든 분석 완료. 건너<binary data, 2 bytes><binary data, 2 bytes><binary data, 2 bytes>니다."; continue; fi
    
    r1_for_kraken2=""; r2_for_kraken2=""
    r1_uncompressed=""; r2_uncompressed=""

    if [[ "$PIPELINE_MODE" == "host" ]]; then
        ### HOST 모드 워크플로우 ###
        kneaddata_prefix="${SAMPLE}_1"
        r1_for_kraken2="${WORK_DIR}/${kneaddata_prefix}_kneaddata_paired_1.fastq.gz"
        r2_for_kraken2="${WORK_DIR}/${kneaddata_prefix}_kneaddata_paired_2.fastq.gz"
        if [[ ! -f "$r1_for_kraken2" || ! -f "$r2_for_kraken2" ]]; then
            log_info "${SAMPLE}: [host] 신규 분석 시작"
            decompressed_files=($(decompress_fastq "$SAMPLE" "$R1" "$R2" "$WORK_DIR"))
            r1_uncompressed="${decompressed_files[0]}"; r2_uncompressed="${decompressed_files[1]}"
            if ! cleaned_files_str=$(run_kneaddata "$SAMPLE" "$r1_uncompressed" "$r2_uncompressed" \
                "$DB_PATH" "$WORK_DIR" "$CLEAN_DIR" "$KNEADDATA_LOG" \
                "$FASTQC_PRE_QC_DIR" "$FASTQC_POST_QC_DIR" "$TRIMMOMATIC_OPTIONS"); then
                log_warn "KneadData 실패. 건너<binary data, 2 bytes><binary data, 2 bytes><binary data, 2 bytes>니다."; rm "$r1_uncompressed" "$r2_uncompressed"; continue
            fi
            summary_log_path="${KNEADDATA_LOG}/${SAMPLE}_1_kneaddata_summary.log"
            if [[ -f "$summary_log_path" ]]; then summarize_kneaddata_log "$SAMPLE" "$summary_log_path" "$KNEADDATA_SUMMARY_TSV"; fi
            rm "$r1_uncompressed" "$r2_uncompressed"
            read -r -a cleaned_files <<< "$cleaned_files_str"
            if [[ -z "${cleaned_files[0]}" ]]; then log_warn "결과 파일 없음. 건너<binary data, 2 bytes><binary data, 2 bytes><binary data, 2 bytes>니다."; continue; fi
            r1_for_kraken2="${cleaned_files[0]}"; r2_for_kraken2="${cleaned_files[1]}"
        else
            log_info "${SAMPLE}: [host] KneadData 결과 발견. Kraken2부터 재개합니다."
        fi

    elif [[ "$PIPELINE_MODE" == "environmental" ]]; then
        ### ENVIRONMENTAL 모드 워크플로우 ###
        r1_for_kraken2="${WORK_DIR}/${SAMPLE}_fastp_1.fastq.gz"
        r2_for_kraken2="${WORK_DIR}/${SAMPLE}_fastp_2.fastq.gz"
        if [[ ! -f "$r1_for_kraken2" || ! -f "$r2_for_kraken2" ]]; then
            log_info "${SAMPLE}: [environmental] 신규 분석 시작"
            run_fastqc "$FASTQC_PRE_QC_DIR" "$R1" "$R2"
            cleaned_files=($(run_fastp "$SAMPLE" "$R1" "$R2" "$WORK_DIR" "$FASTP_REPORTS_DIR" "$FASTP_OPTIONS"))
            r1_for_kraken2="${cleaned_files[0]}"; r2_for_kraken2="${cleaned_files[1]}"
        else
            log_info "${SAMPLE}: [environmental] fastp 결과 발견. Kraken2부터 재개합니다."
        fi
        run_fastqc "$FASTQC_POST_QC_DIR" "$r1_for_kraken2" "$r2_for_kraken2"
    fi
    
    # --- 공통 처리 단계 ---
    run_kraken2 "$SAMPLE" "$r1_for_kraken2" "$r2_for_kraken2" "$KRAKEN_DB" "$KRAKEN_OUT" "$KRAKEN2_SUMMARY_TSV" "$MPA_OUT"
    cp "$r1_for_kraken2" "$CLEAN_DIR/"; cp "$r2_for_kraken2" "$CLEAN_DIR/"
    rm "$r1_for_kraken2"; rm "$r2_for_kraken2"
    log_info "--- 샘플 '$SAMPLE' 처리 완료 ---"
done

# 6. 완료 메시지
log_info "--- 모든 샘플 분석 완료 ---"
log_info "파이프라인 종료 시간: $(date)"
summary_header="### 파이프라인 결과 요약 ###"
summary_body="
  - 전체 실행 로그: $LOG_FILE
  - Kraken2 분류 요약: $SUMMARY_TSV
  - 정제된 FASTQ 파일 (최종 보관): $CLEAN_DIR/
  - Kraken2 분석 결과: $KRAKEN_OUT/
  - MetaPhlAn 형식 보고서: $MPA_OUT/
  - KneadData 상세 로그: $KNEADDATA_LOG/
  - FastQC 보고서 (처리 전/후): $FASTQC_REPORTS_DIR/
  - 페어링 불일치 샘플 목록: $MISMATCH_FILE
"
printf "\n${GREEN}%s${NC}\n" "$summary_header" >&2
printf "%b\n" "$summary_body" | sed -e "s/- \(.*\): \(.*\)/- \1: ${YELLOW}\2${NC}/" >&2
printf "\n%s\n%s\n" "$summary_header" "$summary_body" >> "$LOG_FILE"
