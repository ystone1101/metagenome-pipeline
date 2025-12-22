#!/bin/bash
#=========================
# 파이프라인 기능 함수 정의
#=========================

# [수정 1] 색상 변수 전역 정의 (에러 핸들러 충돌 방지)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 1. 상태 보고용 디렉토리 설정
if [ -d "/dev/shm" ]; then export JOB_STATUS_DIR="/dev/shm/dokkaebi_status"; else export JOB_STATUS_DIR="/tmp/dokkaebi_status"; fi
mkdir -p "$JOB_STATUS_DIR"

# ==========================================================
# --- 로깅(Logging) 및 오류 처리 함수 (최종 수정) ---
# ==========================================================

: "${VERBOSE_MODE:=false}"

# 모든 로깅 함수의 최종 출력을 표준 에러(stderr)로 리디렉션(>&2)하여,
# 함수의 '반환 값'으로 캡처되지 않도록 수정합니다.

log_info() {
    local message=$1
    local GREEN='\033[0;32m'
    local NC='\033[0m'
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    # [수정] Verbose 모드일 때만 화면 출력, 아니면 파일에만 기록
    if [ "$VERBOSE_MODE" = true ]; then
        echo -e "${GREEN}[INFO]${timestamp} | ${message}${NC}" | tee -a "$LOG_FILE" >&2
    else
        echo -e "[INFO]${timestamp} | ${message}" >> "$LOG_FILE"
    fi
}

# log_info() {
#    local message=$1
#    local GREEN='\033[0;32m'
#    local NC='\033[0m'
#    { echo -e "${GREEN}[INFO]$(date +'%Y-%m-%d %H:%M:%S') | ${message}${NC}" | tee -a "$LOG_FILE"; } >&2
# }

log_warn() {
    local message=$1
    local YELLOW='\033[0;33m'
    local NC='\033[0m'
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    # [수정] Warning도 Verbose 모드에 따라 제어 (원하시면 항상 출력으로 변경 가능)
    if [ "$VERBOSE_MODE" = true ]; then
        echo -e "${YELLOW}[WARN]${timestamp} | ${message}${NC}" | tee -a "$LOG_FILE" >&2
    else
        echo -e "[WARN]${timestamp} | ${message}" >> "$LOG_FILE"
    fi
}

# log_warn() {
#    local message=$1
#    local YELLOW='\033[0;33m'
#    local NC='\033[0m'
#    { echo -e "${YELLOW}[WARN]$(date +'%Y-%m-%d %H:%M:%S') | ${message}${NC}" | tee -a "$LOG_FILE"; } >&2
#}

log_error() {
    local message=$1
    local RED='\033[0;31m'
    local NC='\033[0m'
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    # [중요] 에러는 모드 상관없이 항상 화면에도 출력해야 함!
    echo -e "${RED}[ERROR]${timestamp} | ${message}${NC}" | tee -a "$LOG_FILE" >&2
}

# log_error() {
#    local message=$1
#    local RED='\033[0;31m'
#    local NC='\033[0m'
#    { echo -e "${RED}[ERROR]$(date +'%Y-%m-%d %H:%M:%S') | ${message}${NC}" | tee -a "$LOG_FILE"; } >&2
#}

# --- 2. 에러 트랩 정의 ---
_error_handler() {
    local exit_code="$?"; local command="${BASH_COMMAND}"; local script_name="${BASH_SOURCE[0]}"; local line_number="${LINENO}"
    local error_block=$'\n'"---------------------------------\n[ERROR] 스크립트 오류 발생!\n  - 스크립트: ${script_name}\n  - 라인 번호: ${line_number}\n  - 종료 코드: ${exit_code}\n  - 실패한 명령어: '${command}'\n---------------------------------"
    printf "${RED}%s${NC}\n" "$error_block" >&2; printf "%s\n" "$error_block" >> "$LOG_FILE"; exit "${exit_code}"
}
trap '_error_handler' ERR

