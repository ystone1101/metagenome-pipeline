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
if len(sys.argv) < 3:
    print("Usage: python generate_qc_report.py <log_dir> <output_csv>")
    # 테스트용 기본값 (단독 실행 시 사용)
    LOG_DIR = './'
    OUTPUT_CSV = 'KneadData_QC_Report_Full.csv'
else:
    LOG_DIR = sys.argv[1]    # qc.sh가 알려주는 로그 폴더
    OUTPUT_CSV = sys.argv[2] # qc.sh가 알려주는 저장 경로

# QC 기준값 설정
THRESHOLDS = {
    'MAX_TRIM_LOSS': 30.0,       # Trimming 손실률 30% 초과 시 경고
    'MIN_PAIRED_SURVIVAL': 80.0, # Paired Read 유지율 80% 미만 시 경고
    'MAX_HOST_REMOVAL': 30.0,    # Host 제거율 30% 이상 시 경고
    'MIN_FILE_SIZE_GB': 5.0      # 파일 크기 5GB 미만 시 경고
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
    
    # CSV 파일로 저장 (qc.sh가 지정한 경로로)
    df.to_csv(OUTPUT_CSV, index=False, encoding='utf-8-sig')
    
    print("="*60)
    print(f"Successfully saved QC report to: {OUTPUT_CSV}")
    print("="*60)
else:
    print("No valid log files found to analyze.")