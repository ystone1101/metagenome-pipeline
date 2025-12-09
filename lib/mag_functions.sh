#!/bin/bash
#========================================
# FUNCTIONS FOR PIPELINE 2: MAG ANALYSIS
#========================================

#--- BBMap의 repair.sh를 이용한 FASTQ 파일 복구 함수 ---
run_pair_repair() {
    local sample_name=$1; local r1_in=$2; local r2_in=$3; local repair_out_dir=$4
    
    log_info "${sample_name}: BBMap repair.sh로 FASTQ 페어링 복구 중..."
    
    local r1_repaired="${repair_out_dir}/${sample_name}_R1.repaired.fastq.gz"
    local r2_repaired="${repair_out_dir}/${sample_name}_R2.repaired.fastq.gz"
    
    # Checkpoint
    if [[ -f "$r1_repaired" && -f "$r2_repaired" ]]; then
        log_info "${sample_name}: 이미 복구된 파일이 존재합니다. 건너뜁니다."
        echo "${r1_repaired} ${r2_repaired}"
        return 0
    fi

    conda run -n "$BBMAP_ENV" repair.sh \
        in1="$r1_in" in2="$r2_in" \
        out1="$r1_repaired" out2="$r2_repaired" \
        repair >&2
        
    log_info "${sample_name}: 파일 페어링 복구 완료."
    echo "${r1_repaired} ${r2_repaired}"
}
#--- MEGAHIT Assembly Function (Checkpoint 기능 강화) ---
run_megahit() {
    local sample_name=$1; local r1_qc=$2; local r2_qc=$3; local assembly_out_dir=$4; local preset_option=$5; local memory_gb=$6;
    local min_contig_len=$7; local threads=$8; local extra_opts="${9:-}"
    
    # ✨✨ 해결책: 함수가 시작될 때 출력 폴더를 직접 생성합니다. ✨✨
#    mkdir -p "$assembly_out_dir"
    
    local final_assembly_file="${assembly_out_dir}/final.contigs.fa"
    local checkpoint_file="${assembly_out_dir}/checkpoints.txt"

    # 1. 최종 결과 파일이 있으면, 성공으로 간주하고 완전히 건너뜀
    if [[ -f "$final_assembly_file" ]]; then
        log_info "MEGAHIT for ${sample_name} already completed. Skipping."
        echo "$final_assembly_file"
        return 0
    fi

    # 2. 최종 결과는 없지만, 중간 체크포인트 파일이 있으면 --continue 옵션으로 재개
    if [[ -f "$checkpoint_file" ]]; then
        log_info "${sample_name}: Found MEGAHIT checkpoint file. Resuming with --continue option..."
        conda run -n "$MEGAHIT_ENV" megahit --continue -o "$assembly_out_dir" -t "$threads" $extra_opts
    else
        # 3. 아무 결과도 없으면, 처음부터 새로 시작
        # (기존에 불완전한 폴더가 남아있는 경우를 대비해 한번 삭제)
        if [[ -d "$assembly_out_dir" ]]; then
            log_warn "Incomplete MEGAHIT output directory found without a checkpoint. Removing and starting fresh."
            rm -rf "$assembly_out_dir"
        fi
        
        log_info "${sample_name}: Starting MEGAHIT assembly with preset option ('${preset_option}')..."
        conda run -n "$MEGAHIT_ENV" megahit \
            -1 "$r1_qc" -2 "$r2_qc" \
            -o "$assembly_out_dir" \
            --presets "$preset_option" \
            --min-contig-len "$min_contig_len" \
            -t "$threads" -m "$((memory_gb * 1000000000))" $extra_opts
    fi
        
    if [[ -f "$final_assembly_file" ]]; then
        echo "$final_assembly_file"
    else
        log_warn "MEGAHIT for ${sample_name} failed."
        return 1
    fi
}

#--- Kraken2 on Contigs Function ---
run_kraken2_on_contigs() {
    local sample_name=$1; local assembly_file=$2; local kraken_out_dir=$3; local kraken_db=$4; local threads=$5; local extra_opts="${6:-}"
    
    mkdir -p "$kraken_out_dir"
    
    local k2_report="${kraken_out_dir}/${sample_name}_contigs.k2report"
   
    # Checkpoint: 최종 리포트 파일 확인
    if [[ -f "$k2_report" ]]; then
        log_info "Kraken2 on contigs for ${sample_name} exists. Skipping."
        return 0
    fi
    log_info "${sample_name}: Running Kraken2 on assembled contigs..."
    conda run -n "$KRAKEN_ENV" kraken2 --db "$kraken_db" --threads "$threads" \
        --report "$k2_report" "$assembly_file" $extra_opts > "${kraken_out_dir}/${sample_name}_contigs.kraken2"
}

