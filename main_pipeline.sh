#!/bin/bash
#=========================
# 메인 파이프라인 스크립트
#=========================
set -euo pipefail

# 1. 환경 설정 및 함수 라이브러리 로드
source "config/pipeline_config.sh"
source "lib/pipeline_functions.sh"
LOG_FILE="${BASE_DIR}/pipeline_$(date +%Y%m%d_%H%M%S).log"
> "$LOG_FILE"

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
check_conda_dependency "$KNEADDATA_ENV" "kneaddata"
check_conda_dependency "$KNEADDATA_ENV" "fastqc"
check_conda_dependency "$KRAKEN_ENV" "kraken2"
check_conda_dependency "$KRAKEN_ENV" "kreport2mpa.py"
for cmd in pigz cut grep awk cp mv rm; do
    check_system_dependency "$cmd"
done
log_info "모든 소프트웨어 의존성 확인 완료."

# 4. 초기 설정
log_info "스크립트 시작 시간: $(date)"
log_info "KneadData Conda 환경: $KNEADDATA_ENV"
log_info "Kraken/Tools Conda 환경: $KRAKEN_ENV"
mkdir -p "$WORK_DIR" "$KRAKEN_OUT" "$MPA_OUT" "$CLEAN_DIR" "$KNEADDATA_LOG" \
         "$FASTQC_REPORTS_DIR" "$FASTQC_PRE_KNEADDATA_DIR" "$FASTQC_POST_KNEADDATA_DIR"
> "$MISMATCH_FILE"
echo -e "Sample\tTotal\tClassified\tClassified(%)\tUnclassified\tUnclassified(%)" > "$SUMMARY_TSV"

# --- 요약 파일들이 존재하지 않을 때만 생성 ---
if [[ ! -f "$MISMATCH_FILE" ]]; then
    log_info "페어링 불일치 샘플 목록 파일($MISMATCH_FILE)을 새로 생성합니다."
    touch "$MISMATCH_FILE"
fi

if [[ ! -f "$SUMMARY_TSV" ]]; then
    log_info "Kraken2 요약 통계 파일($SUMMARY_TSV)을 새로 생성하고 헤더를 작성합니다."
    echo -e "Sample\tTotal\tClassified\tClassified(%)\tUnclassified\tUnclassified(%)" > "$SUMMARY_TSV"
fi

# 5. 샘플별 루프
for R1 in "$RAW_DIR"/*_1.fastq.gz; do
    SAMPLE=$(basename "$R1" | sed 's/_1.fastq.gz//')
    R2="$RAW_DIR/${SAMPLE}_2.fastq.gz"
    if [[ ! -f "$R2" ]]; then
        log_warn "$SAMPLE 페어링 안됨..."
        echo "$SAMPLE" >> "$MISMATCH_FILE"
        continue
    fi

    log_info "--- 샘플 '$SAMPLE' 분석 시작 ---"

    # Checkpoint 1: Kraken2 최종 결과물 확인
    final_kraken_report="${KRAKEN_OUT}/${SAMPLE}.k2report"
    if [[ -f "$final_kraken_report" ]]; then
        log_info "${SAMPLE}: 이미 모든 분석이 완료되었습니다. 건너뜁니다."
        continue
    fi

    # Checkpoint 2: KneadData 중간 결과물 확인
    kneaddata_prefix="${SAMPLE}_1"
    r1_for_kraken2="${WORK_DIR}/${kneaddata_prefix}_kneaddata_paired_1.fastq.gz"
    r2_for_kraken2="${WORK_DIR}/${kneaddata_prefix}_kneaddata_paired_2.fastq.gz"
    
    r1_uncompressed=""
    r2_uncompressed=""

    if [[ ! -f "$r1_for_kraken2" || ! -f "$r2_for_kraken2" ]]; then
        # KneadData 결과물이 없으면, 처음부터 실행
        log_info "${SAMPLE}: 신규 분석을 시작합니다."
        
        decompressed_files=($(decompress_fastq "$SAMPLE" "$R1" "$R2" "$WORK_DIR"))
        r1_uncompressed="${decompressed_files[0]}"
        r2_uncompressed="${decompressed_files[1]}"

        if ! cleaned_files_str=$(run_kneaddata "$SAMPLE" "$r1_uncompressed" "$r2_uncompressed" \
            "$DB_PATH" "$WORK_DIR" "$CLEAN_DIR" "$KNEADDATA_LOG" \
            "$FASTQC_PRE_KNEADDATA_DIR" "$FASTQC_POST_KNEADDATA_DIR" \
            "$TRIMMOMATIC_OPTIONS"); then
            log_warn "KneadData 처리 중 오류가 발생하여 ${SAMPLE} 분석을 건너뜁니다. 다음 샘플로 진행합니다."
            rm "$r1_uncompressed" "$r2_uncompressed"
            continue
        fi
        
        log_info "${SAMPLE}: 더 이상 필요 없는 압축 해제된 원본 파일을 삭제합니다."
        rm "$r1_uncompressed" "$r2_uncompressed"
        
        read -r -a cleaned_files <<< "$cleaned_files_str"
        if [[ -z "${cleaned_files[0]}" ]]; then
            log_warn "${SAMPLE}: 후속 분석을 위한 파일이 없어 건너뜁니다."
            continue
        fi
        
        r1_for_kraken2="${cleaned_files[0]}"
        r2_for_kraken2="${cleaned_files[1]}"
    else
        # --- 변경점: 로그 메시지를 더 명확하게 수정 ---
        log_info "${SAMPLE}: WORK_DIR에서 이미 처리된 KneadData 파일을 발견했습니다. KneadData 단계를 건너뜁니다."
    fi
    
    # 공통 처리 단계
    run_kraken2 "$SAMPLE" "$r1_for_kraken2" "$r2_for_kraken2" \
        "$KRAKEN_DB" "$KRAKEN_OUT" "$SUMMARY_TSV" "$MPA_OUT"

    log_info "${SAMPLE}: 정제된 FASTQ 파일을 최종 저장 위치(${CLEAN_DIR})로 복사합니다."
    cp "$r1_for_kraken2" "$CLEAN_DIR/"
    cp "$r2_for_kraken2" "$CLEAN_DIR/"

    log_info "${SAMPLE}: WORK_DIR의 모든 임시 파일을 정리합니다."
    if [[ -f "$r1_for_kraken2" ]]; then rm "$r1_for_kraken2"; fi
    if [[ -f "$r2_for_kraken2" ]]; then rm "$r2_for_kraken2"; fi
    if [[ -f "$r1_uncompressed" ]]; then rm "$r1_uncompressed"; fi
    if [[ -f "$r2_uncompressed" ]]; then rm "$r2_uncompressed"; fi

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
