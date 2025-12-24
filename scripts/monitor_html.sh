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
# 2. Python Script (들여쓰기 오류 방지용 왼쪽 정렬 버전)
# ==============================================================================
cat <<'PY_EOF' > "$PLOT_SCRIPT"
import sys, os
import matplotlib
matplotlib.use('Agg')
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import matplotlib.cm as cm # 컬러맵 사용을 위해 추가

# 에러 로그 기록
sys.stderr = open('plot_debug.log', 'w')

try:
    if len(sys.argv) < 5: sys.exit(1)
    qc_file, kraken_file, output_dir, global_total = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    stats_list_file = os.path.join(output_dir, "stat_files.list")
    
    COLOR_BG_DARK = '#1e1e1e'
    COLOR_PASS, COLOR_WARN, COLOR_FAIL, COLOR_EMPTY = '#00e676', '#ff9100', '#ff1744', '#333333'

    # [1] QC Gauge (기존 유지)
    def draw_gauge(ax, title, count, total, color):
        if total == 0: total = 1
        data = [count, total - count, total]
        colors = [color, COLOR_EMPTY, (0,0,0,0)]
        ax.pie(data, radius=2.0, colors=colors, startangle=180, counterclock=False, 
               wedgeprops=dict(width=0.4, edgecolor=COLOR_BG_DARK))
        ax.text(0, -0.2, f"{count}/{total}", ha='center', va='center', fontsize=14, color='white', fontweight='bold')
        ax.text(0, 0.7, title, ha='center', va='center', fontsize=16, fontweight='bold', color=color)
        ax.set_aspect('equal')

    if os.path.exists(qc_file):
        df = pd.read_csv(qc_file)
        notes = df['QC_Note'].fillna("").astype(str).str.lower()
        fig, axes = plt.subplots(2, 2, figsize=(10, 6), facecolor=COLOR_BG_DARK)
        draw_gauge(axes[0,0], "Pass", notes.str.contains('pass').sum(), global_total, COLOR_PASS)
        draw_gauge(axes[0,1], "Low Paired", notes.str.contains('low paired').sum(), global_total, COLOR_WARN)
        draw_gauge(axes[1,0], "High Host", notes.str.contains('high host').sum(), global_total, COLOR_WARN)
        draw_gauge(axes[1,1], "Small File", notes.str.contains('small file').sum(), global_total, COLOR_FAIL)
        plt.subplots_adjust(hspace=0.3, top=0.9)
        plt.savefig(os.path.join(output_dir, 'qc_plot.png'), dpi=150, bbox_inches='tight')
        plt.close()

    # [2] Taxa Box (색상 추가: 초록/회색)
    if os.path.exists(kraken_file) and os.path.getsize(kraken_file) > 0:
        df_k2 = pd.read_csv(kraken_file, sep='\t')
        cols = {c.replace(" ", ""): c for c in df_k2.columns}
        c_col, u_col = cols.get('Classified(%)'), cols.get('Unclassified(%)')
        if c_col and u_col and not df_k2.empty:
            fig, ax = plt.subplots(figsize=(6, 5), facecolor='white')
            
            # 박스 그리기 (객체 받기)
            bp = ax.boxplot([df_k2[c_col].dropna(), df_k2[u_col].dropna()], patch_artist=True, widths=0.6, vert=True)
            
            # [색상 적용] Classified: 초록색, Unclassified: 회색
            colors = ['#2ecc71', '#95a5a6'] 
            for patch, color in zip(bp['boxes'], colors):
                patch.set_facecolor(color)
                patch.set_alpha(0.7) # 약간 투명하게

            ax.set_xticklabels(['Classified', 'Unclassified'], fontsize=12, fontweight='bold')
            ax.set_ylabel('Percentage (%)', fontsize=12, fontweight='bold')
            ax.set_title('Taxonomy Ratio', fontsize=14, fontweight='bold', pad=15)
            ax.set_ylim(-5, 105)
            ax.grid(axis='y', linestyle='--', alpha=0.5)
            plt.savefig(os.path.join(output_dir, 'kraken_box.png'), dpi=150, bbox_inches='tight')
            plt.close()

    # [3] Nx Curve (직각 계단식 + 무지개 컬러맵 적용)
    if os.path.exists(stats_list_file):
        with open(stats_list_file, 'r') as f:
            files = [line.strip() for line in f if line.strip()]

        if files:
            fig, ax = plt.subplots(figsize=(6, 5), facecolor='white')
            has_data = False
            
            # [색상 준비] 파일 개수만큼 서로 다른 색상 생성 (nipy_spectral 컬러맵 사용)
            num_files = len(files)
            # 색상 맵에서 등간격으로 색상 추출
            colors = cm.nipy_spectral(np.linspace(0, 0.9, num_files)) if num_files > 0 else []

            def parse_len(val_s, unit_s=None):
                mult = 1
                if unit_s:
                    if 'KB' in unit_s.upper(): mult = 1e3
                    elif 'MB' in unit_s.upper(): mult = 1e6
                    elif 'GB' in unit_s.upper(): mult = 1e9
                return float(val_s.replace(',', '')) * mult

            for i, fp in enumerate(files):
                if not os.path.exists(fp): continue
                try:
                    with open(fp, 'r') as f_in: lines = f_in.readlines()
                    x_pts, y_pts = [], []
                    total_len = 0
                    start = False
                    for line in lines:
                        if '--------' in line: start = True; continue
                        if not start or not line.strip(): continue
                        parts = line.split()
                        if parts[0] == 'All': total_len = float(parts[-2].replace(',', '')); continue
                        min_l, cum_l = 0, 0
                        if len(parts) > 1 and parts[1] in ['BP', 'KB', 'MB', 'GB']:
                            min_l = parse_len(parts[0], parts[1])
                            cum_l = float(parts[-2].replace(',', ''))
                        else:
                            min_l = float(parts[0].replace(',', ''))
                            cum_l = float(parts[-2].replace(',', ''))
                        if total_len > 0:
                            x_pts.append((cum_l / total_len) * 100)
                            y_pts.append(min_l)
                    
                    if x_pts and y_pts:
                        data = sorted(zip(x_pts, y_pts))
                        xs = [d[0] for d in data]
                        ys = [d[1] for d in data]
                        # [색상 적용] 미리 만들어둔 colors 리스트에서 i번째 색상 사용
                        # alpha=0.6으로 투명도를 주어 겹쳐도 보이게 함
                        ax.step(xs, ys, where='post', linewidth=1.5, alpha=0.6, color=colors[i])
                        has_data = True
                except: continue

            if has_data:
                ax.set_xlabel('Nx Percentage (%)', fontweight='bold')
                ax.set_ylabel('Contig Length (bp)', fontweight='bold')
                ax.set_title('Assembly Nx Curve', fontweight='bold', fontsize=14)
                ax.set_xlim(0, 100)
                ax.set_yscale('log')
                ax.grid(True, which="both", ls="--", alpha=0.3)
                # 범례 추가 (너무 많으면 지저분하므로 10개 이하일 때만 표시)
                if num_files <= 10: ax.legend([os.path.basename(f).split('_')[0] for f in files], fontsize='small', loc='upper right')
                plt.savefig(os.path.join(output_dir, 'assembly_n50.png'), dpi=150, bbox_inches='tight')
                plt.close()

