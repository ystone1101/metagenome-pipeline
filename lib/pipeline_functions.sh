#!/bin/bash
#=========================
# 파이프라인 기능 함수 정의
#=========================

# ==========================================================
# --- 로깅(Logging) 및 오류 처리 함수 (최종 수정) ---
# ==========================================================

# 모든 로깅 함수의 최종 출력을 표준 에러(stderr)로 리디렉션(>&2)하여,
# 함수의 '반환 값'으로 캡처되지 않도록 수정합니다.
log_info() {
    local message=$1
    local GREEN='\033[0;32m'
    local NC='\033[0m'
    { echo -e "${GREEN}[INFO]$(date +'%Y-%m-%d %H:%M:%S') | ${message}${NC}" | tee -a "$LOG_FILE"; } >&2
}

log_warn() {
    local message=$1
    local YELLOW='\033[0;33m'
    local NC='\033[0m'
    { echo -e "${YELLOW}[WARN]$(date +'%Y-%m-%d %H:%M:%S') | ${message}${NC}" | tee -a "$LOG_FILE"; } >&2
}

log_error() {
    local message=$1
    local RED='\033[0;31m'
    local NC='\033[0m'
    { echo -e "${RED}[ERROR]$(date +'%Y-%m-%d %H:%M:%S') | ${message}${NC}" | tee -a "$LOG_FILE"; } >&2
}

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
        # ✨ [수정] 명령어 마지막에 $extra_opts를 추가합니다. (따옴표 없이)
        conda run -n "$KRAKEN_ENV" kraken2 \
            --db "$kraken_db" --threads "$threads" --report "$k2_report" --paired \
            --report-minimizer-data --minimum-hit-groups 3 "$r1_clean_gz" "$r2_clean_gz" $extra_opts > "$k2_output"
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
            log_info "  - Level ${level}: 기존 Bracken 결과 발견. 건너뜁니다."
            continue
        fi

        log_info "  - Level ${level}: 존재비율 재추정 중..."
        conda run -n "$KRAKEN_ENV" bracken -d "$kraken_db" -i "$kraken_report" -r "$read_len" \
            -l "$level" -t "$threshold" -o "$bracken_output_file" -w "$bracken_report_file"
    done
    log_info "${sample_name}: Bracken 모든 레벨 실행 완료."

    # 2. MPA 변환
    # 이제 $species_report_file 변수는 Bracken 실행 여부와 관계없이 항상 올바른 경로를 가짐
    if [[ -f "$species_report_file" ]]; then
        mkdir -p "$mpa_out_dir"
        local mpa_reads="${mpa_out_dir}/${sample_name}_reads.mpa"
        local mpa_percent="${mpa_out_dir}/${sample_name}_percent.mpa"

        if [[ -f "$mpa_reads" && -f "$mpa_percent" ]]; then
            log_info "${sample_name}: 기존 MPA 파일 발견. 변환을 건너뜁니다."
        else
            log_info "${sample_name}: Bracken 리포트를 MPA 형식으로 변환 중..."
            # --display-header 옵션은 유지하되, 만일을 대비해 후처리
            conda run -n "$KRAKEN_ENV" kreport2mpa.py -r "$species_report_file" -o "$mpa_reads" --display-header --no-intermediate-ranks
            conda run -n "$KRAKEN_ENV" kreport2mpa.py -r "$species_report_file" --percentages -o "$mpa_percent" --display-header --no-intermediate-ranks
            
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