# --- 3. 소프트웨어 의존성 확인 ---
check_conda_dependency() {
    local env_name=$1; local cmd=$2
    log_info "Conda 환경 '$env_name'에서 '$cmd' 명령어 존재 여부 확인 중..."
    if ! conda run -n "$env_name" command -v "$cmd" &> /dev/null; then
        local error_msg="[ERROR] Conda 환경 '$env_name'에 '$cmd'가 설치되지 않았습니다."; printf "${RED}%s${NC}\n" "$error_msg" >&2; printf "%s\n" "$error_msg" >> "$LOG_FILE"; exit 1
    fi
    log_info "'$cmd @ $env_name' 명령어 확인 완료."
}
check_system_dependency() {
    local cmd=$1; log_info "시스템 기본 명령어 '$cmd' 존재 여부 확인 중..."
    if ! command -v "$cmd" &> /dev/null; then
        local error_msg="[ERROR] '$cmd' 명령어를 찾을 수 없습니다. PATH를 확인해주세요."; printf "${RED}%s${NC}\n" "$error_msg" >&2; printf "%s\n" "$error_msg" >> "$LOG_FILE"; exit 1
    fi
    log_info "'$cmd' 명령어 확인 완료."
}

# --- 4. 파이프라인 개별 단계 함수들 ---
#--- 압축 해제 함수 ---
decompress_fastq() {
    local sample_name=$1; local r1_gz=$2; local r2_gz=$3; local work_dir=$4
    local r1_uncompressed="${work_dir}/${sample_name}_1.fastq"
    local r2_uncompressed="${work_dir}/${sample_name}_2.fastq"
    log_info "${sample_name}: FASTQ 파일 압축 해제 중..."
    pigz -dc "$r1_gz" > "$r1_uncompressed"; pigz -dc "$r2_gz" > "$r2_uncompressed"
    log_info "${sample_name}: FASTQ 파일 압축 해제 완료."
    echo "${r1_uncompressed} ${r2_uncompressed}"
}

#--- FastQC 직접 실행 함수 ('environmental' 모드용) ---
run_fastqc() {
    local output_dir=$1; local threads=$2; shift 2; local fastq_files=("$@")
    log_info "FastQC 실행 중 -> ${output_dir}"
    conda run -n "$KNEADDATA_ENV" fastqc --outdir "$output_dir" --threads "$threads" "${fastq_files[@]}" || true
    log_info "FastQC 실행 완료."
}

#--- fastp 실행 함수 ('environmental' 모드용) ---
run_fastp() {
    local sample_name=$1; local r1_in=$2; local r2_in=$3
    local clean_dir=$4; local report_dir=$5; local threads=$6; local options="$7"
    local extra_opts="${8}"
    
    local r1_out="${clean_dir}/${sample_name}_fastp_1.fastq.gz"
    local r2_out="${clean_dir}/${sample_name}_fastp_2.fastq.gz"
    
    mkdir -p "$report_dir"
    local json_report="${report_dir}/${sample_name}.fastp.json"
    local html_report="${report_dir}/${sample_name}.fastp.html"

    log_info "${sample_name}: fastp 실행 중..."
    
    # ==============================================================================
    # ✨✨ 핵심 수정: fastp의 표준 출력을 표준 에러로 리디렉션(>&2)합니다. ✨✨
    # ==============================================================================
    # 이렇게 하면 fastp의 진행 보고는 로그에만 남고, 함수의 최종 결과(echo)에 영향을 주지 않습니다.
    conda run -n "$FASTP_ENV" fastp \
        --in1 "$r1_in" --in2 "$r2_in" --out1 "$r1_out" --out2 "$r2_out" \
        --json "$json_report" --html "$html_report" --thread "$threads" $options $extra_opts >&2
        
    log_info "${sample_name}: fastp 실행 완료."
    echo "${r1_out} ${r2_out}"
}

