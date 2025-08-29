create_summary_report() {
    local output_dir=$1
    local report_file="${output_dir}/summary_report.html"
    local p1_dir="${output_dir}/1_microbiome_taxonomy"
    local p2_dir="${output_dir}/2_mag_analysis"
    
    log_info "Creating HTML summary report..."

    # --- HTML Header ---
    cat > "$report_file" <<- EOL
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>Dokkaebi Pipeline Summary Report</title>
        <style>
            body { font-family: sans-serif; margin: 2em; }
            h1, h2 { color: #2c3e50; }
            .container { max-width: 800px; margin: auto; }
            .card { border: 1px solid #ddd; border-radius: 5px; padding: 1em; margin-bottom: 1em; }
            a { color: #3498db; text-decoration: none; }
        </style>
    </head>
    <body>
    <div class="container">
        <h1>Dokkaebi Pipeline Summary</h1>
        <p><b>Execution Date:</b> $(date)</p>
EOL

    # --- Pipeline 1 Summary ---
    echo "<h2>Pipeline 1: QC & Taxonomy</h2>" >> "$report_file"
    echo "<div class='card'>" >> "$report_file"
    if [ -d "$p1_dir" ]; then
        local summary_tsv="${p1_dir}/profile_analysis/kraken2_summary.tsv"
        local merged_bracken="${p1_dir}/profile_analysis/05_bracken_merged/merged_S.tsv"
        echo "<h3>Key Outputs:</h3><ul>" >> "$report_file"
        echo "<li><a href='file://${p1_dir}'>Main QC/Taxonomy Directory</a></li>" >> "$report_file"
        if [ -f "$summary_tsv" ]; then echo "<li><a href='file://${summary_tsv}'>Kraken2 Summary TSV</a></li>" >> "$report_file"; fi
        if [ -f "$merged_bracken" ]; then echo "<li><a href='file://${merged_bracken}'>Bracken Merged Species Table</a></li>" >> "$report_file"; fi
        echo "</ul>" >> "$report_file"
    else
        echo "<p>Pipeline 1 was not run or results are not available.</p>" >> "$report_file"
    fi
    echo "</div>" >> "$report_file"

    # --- Pipeline 2 Summary ---
    echo "<h2>Pipeline 2: MAG Analysis</h2>" >> "$report_file"
    echo "<div class='card'>" >> "$report_file"
    if [ -d "$p2_dir" ]; then
        echo "<h3>Key Outputs:</h3><ul>" >> "$report_file"
        echo "<li><a href='file://${p2_dir}'>Main MAG Analysis Directory</a></li>" >> "$report_file"
        
        for summary_file in "${p2_dir}/06_gtdbtk_on_mags"/*/gtdbtk.*.summary.tsv; do
            if [ -f "$summary_file" ]; then
                local sample_name=$(basename "$(dirname "$summary_file")")
                echo "<li><a href='file://${summary_file}'>GTDB-Tk Summary for ${sample_name}</a></li>" >> "$report_file"
            fi
        done

        echo "<li><a href='file://${p2_dir}/07_bakta_on_mags'>Final Annotated MAGs (Bakta)</a></li>" >> "$report_file"
        echo "</ul>" >> "$report_file"
    else
        echo "<p>Pipeline 2 was not run or results are not available.</p>" >> "$report_file"
    fi
    echo "</div>" >> "$report_file"

    # --- HTML Footer ---
    echo "</div></body></html>" >> "$report_file"

    log_info "HTML report created: ${report_file}"
}
