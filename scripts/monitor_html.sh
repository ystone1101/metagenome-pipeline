#!/bin/bash

# ==============================================================================
# 1. 설정 (경로 확인 필수!)
# ==============================================================================
BASE_DIR="/data/CDC_2024ER110301/results"
RAW_DATA_DIR="/data/CDC_2024ER110301/raw_data"
WEB_DIR="${BASE_DIR}/web_monitor/Dokkaebi_Pipeline/Monitor_V2"

QC_SCRIPT="/home/dnalink/Desktop/GDM/metagenome-pipeline/lib/generate_qc_report.py"
LOG_DIR="${BASE_DIR}/1_microbiome_taxonomy/logs/kneaddata_logs/"
QC_OUTPUT_CSV="${BASE_DIR}/1_microbiome_taxonomy/qc_summary.csv"
KRAKEN_SUMMARY="${BASE_DIR}/1_microbiome_taxonomy/kraken2_summary.tsv"

PLOT_SCRIPT="${WEB_DIR}/generate_plots.py"
PLOT_LOG="${WEB_DIR}/plot_debug.log"

mkdir -p "$WEB_DIR"

# ==============================================================================
# 2. Python Script (원본 수치 기반 시각화 + 여백 완전 제거 📏)
# ==============================================================================
cat <<'PY_EOF' > "$PLOT_SCRIPT"
import sys, os
import matplotlib
matplotlib.use('Agg')
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

if len(sys.argv) < 5: sys.exit(1)
qc_file, kraken_file, output_dir, global_total = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

# 기본 설정
COLOR_BG_DARK = '#1e1e1e'
COLOR_PASS, COLOR_WARN, COLOR_FAIL, COLOR_EMPTY = '#00e676', '#ff9100', '#ff1744', '#333333'

def draw_gauge(ax, title, count, total, color):
    if total == 0: total = 1
    val_pct = count / total
    # 데이터 비중 조절 (반원 형태 유지)
    data = [count, total - count, total]
    colors = [color, COLOR_EMPTY, (0,0,0,0)]
    
    # radius를 줄여서 겹침 방지 (1.5 -> 1.2)
    ax.pie(data, radius=2.0, colors=colors, startangle=180, counterclock=False, 
           wedgeprops=dict(width=0.4, edgecolor=COLOR_BG_DARK))
    
    # 텍스트 위치 세밀 조정
    ax.text(0, -0.05, f"{count}/{total}", ha='center', va='center', fontsize=16, color='white', fontweight='bold')
    ax.text(0, -0.5, f"({val_pct:.1%})", ha='center', va='center', fontsize=11, color='#aaa')
    ax.text(0, 0.7, title, ha='center', va='center', fontsize=20, fontweight='bold', color=color)
    ax.set_aspect('equal')

try:
    # 1. QC Status (다크 배경 유지, 겹침 해결)
    if os.path.exists(qc_file):
        df = pd.read_csv(qc_file)
        notes = df['QC_Note'].fillna("").astype(str).str.replace(r'\([^)]*\)', '', regex=True)
        notes = notes.str.replace(r'[;,]', ' ', regex=True).str.lower()

        fig, axes = plt.subplots(2, 2, figsize=(12, 6), facecolor=COLOR_BG_DARK)
        draw_gauge(axes[0,0], "Pass", notes.str.contains('pass').sum(), global_total, COLOR_PASS)
        draw_gauge(axes[0,1], "Low Paired", notes.str.contains('low paired').sum(), global_total, COLOR_WARN)
        draw_gauge(axes[1,0], "High Host", notes.str.contains('high host').sum(), global_total, COLOR_WARN)
        draw_gauge(axes[1,1], "Small File", notes.str.contains('small file').sum(), global_total, COLOR_FAIL)
        
        plt.subplots_adjust(hspace=0.3, wspace=0.1, top=0.9, bottom=0.1, left=0.15, right=0.85)
        plt.savefig(os.path.join(output_dir, 'qc_plot.png'), dpi=300, bbox_inches='tight', pad_inches=0.1)
        plt.close()

    # 2. Taxa Box & Bar (흰색 배경으로 변경)
    if os.path.exists(kraken_file):
        df_k2 = pd.read_csv(kraken_file, sep='\t')
        
        # Taxa Box Plot
        fig, ax = plt.subplots(figsize=(8, 5), facecolor='white')
        ax.set_facecolor('white')
        bp = ax.boxplot([df_k2['Classified(%)'], df_k2['Unclassified(%)']], 
                        patch_artist=True, widths=0.5, vert=False)
        
        for patch, color in zip(bp['boxes'], ['#2ecc71', '#95a5a6']):
            patch.set_facecolor(color)
            patch.set_edgecolor('#2c3e50')
            
        ax.set_yticklabels(['Classified', 'Unclassified'], color='black', fontsize=12)
        ax.set_xlabel('Percentage (%)', color='black')
        ax.grid(axis='x', linestyle='--', alpha=0.7)
        plt.savefig(os.path.join(output_dir, 'kraken_box.png'), dpi=120, bbox_inches='tight', pad_inches=0.1)
        plt.close()

        # Taxa Bar Plot
        df_sorted = df_k2.sort_values('Classified(%)', ascending=False)
        fig, ax = plt.subplots(figsize=(10, 5), facecolor='white')
        ax.set_facecolor('white')
        ax.bar(range(len(df_sorted)), df_sorted['Classified(%)'], color='#2ecc71', width=1.0, label='Classified')
        ax.bar(range(len(df_sorted)), df_sorted['Unclassified(%)'], bottom=df_sorted['Classified(%)'], 
               color='#ecf0f1', width=1.0, label='Unclassified')
        
        ax.set_ylabel('Percentage (%)', color='black')
        ax.set_title('Taxonomy Classification Distribution', color='black', fontweight='bold')
        ax.set_xticks([])
        ax.set_ylim(0, 100)
        plt.savefig(os.path.join(output_dir, 'kraken_bar.png'), dpi=120, bbox_inches='tight', pad_inches=0.1)
        plt.close()
