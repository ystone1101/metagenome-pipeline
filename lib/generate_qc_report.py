#!/usr/bin/env python3
import os
import glob
import re
import pandas as pd
import sys

# ==============================================================================
# 1. 설정 및 인자 파싱 (파이프라인 연동)
# ==============================================================================

# qc.sh에서 넘겨주는 경로를 받습니다.
# argv[3](kraken2_summary.tsv)과 argv[4](xlsx 출력 경로)는 선택 사항입니다.
# 둘 다 monitoring 사이트(monitor_html.sh)가 읽는 OUTPUT_CSV와는 완전히 분리된
# 별도 산출물이며, OUTPUT_CSV의 컬럼/내용은 이 인자 유무와 관계없이 항상 동일합니다.
if len(sys.argv) < 3:
    print("Usage: python generate_qc_report.py <log_dir> <output_csv> [kraken2_summary_tsv] [output_xlsx]")
    # 테스트용 기본값 (단독 실행 시 사용)
    LOG_DIR = './'
    OUTPUT_CSV = 'KneadData_QC_Report_Full.csv'
    KRAKEN2_TSV = None
    OUTPUT_XLSX = None
else:
    LOG_DIR = sys.argv[1]    # qc.sh가 알려주는 로그 폴더
    OUTPUT_CSV = sys.argv[2] # qc.sh가 알려주는 저장 경로 (monitoring 사이트가 그대로 읽는 파일)
    KRAKEN2_TSV = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
    OUTPUT_XLSX = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
    if KRAKEN2_TSV and not OUTPUT_XLSX:
        OUTPUT_XLSX = os.path.join(os.path.dirname(OUTPUT_CSV) or '.', 'QC_Full_Report.xlsx')

# QC 기준값 설정
THRESHOLDS = {
    'MAX_TRIM_LOSS': 30.0,       # Trimming 손실률 30% 초과 시 경고
    'MIN_PAIRED_SURVIVAL': 80.0, # Paired Read 유지율 80% 미만 시 경고
    'MAX_HOST_REMOVAL': 30.0,    # Host 제거율 30% 이상 시 경고
    'MIN_FILE_SIZE_GB': 5.0,     # 파일 크기 5GB 미만 시 경고
    'MIN_KRAKEN_CLASSIFIED': 70.0,  # Kraken2 classified 비율 70% 미만 시 경고 (가이드라인 기준)
}

