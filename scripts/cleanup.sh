#!/bin/bash

# 🎯 1. 전체 결과가 저장된 상위 경로 설정 (환경에 맞춰 수정하세요!)
BASE_DIR="/data/CDC_2024ER110301/results/2_mag_analysis"

echo "=================================================="
echo "🚀 파이프라인 전역 다이어트(디스크 최적화) 시작!"
echo "=================================================="

# ---------------------------------------------------------
# [1단계] Assembly (MEGAHIT) 다이어트
# ---------------------------------------------------------
echo -e "\n🧹 [1단계] 01_assembly 폴더 스캔 중..."
if [ -d "${BASE_DIR}/01_assembly" ]; then
  cd "${BASE_DIR}/01_assembly" || exit
  
  for dir in KGDM*/ ; do
    [ ! -d "$dir" ] && continue # 폴더가 없으면 에러 없이 넘김
    
    if [ -f "${dir}done" ] && [ -d "${dir}intermediate_contigs" ]; then
      echo "  ▶️ [진행 중] ${dir} Assembly 압축..."
      tar -I 'zstd -10' -cf "${dir}intermediate_contigs.tar.zst" "${dir}intermediate_contigs/" && rm -rf "${dir}intermediate_contigs/"
      echo "  ✅ [완료] ${dir} Assembly 청소 성공"
    elif [ ! -f "${dir}done" ]; then
      echo "  ⏳ [실행 중] ${dir} (아직 MEGAHIT 도는 중)"
    else
      echo "  ⏩ [건너뜀] ${dir} (이미 처리됨)"
    fi
  done
else
  echo "  ⚠️ 01_assembly 폴더가 아직 존재하지 않습니다."
fi

# ---------------------------------------------------------
# [2단계] metaWRAP 다이어트
# ---------------------------------------------------------
echo -e "\n🧹 [2단계] 05_metawrap 폴더 스캔 중..."
if [ -d "${BASE_DIR}/05_metawrap" ]; then
  cd "${BASE_DIR}/05_metawrap" || exit
  
  for dir in KGDM*/ ; do
    [ ! -d "$dir" ] && continue # 폴더가 없으면 넘김
    sample_id=${dir%/}
    flag_file=".${sample_id}.binning.success"
    
    if [ -f "$flag_file" ]; then
      # 이미 청소된 폴더인지 확인 (타겟 폴더 중 하나라도 남아있을 때만 실행)
      if [ -d "${dir}read_qc" ] || [ -d "${dir}binning/work_files" ] || [ -d "${dir}binning/metabat2_bins" ]; then
        echo "  ▶️ [진행 중] ${sample_id} metaWRAP 찌꺼기 멸망 중..."
        
        # 1. 뚱뚱한 폴더들 삭제
        [ -d "${dir}read_qc" ] && rm -rf "${dir}read_qc/"
        [ -d "${dir}binning/work_files" ] && rm -rf "${dir}binning/work_files/"
        [ -d "${dir}bin_refinement/work_files" ] && rm -rf "${dir}bin_refinement/work_files/"
        
        # 2. 오리지널 3대장 압축 (binning 폴더)
        for tool in metabat2_bins maxbin2_bins concoct_bins; do
          if [ -d "${dir}binning/${tool}" ]; then
            tar -I 'zstd -10' -cf "${dir}binning/${tool}.tar.zst" "${dir}binning/${tool}/" && rm -rf "${dir}binning/${tool}/"
          fi
        done
        
        # 3. bin_refinement 중복 제거
        rm -rf "${dir}bin_refinement/metabat2_bins" "${dir}bin_refinement/maxbin2_bins" "${dir}bin_refinement/concoct_bins"
        rm -f ${dir}bin_refinement/metabat2_bins.*
        rm -f ${dir}bin_refinement/maxbin2_bins.*
        rm -f ${dir}bin_refinement/concoct_bins.*
        
        echo "  ✅ [완료] ${sample_id} metaWRAP 청소 성공!"
      else
        echo "  ⏩ [건너뜀] ${sample_id} (이미 완벽하게 청소됨)"
      fi
    else
      echo "  ⏳ [실행 중] ${sample_id} (아직 도는 중)"
    fi
  done
else
  echo "  ⚠️ 05_metawrap 폴더가 아직 존재하지 않습니다."
fi

echo -e "\n=================================================="
echo "🎉 모든 디스크 정리 작업이 안전하게 완료되었습니다!"
echo "=================================================="