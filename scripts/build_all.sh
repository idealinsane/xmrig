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
# fla,bcf,sub,alias,indcall,indbr의 모든 조합과 순열을 고려 (총 1,957개)
options=("fla" "bcf" "sub" "alias" "indcall" "indbr")

# 순열을 생성하는 함수 (재귀적)
generate_permutations() {
    local items=("$@")
    local n=${#items[@]}
    if [ $n -le 1 ]; then
        echo "${items[*]}"
    else
        for i in $(seq 0 $((n-1))); do
            local first=${items[$i]}
            local rest=("${items[@]:0:$i}" "${items[@]:$((i+1))}")
            generate_permutations "${rest[@]}" | while read perm; do
                echo "$first,$perm"
            done
        done
    fi
}

# 모든 조합과 순열을 생성 (k=3만 고려)
obfuscation_passes=()
for ((k=6; k<=6; k++)); do
    # Bash에서 조합을 생성하기 위해 간단한 반복 사용 (모든 가능한 인덱스 조합)
    # (더 나은 방법: comb 또는 외부 도구 사용, 여기서는 간단 구현)
    # 실제로는 중첩 루프나 더 효율적인 방법을 추천
    for i in $(seq 0 $(( (1<<6) - 1 )) ); do  # 모든 부분집합을 비트마스크로 생성
        combo=()
        for ((bit=0; bit<6; bit++)); do
            if (( (i >> bit) & 1 )); then
                combo+=("${options[$bit]}")
            fi
        done
        if [ ${#combo[@]} -eq $k ]; then
            # 선택된 옵션들로 순열 생성
            if [ ${#combo[@]} -gt 0 ]; then
                while IFS= read -r perm; do
                    # 쉼표로 구분된 순열을 추가 (빈 문자열 제거)
                    if [ -n "$perm" ] && [ "$perm" != "none" ]; then
                        obfuscation_passes+=("$perm")
                    fi
                done < <(generate_permutations "${combo[@]}")
            else
                obfuscation_passes+=("none")
            fi
        fi
    done
done

# 중복 제거 (필요시, 순열이 유니크하므로 보통 필요 없음)
obfuscation_passes=($(printf '%s\n' "${obfuscation_passes[@]}" | sort -u))

# 산출물 폴더 생성
mkdir -p "$ARTIFACTS_DIR"

# 결과 로그 파일
LOG_FILE="$ARTIFACTS_DIR/build_results.log"
if [ ! -f "$LOG_FILE" ]; then
  echo "Index | Passes | MD5 | Size (bytes)" >> "$LOG_FILE"
fi
# 빌드 루프
index=249
for passes in "${obfuscation_passes[@]}"; do
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