except Exception as e:
    print(str(e), file=sys.stderr)
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
    if [ "$COUNT_QC" -eq "$TOTAL_SAMPLES" ] && [ "$TOTAL_SAMPLES" -gt 0 ]; then STATUS_QC="DONE"
    elif [ -n "$IS_QC_RUNNING" ] || [ "$COUNT_QC" -gt 0 ]; then STATUS_QC="RUNNING"
    else STATUS_QC="IDLE"; fi

    # 3. Taxonomy
    COUNT_TAX=$(find "$QC_BASE" -name "*_S.bracken" 2>/dev/null | wc -l)
    if [ "$COUNT_TAX" -eq 0 ]; then 
        COUNT_TAX=$(find "$QC_BASE" -name "*.bracken" 2>/dev/null | sed 's/.*\///' | sed -E 's/(_S|_G|_F|_species)\.bracken//g' | sort | uniq | wc -l)
    fi
    PCT_TAX=$(( (COUNT_TAX * 100) / TOTAL_SAMPLES ))
    if [ "$COUNT_TAX" -eq "$TOTAL_SAMPLES" ] && [ "$TOTAL_SAMPLES" -gt 0 ]; then STATUS_TAX="DONE"
    elif [ -n "$IS_TAX_RUNNING" ] || [ "$COUNT_TAX" -gt 0 ]; then STATUS_TAX="RUNNING"
    else STATUS_TAX="IDLE"; fi

    # 4. Assembly / Binning / Annotation
    MAG_BASE="${BASE_DIR}/2_mag_analysis"
    COUNT_ASM=$(find "$MAG_BASE" -path "*/01_assembly/*/final.contigs.fa" 2>/dev/null | wc -l); PCT_ASM=$(( (COUNT_ASM * 100) / TOTAL_SAMPLES ))
    # 1. 100% 완료되었는가?
    if [ "$COUNT_ASM" -eq "$TOTAL_SAMPLES" ] && [ "$TOTAL_SAMPLES" -gt 0 ]; then 
        STATUS_ASM="DONE"
    # 2. 파일이 1개라도 생겼거나, 혹은 지금 막 프로세스가 시작되었는가?
    elif [ -n "$IS_ASM_RUNNING" ] || [ "$COUNT_ASM" -gt 0 ]; then 
        STATUS_ASM="RUNNING"