#--- Bakta Annotation Function for Contigs (출력 경로 수정) ---
run_bakta_for_contigs() {
    local sample_name=$1; local assembly_dir=$2; local out_dir=$3; local bakta_db_path=$4; local tmp_dir=$5; local extra_opts="${6:-}"
    
    log_info "${sample_name}: Running Bakta annotation on assembled contigs..."
#    mkdir -p "$out_dir"
    
    local contig_file="${assembly_dir}/final.contigs.fa"
    local final_gff_file="${out_dir}/${sample_name}.gff3"

    if [[ ! -f "$contig_file" ]]; then
        log_warn "Assembly file not found for Bakta. Skipping."
        return 1
    fi

    if [[ -f "$final_gff_file" ]]; then
        log_info "Bakta annotation for contigs of ${sample_name} already exists. Skipping."
        return 0
    fi

#    # --- 변경점: 최종 결과 파일 경로를 샘플 디렉토리 바로 아래로 지정 ---
#    local final_gff_file="${out_dir}/${sample_name}.gff3"
#
#    # Checkpoint: 최종 gff3 파일이 있는지 확인
#    if [[ -f "$final_gff_file" ]]; then
#        log_info "Bakta annotation for contigs of ${sample_name} already exists. Skipping."
#        return 0
#    fi
    
    local bakta_options=("--threads" "$THREADS" "--meta" "--skip-plot" "--tmp-dir" "$tmp_dir")
    if [[ -n "$bakta_db_path" ]]; then
        bakta_options+=(--db "$bakta_db_path")
    fi
    # 최종 파일은 없지만 폴더가 있는 경우(중단된 경우) --force 옵션 추가
    if [[ -d "$out_dir" ]]; then
        log_info "Previous incomplete output found. Overwriting..."
        bakta_options+=(--force)
    fi

#    conda run -n "$BAKTA_ENV" bakta \
#        --output "$out_dir" \
#        --prefix "$sample_name" \
#        "${bakta_options[@]}" \
#        $extra_opts \
#        "$contig_file"

    # [수정 3] Conda Activate 방식 적용 (Conda 경로 자동 탐지)
    (
        # 현재 실행 중인 Conda의 기본 경로를 찾음
        CONDA_BASE=$(conda info --base)
        
        # conda.sh를 source하여 activate 명령어 활성화
        if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
            source "${CONDA_BASE}/etc/profile.d/conda.sh"
        else
            # 혹시 경로가 다를 경우를 대비한 예비책
            source ~/anaconda3/etc/profile.d/conda.sh 2>/dev/null || source ~/miniconda3/etc/profile.d/conda.sh
        fi

        conda activate "$BAKTA_ENV"
        
        # Bakta 실행 (옵션 순서 정리)
        bakta \
            --output "$out_dir" \
            --prefix "$sample_name" \
            "${bakta_options[@]}" \
            $extra_opts \
            "$contig_file"
    )
}