#--- KneadData 실행 함수 ('host' 모드용) ---
run_kneaddata() {
    local sample_name=$1; local r1_uncompressed=$2; local r2_uncompressed=$3
    local ref_db=$4; local work_dir=$5; local clean_dir=$6; local kneaddata_log_dir=$7; local fastqc_pre_dir=$8
    local fastqc_post_dir=$9; local threads="${10}"; local processes="${11}"; local max_memory="${12}"; local trimmomatic_options_value="${13}"
    local extra_opts="${14}"
    
    local kneaddata_out_dir="${work_dir}/${sample_name}_kneaddata_out"
    local console_log="${kneaddata_log_dir}/${sample_name}_1_kneaddata_console.log"
    local summary_log="${kneaddata_log_dir}/${sample_name}_1_kneaddata_summary.log"
    local kneaddata_prefix="${sample_name}_1"
    
    log_info "${sample_name}: KneadData 실행 중 (내장 FastQC 사용)..."
    
    # KneadData는 스레드(-t)와 프로세스(-p) 옵션을 모두 사용합니다.    
    local kneaddata_args=(
        -i1 "$r1_uncompressed" -i2 "$r2_uncompressed" -db "$ref_db"
        --max-memory "$max_memory" --output "$kneaddata_out_dir"
        --trimmomatic-options "$trimmomatic_options_value" --remove-intermediate-output
        -t "$threads" -p "$processes" --run-fastqc-start --run-fastqc-end
    )
    
    conda run -n "$KNEADDATA_ENV" kneaddata "${kneaddata_args[@]}" $extra_opts > "$console_log" 2>&1
    log_info "${sample_name}: KneadData 실행 완료. 결과 파일 확인 중..."
    
    local paired_r1_out="${kneaddata_out_dir}/${kneaddata_prefix}_kneaddata_paired_1.fastq"
    if [[ ! -f "$paired_r1_out" ]]; then
        printf "${RED}[FATAL] KneadData가 최종 출력 파일을 생성하지 못했습니다!${NC}\n" >&2
        printf "${RED}       콘솔 로그 파일(%s)을 확인하여 원인을 파악해주세요.${NC}\n" "$console_log" >> "$LOG_FILE"
        return 1
    fi
    log_info "${sample_name}: 최종 결과 파일 생성 확인."
    local kneaddata_log_file="${kneaddata_out_dir}/${kneaddata_prefix}_kneaddata.log"
    if [[ -f "$kneaddata_log_file" ]]; then mv "$kneaddata_log_file" "$summary_log"; fi

    log_info "${sample_name}: FastQC 보고서 이동 중..."
    mv "${kneaddata_out_dir}/fastqc/${sample_name}_1_fastqc.zip"    "$fastqc_pre_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${sample_name}_1_fastqc.html"   "$fastqc_pre_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${sample_name}_2_fastqc.zip"    "$fastqc_pre_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${sample_name}_2_fastqc.html"   "$fastqc_pre_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_paired_1_fastqc.zip"  "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_paired_1_fastqc.html" "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_paired_2_fastqc.zip"  "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_paired_2_fastqc.html" "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_unmatched_1_fastqc.zip"  "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_unmatched_1_fastqc.html" "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_unmatched_2_fastqc.zip"  "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_unmatched_2_fastqc.html" "$fastqc_post_dir/" 2>/dev/null || true
    log_info "${sample_name}: FastQC 보고서 이동 완료."
    local paired_r2_out="${kneaddata_out_dir}/${kneaddata_prefix}_kneaddata_paired_2.fastq"
    pigz "$paired_r1_out"; pigz "$paired_r2_out"
    local r1_gz="${paired_r1_out}.gz"; local r2_gz="${paired_r2_out}.gz"
    local r1_final_path="${clean_dir}/$(basename "$r1_gz")"; local r2_final_path="${clean_dir}/$(basename "$r2_gz")"
    mv "$r1_gz" "$r1_final_path"; mv "$r2_gz" "$r2_final_path"
    rm -rf "$kneaddata_out_dir"
    echo "${r1_final_path} ${r2_final_path}"
}