except Exception as e:
    with open("plot_error.log", "w") as f: f.write(str(e))
    sys.exit(1)
PY_EOF

# ==============================================================================
# 3. 메인 루프 (사용자 원본 카운팅 로직 100% 복구 ✨)
# ==============================================================================
while true; do
    # --------------------------------------------------------------------------
    # [데이터 수집] - 사용자 원본 로직 그대로
    # --------------------------------------------------------------------------
    # 1. Total Samples
    if [ -d "$RAW_DATA_DIR" ]; then
        TOTAL_SAMPLES=$(find "$RAW_DATA_DIR" -maxdepth 1 -name "*.fastq.gz" | sed 's/.*\///' | sed -E 's/(_1|_2|_R1|_R2)\.fastq\.gz//g' | sed 's/\.fastq\.gz//g' | sort | uniq | wc -l)
    else TOTAL_SAMPLES=1; fi
    if [ "$TOTAL_SAMPLES" -eq 0 ]; then TOTAL_SAMPLES=1; fi

    # 2. QC (Reads QC)
    QC_BASE="${BASE_DIR}/1_microbiome_taxonomy"
    COUNT_QC=$(find "$QC_BASE" -name "*_paired_1.fastq.gz" 2>/dev/null | wc -l)
    PCT_QC=$(( (COUNT_QC * 100) / TOTAL_SAMPLES ))

    # 3. Taxonomy
    COUNT_TAX=$(find "$QC_BASE" -name "*_S.bracken" 2>/dev/null | wc -l)
    if [ "$COUNT_TAX" -eq 0 ]; then 
        COUNT_TAX=$(find "$QC_BASE" -name "*.bracken" 2>/dev/null | sed 's/.*\///' | sed -E 's/(_S|_G|_F|_species)\.bracken//g' | sort | uniq | wc -l)
    fi
    PCT_TAX=$(( (COUNT_TAX * 100) / TOTAL_SAMPLES ))

    # 4. Assembly / Binning / Annotation
    MAG_BASE="${BASE_DIR}/2_mag_analysis"
    COUNT_ASM=$(find "$MAG_BASE" -name "final.contigs.fa" 2>/dev/null | wc -l); PCT_ASM=$(( (COUNT_ASM * 100) / TOTAL_SAMPLES ))
    if [ "$COUNT_ASM" -gt 0 ] && [ "$COUNT_ASM" -lt "$TOTAL_SAMPLES" ]; then STATUS_ASM="RUNNING"; 
    elif [ "$COUNT_ASM" -eq "$TOTAL_SAMPLES" ] && [ "$TOTAL_SAMPLES" -gt 1 ]; then STATUS_ASM="DONE"; 
    else STATUS_ASM="IDLE"; fi

    COUNT_MAG=$(find "$MAG_BASE" -name "gtdbtk.*.summary.tsv" 2>/dev/null | wc -l); PCT_MAG=$(( (COUNT_MAG * 100) / TOTAL_SAMPLES ))
    if [ "$COUNT_MAG" -gt 0 ] && [ "$COUNT_MAG" -lt "$TOTAL_SAMPLES" ]; then STATUS_MAG="RUNNING"; 
    elif [ "$COUNT_MAG" -eq "$TOTAL_SAMPLES" ] && [ "$TOTAL_SAMPLES" -gt 1 ]; then STATUS_MAG="DONE"; 
    else STATUS_MAG="IDLE"; fi

    COUNT_FUNC=$(find "$MAG_BASE" -name "*.gff3" -o -name "*.emapper.annotations" 2>/dev/null | wc -l); PCT_FUNC=$(( (COUNT_FUNC * 100) / TOTAL_SAMPLES ))
    if [ "$COUNT_FUNC" -gt 0 ] && [ "$COUNT_FUNC" -lt "$TOTAL_SAMPLES" ]; then STATUS_FUNC="RUNNING"; 
    elif [ "$COUNT_FUNC" -eq "$TOTAL_SAMPLES" ] && [ "$TOTAL_SAMPLES" -gt 1 ]; then STATUS_FUNC="DONE"; 
    else STATUS_FUNC="IDLE"; fi

    # --------------------------------------------------------------------------
    # [프로세스 체크 및 파일 업데이트]
    # --------------------------------------------------------------------------
    ALL_PROCESSES=$(ps -ef); IS_QC_RUNNING=$(echo "$ALL_PROCESSES" | grep "kneaddata" | grep -v "grep"); IS_TAX_RUNNING=$(echo "$ALL_PROCESSES" | grep -E "kraken2|bracken" | grep -v "grep")
    find "$QC_BASE" -name "*.kraken2" -o -name "*.output" 2>/dev/null | sed 's/.*\///' | sed 's/\.kraken2//' | sed 's/\.output//' | sort | uniq > /tmp/h_start.txt
    find "$QC_BASE" -name "*.bracken" 2>/dev/null | sed 's/.*\///' | sed -E 's/(_S|_G|_F|_species)\.bracken//g' | sed 's/\.bracken//g' | sort | uniq > /tmp/h_end.txt
    STALLED_COUNT=$(comm -23 /tmp/h_start.txt /tmp/h_end.txt | wc -l)

    python3 "$QC_SCRIPT" "$LOG_DIR" "$QC_OUTPUT_CSV" 2>/dev/null; cp "$QC_OUTPUT_CSV" "${WEB_DIR}/qc_summary.csv" 2>/dev/null; cp "$KRAKEN_SUMMARY" "${WEB_DIR}/kraken2_summary.tsv" 2>/dev/null
    python3 "$PLOT_SCRIPT" "${WEB_DIR}/qc_summary.csv" "${WEB_DIR}/kraken2_summary.tsv" "$WEB_DIR" "$TOTAL_SAMPLES" > "$PLOT_LOG" 2>&1

    csv_to_html() {
        [ ! -f "$1" ] && echo "<p class='text-muted'>No data</p>" && return
        echo "<div class='table-responsive' style='max-height: 450px; overflow-y: auto;'><table class='table table-sm table-dark table-striped small mb-0'>"
        echo "<thead class='sticky-top bg-dark'><tr>$(head -n 1 "$1" | awk -F"$2" '{for(i=1;i<=NF;i++) print "<th>"$i"</th>"}')</tr></thead>"
        echo "<tbody>$(tail -n +2 "$1" | awk -F"$2" '{print "<tr>"; for(i=1;i<=NF;i++) print "<td>"$i"</td>"; print "</tr>"}')</tbody></table></div>"
    }

    # QC Summary 데이터를 정렬합니다. (헤더 제외, 쉼표 기준, 첫 번째 컬럼 정렬)
    SORTED_QC_DATA=$(tail -n +2 "${WEB_DIR}/qc_summary.csv" | sort -t',' -k1 2>/dev/null)

    # 정렬된 데이터를 임시 파일로 저장 (csv_to_html이 파일 경로를 기대하므로)
    echo "$(head -n 1 "${WEB_DIR}/qc_summary.csv" 2>/dev/null)" > "${WEB_DIR}/qc_summary_sorted.csv"
    echo "$SORTED_QC_DATA" >> "${WEB_DIR}/qc_summary_sorted.csv"

    QC_TABLE=$(csv_to_html "${WEB_DIR}/qc_summary_sorted.csv" ","); KR_TABLE=$(csv_to_html "${WEB_DIR}/kraken2_summary.tsv" "\t")