# 3. 그 외에는 아직 시작 전임
    else 
        STATUS_ASM="IDLE"
    fi

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
    ALL_PROCESSES=$(ps -ef); IS_QC_RUNNING=$(echo "$ALL_PROCESSES" | grep "kneaddata" | grep -v "grep"); IS_TAX_RUNNING=$(echo "$ALL_PROCESSES" | grep -E "kraken2|bracken" | grep -v "grep"); IS_ASM_RUNNING=$(echo "$ALL_PROCESSES" | grep -E "spades|megahit|mag.sh" | grep -v "grep")
    find "$QC_BASE" -name "*.kraken2" -o -name "*.output" 2>/dev/null | sed 's/.*\///' | sed 's/\.kraken2//' | sed 's/\.output//' | sort | uniq > /tmp/h_start.txt
    find "$QC_BASE" -name "*.bracken" 2>/dev/null | sed 's/.*\///' | sed -E 's/(_S|_G|_F|_species)\.bracken//g' | sed 's/\.bracken//g' | sort | uniq > /tmp/h_end.txt
    STALLED_COUNT=$(comm -23 /tmp/h_start.txt /tmp/h_end.txt | wc -l)

    python3 "$QC_SCRIPT" "$LOG_DIR" "$QC_OUTPUT_CSV" 2>/dev/null; cp "$QC_OUTPUT_CSV" "${WEB_DIR}/qc_summary.csv" 2>/dev/null; cp "$KRAKEN_SUMMARY" "${WEB_DIR}/kraken2_summary.tsv" 2>/dev/null
    # python3 "$PLOT_SCRIPT" "${WEB_DIR}/qc_summary.csv" "${WEB_DIR}/kraken2_summary.tsv" "$WEB_DIR" "$TOTAL_SAMPLES" > "$PLOT_LOG" 2>&1

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

    # --------------------------------------------------------------------------
    # [수정] Assembly Stats 통합 데이터 준비 (Contig 기준)
    # --------------------------------------------------------------------------
    if [ "$COUNT_ASM" -eq "$TOTAL_SAMPLES" ] && [ "$TOTAL_SAMPLES" -gt 0 ]; then 
        STATUS_ASM="DONE"
    
    # 2. 완료된 파일이 없더라도(0개라도), 프로세스가 돌고 있으면 무조건 RUNNING!
    elif [ -n "$IS_ASM_RUNNING" ] || [ "$COUNT_ASM" -gt 0 ]; then 
        STATUS_ASM="RUNNING"
    
    # 3. 돌지도 않고 완료된 파일도 없으면 그때서야 IDLE
    else 
        STATUS_ASM="IDLE"
    fi

    ASM_STATS_MERGED="${WEB_DIR}/assembly_stats_summary.tsv"
    # 헤더 명칭을 Contig 중심으로 변경
    echo -e "Sample\tContigs\tTotal_Len\tContig_N50\tContig_L50\tMax_Contig\tGC(%)" > "$ASM_STATS_MERGED"

    find "${MAG_BASE}" -path "*/02_assembly_stats/*_stats.txt" 2>/dev/null | while read -r stat_file; do
        if [ -f "$stat_file" ]; then
            s_name=$(basename "$stat_file" | sed 's/_1_kneaddata_paired_assembly_stats.txt//' | sed 's/_assembly_stats.txt//')
            
            # [수정] Scaffold 대신 Contig 라인을 추출하도록 패턴 변경
            contig_total=$(grep "Main genome contig total:" "$stat_file" | awk '{print $NF}')
            # MB 단위를 포함한 전체 Contig 길이
            contig_seq_total=$(grep "Main genome contig sequence total:" "$stat_file" | awk '{print $6, $7}')
            # Contig N/L50에서 뒷부분(L50, 즉 길이)만 추출
            # 원본 데이터 라인 추출 (예: "Main genome contig N/L50: 4368/15.008 KB")
            raw_line=$(grep -w "contig" "$stat_file" | grep "N/L50:" | head -n 1)
            data_part=$(echo "$raw_line" | awk -F':' '{print $2}')

            # 1. N50 추출: 콜론(:) 뒤에서부터 슬래시(/) 전까지의 숫자만 추출
            contig_n50=$(echo "$data_part" | cut -d'/' -f1 | xargs)
            
            # 2. L50 추출: 슬래시(/) 뒷부분의 값(숫자 + 단위)만 추출
            contig_l50=$(echo "$data_part" | cut -d'/' -f2- | xargs)
            
            # 가장 긴 Contig 길이
            max_contig=$(grep "Max contig length:" "$stat_file" | awk '{print $4, $5}')
                
            # 1. GC 수치 추출: 파일의 2행 8열 (0.4849 형태를 %로 변환 가능)
            # awk 'NR==2 {print $8}'를 사용하면 0.4849를 직접 가져옵니다.
            gc_raw=$(awk 'NR==2 {print $8}' "$stat_file")
            
            # 소수점을 백분율(%)로 표시하고 싶다면 아래와 같이 계산 (예: 48.49)
            if [ -n "$gc_raw" ]; then
                gc_val=$(echo "$gc_raw * 100" | bc -l | cut -c 1-5)
            else
                gc_val="-"
            fi
            
            echo -e "${s_name}\t${contig_total}\t${contig_seq_total}\t${contig_n50}\t${contig_l50}\t${max_contig}\t${gc_val}" >> "$ASM_STATS_MERGED"
        fi
    done

    # --------------------------------------------------------------------------
    # [정렬] Assembly Stats 파일만 샘플명(1열) 기준으로 정렬
    # --------------------------------------------------------------------------
    # 1. 헤더 추출
    header=$(head -n 1 "$ASM_STATS_MERGED")
    
    # 2. 데이터 부분만 추출하여 샘플명(1열) 기준 자연 정렬(-V) 수행 후 임시 저장
    # sort -V는 Sample_1, Sample_2, Sample_10 순으로 똑똑하게 정렬합니다.
    tail -n +2 "$ASM_STATS_MERGED" | sort -k1,1 -V > "${ASM_STATS_MERGED}.tmp"
    
    # 3. 헤더와 정렬된 데이터를 다시 합침
    echo "$header" > "$ASM_STATS_MERGED"
    cat "${ASM_STATS_MERGED}.tmp" >> "$ASM_STATS_MERGED"
    
    # 4. 임시 파일 삭제
    rm "${ASM_STATS_MERGED}.tmp"

    # --------------------------------------------------------------------------
    # [데이터 수집] Taxonomy Assignment (Contig) - Kraken2 Contig Report 기반
    # --------------------------------------------------------------------------
    CONTIG_TAX_SUMMARY="${WEB_DIR}/kraken2_contig_summary.tsv"
    
    # 헤더 작성 (Read 표와 100% 동일하게 구성)
    echo -e "Sample\tTotal\tClassified\tClassified(%)\tUnclassified\tUnclassified(%)" > "$CONTIG_TAX_SUMMARY"

    # [수정 포인트 1] -path를 사용하여 03_kraken_on_contigs 하위의 리포트를 찾습니다.
    # 패턴 양옆에 *를 붙여 하위 경로 어디에 있든 찾을 수 있게 합니다.
    while read -r k2_file; do
        if [ -f "$k2_file" ]; then
            # 샘플명 추출 (테스트 확인 완료)
            s_name=$(basename "$k2_file" | sed -E 's/(_1)?_kneaddata_paired_contigs\.k2report//')
            
            # [방금 터미널에서 성공한 그 코드] 정밀 수치 추출
            uncl_count=$(grep -P "^\s*\d+\.\d+\s+\d+\s+\d+\s+U\s" "$k2_file" | awk '{print $2}')
            cl_count=$(grep -P "^\s*\d+\.\d+\s+\d+\s+\d+\s+R\s" "$k2_file" | head -n 1 | awk '{print $2}')

            # 값이 없을 경우 대비
            uncl_count=${uncl_count:-0}
            cl_count=${cl_count:-0}
            total_count=$(( uncl_count + cl_count ))

            # 백분율 계산
            if [ "$total_count" -gt 0 ]; then
                cl_pct=$(echo "scale=2; ($cl_count * 100) / $total_count" | bc -l)
                uncl_pct=$(echo "scale=2; 100 - $cl_pct" | bc -l)
            else
                cl_pct="0.00"; uncl_pct="0.00"
            fi
            
            # 파일에 데이터 기록
            echo -e "${s_name}\t${total_count}\t${cl_count}\t${cl_pct}\t${uncl_count}\t${uncl_pct}" >> "$CONTIG_TAX_SUMMARY"
        fi
    done < <(find "${MAG_BASE}" -path "*/03_kraken_on_contigs/*/*.k2report" 2>/dev/null)

    # 3. 정렬 및 HTML 반영
    if [ -s "$CONTIG_TAX_SUMMARY" ]; then
        header_ct=$(head -n 1 "$CONTIG_TAX_SUMMARY")
        tail -n +2 "$CONTIG_TAX_SUMMARY" | sort -k1,1 -V > "${CONTIG_TAX_SUMMARY}.tmp"
        echo "$header_ct" > "$CONTIG_TAX_SUMMARY"
        cat "${CONTIG_TAX_SUMMARY}.tmp" >> "$CONTIG_TAX_SUMMARY"
        rm "${CONTIG_TAX_SUMMARY}.tmp"
    fi

    # --------------------------------------------------------------------------
    # HTML 변환용 변수
    # --------------------------------------------------------------------------

    QC_TABLE=$(csv_to_html "${WEB_DIR}/qc_summary_sorted.csv" ",") 
    KR_TABLE=$(csv_to_html "${WEB_DIR}/kraken2_summary.tsv" "\t")
    AS_TABLE=$(csv_to_html "${WEB_DIR}/assembly_stats_summary.tsv" "\t")
    CT_KR_TABLE=$(csv_to_html "${WEB_DIR}/kraken2_contig_summary.tsv" "\t")

    # 1. 파이썬이 읽을 통계 파일 목록 만들기 (Nx Curve용)
    find "${MAG_BASE}" -path "*/02_assembly_stats/*_stats.txt" > "${WEB_DIR}/stat_files.list"

    # 2. 파이썬 스크립트 실행 (재료가 다 준비된 상태에서 실행)
    python3 "$PLOT_SCRIPT" "${WEB_DIR}/qc_summary.csv" "${WEB_DIR}/kraken2_summary.tsv" "$WEB_DIR" "$TOTAL_SAMPLES" > "$PLOT_LOG" 2>&1

    # [추가] 이미지 캐시 갱신용 타임스탬프
    TIMESTAMP=$(date +%s)

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
        /* 진행바 텍스트 중앙 고정 스타일 - 미세 보정 버전 */
        .progress { 
            position: relative; 
            height: 1.4rem; /* 높이를 살짝 키워 시원하게 배치 */
            background-color: #2a2a2a; /* 조금 더 밝은 회색으로 텍스트 대비 향상 */
            overflow: hidden; /* 바깥으로 나가는 바 제거 */
            border-radius: 4px;
        }
        .progress-text {
            position: absolute;
            width: 100%;
            left: 0;
            top: 0;
            text-align: center;
            color: #ffffff;
            font-weight: 800; /* 조금 더 두껍게 */
            line-height: 1.4rem; /* progress 높이와 일치시켜 세로 중앙 정렬 */
            z-index: 10;
            text-shadow: 1px 1px 3px rgba(0,0,0,1); /* 그림자를 진하게 주어 파란바 위에서도 선명하게 */
            pointer-events: none;
            font-size: 0.85rem;
        }
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
                            <div class="progress mb-2">
                                <span class="progress-text">$COUNT_QC / $TOTAL_SAMPLES</span>
                                <div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_QC%"></div>
                            </div>
                            $(if [ "$STATUS_QC" == "DONE" ]; then echo "<span class='badge bg-success px-3 py-2'>DONE</span>"; elif [ "$STATUS_QC" == "RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>

                        <div class="mb-4">
                            <div class="d-flex justify-content-between small fw-bold mb-1"><span>2️⃣ Taxonomy Assignment</span><span class="text-neon">$PCT_TAX%</span></div>
                            <div class="progress mb-2">
                                <span class="progress-text">$COUNT_TAX / $TOTAL_SAMPLES</span>
                                <div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_TAX%"></div>
                            </div>
                            $(if [ "$STATUS_TAX" == "DONE" ]; then echo "<span class='badge bg-success px-3 py-2'>DONE</span>"; elif [ "$STATUS_TAX" == "RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>

                        <h6 class="text-secondary pt-4 mt-4 mb-2 border-top border-secondary">STEP 2: ASSEMBLY & ANNOTATION</h6>
                        
                        <div class="mb-4">
                            <div class="d-flex justify-content-between small fw-bold mb-1"><span>3️⃣ Assembly</span><span class="text-neon">$PCT_ASM%</span></div>
                            <div class="progress mb-2">
                                <span class="progress-text">$COUNT_ASM / $TOTAL_SAMPLES</span>
                                <div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_ASM%"></div>
                            </div>
                            $(if [ "$STATUS_ASM" == "DONE" ]; then echo "<span class='badge bg-success px-3 py-2'>DONE</span>"; elif [ "$STATUS_ASM" == "RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>
                        <div class="mb-4">
                            <div class="d-flex justify-content-between small fw-bold mb-1"><span>4️⃣ Binning</span><span class="text-neon">$PCT_MAG%</span></div>
                            <div class="progress mb-2">
                                <span class="progress-text">$COUNT_MAG / $TOTAL_SAMPLES</span>
                                <div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_MAG%"></div>
                            </div>
                            $(if [ "$STATUS_MAG" == "RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; elif [ "$STATUS_MAG" == "DONE" ]; then echo "<span class='badge bg-success px-3 py-2'>DONE</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>
                        <div class="mb-0">
                            <div class="d-flex justify-content-between small fw-bold mb-1"><span>5️⃣ Annotation</span><span class="text-neon">$PCT_FUNC%</span></div>
                            <div class="progress mb-2">
                                <span class="progress-text">$COUNT_FUNC / $TOTAL_SAMPLES</span>
                                <div class="progress-bar bg-neon progress-bar-striped progress-bar-animated" style="width: $PCT_FUNC%"></div>
                            </div>
                            $(if [ "$STATUS_FUNC" == "RUNNING" ]; then echo "<span class='badge bg-primary px-3 py-2'>RUNNING</span>"; elif [ "$STATUS_FUNC" == "DONE" ]; then echo "<span class='badge bg-success px-3 py-2'>DONE</span>"; else echo "<span class='badge bg-secondary px-3 py-2'>IDLE</span>"; fi)
                        </div>
                    </div> </div> </div> <div class="col-lg-6">
                <div class="card border-neon shadow-lg">
                    <div class="card-header bg-dark text-neon py-2 d-flex justify-content-between align-items-center">
                        <span class="fw-bold">📊 ANALYSIS DASHBOARD</span>
                        <ul class="nav nav-tabs border-0">
                            <li class="nav-item"><button class="nav-link active small" data-bs-toggle="tab" data-bs-target="#p-qc">QC Status</button></li>
                            <li class="nav-item"><button class="nav-link small" data-bs-toggle="tab" data-bs-target="#p-box">Taxa Box</button></li>
                            <li class="nav-item"><button class="nav-link small" data-bs-toggle="tab" data-bs-target="#p-n50">Assembly Quality</button></li>
                        </ul>
                    </div>
                    <div class="card-body p-2 d-flex flex-column mt-5 pb-0">
                        <div class="tab-content flex-grow-1">
                            <div class="tab-pane fade show active" id="p-qc">
                                <div class="plot-container" style="justify-content: center; gap: 0px;">
                                    <img src="qc_plot.png?v=$TIMESTAMP" class="plot-img" style="max-height: 85%; width: auto;">
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
                            <div class="tab-pane fade h-100" id="p-box"><div class="plot-container"><img src="kraken_box.png?v=$TIMESTAMP" class="plot-img"></div></div>
                            <div class="tab-pane fade h-100" id="p-n50"><div class="plot-container"><img src="assembly_n50.png?v=$TIMESTAMP" class="plot-img"></div></div>
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
                            <li class="nav-item"><button class="nav-link small" data-bs-toggle="tab" data-bs-target="#c-kr">Taxonomy (Read)</button></li>
                            <li class="nav-item"><button class="nav-link small" data-bs-toggle="tab" data-bs-target="#c-as">Assembly Stats</button></li>
                            <li class="nav-item"><button class="nav-link small" data-bs-toggle="tab" data-bs-target="#c-ct-kr">Taxonomy (Contig)</button></li>
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
                            <div class="tab-pane fade" id="c-as">
                                <div class="text-end mb-1"><a href="assembly_stats_summary.tsv" class="text-neon text-decoration-none small" download>📥 Download TSV</a></div>
                                $(csv_to_html "${WEB_DIR}/assembly_stats_summary.tsv" "\t")
                            </div>
                            <div class="tab-pane fade" id="c-ct-kr">
                                <div class="text-end mb-1"><a href="kraken2_contig_summary.tsv" class="text-neon text-decoration-none small" download>📥 Download TSV</a></div>
                                $(csv_to_html "${WEB_DIR}/kraken2_contig_summary.tsv" "\t")
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