#--- Kraken2 실행 함수 ---
run_kraken2() {
    local sample_name=$1; local r1_clean_gz=$2; local r2_clean_gz=$3; local kraken_db=$4
    local kraken_out_dir=$5; local summary_tsv_file=$6; local threads=$7; local extra_opts="${8}"
    
    local k2_output="${kraken_out_dir}/${sample_name}.kraken2"; local k2_report="${kraken_out_dir}/${sample_name}.k2report"
    if [[ -f "$k2_output" && -f "$k2_report" ]]; then
        log_info "${sample_name}: 기존 Kraken2 결과 발견. 건너뜁니다."
    else
        log_info "${sample_name}: Kraken2 실행 중 (환경: ${KRAKEN_ENV})..."
        (
            # 1. Conda 경로 자동 탐지
            CONDA_BASE=$(conda info --base)
            if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
                source "${CONDA_BASE}/etc/profile.d/conda.sh"
            else
                source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source ~/anaconda3/etc/profile.d/conda.sh
            fi
            
            # 2. 환경 활성화
            conda activate "$KRAKEN_ENV"
            
            # 3. Kraken2 직접 실행 (로그 파일로 완벽하게 돌림)
            kraken2 \
                --db "$kraken_db" --threads "$threads" --report "$k2_report" --paired \
                --report-minimizer-data --minimum-hit-groups 3 "$r1_clean_gz" "$r2_clean_gz" $extra_opts \
                > "$k2_output" 2>> "$LOG_FILE"
        )

        log_info "${sample_name}: Kraken2 실행 완료."

    fi
    
    log_info "${sample_name}: Kraken2 분류 통계 계산 중..."
    local summary_stats=($(head -n 2 "$k2_report" | awk '{print $2}')); local UNCLASSIFIED=${summary_stats[0]:-0}; local CLASSIFIED=${summary_stats[1]:-0}
    local TOTAL=$((CLASSIFIED + UNCLASSIFIED));
    local PC_C=$(awk -v c=$CLASSIFIED -v t=$TOTAL 'BEGIN { if (t > 0) printf "%.2f", (c/t)*100; else printf "0.00" }')
    local PC_U=$(awk -v u=$UNCLASSIFIED -v t=$TOTAL 'BEGIN { if (t > 0) printf "%.2f", (u/t)*100; else printf "0.00" }')
    echo -e "${sample_name}\t${TOTAL}\t${CLASSIFIED}\t${PC_C}\t${UNCLASSIFIED}\t${PC_U}" >> "$summary_tsv_file"
}

#--- Bracken 실행 및 MPA 변환 함수 ---
#--- Bracken 실행 및 MPA 변환 함수 (Checkpoint 로직 수정) ---
run_bracken_and_mpa() {
    local sample_name=$1; local kraken_report=$2; local kraken_db=$3; local bracken_out_dir=$4; local mpa_out_dir=$5;
    local read_len=$6; local threshold=$7   
    
    log_info "${sample_name}: Bracken 실행 및 MPA 변환 시작..."
    mkdir -p "$bracken_out_dir"
    
    # --- 변경점: Species 레벨 리포트 파일 경로를 미리 정의 ---
    local species_report_file="${bracken_out_dir}/${sample_name}_S.breport"

    # 1. Bracken 실행
    for level in $BRACKEN_LEVELS; do
        local bracken_output_file="${bracken_out_dir}/${sample_name}_${level}.bracken"
        local bracken_report_file="${bracken_out_dir}/${sample_name}_${level}.breport"

        if [[ -f "$bracken_output_file" && -f "$bracken_report_file" ]]; then
            echo "[INFO]$(date +'%Y-%m-%d %H:%M:%S') |   - Level ${level}: 기존 Bracken 결과 발견. 건너뜁니다." >> "$LOG_FILE"
            continue
        fi

        log_info "  - Level ${level}: 존재비율 재추정 중..."
        conda run -n "$KRAKEN_ENV" bracken -d "$kraken_db" -i "$kraken_report" -r "$read_len" \
            -l "$level" -t "$threshold" -o "$bracken_output_file" -w "$bracken_report_file" >> "$LOG_FILE" 2>&1
    done
    log_info "${sample_name}: Bracken 모든 레벨 실행 완료."

    # 2. MPA 변환
    # 이제 $species_report_file 변수는 Bracken 실행 여부와 관계없이 항상 올바른 경로를 가짐
    if [[ -f "$species_report_file" ]]; then
        mkdir -p "$mpa_out_dir"
        local mpa_reads="${mpa_out_dir}/${sample_name}_reads.mpa"
        local mpa_percent="${mpa_out_dir}/${sample_name}_percent.mpa"

        if [[ -f "$mpa_reads" && -f "$mpa_percent" ]]; then
            echo "[INFO]$(date +'%Y-%m-%d %H:%M:%S') | ${sample_name}: 기존 MPA 파일 발견. 변환을 건너뜁니다." >> "$LOG_FILE"
        else
            log_info "${sample_name}: Bracken 리포트를 MPA 형식으로 변환 중..."
            # --display-header 옵션은 유지하되, 만일을 대비해 후처리
            conda run -n "$KRAKEN_ENV" kreport2mpa.py -r "$species_report_file" -o "$mpa_reads" --display-header --no-intermediate-ranks >> "$LOG_FILE" 2>&1
            conda run -n "$KRAKEN_ENV" kreport2mpa.py -r "$species_report_file" --percentages -o "$mpa_percent" --display-header --no-intermediate-ranks >> "$LOG_FILE" 2>&1
            
            # --- 신규 추가: sed를 이용한 헤더 강제 수정 ---
            log_info "${sample_name}: MPA 파일 헤더를 샘플 이름으로 교정 중..."
            # 생성된 파일의 현재 헤더(두 번째 컬럼)를 가져옴
            local current_header_reads=$(head -n 1 "$mpa_reads" | cut -f 2)
            # 현재 헤더를 정확한 샘플 이름으로 교체
            sed -i "1s/${current_header_reads}/${sample_name}/" "$mpa_reads"
            
            local current_header_percent=$(head -n 1 "$mpa_percent" | cut -f 2)
            sed -i "1s/${current_header_percent}/${sample_name}/" "$mpa_percent"

            log_info "${sample_name}: MPA 파일 생성 및 헤더 수정 완료."
        fi
    else
        log_warn "${sample_name}: Species 레벨 Bracken 리포트가 없어 MPA 변환을 건너뜁니다."
    fi
}

