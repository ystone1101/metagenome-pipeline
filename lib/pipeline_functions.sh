#!/bin/bash
#=========================
# 파이프라인 기능 함수 정의
#=========================

#--- 로그 출력 함수 (콘솔 출력과 파일 기록을 직접 수행) ---
log_info() {
    local message="[INFO] $(date +'%Y-%m-%d %H:%M:%S') | $1"
    # 콘솔에는 컬러 메시지 출력
    printf "${GREEN}%s${NC}\n" "$message" >&2
    # 로그 파일에는 일반 텍스트 메시지 추가
    echo "$message" >> "$LOG_FILE"
}
log_warn() {
    local message="[WARNING] $(date +'%Y-%m-%d %H:%M:%S') | $1"
    printf "${YELLOW}%s${NC}\n" "$message" >&2
    echo "$message" >> "$LOG_FILE"
}

# 압축된 FASTQ 파일을 압축 해제하는 함수
decompress_fastq() {
    local sample_name=$1 
    local r1_gz=$2 
    local r2_gz=$3 
    local work_dir=$4
    local r1_uncompressed="${work_dir}/${sample_name}_1.fastq"
    local r2_uncompressed="${work_dir}/${sample_name}_2.fastq"
    log_info "${sample_name}: FASTQ 파일 압축 해제 중 (pigz 사용)..."
    pigz -dc "$r1_gz" > "$r1_uncompressed"
    pigz -dc "$r2_gz" > "$r2_uncompressed"
    log_info "${sample_name}: FASTQ 파일 압축 해제 완료."
    echo "${r1_uncompressed} ${r2_uncompressed}"
}

# KneadData를 실행하고 결과물의 존재 여부를 확인하는 안정적인 함수
run_kneaddata() {
    local sample_name=$1 
    local r1_uncompressed=$2 
    local r2_uncompressed=$3
    local ref_db=$4 
    local work_dir=$5
    local clean_dir=$6
    local kneaddata_log_dir=$7
    local fastqc_pre_dir=$8
    local fastqc_post_dir=$9 
    local trimmomatic_options_string="${10}"
    local kneaddata_out_dir="${work_dir}/${sample_name}_kneaddata_out"
    local console_log="${kneaddata_log_dir}/${sample_name}_kneaddata_console.log"
    local summary_log="${kneaddata_log_dir}/${sample_name}_kneaddata_summary.log"
    local kneaddata_prefix="${sample_name}_1"

    log_info "${sample_name}: KneadData 실행 중 (FastQC 포함)..."
    conda run -n "$KNEADDATA_ENV" kneaddata \
        --input1 "$r1_uncompressed" \
        --input2 "$r2_uncompressed" \
        --reference-db "$ref_db" \
        --output "$kneaddata_out_dir" \
        --threads "$KNEADDATA_THREADS" \
        --processes 2 \
        --max-memory "$KNEADDATA_MAX_MEMORY" \
        --run-fastqc-start \
        --run-fastqc-end \
        --remove-intermediate-output \
        --bowtie2-options="--very-fast" \
        --bowtie2-options="-p 8" \
        --trimmomatic-options="$trimmomatic_options_string" > "$console_log" 2>&1

    log_info "${sample_name}: KneadData 실행 완료. 결과 파일 확인 중..."

    local paired_r1_out="${kneaddata_out_dir}/${kneaddata_prefix}_kneaddata_paired_1.fastq"
    if [[ ! -f "$paired_r1_out" ]]; then
        local fatal_msg1="[FATAL] KneadData가 최종 출력 파일($paired_r1_out)을 생성하지 못했습니다!"
        local fatal_msg2="       콘솔 로그 파일($console_log)을 확인하여 원인을 파악해주세요."
        printf "${RED}%s\n%s${NC}\n" "$fatal_msg1" "$fatal_msg2" >&2
        printf "%s\n%s\n" "$fatal_msg1" "$fatal_msg2" >> "$LOG_FILE"
        return 1
    fi
    log_info "${sample_name}: 최종 결과 파일 생성 확인."
    
    local kneaddata_log_file="${kneaddata_out_dir}/${kneaddata_prefix}_kneaddata.log"
    if [[ -f "$kneaddata_log_file" ]]; then
        mv "$kneaddata_log_file" "$summary_log"
        log_info "${sample_name}: KneadData 요약 로그 이동 완료."
    fi

    log_info "${sample_name}: FastQC 보고서 이동 중..."
    # 처리 전(pre) FastQC 보고서를 pre_kneaddata 디렉토리로 이동
    mv "${kneaddata_out_dir}/fastqc/${sample_name}_1_fastqc.zip"    "$fastqc_pre_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${sample_name}_1_fastqc.html"   "$fastqc_pre_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${sample_name}_2_fastqc.zip"    "$fastqc_pre_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${sample_name}_2_fastqc.html"   "$fastqc_pre_dir/" 2>/dev/null || true

    # 처리 후(post) FastQC 보고서를 post_kneaddata 디렉토리로 이동
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_paired_1_fastqc.zip"  "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_paired_1_fastqc.html" "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_paired_2_fastqc.zip"  "$fastqc_post_dir/" 2>/dev/null || true
    mv "${kneaddata_out_dir}/fastqc/${kneaddata_prefix}_kneaddata_paired_2_fastqc.html" "$fastqc_post_dir/" 2>/dev/null || true

    log_info "${sample_name}: FastQC 보고서 이동 완료."

    local paired_r2_out="${kneaddata_out_dir}/${kneaddata_prefix}_kneaddata_paired_2.fastq"
    log_info "${sample_name}: 정제된 FASTQ 파일 압축 중..."
    pigz "$paired_r1_out"; pigz "$paired_r2_out"
    
    local r1_gz="${paired_r1_out}.gz"; local r2_gz="${paired_r2_out}.gz"
    local r1_final_path="${work_dir}/$(basename "$r1_gz")"
    local r2_final_path="${work_dir}/$(basename "$r2_gz")"
    mv "$r1_gz" "$r1_final_path"; mv "$r2_gz" "$r2_final_path"
    
    rm -rf "$kneaddata_out_dir"
    echo "${r1_final_path} ${r2_final_path}"
}