#--- Bakta Annotation Function for MAGs (Checkpoint 강화 버전) ---
run_bakta_for_mags() {
    local sample_name=$1; local bins_dir=$2; local out_dir=$3; local bakta_db_path=$4; local tmp_dir=$5; local extra_opts="${6:-}"
    
    # === [설정] 동시 실행할 Bakta 개수 ===
    # (주의: Bakta 하나당 메모리를 꽤 쓰므로 2~4개 추천)
    local MAX_BAKTA_JOBS=4 
    
    # 전체 스레드를 작업 수로 나누기
    local THREADS_PER_BAKTA=$(( THREADS / MAX_BAKTA_JOBS ))
    if [[ "$THREADS_PER_BAKTA" -lt 1 ]]; then THREADS_PER_BAKTA=1; fi

    log_info "${sample_name}: Running Bakta annotation on MAGs (Parallel: $MAX_BAKTA_JOBS jobs)..."

    mkdir -p "$out_dir"
    local checkpoint_file="${out_dir}/bakta_checkpoint.txt"

    # 이미 전체 완료되었는지 확인
    if [[ -f "$checkpoint_file" ]] && grep -Fxq "done" "$checkpoint_file"; then
        log_info "All MAGs for ${sample_name} have already been annotated. Skipping."
        return 0
    fi
    touch "$checkpoint_file"
    
    local total_bins=$(ls -1 "${bins_dir}"/*.fa 2>/dev/null | wc -l)
    if [[ "$total_bins" -eq 0 ]]; then
        log_warn "No bins found in ${bins_dir}. Marking as complete."
        echo "done" > "$checkpoint_file"
        return 0
    fi

    # --- 병렬 루프 시작 ---
    for bin_file in "${bins_dir}"/*.fa; do
        if [[ ! -f "$bin_file" ]]; then continue; fi
        
        local base_name=$(basename "$bin_file" .fa)
        
        # 이미 완료된 Bin은 건너뜀
        if grep -Fxq "$base_name" "$checkpoint_file"; then continue; fi

        # 이미 '실행 중'인 Bin 건너 뜀 (중복 실행 방지)
        local processing_flag="${out_dir}/${base_name}.processing"
        if [[ -f "$processing_flag" ]]; then
            continue
        fi

        local bakta_output_subdir="${out_dir}/${base_name}"
        local final_gff_file="${bakta_output_subdir}/${base_name}.gff3"
        
        local bakta_options=("--threads" "$THREADS_PER_BAKTA" "--skip-plot" "--tmp-dir" "$tmp_dir")
        if [[ -n "$bakta_db_path" ]]; then bakta_options+=(--db "$bakta_db_path"); fi
        if [[ -d "$bakta_output_subdir" && ! -f "$final_gff_file" ]]; then bakta_options+=(--force); fi
        
        # [핵심] Job Limiter: 실행 중인 작업이 꽉 찼으면 대기
        while [ $(jobs -r | wc -l) -ge "$MAX_BAKTA_JOBS" ]; do sleep 5; done
        
        # 실행 시작 표시 
        touch "$processing_flag"

        # [핵심] 백그라운드(&)로 실행
        (
            log_info "  [Start] Annotating MAG: ${base_name}"
            if conda run -n "$BAKTA_ENV" bakta --output "$bakta_output_subdir" --prefix "$base_name" "${bakta_options[@]}" "$bin_file" $extra_opts > /dev/null 2>&1; then
                echo "$base_name" >> "$checkpoint_file"
            else
                log_warn "  [Fail] Bakta annotation failed for ${base_name}."
            fi

            # 작업 종료 후 깃발 제거
            rm -f "$processing_flag"
        ) & 

    done
    
    # --- 모든 작업이 끝날 때까지 대기 ---
    wait
    
    # 완료 표시
    log_info "Finished annotating all MAGs for ${sample_name}."
    echo "done" >> "$checkpoint_file"
}

#run_bakta_for_mags() {
#    local sample_name=$1; local bins_dir=$2; local out_dir=$3; local bakta_db_path=$4; local tmp_dir=$5; local extra_opts="${6}"
#    log_info "${sample_name}: Running Bakta annotation on final MAGs..."#
#
#    mkdir -p "$out_dir"
#
#    local checkpoint_file="${out_dir}/bakta_checkpoint.txt"
#
#    # --- ✨ 1. 최종 완료 여부 우선 확인 ---
#    # checkpoint 파일에 'done'이라는 완료 표시가 있으면, 더 이상 확인하지 않고 즉시 건너뜁니다.
#    if [[ -f "$checkpoint_file" ]] && grep -Fxq "done" "$checkpoint_file"; then
#        log_info "All MAGs for ${sample_name} have already been annotated by Bakta (found 'done' marker). Skipping."
#        return 0
#    fi
#    
#    # checkpoint 파일이 없으면 새로 생성합니다.
#    touch "$checkpoint_file"
#    
#    # 처리할 bin 파일이 하나도 없는 경우를 대비
#    local total_bins=$(ls -1 "${bins_dir}"/*.fa 2>/dev/null | wc -l)
#    if [[ "$total_bins" -eq 0 ]]; then
#        log_warn "No bins found in ${bins_dir} to annotate. Marking as complete and skipping."
#        echo "done" > "$checkpoint_file"
#        return 0
#    fi
#
#    # 3. 각 Bin 파일에 대해 반복 작업 수행
#    for bin_file in "${bins_dir}"/*.fa; do
#        if [[ ! -f "$bin_file" ]]; then continue; fi
#        
#        local base_name=$(basename "$bin_file" .fa)
#        
#        # --- ✨ 2. 'done' 표시가 없을 경우, 개별 Bin 완료 여부 확인 ---
#        # checkpoint 파일에서 현재 bin 이름이 있는지 확인하고, 있으면 건너뜁니다.
#        if grep -Fxq "$base_name" "$checkpoint_file"; then
#            continue
#        fi
#
#        local bakta_output_subdir="${out_dir}/${base_name}"
#        local final_gff_file="${bakta_output_subdir}/${base_name}.gff3"
#        
#        local bakta_options=("--threads" "$THREADS" "--skip-plot" "--tmp-dir" "$tmp_dir")
#        if [[ -n "$bakta_db_path" ]]; then
#            bakta_options+=(--db "$bakta_db_path")
#        fi
#        if [[ -d "$bakta_output_subdir" && ! -f "$final_gff_file" ]]; then
#            log_warn "Incomplete Bakta output for ${base_name}. Re-running with --force."
#            bakta_options+=(--force)
#        fi
#        
#        log_info "  - Annotating MAG: ${base_name}..."
#        if conda run -n "$BAKTA_ENV" bakta --output "$bakta_output_subdir" --prefix "$base_name" "${bakta_options[@]}" "$bin_file" $extra_opts; then
#            echo "$base_name" >> "$checkpoint_file"
#        else
#            log_warn "Bakta annotation failed for ${base_name}."
#        fi
#    done
#    
#    # --- ✨ 3. 모든 작업 완료 후 'done' 표식 기록 ---
#    # for 루프가 성공적으로 모두 끝나면, checkpoint 파일 마지막에 'done'을 추가합니다.
#    log_info "Finished annotating all MAGs for ${sample_name}. Marking as complete."
#    echo "done" >> "$checkpoint_file"
# }

#--- MetaWRAP Pipeline Function for a single sample ---
run_metawrap_sample() {
    local sample_name=$1
    local assembly_file=$2
    local r1_repaired_gz=$3
    local r2_repaired_gz=$4
    local metawrap_sample_dir=$5
    local min_completeness=$6  
    local max_contamination=$7
    local binning_extra_opts="${8:-}"
    local refinement_extra_opts="${9:-}"

    local final_bins_dir="${metawrap_sample_dir}/bin_refinement/metawrap_${min_completeness}_${max_contamination}_bins"
    
#    if [[ -d "$final_bins_dir" ]]; then
#        log_info "${sample_name}: MetaWRAP pipeline already completed. Skipping."
#        return 0
#    fi

    if [[ -d "$final_bins_dir" && -n "$(ls -A "$final_bins_dir" 2>/dev/null)" ]]; then
        log_info "${sample_name}: MetaWRAP pipeline already completed (Bins found). Skipping."
        return 0
    fi

    local read_qc_dir="${metawrap_sample_dir}/read_qc"
    local temp_uncompressed_dir="${metawrap_sample_dir}/temp_uncompressed_reads"

    # 1. pigz를 사용하여 복구된 파일을 MetaWRAP용으로 압축 해제
    mkdir -p "$temp_uncompressed_dir"
    local r1_uncompressed="${temp_uncompressed_dir}/${sample_name}_1.repaired.fastq"
    local r2_uncompressed="${temp_uncompressed_dir}/${sample_name}_2.repaired.fastq"

    log_info "${sample_name}: Decompressing repaired reads with pigz for MetaWRAP..."
    pigz -dc "$r1_repaired_gz" > "$r1_uncompressed"
    pigz -dc "$r2_repaired_gz" > "$r2_uncompressed"

    # 2. 압축 해제된 파일로 metawrap read_qc 수행
    if [[ ! -d "$read_qc_dir" || -z "$(ls -A "$read_qc_dir")" ]]; then
        log_info "${sample_name}: Running MetaWRAP read_qc module (Pairing Check)..."
        conda run -n "$METAWRAP_ENV" metawrap read_qc \
            -1 "$r1_uncompressed" -2 "$r2_uncompressed" \
            -t "$THREADS" -o "$read_qc_dir" \
            --skip-bmtagger --skip-pre-qc-report --skip-post-qc-report --skip-trimming
    else
        log_info "${sample_name}: MetaWRAP read_qc results found. Skipping."
    fi
    
    # Read QC가 끝나면 임시 압축 해제 파일 삭제
    log_info "${sample_name}: Cleaning up temporary uncompressed read files..."
    rm -rf "$temp_uncompressed_dir"

    # 3. Binning
    local initial_bins_dir="${metawrap_sample_dir}/binning"
    if [[ ! -d "${initial_bins_dir}/concoct_bins" ]]; then
        log_info "${sample_name}: Running MetaWRAP binning module..."
        conda run -n "$METAWRAP_ENV" metawrap binning -o "$initial_bins_dir" -t "$THREADS" -a "$assembly_file" --metabat2 --maxbin2 --concoct $binning_extra_opts "${read_qc_dir}/"*.fastq 
    else
        log_info "${sample_name}: MetaWRAP binning results found. Skipping."
    fi

    # 4. Bin Refinement
    log_info "${sample_name}: Running MetaWRAP bin_refinement module..."
    conda run -n "$METAWRAP_ENV" metawrap bin_refinement -o "${metawrap_sample_dir}/bin_refinement" -t "$THREADS" \
        -A "${initial_bins_dir}/metabat2_bins/" -B "${initial_bins_dir}/maxbin2_bins/" \
        -C "${initial_bins_dir}/concoct_bins/" -c "$min_completeness" -x "$max_contamination" $refinement_extra_opts
        
    if [[ ! -d "$final_bins_dir" ]]; then
        log_warn "MetaWRAP bin_refinement failed for ${sample_name}."
        return 1
    fi
    log_info "${sample_name}: MetaWRAP pipeline completed successfully."
}

#--- GTDB-Tk Classification Function ---
run_gtdbtk() {
    local sample_name=$1; local final_bins_dir=$2; local gtdbtk_out_dir=$3; local extra_opts="${4:-}"
    
    mkdir -p "$gtdbtk_out_dir"
    
    # ✨ [수정] 체크포인트 기준을 '폴더'가 아닌 '최종 결과 파일'로 변경하여 더 엄격하게 만듭니다.
    if [[ -f "${gtdbtk_out_dir}/gtdbtk.bac120.summary.tsv" || -f "${gtdbtk_out_dir}/gtdbtk.ar53.summary.tsv" ]]; then 
        log_info "GTDB-Tk for ${sample_name} exists. Skipping."
        return 0
    fi
    
    if [ -z "$(ls -A "$final_bins_dir" 2>/dev/null)" ]; then 
        log_warn "No bins found for ${sample_name}. Skipping GTDB-Tk."
        return 1
    fi
    
    log_info "${sample_name}: Running GTDB-Tk classification ...";
    
    # 이전에 불완전하게 생성된 결과 폴더가 있다면 삭제하고 새로 시작합니다.
    if [ -d "${gtdbtk_out_dir}/classify" ]; then
        log_warn "Incomplete GTDB-Tk output directory found. Cleaning up..."
        rm -rf "${gtdbtk_out_dir:?}"/*
    fi

    (
        # Conda 경로 자동 탐지
        CONDA_BASE=$(conda info --base)
        if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then
            source "${CONDA_BASE}/etc/profile.d/conda.sh"
        else
            source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source ~/anaconda3/etc/profile.d/conda.sh
        fi
        
        # 환경 활성화
        conda activate "$GTDBTK_ENV"
        
        # 환경변수 설정 (활성화된 쉘 내부에서)
        export GTDBTK_DATA_PATH="${GTDBTK_DATA_PATH}"
        
        # GTDB-Tk 실행
        if gtdbtk classify_wf \
            --genome_dir "${final_bins_dir}" \
            --out_dir "${gtdbtk_out_dir}" \
            --cpus "${THREADS}" \
            -x fa \
            --skip_ani_screen \
            ${extra_opts}; then
            
            log_info "GTDB-Tk finished successfully for ${sample_name}."
        else
            log_error "GTDB-Tk failed for ${sample_name}."
            exit 1
        fi
    )
    # conda run -n "$GTDBTK_ENV" bash -c "export GTDBTK_DATA_PATH='${GTDBTK_DATA_PATH}'; gtdbtk classify_wf \
    #    --genome_dir '${final_bins_dir}' \
    #    --out_dir '${gtdbtk_out_dir}' \
    #    --cpus '${THREADS}' \
    #    -x fa \
    #    --skip_ani_screen ${extra_opts}"
}

# --- Automated Pipeline Self-Test Function ---
run_pipeline_test() {
    echo "========================================"
    echo "    STARTING AUTOMATED PIPELINE TEST    "
    echo "========================================"

    # --- 1. 테스트 환경 및 데이터 설정 ---
    local test_input_dir="test/input"
    local test_sra_id="SRR8942316"
    local test_fastq_r1="${test_input_dir}/${test_sra_id}_1.fastq"
    
    mkdir -p "$test_input_dir"

    # --- 2. 테스트 데이터 다운로드 (파일이 없을 경우에만) ---
    if [[ ! -f "$test_fastq_r1" ]]; then
        log_info "Test data not found. Downloading from SRA..."
        # fastq-dump가 있는지 확인할 때도, sra-tools_env 안을 들여다보도록 수정
        if ! conda run -n sra-tools_env command -v fastq-dump &> /dev/null; then
        # 오류 메시지도 더 명확하게 수정
            log_error "sra-tools (fastq-dump) not found within the 'sra-tools_env' conda environment. Please check the installation and environment name."
            exit 1

        fi

        conda run -n sra-tools_env fastq-dump --split-files -X 500000 "$test_sra_id" -O "$test_input_dir"
        log_info "Test data download complete."
        # ✨✨ 다운로드된 파일을 gzip으로 압축하는 단계를 추가합니다. ✨✨
        log_info "Compressing downloaded test files..."
        gzip "${test_input_dir}/${test_sra_id}_1.fastq"
        gzip "${test_input_dir}/${test_sra_id}_2.fastq"
    else
        log_info "Compressed test data found. Skipping download."
    fi

    # --- 3. 이전 테스트 결과 삭제 ---
#    if [ -d "MAG_analysis" ]; then
#       log_info "Removing previous analysis directory to ensure a fresh test."
#        rm -rf "MAG_analysis"
#    fi

    # --- 4. 파이프라인 실행 ---
    # $0은 현재 실행 중인 스크립트(3_mag_per_sample.sh)를 의미합니다.
    log_info "Running pipeline in 'all' mode on test data..."
    "$0" all \
        --input_dir "$test_input_dir" \
        --gtdbtk_db_dir "$GTDBTK_DB_DIR_ARG" \
        --bakta_db_dir "$BAKTA_DB_DIR_ARG" \
        --kraken2_db "$KRAKEN2_DB_ARG" \
        --threads 4 --memory 30 \
        --min_completeness 10 --max_contamination 100 \
        --_internal_test_input_dir "$test_input_dir" # 테스트용 내부 옵션

    if [[ $? -ne 0 ]]; then
        log_error "Pipeline execution failed during the test run."
        exit 1
    fi # 테스트용 내부 옵션

    # --- 5. 결과 확인 ---
    log_info "Verifying test results..."
    local has_failed=false

    # ✨✨ 핵심 수정: 모든 예상 경로가 'test/input/MAG_analysis'를 가리키도록 수정합니다. ✨✨
    local result_dir="test/input/MAG_analysis"    
    
    declare -a expected_files=(
        "${result_dir}/01_assembly/${test_sra_id}/final.contigs.fa"
        "${result_dir}/02_assembly_stats/${test_sra_id}_assembly_stats.txt"
        "${result_dir}/03_kraken_on_contigs/${test_sra_id}/${test_sra_id}_contigs.k2report"
        "${result_dir}/04_bakta_on_contigs/${test_sra_id}/${test_sra_id}.gff3"
        "${result_dir}/05_metawrap/${test_sra_id}/bin_refinement/metawrap_10_100_bins"
        "${result_dir}/06_gtdbtk_on_mags/${test_sra_id}/gtdbtk.bac120.summary.tsv"
    )
    for f in "${expected_files[@]}"; do
        printf "  - Checking for %-70s..." "$f";
        if [[ -s "$f" || -d "$f" && -n "$(ls -A "$f")" ]]; then echo -e "\033[0;32mPASSED\033[0m"; else echo -e "\033[0;31mFAILED\033[0m"; has_failed=true; fi
    done
    
    printf "  - Checking for MAG-based Bakta .gff3 files..."
    local mag_bakta_dir="${result_dir}/07_bakta_on_mags/${test_sra_id}"
    if [[ -d "$mag_bakta_dir" && $(find "$mag_bakta_dir" -name "*.gff3" 2>/dev/null | wc -l) -gt 0 ]]; then echo -e "\033[0;32mPASSED\033[0m"; else echo -e "\033[0;31mFAILED\033[0m"; has_failed=true; fi

    # --- 6. 최종 결과 보고 ---
    echo "========================================"
    if [ "$has_failed" = true ]; then
        echo -e "\033[0;31m    TEST FAILED. Please check the logs.\033[0m"; exit 1
    else
        echo -e "\033[0;32m    ALL TESTS PASSED! The pipeline is working correctly.\033[0m"; exit 0
    fi
}

#--- [Pro 3.6] EggNOG Annotation for Contigs (Default Strategy) ---
run_eggnog_on_contigs() {
    local sample_name=$1; local assembly_file=$2; local out_dir=$3; local eggnog_db_path=$4; local extra_opts="${5:-}"; local summary_csv="${6:-}"
    
    log_info "${sample_name}: Running EggNOG-mapper on Contigs..."
    mkdir -p "$out_dir"
    
    local protein_file="${out_dir}/${sample_name}.faa"
    local gene_file="${out_dir}/${sample_name}.ffn"
    local gff_file="${out_dir}/${sample_name}.gff"
    local eggnog_output_prefix="${out_dir}/${sample_name}"

    # Checkpoint
    if [[ -f "${eggnog_output_prefix}.emapper.annotations" ]]; then
        echo "[INFO] EggNOG annotation for ${sample_name} already exists. Skipping." >> "$LOG_FILE"
        return 0
    fi

    # 1. Prodigal 실행 (유전자/단백질 서열 추출)
    # (Bakta 환경엔 prodigal 바이너리가 없을 수 있으므로 GTDBTK_ENV 사용)
    if [[ ! -f "$protein_file" ]]; then
        # log_info "  [Prodigal] Predicting genes..."
        conda run -n "$GTDBTK_ENV" prodigal \
            -i "$assembly_file" \
            -a "$protein_file" \
            -d "$gene_file" \
            -o "$gff_file" \
            -f gff \
            -p meta -q > /dev/null 2>&1
    fi

    # 2. EggNOG-mapper 실행
    # log_info "  [EggNOG] Annotating proteins..."
    (
        CONDA_BASE=$(conda info --base)
        if [ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]; then source "${CONDA_BASE}/etc/profile.d/conda.sh"; else source ~/miniconda3/etc/profile.d/conda.sh; fi
        conda activate "$EGGNOG_ENV"
        
        # 화면 출력 방지를 위해 로그 파일로 리다이렉션 (>> "$LOG_FILE" 2>&1)
        emapper.py -i "$protein_file" \
            --output "$sample_name" \
            --output_dir "$out_dir" \
            --data_dir "$eggnog_db_path" \
            -m diamond --itype proteins --cpu "$THREADS" \
            --metagenome \
            --go_evidence non-electronic \
            --tax_scope auto \
            --override $extra_opts >> "$LOG_FILE" 2>&1
    )
    
    log_info "${sample_name}: EggNOG annotation finished."

# 3. 주석 비율 검증
    check_annotation_ratio "$sample_name" "$protein_file" "$annotation_file"
}

# --- [내부 함수] 주석 비율 계산기 (유지) ---
check_annotation_ratio() {
    local sample=$1; local prot_file=$2; local annot_file=$3
    
    if [[ -f "$prot_file" && -f "$annot_file" ]]; then
        local total_genes=$(grep -c "^>" "$prot_file")
        local annotated_genes=$(grep -v "^#" "$annot_file" | wc -l)
        
        if [ "$total_genes" -gt 0 ]; then
            local ratio=$(awk -v a="$annotated_genes" -v t="$total_genes" 'BEGIN {printf "%.2f", (a/t)*100}')
            local msg="${sample}: Functional Annotation Ratio = ${ratio}% ($annotated_genes / $total_genes)"
            
            if (( $(echo "$ratio >= 80.0" | bc -l) )); then
                log_info "[PASS] $msg (>= 80%)"
            else
                log_warn "[LOW-QUAL] $msg (< 80% - Check assembly quality)"
            fi

            if [[ -n "$csv_file" ]]; then
                # 중복 기록 방지 (이미 해당 샘플이 있으면 덮어쓰지 않고 넘어감, 혹은 grep으로 체크)
                if ! grep -q "^${sample}," "$csv_file"; then
                    echo "${sample},${total_genes},${annotated_genes},${ratio},${status}" >> "$csv_file"
                fi
            fi
        fi
    fi
}