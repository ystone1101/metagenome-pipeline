#!/bin/bash
# FUNCTIONS FOR PIPELINE 2: DIVERSITY ANALYSIS

# Alpha/Beta 함수는 main_functions.sh의 로그 함수를 사용한다고 가정함

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
            conda run -n "$KRAKEN_ENV" python KrakenTools/DiversityTools/alpha_diversity.py -f "$bracken_file" -a "$index" > "$alpha_output_file"
        done
    done
}

#--- Beta Diversity Calculation Function ---
run_beta_diversity() {
    local bracken_dir=$1; local level=$2; local beta_out_dir=$3
    log_info "Calculating Beta Diversity at Level '${level}'..."
    mkdir -p "$beta_out_dir"
    local bracken_files=$(find "$bracken_dir" -name "*_${level}.bracken" | tr '\n' ' ')
    if [[ -z "$bracken_files" ]]; then log_warn "No Bracken files found for level '${level}'."; return; fi
    local beta_output_file="${beta_out_dir}/beta_diversity_${level}.tsv"
    conda run -n "$KRAKEN_ENV" python KrakenTools/DiversityTools/beta_diversity.py -i ${bracken_files} --type bracken > "$beta_output_file"
}
