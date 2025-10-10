#!/bin/bash

# Polaris clang 경로
export POLARIS_HOME=/home/ubuntu/polarisObfuscator/bin

# XMRig 소스 디렉토리 경로
SOURCE_DIR=/home/ubuntu/obfuscation/xmrig_attribute

# 빌드 디렉토리 접두어
BUILD_ROOT=obfus_build_xmrig

# 산출물 저장 폴더
ARTIFACTS_DIR=artifacts

# 난독화 옵션 리스트
# fla,bcf,sub,alias,indcall,indbr 2^6 = 64개 조합
options=("fla" "bcf" "sub" "alias" "indcall" "indbr")
obfuscation_passes=()
for mask in $(seq 0 63); do
  combo=()
  for bit in $(seq 0 5); do
    if (( (mask >> bit) & 1 )); then
      combo+=("${options[$bit]}")
    fi
  done
  if [ ${#combo[@]} -gt 0 ]; then
    obfuscation_passes+=("$(IFS=,; echo "${combo[*]}")")
  else
    obfuscation_passes+=("")
  fi
done

# 산출물 폴더 생성
mkdir -p "$ARTIFACTS_DIR"

# 결과 로그 파일
LOG_FILE="$ARTIFACTS_DIR/build_results.log"
echo "Index | Passes | MD5 | Size (bytes)" > "$LOG_FILE"
# 빌드 루프
index=1
for passes in "${obfuscation_passes[@]}"; do
  if (( index % 2 == 1 )); then
    ((index++))
    continue
  fi
  echo $index

  BUILD_DIR=${BUILD_ROOT}_${index}
  if [ -n "$passes" ]; then
    PASS_FLAGS="-mllvm -passes=$passes"
    LABEL="$passes"
  else
    PASS_FLAGS=""
    LABEL="none"
  fi
  echo "🔧 Building $BUILD_DIR with passes: $LABEL"

  # 디렉토리 생성
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  # CMake 설정
  cmake "$SOURCE_DIR" \
    -DCMAKE_C_COMPILER=$POLARIS_HOME/clang \
    -DCMAKE_CXX_COMPILER=$POLARIS_HOME/clang++ \
    -DCMAKE_C_FLAGS="-O0 -pipe $PASS_FLAGS" \
    -DCMAKE_CXX_FLAGS="-O0 -pipe $PASS_FLAGS"

  # 빌드
  make -j$(nproc)

  # 결과 정리
  if [[ -f xmrig ]]; then
    new_name="xmrig_${index}"
    artifact_path="../$ARTIFACTS_DIR/$new_name"
    mv -f xmrig "$artifact_path"
    md5=$(md5sum "$artifact_path" | awk '{print $1}')
    size=$(stat -c%s "$artifact_path")
    echo "$index | $LABEL | $md5 | $size" >> "../$LOG_FILE"
    echo "✅ [$index] Build success: $artifact_path MD5=$md5 Size=${size}B"
  else
    echo "$index | $LABEL | FAILED | -" >> "../$LOG_FILE"
    echo "❌ [$index] Build failed"
  fi

  cd ..
  ((index++))
done

echo "🎉 All builds finished. Summary written to $LOG_FILE"
