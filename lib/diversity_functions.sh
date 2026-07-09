#!/bin/bash
# FUNCTIONS FOR PIPELINE 1: DIVERSITY ANALYSIS

# Alpha/Beta 함수는 pipeline_functions.sh의 로그 함수(log_info/log_warn)를 사용한다고 가정함
# alpha_diversity.py / beta_diversity.py 는 kraken_env에 이미 설치된 krakentools(bioconda)
# 패키지가 제공하는 실행 파일이며, 별도 저장소 clone이 필요 없습니다.

#--- Alpha Diversity Calculation Function ---
run_alpha_diversity() {
    local bracken_dir=$1; local level=$2; local alpha_out_dir=$3
    log_info "Calculating Alpha Diversity at Level '${level}'..."
    mkdir -p "$alpha_out_dir"
    for bracken_file in "${bracken_dir}"/*_${level}.bracken; do
        if [[ ! -f "$bracken_file" ]]; then continue; fi
        local sample_name=$(basename "$bracken_file" | sed "s/_${level}\.bracken//")
        for index in $ALPHA_DIVERSITY_INDICES; do
            local alpha_output_file="${alpha_out_dir}/${sample_name}_${index}.alpha.txt"
            if [[ -s "$alpha_output_file" ]]; then continue; fi
            conda run -n "$KRAKEN_ENV" alpha_diversity.py -f "$bracken_file" -a "$index" > "$alpha_output_file" 2>>"$LOG_FILE"
        done
    done
    log_info "Alpha Diversity calculation for Level '${level}' finished."
}

#--- 개별 Alpha Diversity 결과 파일들을 샘플 x 지표 표 하나로 통합 ---
merge_alpha_diversity() {
    local alpha_out_dir=$1; local merged_file=$2

    local sample_names=()
    for f in "${alpha_out_dir}"/*_*.alpha.txt; do
        [[ -f "$f" ]] || continue
        local base; base=$(basename "$f" .alpha.txt)
        local sample="${base%_*}"
        local already_added=false
        for s in "${sample_names[@]:-}"; do [[ "$s" == "$sample" ]] && already_added=true && break; done
        [[ "$already_added" == false ]] && sample_names+=("$sample")
    done

    if [[ ${#sample_names[@]} -eq 0 ]]; then
        log_warn "No alpha diversity result files found in ${alpha_out_dir}."
        return
    fi

    {
        printf "Sample"
        for index in $ALPHA_DIVERSITY_INDICES; do printf "\t%s" "$index"; done
        printf "\n"
        for sample in "${sample_names[@]}"; do
            printf "%s" "$sample"
            for index in $ALPHA_DIVERSITY_INDICES; do
                local f="${alpha_out_dir}/${sample}_${index}.alpha.txt"
                local val="NA"
                # krakentools의 출력은 보통 "<지표 이름>: <값>" 형태이므로 마지막 콜론 뒤 값만 추출
                [[ -f "$f" ]] && val=$(awk -F: '{print $NF}' "$f" | tr -d '[:space:]')
                [[ -z "$val" ]] && val="NA"
                printf "\t%s" "$val"
            done
            printf "\n"
        done
    } > "$merged_file"
    log_info "Alpha diversity summary table written: ${merged_file}"
}

#--- Beta Diversity Calculation Function ---
run_beta_diversity() {
    local bracken_dir=$1; local level=$2; local beta_out_dir=$3
    log_info "Calculating Beta Diversity at Level '${level}'..."
    mkdir -p "$beta_out_dir"
    local beta_output_file="${beta_out_dir}/beta_diversity_${level}.tsv"
    if [[ -s "$beta_output_file" ]]; then
        log_info "Beta diversity for Level '${level}' already exists. Skipping."
        return
    fi

    local bracken_files=()
    for f in "${bracken_dir}"/*_${level}.bracken; do
        [[ -f "$f" ]] && bracken_files+=("$f")
    done
    if [[ ${#bracken_files[@]} -eq 0 ]]; then
        log_warn "No Bracken files found for Level '${level}'."
        return
    fi

    conda run -n "$KRAKEN_ENV" beta_diversity.py -i "${bracken_files[@]}" --type bracken > "$beta_output_file" 2>>"$LOG_FILE"
    log_info "Beta Diversity calculation for Level '${level}' finished."
}