#--- 모든 샘플의 Bracken 결과 통합 함수 ---
merge_bracken_outputs() {
    local bracken_in_dir=$1; local bracken_out_dir=$2
    log_info "모든 Bracken 결과 파일을 분류 계급별로 통합합니다..."
    mkdir -p "$bracken_out_dir"
    for level in $BRACKEN_LEVELS; do
        log_info "  - Level ${level}의 결과 통합 중..."
        local bracken_files=($(find "$bracken_in_dir" -name "*_${level}.bracken" | sort))
        if [[ ${#bracken_files[@]} -eq 0 ]]; then log_warn "Level ${level}에 해당하는 Bracken 파일이 없어 건너뜁니다."; continue; fi
        local sample_names=(); for file in "${bracken_files[@]}"; do local sample_name=$(basename "$file" | sed "s/_${level}\.bracken//"); sample_names+=("$sample_name"); done
        local names_str=$(IFS=,; echo "${sample_names[*]}")
        local merged_output="${bracken_out_dir}/merged_${level}.tsv"
        conda run -n "$KRAKEN_ENV" combine_bracken_outputs.py --files "${bracken_files[@]}" --names "$names_str" -o "$merged_output"
    done
    log_info "Bracken 결과 통합 완료. 결과물 저장 경로: ${bracken_out_dir}"
}

# ==========================================================
# --- Get R2 Pair Path Function (Shared Logic) ---
# 설명: R1 파일 경로를 입력받아 해당하는 R2 파일 경로를 추정하여 반환합니다.
# ==========================================================
get_r2_path() {
    local r1_path=$1
    local r1_base=$(basename "$r1_path")
    local r1_dir=$(dirname "$r1_path")
    
    # BASH 정규식 매칭을 사용하여 안전하게 R2 파일명 구성
    # 패턴: (Prefix)(Tag: _R1, _1, .R1, .1)(Suffix)
    if [[ "$r1_base" =~ ^(.*)(_R?1|_1|\.R1|\.1)(.*)\.fastq\.gz$ ]]; then
        local prefix="${BASH_REMATCH[1]}"
        local clean_tag="${BASH_REMATCH[2]}"
        local suffix="${BASH_REMATCH[3]}"
        
        # tag 치환: 1 -> 2, R1 -> R2
        CLEAN_TAG="${clean_tag/R1/R2}"
        CLEAN_TAG="${CLEAN_TAG/r1/r2}"
        CLEAN_TAG="${CLEAN_TAG/_1/_2}"
        CLEAN_TAG="${CLEAN_TAG/.1/.2}"

        echo "${r1_dir}/${prefix}${CLEAN_TAG}${suffix}.fastq.gz"
        return 0
    else
        # 패턴 불일치 시 오류 코드 반환
        return 1
    fi
}

# --- Check for New Input Files (Used by MAG to break early) ---
# 설명: mag.sh 내부에서 run_all.sh의 상태 파일을 읽어 변경 감지
check_for_new_input_files() {
    local raw_dir=$1
    local state_file=$2
    
    local CURRENT_STATE_FILE=$(mktemp)
    
    # [stat 감지] 현재 입력 폴더의 상태를 빠르게 기록
    if [[ -n "$(find "$raw_dir" -maxdepth 1 -type f -name "*.fastq.gz" 2>/dev/null)" ]]; then
        find "$raw_dir" -maxdepth 1 -type f -name "*.fastq.gz" -printf "%f\t%s\t%T@\n" | sort > "$CURRENT_STATE_FILE"
    else
        touch "$CURRENT_STATE_FILE"
    fi

    # [비교] 이전 상태와 현재 상태 비교
    if [ -f "$state_file" ] && diff -q "$state_file" "$CURRENT_STATE_FILE" >/dev/null; then
        # 변화 없음
        rm -f "$CURRENT_STATE_FILE"
        return 0
    else
        sleep 5
        local STABILITY_CHECK_FILE=$(mktemp)
        find "$raw_dir" -maxdepth 1 -type f -name "*.fastq.gz" -printf "%f\t%s\t%T@\n" | sort > "$STABILITY_CHECK_FILE"

        if diff -q "$CURRENT_STATE_FILE" "$STABILITY_CHECK_FILE" >/dev/null; then
            # 5초 전과 후가 동일함 -> 전송 완료됨 -> 진짜 변화!
            rm -f "$CURRENT_STATE_FILE" "$STABILITY_CHECK_FILE"
            return 99 # 신호 발생
        else
            # 5초 사이에 또 변함 -> 아직 전송 중임 -> 이번 턴은 무시하고 대기
            rm -f "$CURRENT_STATE_FILE" "$STABILITY_CHECK_FILE"
            return 0 # 아직 준비 안 됨 (변화 없음으로 처리)
        fi
    fi
}

# ==========================================================
# --- [Pro 3.4] Fixed-Height Dashboard Functions ---
# ==========================================================

# 2. 상태 업데이트/삭제 함수
set_job_status() { local sample=$1; local status=$2; echo "   ├─ [${sample}] ${status}" > "${JOB_STATUS_DIR}/${sample}.status"; }
clear_job_status() { local sample=$1; rm -f "${JOB_STATUS_DIR}/${sample}.status"; }

# 3. [핵심] 고정 높이 대시보드 출력 함수
print_progress_bar() {
    local current=$1; local total=$2; local sample_name=$3
    
    if [ "$total" -eq 0 ]; then total=1; fi
    local percent=$(( 100 * current / total ))
    
    # 터미널 너비 감지
    local term_width=$(tput cols 2>/dev/null || echo 80)
    local bar_len=$(( term_width * 40 / 100 )); if [ "$bar_len" -lt 10 ]; then bar_len=10; fi
    local filled_len=$(( percent * bar_len / 100 )); local empty_len=$(( bar_len - filled_len ))
    
    # Bar Design (White Block)
    local bar_str=""; if [ "$filled_len" -gt 0 ]; then bar_str+="\033[47m$(printf "%0.s " $(seq 1 $filled_len))\033[0m"; fi
    if [ "$empty_len" -gt 0 ]; then bar_str+="\033[90m$(printf "%0.s·" $(seq 1 $empty_len))\033[0m"; fi

    if [ "$VERBOSE_MODE" = false ]; then
        # --- [설정] 그룹별 표시 줄 수 (높이 고정) ---
        local QC_LIMIT=5
        local KRAKEN_LIMIT=3
        local BRACKEN_LIMIT=3
        
        # 전체 대시보드 높이 계산: 헤더(1) + (그룹헤더(1)+본문)*3 = 총 15줄
        #local TOTAL_HEIGHT=$(( 1 + (1 + QC_LIMIT) + (1 + KRAKEN_LIMIT) + (1 + BRACKEN_LIMIT) ))
        local TOTAL_HEIGHT=$(( 1 + (1 + QC_LIMIT) + (1 + KRAKEN_LIMIT) + (1 + BRACKEN_LIMIT) + (1 + 3) + (1 + 2) + (1 + 2) ))
        
        # 1. 커서 이동: 처음이 아니면 고정 높이만큼 위로 이동
        local lines_to_clear=${LAST_PRINT_LINES:-0}
        if [ "$lines_to_clear" -gt 0 ]; then printf "\033[%dA" "$TOTAL_HEIGHT" >&2; fi
        
        # 2. 메인 헤더 출력
        printf "\r\033[K [Progress] [%b] %3d%% | Latest: %s\n" "$bar_str" "$percent" "$sample_name" >&2

        # 3. 상태 파일 읽기
        local all_status=""
        if [ -d "$JOB_STATUS_DIR" ]; then
            all_status=$(find "${JOB_STATUS_DIR}" -maxdepth 1 -name "*.status" -type f -exec cat {} + 2>/dev/null | sort)
        fi

        # --- [내부 함수] 고정 높이 출력기 ---
        print_fixed_group() {
            local title=$1; local keyword=$2; local color=$3; local limit=$4; local data=$5
            
            # 그룹 헤더 출력
            printf "\033[K   ├─ ${color}${title}\033[0m\n" >&2
            
            # 데이터 필터링 및 정렬 (Running 우선)
            local group_lines=$(echo "$data" | grep -i "$keyword" || true)
            local running_lines=$(echo "$group_lines" | grep "Running" | sort)
            local other_lines=$(echo "$group_lines" | grep -v "Running" | sort)
            local sorted_data="${running_lines}${running_lines:+$'\n'}${other_lines}"
            
            # 라인 카운팅
            local count=0
            local printed_lines=0
            
            # 데이터가 없으면 sorted_data가 빈 줄 하나를 가질 수 있으므로 체크
            if [[ -n "$group_lines" ]]; then
                local total_items=$(echo "$group_lines" | wc -l)
                
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    
                    if [ "$printed_lines" -lt "$limit" ]; then
                        # 마지막 줄인데 남은 게 더 많다면 "... more" 출력
                        if [ "$printed_lines" -eq $((limit - 1)) ] && [ "$total_items" -gt "$limit" ]; then
                            local remain=$((total_items - printed_lines))
                            printf "\033[K   │    └─ ... %d more samples ...\n" "$remain" >&2
                        else
                            # 일반 출력 (너비 잘림 적용)
                            local clean_line=$(echo "$line" | sed 's/^[[:space:]]*├─ //')
                            local display_str="   │    ├─ ${clean_line}"
                            printf "\033[K%s\n" "${display_str:0:$((term_width - 1))}" >&2
                        fi
                        printed_lines=$((printed_lines + 1))
                    fi
                    count=$((count + 1))
                done <<< "$sorted_data"
            fi
            
            # 남은 빈 줄 채우기 (Padding) -> 화면 고정의 핵심!
            while [ "$printed_lines" -lt "$limit" ]; do
                printf "\033[K\n" >&2
                printed_lines=$((printed_lines + 1))
            done
        }

        # --- 그룹별 출력 (고정 높이 적용) ---
        print_fixed_group "QC / Repair (Pre-processing)" "QC|Repair" "\033[1;33m" "$QC_LIMIT" "$all_status"
        print_fixed_group "Kraken2 (Taxonomy)" "Kraken" "\033[1;34m" "$KRAKEN_LIMIT" "$all_status"
        print_fixed_group "Annotation (Bracken/MPA)" "Bracken" "\033[1;35m" "$BRACKEN_LIMIT" "$all_status"
        print_fixed_group "MAG - Assembly" "Assembly" "\033[1;36m" "3" "$all_status"
        print_fixed_group "MAG - Binning" "Binning" "\033[1;32m" "2" "$all_status"
        print_fixed_group "MAG - Annotation (GTDB/Bakta)" "GTDB|Bakta" "\033[1;35m" "2" "$all_status"

        export LAST_PRINT_LINES="$TOTAL_HEIGHT"
    else
        log_info "--- [${current}/${total}] ${percent}% Processing: ${sample_name} ---"
    fi
    
    echo "[PROGRESS] [${current}/${total}] ${percent}% - Processing: ${sample_name}" >> "$LOG_FILE"
}