# ==============================================================================
# 2. 파싱 함수 정의
# ==============================================================================
def parse_kneaddata_summary(file_path):
    """
    _summary.log 파일 하나를 읽어 QC 정보를 딕셔너리로 반환
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # [A] 기본 정보 및 Sample ID 추출
        filename = os.path.basename(file_path)
        if '_kneaddata' in filename:
            sample_id = filename.split('_kneaddata')[0]
        else:
            sample_id = filename.replace('_summary.log', '').replace('.log', '')

        # [B] 수치 데이터 추출
        
        # 1. Raw Reads
        raw_match = re.search(r'Input Read Pairs: (\d+)', content)
        raw_pairs = float(raw_match.group(1)) if raw_match else 0
        raw_reads = raw_pairs * 2

        # 2. Trimming Stats (Survival Rate)
        surviving_match = re.search(r'Both Surviving: \d+ \(([\d\.]+)%\)', content)
        paired_surv = float(surviving_match.group(1)) if surviving_match else 0.0

        # 3. Trimming Loss
        dropped_match = re.search(r'Dropped: \d+ \(([\d\.]+)%\)', content)
        trim_loss = float(dropped_match.group(1)) if dropped_match else 0.0

        # 4. Host Removal Rate 계산
        trim_matches = re.findall(r'READ COUNT: trimmed (pair|orphan)[12] .*?:\s*([\d\.]+)', content)
        total_trimmed = sum(float(m[1]) for m in trim_matches)
        
        trf_matches = re.findall(r'Total number of sequences with repeats removed from file .*?:\s*(\d+)', content)
        total_trf_removed = sum(int(m) for m in trf_matches)
        
        final_matches = re.findall(r'READ COUNT: final (pair|orphan)[12] .*?:\s*([\d\.]+)', content)
        total_final = sum(float(m[1]) for m in final_matches)

        total_after_trf = total_trimmed - total_trf_removed
        host_rem_rate = 0.0
        if total_after_trf > 0:
            host_rem_rate = ((total_after_trf - total_final) / total_after_trf) * 100

        # 5. 파일 크기 추정 (GB)
        est_size_gb = (total_final * 300) / (1024**3)

        # [C] QC Flagging (비고란 작성)
        notes = []
        if trim_loss > THRESHOLDS['MAX_TRIM_LOSS']: 
            notes.append(f"High Trim Loss({trim_loss:.1f}%)")
        if paired_surv < THRESHOLDS['MIN_PAIRED_SURVIVAL']: 
            notes.append(f"Low Paired({paired_surv:.1f}%)")
        if host_rem_rate >= THRESHOLDS['MAX_HOST_REMOVAL']: 
            notes.append(f"High Host({host_rem_rate:.1f}%)")
        if est_size_gb < THRESHOLDS['MIN_FILE_SIZE_GB']: 
            notes.append(f"Small File({est_size_gb:.1f}GB)")
        
        qc_status = "; ".join(notes) if notes else "Pass"

        return {
            'Sample_ID': sample_id,
            'Raw_Reads': int(raw_reads),
            'Trimmed_Reads': int(total_trimmed),
            'Final_Reads': int(total_final),
            'Trim_Loss(%)': round(trim_loss, 2),
            'Paired_Surv(%)': round(paired_surv, 2),
            'Host_Rem(%)': round(host_rem_rate, 2),
            'Est_Size(GB)': round(est_size_gb, 2),
            'QC_Note': qc_status
        }

    except Exception as e:
        # 에러 발생 시에도 멈추지 않고 에러 메시지 반환
        return {'Sample_ID': os.path.basename(file_path), 'QC_Note': f"Error: {str(e)}"}

# ==============================================================================
# 3. 메인 실행부
# ==============================================================================
print(f"Analyzing logs in: {LOG_DIR}")

# *_summary.log 패턴 검색 (qc.sh가 생성하는 파일명 기준)
search_pattern = os.path.join(LOG_DIR, '*_summary.log')
log_files = glob.glob(search_pattern)

# 만약 summary 로그가 없으면 console 로그라도 찾음 (호환성)
if not log_files:
    search_pattern = os.path.join(LOG_DIR, '*_console.log')
    log_files = glob.glob(search_pattern)

print(f"Found {len(log_files)} log files.")

results = []
for i, filepath in enumerate(log_files):
    data = parse_kneaddata_summary(filepath)
    if data:
        results.append(data)

# 결과 저장
if results:
    df = pd.DataFrame(results)
    
    # 컬럼 순서 정리
    columns_order = [
        'Sample_ID', 'Raw_Reads', 'Trimmed_Reads', 'Final_Reads',
        'Trim_Loss(%)', 'Paired_Surv(%)', 'Host_Rem(%)', 
        'Est_Size(GB)', 'QC_Note'
    ]
    
    # 데이터프레임에 없는 컬럼이 있을 경우 대비
    existing_cols = [c for c in columns_order if c in df.columns]
    df = df[existing_cols]
    
    # CSV 파일로 저장 (qc.sh가 지정한 경로로, monitoring 사이트가 그대로 읽는 파일이므로
    # 아래 Kraken2/Excel 처리와 무관하게 항상 동일한 내용으로 저장합니다)
    df.to_csv(OUTPUT_CSV, index=False, encoding='utf-8-sig')

    print("="*60)
    print(f"Successfully saved QC report to: {OUTPUT_CSV}")
    print("="*60)

    # ==========================================================================
    # 4. [선택] Kraken2 결과 병합 + 통합 Excel 리포트 생성
    #    monitoring 사이트는 이 파일의 존재를 모르므로 대시보드에는 영향 없음
    # ==========================================================================
    if KRAKEN2_TSV:
        try:
            if not os.path.isfile(KRAKEN2_TSV):
                print(f"[WARN] Kraken2 summary not found: {KRAKEN2_TSV}. Skipping Excel merge.")
            else:
                kdf = pd.read_csv(KRAKEN2_TSV, sep='\t')

                def normalize_sample_id(s):
                    # KneadData 로그에서 뽑은 Sample_ID는 kneaddata_prefix 관례상
                    # 끝에 "_1"이 붙어있는 경우가 있어(예: SAMPLE_1), Kraken2 요약의
                    # 원본 샘플명(예: SAMPLE)과 맞추기 위해 제거하고 매칭을 시도합니다.
                    s = str(s)
                    return s[:-2] if s.endswith('_1') else s

                kraken_lookup = {str(row['Sample']): row for _, row in kdf.iterrows()}

                full_df = df.copy()
                classified_pct = []
                kraken_notes = []
                for sample_id in full_df['Sample_ID']:
                    candidates = [str(sample_id), normalize_sample_id(sample_id)]
                    match = None
                    for c in candidates:
                        if c in kraken_lookup:
                            match = kraken_lookup[c]
                            break
                    if match is None:
                        classified_pct.append(None)
                        kraken_notes.append("No Kraken2 Match")
                        continue
                    pct = float(match['Classified(%)'])
                    classified_pct.append(pct)
                    if pct < THRESHOLDS['MIN_KRAKEN_CLASSIFIED']:
                        kraken_notes.append(f"Low Classified({pct:.1f}%)")
                    else:
                        kraken_notes.append("Pass")

                full_df['Kraken_Classified(%)'] = classified_pct
                full_df['Kraken_Note'] = kraken_notes

                unmatched = int((full_df['Kraken_Note'] == "No Kraken2 Match").sum())
                if unmatched:
                    print(f"[WARN] {unmatched} sample(s) had no matching row in {KRAKEN2_TSV} "
                          "(sample naming mismatch?). Check 'Kraken_Note' column in the xlsx.")

                full_df.to_excel(OUTPUT_XLSX, index=False, sheet_name="QC_Full_Report")
                print(f"Successfully saved combined QC+Kraken2 report to: {OUTPUT_XLSX}")
        except ImportError:
            print("[WARN] openpyxl not installed in this environment; skipping Excel export. "
                  "Install it (e.g. `conda install -n KneadData_env openpyxl`) to enable this feature.")
        except Exception as e:
            print(f"[WARN] Failed to build combined Excel report: {e}")
else:
    print("No valid log files found to analyze.")