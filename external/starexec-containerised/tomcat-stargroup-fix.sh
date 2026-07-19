#!/bin/bash
# Entry-point shim for the ghcr.io/starexecmiami/starexec-arc image.
#
# The image's init (/usr/local/bin/init-starexec.sh) starts Tomcat with
#     /project/apache-tomcat-7/bin/catalina.sh run &
# and never drops privileges, so the Tomcat JVM runs as root:root (primary
# group "root"). Solver uploads are extracted by creating a fresh temp dir
# under /local/sandbox (Java File.mkdirs, hence owned by the JVM's user:group)
# and then running `unzip` / `tar` as the unprivileged `sandbox` user. The
# servlet only makes that dir group-accessible (`chmod g+rws`), so extraction
# succeeds only if the dir's group is one the `sandbox` user belongs to. As
# root:root it is not, so the sandbox user cannot write the dir: zero files are
# extracted and every solver upload dies with HTTP 500
# "error has occurred ... error when extracting solver".
#
# Benchmarks are unaffected because they extract in-process (as root, into the
# tomcat-owned volume) and never hand off to the sandbox user -- which is why
# only *solver* uploads fail.
#
# setgid-directory and default-POSIX-ACL group inheritance both fail to
# propagate under this rootless-podman + vfs environment, so the temp dir's
# group has to come from the Tomcat process itself. This shim rewrites the
# launch line so Tomcat runs with primary group `star-web` (which contains
# sandbox, sandbox2, tomcat) while staying uid 0 -- nothing else about the
# image's root-based SSH/podman job dispatch changes.
set -e

sed -i \
  's#^/project/apache-tomcat-7/bin/catalina.sh run &#sg star-web -c "/project/apache-tomcat-7/bin/catalina.sh run" \&#' \
  /usr/local/bin/init-starexec.sh

exec /usr/local/bin/init-starexec.sh