# Kraken2를 실행하고 분류 통계를 추출하며 MetaPhlAn 형식으로 변환하는 함수
run_kraken2() {
    local sample_name=$1
    local r1_clean_gz=$2
    local r2_clean_gz=$3
    local kraken_db=$4
    local kraken_out_dir=$5
    local summary_tsv_file=$6
    local mpa_out_dir=$7
    local k2_output="${kraken_out_dir}/${sample_name}.kraken2"
    local k2_report="${kraken_out_dir}/${sample_name}.k2report"
    local k2_report_6col="${mpa_out_dir}/${sample_name}.k2report.6col"
    local mpa_reads="${mpa_out_dir}/${sample_name}_reads.mpa"
    local mpa_percent="${mpa_out_dir}/${sample_name}_percent.mpa"

    log_info "${sample_name}: Kraken2 실행 중 (환경: ${KRAKEN_ENV})..."
    conda run -n "$KRAKEN_ENV" kraken2 \
        --db "$kraken_db" \
        --threads "$KRAKEN2_THREADS" \
        --report "$k2_report" \
        --paired \
        --report-minimizer-data \
        --minimum-hit-groups 3 \
        "$r1_clean_gz" \
        "$r2_clean_gz" \
        > "$k2_output"
    log_info "${sample_name}: Kraken2 실행 완료."

    log_info "${sample_name}: Kraken2 분류 통계 계산 중..."
    local TOTAL=$(grep -c '^' "$k2_output")
    local CLASSIFIED=$(grep -c '^C' "$k2_output")
    local UNCLASSIFIED=$((TOTAL - CLASSIFIED))
    local PC_C=$(awk -v c=$CLASSIFIED -v t=$TOTAL 'BEGIN { if (t > 0) printf "%.2f", (c/t)*100; else printf "0.00" }')
    local PC_U=$(awk -v u=$UNCLASSIFIED -v t=$TOTAL 'BEGIN { if (t > 0) printf "%.2f", (u/t)*100; else printf "0.00" }')
    echo -e "${sample_name}\t${TOTAL}\t${CLASSIFIED}\t${PC_C}\t${UNCLASSIFIED}\t${PC_U}" >> "$summary_tsv_file"
    log_info "${sample_name}: Kraken2 분류 통계 SUMMARY_TSV에 추가 완료."

    log_info "${sample_name}: kreport2mpa.py 변환 (리드 기반) 중..."
    cut -f1-3,6-8 "$k2_report" > "$k2_report_6col"
    conda run -n "$KRAKEN_ENV" kreport2mpa.py \
        -r "$k2_report_6col" \
        -o "$mpa_reads" \
        --display-header \
        --no-intermediate-ranks
    log_info "${sample_name}: kreport2mpa.py (리드 기반) 변환 완료."

    log_info "${sample_name}: kreport2mpa.py 변환 (비율 기반) 중..."
    conda run -n "$KRAKEN_ENV" kreport2mpa.py \
        --percentages \
        -r "$k2_report_6col" \
        -o "$mpa_percent" \
        --display-header \
        --no-intermediate-ranks
    log_info "${sample_name}: kreport2mpa.py (비율 기반) 변환 완료."

    rm "$k2_report_6col"
}
