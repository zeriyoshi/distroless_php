# distroless_php
ARG PLATFORM=""
ARG DEBIAN_IMAGE="debian"
ARG DEBIAN_TAG="12"

ARG DISTROLESS_IMAGE="gcr.io/distroless/base-nossl-debian12"
ARG DISTROLESS_TAG="latest"

ARG BUSYBOX_TAG="latest"

ARG USER="nonroot"

FROM --platform=${PLATFORM} ${DEBIAN_IMAGE}:${DEBIAN_TAG} AS builder-php

# List of executable binaries to run with Distroless 
ARG DISTROLESS_PACKAGING_BINARIES="/usr/local/bin/php /usr/local/sbin/php-fpm"

# Global compile options
ARG DISTROLESS_CFLAGS="-O2"
ARG DISTROLESS_CPPFLAGS="-O2"
ARG DISTROLESS_LDFLAGS=""

# PHP specified compile options (based on docker-library/php)
ARG DISTROLESS_PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ARG DISTROLESS_PHP_CPPFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ARG DISTROLESS_PHP_LDFLAGS="-Wl,-O1 -pie"
ARG DISTROLESS_PHP_INI_DIR="/usr/local/etc/php"
ARG DISTROLESS_PHP_CONFIGURE_OPTIONS="--enable-bcmath --enable-exif --enable-intl --enable-pcntl --enable-sockets --enable-sysvmsg --enable-sysvsem --enable-sysvshm --with-gmp --with-pdo-mysql --with-zip --with-pic --enable-mysqlnd --with-password-argon2 --with-sodium --with-pdo-sqlite=/usr --with-sqlite3=/usr --with-curl --with-iconv --with-openssl --with-readline --with-zlib --disable-phpdbg --disable-cgi --enable-fpm --with-fpm-user=nonroot --with-fpm-group=nonroot"
ARG DISTROLESS_PHP_DEBIAN_PACKAGES="libgmp-dev libzip-dev libyaml-dev libzstd-dev libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev libsodium-dev libsqlite3-dev libssl-dev zlib1g-dev"

ARG DISTROLESS_PHP_IGNORE_EXTENSIONS="xdebug"

# Install build dependencies
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      "build-essential" "ca-certificates" "pkg-config" "autoconf" "automake" "bison" "re2c" "curl" "bash"

# ICU custom build for size reduction
COPY "third_party/unicode-org/icu" "/tmp/icu"
COPY "third_party/alpinelinux/aports/main/icu/data-filter-en.yml" "/tmp/icu/data-filter-en.yml"
RUN apt-get update \
 && apt-get install -y "python3" "python3-yaml" \
 && cd "/tmp/icu/icu4c/source" \
 &&   python3 -c 'import sys, yaml, json; json.dump(yaml.safe_load(sys.stdin), sys.stdout)' < "/tmp/icu/data-filter-en.yml" > "/tmp/icu/data-filter-en.json" \
 &&   ICU_DATA_FILTER_FILE="/tmp/icu/data-filter-en.json" CFLAGS="${DISTROLESS_CFLAGS}" CPPFLAGS="${DISTROLESS_CPPFLAGS}" LDFLAGS="${DISTROLESS_LDFLAGS}" ./configure --prefix="/usr" --with-data-packaging=static --disable-samples --enable-shared --disable-static \
 &&   make -j"$(nproc)" \
 &&   make install \
 && cd -

# Install libxml2 with self build ICU
COPY "third_party/GNOME/libxml2" "/tmp/libxml2"
RUN apt-get update \
 && apt-get install -y "meson" "ninja-build" "git" "zlib1g-dev" "python3-dev" \
 && cd "/tmp/libxml2" \
 &&   meson setup --prefix="/usr" "build" \
 &&   ninja -C "build" \
 &&   ninja -C "build" install \
 && cd -

# Build and install PHP
COPY "third_party/php/php-src" "/tmp/php-src"
RUN apt-get update \
 && apt-get install -y ${DISTROLESS_PHP_DEBIAN_PACKAGES} \
 && cd "/tmp/php-src" \
 &&   ./buildconf --force \
 &&   CFLAGS="-I/usr/include/libxml2 ${DISTROLESS_PHP_CFLAGS} ${DISTROLESS_CFLAGS}" CPPFLAGS="-I/usr/include/libxml2 ${DISTROLESS_PHP_CPPFLAGS} ${DISTROLESS_CPPFLAGS}" LDFLAGS="${DISTROLESS_PHP_LDFLAGS} ${DISTROLESS_LDFLAGS}" ./configure \
        --with-config-file-path="${DISTROLESS_PHP_INI_DIR}" \
        --with-config-file-scan-dir="${DISTROLESS_PHP_INI_DIR}/conf.d" \
        --enable-option-checking=fatal \
        ${DISTROLESS_PHP_CONFIGURE_OPTIONS} \
 &&   make -j"$(nproc)" \
 &&   find -type f -name '*.a' -delete \
 &&   make install \
 && cd - 

# # Install third-party PHP Extensions
# COPY "php_extensions" "/tmp/php_extensions"
# RUN for EXTENSION_PATH in $(find "/tmp/php_extensions" -mindepth 1 -maxdepth 1 | sort); do \
#       if test "x$(echo "${DISTROLESS_PHP_IGNORE_EXTENSIONS}" | grep "$(basename "${EXTENSION_PATH}")")" = "x"; then \
#         set -e; \
#         cd "${EXTENSION_PATH}" \
#         &&   DISTROLESS_CFLAGS="${DISTROLESS_CFLAGS}" \
#              DISTROLESS_CPPFLAGS="${DISTROLESS_CPPFLAGS}" \
#              DISTROLESS_LDFLAGS="${DISTROLESS_LDFLAGS}" \
#              DISTROLESS_PHP_CFLAGS="${DISTROLESS_PHP_CFLAGS}" \
#              DISTROLESS_PHP_CPPFLAGS="${DISTROLESS_PHP_CPPFLAGS}" \
#              DISTROLESS_PHP_LDFLAGS="${DISTROLESS_PHP_LDFLAGS}" \
#         &&     ./install \
#         &&     ./test \
#         cd - ; \
#       fi ; \
#     done

# Extract required binaries and extension shared libraries
COPY --chmod=755 "third_party/zeriyoshi/dependency_resolve/dependency_resolve.php" "/usr/local/bin/dependency_resolve"
RUN dependency_resolve \
      "/usr/bin/ldd" \
        ${DISTROLESS_PACKAGING_BINARIES} \
        $(find "$(php-config --extension-dir)" -type f) | \
          xargs -I {} sh -c 'mkdir -p /root/rootfs/$(dirname "{}") && cp -apP "{}" /root/rootfs/{}' \
 && find "/root/rootfs" -type f -print0 | xargs -0 -n 1 sh -c 'strip --strip-all "$0" || true'

FROM --platform=${PLATFORM} busybox:${BUSYBOX_TAG} AS builder-busybox

FROM --platform=${PLATFORM} ${DISTROLESS_IMAGE}:${DISTROLESS_TAG}

# Add busybox for PHP's shell depended functions
COPY --from=builder-busybox "/bin/busybox" "/bin/busybox"
RUN ["/bin/busybox", "ln", "-s", "/bin/busybox", "/bin/sh"]

# Remove pre-installed libraries
RUN ["/bin/busybox", "rm", "-rf", "/usr/lib"]

# Copy rootfs from builder-php context
COPY --from=builder-php "/root/rootfs" "/"

USER ${USER}

ENTRYPOINT ["/bin/sh"]
