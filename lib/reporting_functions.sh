#!/bin/bash
#================================================
# REPORTING FUNCTIONS (Advanced Dashboard Style - Workflow Order)
#================================================

# --- CSV/TSV 파일을 HTML 테이블로 변환하는 헬퍼 함수 ---
file_to_html_table() {
    local file=$1
    local delim=$2
    
    if [ ! -f "$file" ]; then
        echo "<p class='text-muted'>No data available ($file)</p>"
        return
    fi

    echo "<div class='table-responsive'><table class='table table-hover table-bordered'>"
    
    # Header 처리
    echo "<thead><tr>"
    head -n 1 "$file" | awk -F"$delim" '{for(i=1;i<=NF;i++) print "<th>"$i"</th>"}'
    echo "</tr></thead>"
    
    # Body 처리 (PASS/FAIL 색상 강조 기능 추가 - EggNOG Status 기준)
    echo "<tbody>"
    tail -n +2 "$file" | awk -F"$delim" '{
        print "<tr>"
        for(i=1;i<=NF;i++) {
            # 상태에 따른 색상 강조 로직 (EggNOG Summary CSV의 5번째 필드 기준)
            if (i == 5 && $i ~ /PASS/) print "<td><span class=\"badge bg-success\">"$i"</span></td>"
            else if (i == 5 && $i ~ /LOW-QUAL|WARN/) print "<td><span class=\"badge bg-warning\">"$i"</span></td>"
            else if (i == 5 && $i ~ /FAIL|ERROR/) print "<td><span class=\"badge bg-danger\">"$i"</span></td>"
            else print "<td>"$i"</td>"
        }
        print "</tr>"
    }'
    echo "</tbody></table></div>"
}

