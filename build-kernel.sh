#!/bin/bash
#
# =====================================================
# 범용 ARM64 커널 빌드용 Docker 자동화 스크립트
# -----------------------------------------------------
# 지원 타겟:
#   - rpi4  → DEFCONFIG=bcm2711_defconfig
#   - qemu  → DEFCONFIG=defconfig (QEMU virt 머신)
# =====================================================
#
# [📦 Docker 이미지 빌드]
# $ docker build -t kernel-builder -f Dockerfile.kernel-builder .
#
# [📝 사용 예시]
# $ ./build-kernel.sh all
# $ ./build-kernel.sh rpi4 build
# $ ./build-kernel.sh qemu menuconfig
#

# ---------- 설정 ----------
DEFCONFIG=${DEFCONFIG:-defconfig}
KERNEL_DIR=$(pwd)
ARCH=arm64
CROSS=aarch64-linux-gnu-
OUTPUT_DIR=$KERNEL_DIR/output
LOG_DIR=$KERNEL_DIR/log
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/build-$TIMESTAMP.log"
DOCKER_IMAGE=kernel-builder
MAKE="make ARCH=$ARCH CROSS_COMPILE=${CROSS} O=/kernel/build"
# --------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

mkdir -p "$LOG_DIR" "$OUTPUT_DIR"

usage() {
  echo "사용법: $0 [clean|menuconfig|build|modules|all|rpi4|qemu] [subcommand]"
  echo "preset 사용 예: ./build-kernel.sh rpi4 all"
  exit 1
}

# 프리셋 처리
ACTION=$1
if [ "$ACTION" == "rpi4" ]; then
  PRESET="rpi4"
  DEFCONFIG="bcm2711_defconfig"
  SUBACTION=$2
elif [ "$ACTION" == "qemu" ]; then
  PRESET="qemu"
  DEFCONFIG="defconfig"
  SUBACTION=$2
else
  PRESET=""
  SUBACTION=$ACTION
fi

[ -z "$SUBACTION" ] && usage

echo "[+] 작업 디렉토리: $KERNEL_DIR"
echo "[+] PRESET: $PRESET"
echo "[+] DEFCONFIG: $DEFCONFIG"
echo "[+] 실행: $SUBACTION"
echo "[+] 로그: $LOG_FILE"

run_in_docker() {
  echo "[*] Docker 빌드 시작..."
  SECONDS=0

  docker run --rm \
    -v "$KERNEL_DIR":/kernel \
    -w /kernel \
    "$DOCKER_IMAGE" \
    bash -c "$1" | tee "$LOG_FILE"

  EXIT_CODE=${PIPESTATUS[0]}
  DURATION=$SECONDS

  if [ "$EXIT_CODE" -eq 0 ]; then
    echo -e "${GREEN}[✔] 빌드 성공 (${DURATION}s)${NC}"
    copy_outputs
  else
    echo -e "${RED}[✘] 빌드 실패 (${DURATION}s)${NC}"
    exit $EXIT_CODE
  fi
}

# 빌드 결과물 정리
copy_outputs() {
  echo "[*] 빌드 결과 output/ 디렉토리에 정리 중..."
  BUILD_DIR="$KERNEL_DIR/build"

  cp -v "$BUILD_DIR/arch/arm64/boot/Image" "$OUTPUT_DIR/" 2>/dev/null
  cp -v "$BUILD_DIR/System.map" "$OUTPUT_DIR/" 2>/dev/null
  cp -v "$BUILD_DIR/Module.symvers" "$OUTPUT_DIR/" 2>/dev/null

  # DTB 디렉토리 복사
  mkdir -p "$OUTPUT_DIR/dtbs"
  cp -v "$BUILD_DIR/arch/arm64/boot/dts/"*.dtb "$OUTPUT_DIR/dtbs/" 2>/dev/null || true
  cp -v "$BUILD_DIR/arch/arm64/boot/dts/"*/*.dtb "$OUTPUT_DIR/dtbs/" 2>/dev/null || true

  # 모듈 복사
  if [ -d "$KERNEL_DIR/output_mods/lib/modules" ]; then
    mkdir -p "$OUTPUT_DIR/modules"
    cp -rv "$KERNEL_DIR/output_mods/lib/modules" "$OUTPUT_DIR/modules/"
  fi
}

# 실제 작업 분기
case "$SUBACTION" in
  clean)
    run_in_docker "cd /kernel && make ARCH=$ARCH CROSS_COMPILE=${CROSS} mrproper && rm -rf /kernel/build /kernel/output_mods"
    run_in_docker "
      cd /kernel && \
      make ARCH=$ARCH CROSS_COMPILE=$CROSS mrproper && \
      rm -rf /kernel/build/* /kernel/output_mods/*"
    ;;
  menuconfig)
    run_in_docker "$MAKE $DEFCONFIG && $MAKE menuconfig"
    ;;
  build)
    run_in_docker "$MAKE $DEFCONFIG && $MAKE -j\$(nproc) Image dtbs"
    ;;
  modules)
    run_in_docker "$MAKE -j\$(nproc) modules && $MAKE modules_install INSTALL_MOD_PATH=/kernel/output_mods"
    ;;
  all)
    run_in_docker "$MAKE $DEFCONFIG && \
      $MAKE -j\$(nproc) Image dtbs && \
      $MAKE -j\$(nproc) modules && \
      $MAKE modules_install INSTALL_MOD_PATH=/kernel/output_mods"
    ;;
  *)
    usage
    ;;
esac