# --------------------------------------------------------------------------
    # [HTML 생성 - 태그 오류 수정 및 하단 테이블 포함 전문]
    # --------------------------------------------------------------------------
    cat <<EOF > "$WEB_DIR/index.html"
<!DOCTYPE html>
<html lang="ko" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <title>Dokkaebi Pipeline Monitor</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <style>
        body { font-family: 'Noto Sans KR', sans-serif; background-color: #121212; color: #e0e0e0; padding-top: 1.5rem; }
        .text-neon { color: #00e676; text-shadow: 0 0 10px rgba(0, 230, 118, 0.4); }
        /* 높이 균등화를 위한 설정 */
        .equal-height-row { display: flex; align-items: stretch; }
        .card { background-color: #1e1e1e; border: 1px solid #333; height: 100%; display: flex; flex-direction: column; }
        .card-body { flex: 1; }
        /* 이미지 영역 최적화 (높이 자동 조절) */
        .plot-container { height: 100%; min-height: 400px; display: flex; flex-direction: column; align-items: center; justify-content: center; overflow: hidden; padding: 0; background-color: #1e1e1e; }
        .plot-img { max-width: 95%; max-height: 95%; height: auto; width: auto; object-fit: contain; margin: auto; }
        .nav-tabs .nav-link { color: #aaa; border: none; }
        .nav-tabs .nav-link.active { color: #00e676; background: none; border-bottom: 3px solid #00e676; font-weight: bold; }
        .table-responsive { max-height: 450px; overflow-y: auto; }
    </style>
</head>
<body>
    <div class="container-fluid" style="max-width: 1400px;">
        <div class="d-flex justify-content-between align-items-end mb-4 border-bottom border-secondary pb-3">
            <div><h1 class="display-6 fw-bold text-neon mb-0">🧬 Metagenome Pipeline</h1>
            <h5 class="text-light mt-4 mb-1">임신성 당뇨병 환자의 예후 추적 연구 기반 마이크로바이옴 변화 데이터 구축</h5>
            <h6 class="text-muted mb-2">Contsruction of Microbiome Change Data based on prognostic tracking study in Gestational Diabets patients</h6>
            <small class="text-secondary">Update: $(date '+%Y-%m-%d %H:%M:%S')</small></div>
            <div><span class="badge bg-secondary">V4.7 Professional</span></div>
        </div>

        <div class="row equal-height-row g-4">
            <div class="col-lg-6">
                <div class="card border-secondary shadow-sm h-100">
                    <div class="card-header bg-dark py-2 small fw-bold text-neon text-uppercase">Analysis Progress Overview</div>
                    <div class="card-body pt-3">
                        <h6 class="text-secondary mt-3 mb-2">STEP 1: QUALITY CHECK & CLASSIFICATION</h6>
                        <div class="mb-4">
                            <div class="d-flex justify-content-between small fw-bold mb-1"><span>1️⃣ Reads QC</span><span class="text-neon">$PCT_QC%</span></div>
                            <div class="progress mb-2"><div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_QC%">$COUNT_QC / $TOTAL_SAMPLES</div></div>
                            $(if [ -n "$IS_QC_RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>
                        <div class="mb-4">
                            <div class="d-flex justify-content-between small fw-bold mb-1"><span>2️⃣ Taxonomy Assignment</span><span class="text-neon">$PCT_TAX%</span></div>
                            <div class="progress mb-2"><div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_TAX%">$COUNT_TAX / $TOTAL_SAMPLES</div></div>
                            $(if [ -n "$IS_TAX_RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; elif [ "$STALLED_COUNT" -gt 0 ]; then echo "<span class='badge bg-danger px-3 py-2'>STALLED ($STALLED_COUNT)</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>
                        <h6 class="text-secondary pt-4 mt-4 mb-2 border-top border-secondary">STEP 2: ASSEMBLY & ANNOTATION</h6>
                        <div class="mb-4">
                            <div class="d-flex justify-content-between small fw-bold mb-1"><span>3️⃣ Assembly</span><span class="text-neon">$PCT_ASM%</span></div>
                            <div class="progress mb-2"><div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_ASM%">$COUNT_ASM / $TOTAL_SAMPLES</div></div>
                            $(if [ "$STATUS_ASM" == "RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; elif [ "$STATUS_ASM" == "DONE" ]; then echo "<span class='badge bg-success px-3 py-2'>DONE</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>
                        <div class="mb-4">
                            <div class="d-flex justify-content-between small fw-bold mb-1"><span>4️⃣ Binning</span><span class="text-neon">$PCT_MAG%</span></div>
                            <div class="progress mb-2"><div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_MAG%">$COUNT_MAG / $TOTAL_SAMPLES</div></div>
                            $(if [ "$STATUS_MAG" == "RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; elif [ "$STATUS_MAG" == "DONE" ]; then echo "<span class='badge bg-success px-3 py-2'>DONE</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>
                        <div class="mb-0">
                            <div class="d-flex justify-content-between small fw-bold mb-1"><span>5️⃣ Annotation</span><span class="text-neon">$PCT_FUNC%</span></div>
                            <div class="progress mb-2"><div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_FUNC%">$COUNT_FUNC / $TOTAL_SAMPLES</div></div>
                            $(if [ "$STATUS_FUNC" == "RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; elif [ "$STATUS_FUNC" == "DONE" ]; then echo "<span class='badge bg-success px-3 py-2'>DONE</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>
                    </div> </div> </div> <div class="col-lg-6">
                <div class="card border-neon shadow-lg">
                    <div class="card-header bg-dark text-neon py-2 d-flex justify-content-between align-items-center">
                        <span class="fw-bold">📊 ANALYSIS DASHBOARD</span>
                        <ul class="nav nav-tabs border-0">
                            <li class="nav-item"><button class="nav-link active small" data-bs-toggle="tab" data-bs-target="#p-qc">QC Status</button></li>
                            <li class="nav-item"><button class="nav-link small" data-bs-toggle="tab" data-bs-target="#p-bar">Taxa Bar</button></li>
                            <li class="nav-item"><button class="nav-link small" data-bs-toggle="tab" data-bs-target="#p-box">Taxa Box</button></li>
                        </ul>
                    </div>
                    <div class="card-body p-2 d-flex flex-column mt-5 pb-0">
                        <div class="tab-content flex-grow-1">
                            <div class="tab-pane fade show active" id="p-qc">
                                <div class="plot-container" style="justify-content: center; gap: 0px;">
                                    <img src="qc_plot.png" class="plot-img" style="max-height: 85%; width: auto;">
                                    <div class="px-3 py-3 border border-secondary rounded bg-black text-white small opacity-90" style="width: 95%; max-width: 700px; margin-bottom: 20px; margin-top: -60px; position: relative; z-index: 10;">
                                        <div class="row g-2 text-start">
                                            <div class="col-6"><span class="text-neon fw-bold">Pass</span>: 정상 (QC 통과)</div>
                                            <div class="col-6"><span class="text-warning fw-bold">Low Paired</span>: Read 페어링 비율 80% 미만</div>
                                            <div class="col-6"><span class="text-warning fw-bold">High Host</span>: 호스트 Read 제거율 30% 초과 </div>
                                            <div class="col-6"><span class="text-danger fw-bold">Small File</span>: 데이터 파일 크기 5 GB 미달 </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                            <div class="tab-pane fade h-100" id="p-bar"><div class="plot-container"><img src="kraken_bar.png" class="plot-img"></div></div>
                            <div class="tab-pane fade h-100" id="p-box"><div class="plot-container"><img src="kraken_box.png" class="plot-img"></div></div>
                        </div>
                    </div>
                </div>
            </div> </div> <div class="row mt-4">
            <div class="col-12">
                <div class="card border-secondary">
                    <div class="card-header py-2 fw-bold small text-secondary text-uppercase">Data Summary Viewer</div>
                    <div class="card-body py-2">
                        <ul class="nav nav-tabs mb-2">
                            <li class="nav-item"><button class="nav-link active small" data-bs-toggle="tab" data-bs-target="#c-qc">QC Summary</button></li>
                            <li class="nav-item"><button class="nav-link small" data-bs-toggle="tab" data-bs-target="#c-kr">Taxonomy Assignment</button></li>
                        </ul>
                        <div class="tab-content pt-2">
                            <div class="tab-pane fade show active" id="c-qc">
                                <div class="text-end mb-1"><a href="qc_summary.csv" class="text-neon text-decoration-none small" download>📥 Download CSV</a></div>
                                $QC_TABLE
                            </div>
                            <div class="tab-pane fade" id="c-kr">
                                <div class="text-end mb-1"><a href="kraken2_summary.tsv" class="text-neon text-decoration-none small" download>📥 Download TSV</a></div>
                                $KR_TABLE
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
            <div class="text-center py-2 small text-secondary mt-2"> 
                Running on <strong>JS LINK</strong>
            </div>

            <footer class="py-1 border-top border-secondary mt-2">
        </footer>   
    </div>
</body>
</html>
EOF
    rm /tmp/h_start.txt /tmp/h_end.txt /tmp/h_candidates.txt 2>/dev/null
    sleep 7200
done