create_summary_report() {
    local output_dir=$1
    local report_file="${output_dir}/summary_report.html"
    local p1_dir="${output_dir}/1_microbiome_taxonomy"
    local p2_dir="${output_dir}/2_mag_analysis"
    
    if command -v log_info &> /dev/null; then
        log_info "Creating Advanced HTML summary report (Workflow Order)..."
    fi

    # --- 1. HTML Head & CSS (Bootstrap 5 CDN 사용) ---
    cat > "$report_file" <<- EOL
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dokkaebi Pipeline Report</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background-color: #f8f9fa; padding-top: 20px; }
        .header { background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); color: white; padding: 2rem 0; margin-bottom: 2rem; border-radius: 0 0 10px 10px; }
        .card { margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); border: none; }
        .card-header { background-color: #fff; border-bottom: 2px solid #f0f0f0; font-weight: bold; font-size: 1.1rem; color: #333; }
        .table th { background-color: #f1f3f5; font-weight: 600; }
        .badge { font-size: 0.9em; }
        .footer { text-align: center; margin-top: 3rem; color: #6c757d; font-size: 0.9rem; }
    </style>
</head>
<body>

<div class="container">
    <div class="header text-center rounded">
        <h1 class="display-4 fw-bold">👹 Dokkaebi Pipeline Report</h1>
        <p class="lead">Metagenome Analysis Summary</p>
        <p class="small">Generated on: $(date)</p>
    </div>

    <div class="card">
        <div class="card-header">📋 1. Reads QC & Host Filtering Summary</div>
        <div class="card-body">
            <p>Summary of host removal and quality trimming steps (KneadData/Fastp/MultiQC). Check the MultiQC link below for detailed quality metrics.</p>
EOL
            # QC Summary 테이블 임베딩 (KneadData_QC_Summary.csv 가정)
            local qc_summary_csv="${p1_dir}/KneadData_QC_Summary.csv"
            if [ -f "$qc_summary_csv" ]; then
                # CSV 파일 변환 (구분자: ,)
                file_to_html_table "$qc_summary_csv" "," >> "$report_file"
            else
                echo "<div class='alert alert-warning'>KneadData QC Summary not found. (Check QC pipeline execution)</div>" >> "$report_file"
            fi
    cat >> "$report_file" <<- EOL
        </div>
    </div>

    <div class="card">
        <div class="card-header">📊 2. Reads Classification Summary (Kraken2 & Bracken)</div>
        <div class="card-body">
            <p>Summary of read classification rates using Kraken2 and the final consolidated Bracken output.</p>
EOL
            # Kraken2 Read 요약 테이블 임베딩
            local kraken_summary="${p1_dir}/kraken2_summary.tsv"
            if [ -f "$kraken_summary" ]; then
                echo "<h6>2.1. Kraken2 Reads Classification Rate</h6>" >> "$report_file"
                file_to_html_table "$kraken_summary" "\t" >> "$report_file"
            else
                echo "<div class='alert alert-warning'>Kraken2 Read summary not found.</div>" >> "$report_file"
            fi
            
            local bracken_merged="${p1_dir}/05_bracken_merged/merged_S.tsv"
            if [ -f "$bracken_merged" ]; then
                echo "<h6>2.2. Bracken Consolidated Output (Input for R Analysis)</h6>" >> "$report_file"
                echo "<p class='text-muted'>The file <code>merged_S.tsv</code> is the primary input for diversity analysis (R/Phyloseq).</p>" >> "$report_file"
                echo "<a href=\"${p1_dir}/05_bracken_merged/\" class=\"btn btn-sm btn-info\">View Bracken Merged Directory</a>" >> "$report_file"
            fi

    cat >> "$report_file" <<- EOL
        </div>
    </div>
    
    <div class="card">
        <div class="card-header">🔬 3. Contig Classification Summary (Kraken2 on Assembly)</div>
        <div class="card-body">
            <p>Summary of taxonomic classification rates on assembled contigs (Checking assembly quality).</p>
EOL
            # Kraken2 Contig 요약 테이블 임베딩
            local kraken_contig_summary="${p2_dir}/kraken2_contigs_summary.tsv"
            if [ -f "$kraken_contig_summary" ]; then
                file_to_html_table "$kraken_contig_summary" "\t" >> "$report_file"
            else
                echo "<div class='alert alert-warning'>Kraken2 Contig summary not found. (Run MAG pipeline first)</div>" >> "$report_file"
            fi
    cat >> "$report_file" <<- EOL
        </div>
    </div>

    <div class="card">
        <div class="card-header">🦠 4. MAG Statistics (GTDB-Tk)</div>
        <div class="card-body">
            <p>Taxonomic classification and quality assessment of recovered Metagenome-Assembled Genomes (MAGs).</p>
            <div class="accordion" id="accordionMAG">
EOL
            # GTDB-Tk 결과 (MAG 개수 포함)
            local gtdb_dir="${p2_dir}/06_gtdbtk_on_mags"
            local count=0
            if [ -d "$gtdb_dir" ]; then
                for summary in "$gtdb_dir"/*/gtdbtk.*.summary.tsv; do
                    if [ -f "$summary" ]; then
                        count=$((count+1))
                        local sample_id=$(basename "$(dirname "$summary")")
                        
                        # MAG 개수 계산 (헤더 제외한 줄 수)
                        local mag_count=$(awk 'NR>1 {print $0}' "$summary" | wc -l)

                        # Accordion Header에 MAG 개수 포함
                        echo "<div class='accordion-item'><h2 class='accordion-header'><button class='accordion-button collapsed' type='button' data-bs-toggle='collapse' data-bs-target='#collapse$count'>Sample: $sample_id (Recovered MAGs: $mag_count)</button></h2>" >> "$report_file"
                        
                        echo "<div id='collapse$count' class='accordion-collapse collapse' data-bs-parent='#accordionMAG'><div class='accordion-body'>" >> "$report_file"
                        
                        # TSV 테이블 변환 (Completeness/Contamination 포함)
                        file_to_html_table "$summary" "\t" >> "$report_file"
                        
                        echo "</div></div></div>" >> "$report_file"
                    fi
                done
            fi
            
            if [ "$count" -eq 0 ]; then
                 echo "<div class='alert alert-info'>No MAGs classified yet. (Binning/Refinement may be skipped or failed)</div>" >> "$report_file"
            fi
    cat >> "$report_file" <<- EOL
            </div>
        </div>
    </div>

    <div class="card">
        <div class="card-header">🧬 5. Functional Annotation QC (EggNOG/Bakta)</div>
        <div class="card-body">
            <p>Quality check for gene prediction and functional annotation on Contigs/MAGs.</p>
EOL
            # EggNOG QC 요약 테이블 임베딩
            local eggnog_summary="${p2_dir}/eggnog_annotation_summary.csv"
            if [ -f "$eggnog_summary" ]; then
                file_to_html_table "$eggnog_summary" "," >> "$report_file"
            else
                echo "<div class='alert alert-secondary'>Annotation summary not found (or not running).</div>" >> "$report_file"
            fi
    cat >> "$report_file" <<- EOL
        </div>
    </div>

    <div class="card">
        <div class="card-header">📁 6. Output Directories</div>
        <div class="card-body">
            <ul class="list-group list-group-flush">
                <li class="list-group-item"><a href="./1_microbiome_taxonomy/" target="_blank">📂 1_microbiome_taxonomy (QC & Reads Taxonomy Results)</a></li>
                <li class="list-group-item"><a href="./2_mag_analysis/" target="_blank">📂 2_mag_analysis (Assembly, Binning & MAGs Results)</a></li>
                <li class="list-group-item"><a href="./2_mag_analysis/07_bakta_on_mags/" target="_blank">📂 Final MAG Annotations (Bakta)</a></li>
                <li class="list-group-item"><a href="./1_microbiome_taxonomy/06_multiqc_report/multiqc_report_post_qc.html" target="_blank">📄 MultiQC Post-QC Report (QC 상세 결과)</a></li>
            </ul>
        </div>
    </div>

    <div class="footer">
        <p>Generated by Dokkaebi Pipeline v3.9 | Developed for Metagenome Analysis</p>
    </div>

</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOL
}

if command -v log_info &> /dev/null; then
    log_info "Reporting functions loaded."
fi